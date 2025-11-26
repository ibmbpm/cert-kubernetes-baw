#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#function show_help() {
#    echo "Usage: $0 [-h] [-t] -n <namespace> [-o output-file]"
#    echo "  -n <namespace>        Namespace where BAW is installed."
#    echo "  -o output-file        File where the kubernetes manifests will be generated. Default is a temporary file."
#    echo "  -t                    Configure ingresses to perform tls termination with certificates into baw-ingress-tls-secret secret."
#
#}



function check_prereqs() {
    info "Checking prereqs ..."
    #check_command ${CLI_CMD}

    licensing_namespace=$(${CLI_CMD} get sub -A | grep ibm-licensing-operator-app | cut -d ' ' -f1)

    cp_console_hostname=$(${CLI_CMD} get cm ibmcloud-cluster-info -n ${baw_namespace} -o jsonpath='{.data.cluster_address}')
    if [[ -z ${cp_console_hostname} ]]; then
        error "Cannot find cluster_address value in ibmcloud-cluster-info config map in namespace ${baw_namespace}. Check that BAW is installed under ${baw_namespace}."
        exit 1
    fi

    domain_name=$(${CLI_CMD} get cm ibm-cpp-config -n ${baw_namespace} -o jsonpath='{.data.domain_name}')
    if [[ -z ${domain_name} ]]; then
        error "Cannot find domain_name value in ibm-cpp-config config map in namespace ${baw_namespace}. Check that BAW is installed under ${baw_namespace}."
        exit 1
    fi

}

