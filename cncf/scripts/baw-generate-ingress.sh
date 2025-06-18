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

    info "Writing kubernetes manifests to ${output_file}"
    cp "${current_dir}/${template_file}" ${output_file}
    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g" ${output_file}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g" ${output_file}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g" ${output_file}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g" ${output_file}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${output_file}

    # add nginx.ingress.kubernetes.io/proxy-buffer-size annotations to zen ingress
    echo "" >> ${output_file}
    echo "---" >> ${output_file}

    tmp_zen_ingress=$(mktemp)

    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
        ${CLI_CMD} patch -f - -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' --type=merge --dry-run='client' -o yaml | \
        ${CLI_CMD} patch -f - -p '{"metadata":{"annotations":{"nginx.ingress.kubernetes.io/proxy-buffer-size":"8k","nginx.ingress.kubernetes.io/proxy-body-size":"0"}}}' --type=merge --dry-run='client' -o yaml \
        > ${tmp_zen_ingress}
    else
        info "zen-ingress not found in namespace ${baw_namespace}. Skipping."
    fi

    if [[ "${tls_termination}" = true ]]; then
        tmp_zen_ingress_work=$(mktemp)
        # add tls section
        # ${CLI_CMD} patch -f ${tmp_zen_ingress} -p='[{"op": "add", "path": "/spec", "value": {"tls": { "hosts": ["CPD_HOST"], "secretName": "cpd-ingress-tls-secret" }}}]' --type=json --dry-run='client' -o yaml | \
        ${CLI_CMD} patch -f ${tmp_zen_ingress} -p '{"spec": {"tls": [{"hosts": ["CPD_HOST"], "secretName": "cpd-ingress-tls-secret" }]}}' --type=merge --dry-run='client' -o yaml | \
        # add annotation
        ${CLI_CMD} patch -f - -p '{"metadata":{"annotations":{"cert-manager.io/issuer":"zen-tls-issuer","cert-manager.io/common-name":"CPD_HOST"}}}' --type=merge --dry-run='client' -o yaml  \
        > ${tmp_zen_ingress_work}
        cat ${tmp_zen_ingress_work} > ${tmp_zen_ingress} && rm ${tmp_zen_ingress_work}
        ${SED_COMMAND} "s/CPD_HOST/${baw_namespace}-cpd.${domain_name}/g" ${tmp_zen_ingress}
    fi

    cat ${tmp_zen_ingress} >> ${output_file}
    rm ${tmp_zen_ingress}
    #Workaround to move extra file in Mac that has "" at the end of output_file such as ingress_nginx.yaml""
    if [[ -f "$output_file\"\"" ]]; then
        echo "Removing extra \" from the end of the file name"
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
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
