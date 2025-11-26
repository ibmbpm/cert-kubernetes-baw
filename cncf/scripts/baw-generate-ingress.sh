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
    # TEMP FILE to collect ALL patched CNCP ingresses
    #
    tmp_ingresses=$(mktemp)

    #
    # List of all CNCP identity ingresses to patch
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

    #
    # 1. Process each CNCP ingress (patch proxy-buffer-size = 16k)
    #
    for ing in "${CNCP_INGS[@]}"; do
        if ${CLI_CMD} get ingress "$ing" -n ${baw_namespace} >/dev/null 2>&1; then
            info "Patching CNCP ingress: $ing"

            tmp_single=$(mktemp)

            ${CLI_CMD} get ingress "$ing" -n ${baw_namespace} -o yaml | \
            # strip cluster-generated fields
            ${CLI_CMD} patch -f - \
                -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' \
                --type=merge --dry-run=client -o yaml | \
            # add proxy-buffer-size annotation
            ${CLI_CMD} patch -f - \
                -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"16k"}}}' \
                --type=merge --dry-run=client -o yaml \
            > ${tmp_single}

            cat ${tmp_single} >> ${tmp_ingresses}
            echo "---" >> ${tmp_ingresses}
            rm -f ${tmp_single}
        else
            info "CNCP ingress $ing not found — skipping"
        fi
    done

    #
    # Optional: Patch legacy zen-ingress if still present (harmless)
    #
    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        info "Legacy zen-ingress detected — patching as well"

        tmp_zen=$(mktemp)

        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' \
            --type=merge --dry-run=client -o yaml | \
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"16k"}}}' \
            --type=merge --dry-run=client -o yaml \
        > ${tmp_zen}

        cat ${tmp_zen} >> ${tmp_ingresses}
        echo "---" >> ${tmp_ingresses}
        rm -f ${tmp_zen}
    fi

    #
    # 2. WRITE CNCP (and legacy) patched ingresses FIRST in output
    #
    if [[ -s ${tmp_ingresses} ]]; then
        info "Writing patched CNCP ingresses to TOP of ${output_file}"
        cat ${tmp_ingresses} > ${output_file}
    else
        info "No CNCP ingresses found — starting with an empty file"
        : > ${output_file}
    fi

    rm -f ${tmp_ingresses}

    #
    # 3. Append your original template ingress file AFTER patched ingresses
    #
    tmp_template=$(mktemp)
    cp "${current_dir}/${template_file}" ${tmp_template}

    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g"          ${tmp_template}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g"         ${tmp_template}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g"               ${tmp_template}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g"              ${tmp_template}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${tmp_template}

    info "Appending template ingress AFTER CNCP ingresses"
    echo "---" >> ${output_file}
    cat ${tmp_template} >> ${output_file}

    rm -f ${tmp_template}

    # macOS cleanup
    if [[ -f "$output_file\"\"" ]]; then
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
