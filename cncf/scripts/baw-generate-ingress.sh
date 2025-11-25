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
    # Create output file if not provided
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Generating manifests into ${output_file}"

    #
    # IMPORTANT: delete existing zen-ingress to force ingress-nginx reload
    #
    info "Deleting existing zen-ingress to enforce fresh controller reload"
    ${CLI_CMD} delete ingress zen-ingress -n ${baw_namespace} --ignore-not-found=true

    #
    # Generate patched zen-ingress first
    #
    tmp_zen_ingress=$(mktemp)

    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        info "Extracting and patching zen-ingress from cluster"

        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' \
            --type=merge --dry-run=client -o yaml | \
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"8k"}}}' \
            --type=merge --dry-run=client -o yaml \
        > ${tmp_zen_ingress}

    else
        info "zen-ingress does not exist on cluster yet — skipping extraction"
        # Build empty basis if needed
        echo "# zen-ingress placeholder will be created by operator" > ${tmp_zen_ingress}
    fi

    #
    # TLS patch if enabled
    #
    if [[ "${tls_termination}" = true ]]; then
        info "Adding TLS configuration into zen-ingress"
        tmp_tls_patch=$(mktemp)

        ${CLI_CMD} patch -f ${tmp_zen_ingress} \
            -p '{"spec": {"tls": [{"hosts": ["CPD_HOST"], "secretName": "cpd-ingress-tls-secret"}]}}' \
            --type=merge --dry-run=client -o yaml | \
        ${CLI_CMD} patch -f - \
            -p '{"metadata":{"annotations":{"cert-manager.io/issuer":"zen-tls-issuer"}}}' \
            --type=merge --dry-run=client -o yaml \
        > ${tmp_tls_patch}

        mv ${tmp_tls_patch} ${tmp_zen_ingress}
        ${SED_COMMAND} "s/CPD_HOST/${baw_namespace}-cpd.${domain_name}/g" ${tmp_zen_ingress}
    fi


    #
    # WRITE ORDER → ZEN-INGRESS FIRST
    #
    info "Writing zen-ingress FIRST into output manifest"
    cat ${tmp_zen_ingress} > ${output_file}     # overwrite file with zen ingress
    echo "---" >> ${output_file}


    #
    # Now append the template contents AFTER zen-ingress
    #
    tmp_template=$(mktemp)
    cp "${current_dir}/${template_file}" ${tmp_template}

    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g"   ${tmp_template}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g"  ${tmp_template}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g"        ${tmp_template}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g"       ${tmp_template}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${tmp_template}

    info "Appending template manifests AFTER zen-ingress"
    cat ${tmp_template} >> ${output_file}

    rm -f ${tmp_template} ${tmp_zen_ingress}

    # macOS cleanup
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi

    info "Manifest generation completed successfully"
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
