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

    # Temporary file to accumulate patched ingress resources (zen or cncf-*)
    tmp_ingresses=$(mktemp)

    #
    # 1. Detect ingress model: legacy zen-ingress vs new cncf-* ingresses
    #
    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        ####################################################################
        # Legacy model: zen-ingress present (pre / hybrid 6.2.2 behaviour)
        ####################################################################
        info "Detected legacy zen-ingress; patching it"

        tmp_zen_ingress=$(mktemp)

        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
        # strip cluster-managed fields
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' \
            --type=merge --dry-run=client -o yaml | \
        # add proxy-buffer-size annotation
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"8k"}}}' \
            --type=merge --dry-run=client -o yaml \
        > ${tmp_zen_ingress}

        # optional TLS termination logic ONLY for legacy zen-ingress
        if [[ "${tls_termination}" = true ]]; then
            info "Adding TLS configuration into legacy zen-ingress"

            tmp_zen_tls=$(mktemp)

            ${CLI_CMD} patch -f ${tmp_zen_ingress} \
                -p '{"spec": {"tls": [{"hosts": ["CPD_HOST"], "secretName": "cpd-ingress-tls-secret" }]}}' \
                --type=merge --dry-run=client -o yaml | \
            ${CLI_CMD} patch -f - \
                -p '{"metadata":{"annotations":{"cert-manager.io/issuer":"zen-tls-issuer"}}}' \
                --type=merge --dry-run=client -o yaml \
                > ${tmp_zen_tls}

            mv ${tmp_zen_tls} ${tmp_zen_ingress}
            ${SED_COMMAND} "s/CPD_HOST/${baw_namespace}-cpd.${domain_name}/g" ${tmp_zen_ingress}
        fi

        # Add patched zen-ingress to the ingresses buffer
        cat ${tmp_zen_ingress} >> ${tmp_ingresses}
        echo "---" >> ${tmp_ingresses}
        rm -f ${tmp_zen_ingress}

    else
        ####################################################################
        # New model: cncf-* ingresses (Zen 6.2.2+)
        ####################################################################
        info "zen-ingress not found; checking for cncf platform ingresses (Zen 6.2.2+ model)"

        # These are the main identity / OIDC ingresses relevant for logout
        for ing in cncf-platform-oidc cncf-platform-auth cncf-platform-id-provider; do
            if ${CLI_CMD} get ingress "${ing}" -n ${baw_namespace} >/dev/null 2>&1; then
                info "Patching ${ing} with proxy-buffer-size annotation"

                tmp_cncf=$(mktemp)

                ${CLI_CMD} get ingress "${ing}" -n ${baw_namespace} -o yaml | \
                # strip cluster-managed fields
                ${CLI_CMD} patch -f - \
                    -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' \
                    --type=merge --dry-run=client -o yaml | \
                # add proxy-buffer-size annotation
                ${CLI_CMD} patch -f - \
                    -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"8k"}}}' \
                    --type=merge --dry-run=client -o yaml \
                > ${tmp_cncf}

                cat ${tmp_cncf} >> ${tmp_ingresses}
                echo "---" >> ${tmp_ingresses}
                rm -f ${tmp_cncf}
            else
                info "Ingress ${ing} not found in namespace ${baw_namespace}; skipping."
            fi
        done
    fi

    #
    # 2. Write patched ingresses (if any) FIRST into output_file
    #
    if [[ -s ${tmp_ingresses} ]]; then
        info "Writing patched Zen/cncf ingresses at TOP of ${output_file}"
        cat ${tmp_ingresses} > ${output_file}
        # trailing '---' is already added after each ingress
    else
        info "No Zen or cncf platform ingresses found to patch; output will contain only template ingress."
        # truncate output file to start fresh
        : > ${output_file}
    fi

    rm -f ${tmp_ingresses}

    #
    # 3. Process the static template and append AFTER the patched ingresses
    #
    tmp_template=$(mktemp)
    cp "${current_dir}/${template_file}" ${tmp_template}

    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g"          ${tmp_template}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g"         ${tmp_template}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g"               ${tmp_template}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g"              ${tmp_template}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${tmp_template}

    info "Appending original template contents AFTER patched ingresses"
    # If no ingresses were written, this will just be the full file
    cat ${tmp_template} >> ${output_file}
    rm -f ${tmp_template}

    # Workaround to remove extra file in Mac that has "" at the end of output_file such as ingress_nginx.yaml""
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