function get_client_id() {
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${baw_namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' | base64 --decode)
    if [[ -z ${client_id} ]]; then
        error "Cannot retrieve client_ID from ibm-iam-bindinfo-platform-oidc-credential secret. Check if the BAW Standalone Custom Resource file has the status marked as ready."
        exit 1
    fi
}

function replace() {
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Generating ingress manifests into ${output_file}"

    #
    # Temp file to collect patched ingresses (CNCP + zen-ingress)
    #
    tmp_ingresses=$(mktemp)

    #
    # CNCP identity ingresses we want to patch (Option C)
    #
    CNCP_INGS=(
        cncf-platform-oidc
        cncf-platform-auth
        cncf-platform-id-provider
        cncf-platform-id-auth
        cncf-id-mgmt
        cncf-platform-login
        cncf-saml-ui-callback
        cncf-social-login-callback
    )

    ########################################################################
    # 1. Patch all CNCP identity ingresses (if they exist)
    ########################################################################
    for ing in "${CNCP_INGS[@]}"; do
        if ${CLI_CMD} get ingress "$ing" -n "${baw_namespace}" >/dev/null 2>&1; then
            info "Patching CNCP ingress: $ing"

            tmp_single=$(mktemp)

            ${CLI_CMD} get ingress "$ing" -n "${baw_namespace}" -o yaml | \
            # strip cluster-managed metadata
            ${CLI_CMD} patch -f - \
                -p '{"metadata":{
                        "creationTimestamp": null,
                        "generation": null,
                        "ownerReferences": null,
                        "resourceVersion": null,
                        "uid": null
                     },
                     "status":null}' \
                --type=merge --dry-run=client -o yaml | \
            # add proxy-buffer-size + proxy-body-size
            ${CLI_CMD} patch -f - \
                -p "{
                      \"metadata\": {
                        \"annotations\": {
                          \"nginx.ingress.kubernetes.io/proxy-buffer-size\": \"16k\",
                          \"nginx.ingress.kubernetes.io/proxy-body-size\": \"0\"
                        }
                      }
                    }" \
                --type=merge --dry-run=client -o yaml \
            > "${tmp_single}"

            cat "${tmp_single}" >> "${tmp_ingresses}"
            echo "---" >> "${tmp_ingresses}"
            rm -f "${tmp_single}"
        else
            info "CNCP ingress $ing not found in namespace ${baw_namespace} — skipping"
        fi
    done

    ########################################################################
    # 2. Patch legacy zen-ingress (if it exists)
    #    - buffer-size 16k
    #    - body-size 0
    #    - cert-manager.io/issuer = zen-tls-issuer
    #    - cert-manager.io/common-name = <ns>-cpd.<domain>
    #    - spec.tls.hosts[0] = <ns>-cpd.<domain>
    #    - spec.tls.secretName = cpd-ingress-tls-secret
    ########################################################################
    if ${CLI_CMD} get ingress zen-ingress -n "${baw_namespace}" >/dev/null 2>&1; then
        info "zen-ingress detected — patching annotations + TLS"

        tmp_zen=$(mktemp)

        ${CLI_CMD} get ingress zen-ingress -n "${baw_namespace}" -o yaml | \
        # strip cluster-managed fields
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{
                    "creationTimestamp": null,
                    "generation": null,
                    "ownerReferences": null,
                    "resourceVersion": null,
                    "uid": null
                 },
                 "status":null}' \
            --type=merge --dry-run=client -o yaml | \
        # add annotations: buffer/body size + issuer + CN
        ${CLI_CMD} patch -f - \
            -p "{
                  \"metadata\": {
                    \"annotations\": {
                      \"nginx.ingress.kubernetes.io/proxy-buffer-size\": \"16k\",
                      \"nginx.ingress.kubernetes.io/proxy-body-size\": \"0\",
                      \"cert-manager.io/issuer\": \"zen-tls-issuer\",
                      \"cert-manager.io/common-name\": \"${baw_namespace}-cpd.${domain_name}\"
                    }
                  }
                }" \
            --type=merge --dry-run=client -o yaml | \
        # ensure TLS block exists and uses cpd-ingress-tls-secret
        ${CLI_CMD} patch -f - \
            -p "{
                  \"spec\": {
                    \"tls\": [
                      {
                        \"hosts\": [ \"CPD_HOST\" ],
                        \"secretName\": \"cpd-ingress-tls-secret\"
                      }
                    ]
                  }
                }" \
            --type=merge --dry-run=client -o yaml \
        > "${tmp_zen}"

        # replace CPD_HOST placeholder with real host: <ns>-cpd.<domain>
        ${SED_COMMAND} "s/CPD_HOST/${baw_namespace}-cpd.${domain_name}/g" "${tmp_zen}"

        cat "${tmp_zen}" >> "${tmp_ingresses}"
        echo "---" >> "${tmp_ingresses}"
        rm -f "${tmp_zen}"
    else
        info "zen-ingress not found in namespace ${baw_namespace} — skipping zen patch"
    fi

    ########################################################################
    # 3. Write patched ingresses (if any) at TOP of output_file
    ########################################################################
    if [[ -s "${tmp_ingresses}" ]]; then
        info "Writing patched CNCP/zen ingresses to top of ${output_file}"
        cat "${tmp_ingresses}" > "${output_file}"
    else
        info "No ingresses patched — starting with empty output"
        : > "${output_file}"
    fi

    rm -f "${tmp_ingresses}"

    ########################################################################
    # 4. Append original template ingress AFTER patched ingresses
    ########################################################################
    tmp_template=$(mktemp)
    cp "${current_dir}/${template_file}" "${tmp_template}"

    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g"          "${tmp_template}"
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g"         "${tmp_template}"
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g"               "${tmp_template}"
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g"              "${tmp_template}"
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" "${tmp_template}"

    info "Appending template ingress AFTER patched ingresses"
    echo "---" >> "${output_file}"
    cat "${tmp_template}" >> "${output_file}"
    rm -f "${tmp_template}"

    ########################################################################
    # 5. macOS extra file cleanup
    ########################################################################
    if [[ -f "$output_file\"\"" ]]; then
        echo "Removing extra \" from the end of the file name"
        rm -f "${output_file}\"\"" 2>/dev/null
    fi

    info "Ingress manifest generation completed successfully"
}

function baw_cncf_generate_ingress() {
    baw_namespace=$1
    output_file=$2
    tls_termination=$3
    client_id=""
    cp_console_hostname=""
    domain_name=""
    if [[ "${tls_termination}" = true ]]; then
        template_file="ingress_template_nginx_tls.yaml"
    else
        template_file="ingress_template_nginx.yaml"
    fi
    check_prereqs
    get_client_id
    replace

}
