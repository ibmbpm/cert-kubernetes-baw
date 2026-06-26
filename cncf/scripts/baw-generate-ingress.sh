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
    # TEMP file to collect patched ingresses
    #
    tmp_ingresses=$(mktemp)

    #
    # The full list of CNCF identity ingresses
    #
    CNCF_INGS=(
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
    # 1. Patch all CNCF identity ingresses
    #
    for ing in "${CNCF_INGS[@]}"; do
        if ${CLI_CMD} get ingress "$ing" -n ${baw_namespace} >/dev/null 2>&1; then
            info "Patching CNCF ingress: $ing"

            tmp_single=$(mktemp)

            ${CLI_CMD} get ingress "$ing" -n ${baw_namespace} -o yaml | \
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
            > ${tmp_single}

            cat ${tmp_single} >> ${tmp_ingresses}
            echo "---" >> ${tmp_ingresses}
            rm -f ${tmp_single}
        else
            info "CNCF ingress $ing not found — skipping"
        fi
    done

    #
    # 2. Delete common-web-ui ingress if it exists
    #
    if ${CLI_CMD} get ingress cncf-common-web-ui -n ${baw_namespace} >/dev/null 2>&1; then
        info "Deleting existing cncf-common-web-ui ingress..."
        ${CLI_CMD} delete ingress cncf-common-web-ui -n ${baw_namespace}
        if [ $? -eq 0 ]; then
            success "Successfully deleted cncf-common-web-ui ingress"
        else
            warning "Failed to delete cncf-common-web-ui ingress"
        fi
    else
        info "cncf-common-web-ui ingress not found — skipping deletion"
    fi

    #
    # 3. Patch legacy zen-ingress (if it exists)
    #
    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        info "Legacy zen-ingress detected — applying buffer-size, body-size, CN"

        tmp_zen=$(mktemp)

        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
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
        ${CLI_CMD} patch -f - \
            -p "{
                  \"metadata\": {
                    \"annotations\": {
                      \"nginx.ingress.kubernetes.io/proxy-buffer-size\": \"16k\",
                      \"nginx.ingress.kubernetes.io/proxy-body-size\": \"0\",
                      \"cert-manager.io/common-name\": \"${baw_namespace}-cpd.${domain_name}\"
                    }
                  }
                }" \
            --type=merge --dry-run=client -o yaml \
        > ${tmp_zen}

        if [[ "${tls_termination}" = true ]]; then
            tmp_zen_tls=$(mktemp)
            ${CLI_CMD} patch -f ${tmp_zen} \
                -p "{
                      \"metadata\": {
                        \"annotations\": {
                          \"cert-manager.io/issuer\": \"zen-tls-issuer\"
                        }
                      },
                      \"spec\": {
                        \"tls\": [{
                          \"hosts\": [\"${baw_namespace}-cpd.${domain_name}\"],
                          \"secretName\": \"cpd-ingress-tls-secret\"
                        }]
                      }
                    }" \
                --type=merge --dry-run=client -o yaml \
            > ${tmp_zen_tls}
            cat ${tmp_zen_tls} > ${tmp_zen}
            rm -f ${tmp_zen_tls}
        fi

        cat ${tmp_zen} >> ${tmp_ingresses}
        echo "---" >> ${tmp_ingresses}
        rm -f ${tmp_zen}
    else
        info "zen-ingress not found — skipping legacy ingress patch"
    fi

    #
    # 4. Write patched ingresses FIRST into output_file
    #
    if [[ -s ${tmp_ingresses} ]]; then
        info "Writing patched CNCF/zen ingresses at TOP of ${output_file}"
        cat ${tmp_ingresses} > ${output_file}
    else
        info "No ingresses patched — starting with empty output"
        : > ${output_file}
    fi

    rm -f ${tmp_ingresses}

    #
    # 5. Append the original template after patched ingresses
    #
    tmp_template=$(mktemp)
    cp "${current_dir}/${template_file}" ${tmp_template}

    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g"          ${tmp_template}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g"         ${tmp_template}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g"               ${tmp_template}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g"              ${tmp_template}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${tmp_template}

    info "Appending template ingress AFTER patched ingresses"
    echo "---" >> ${output_file}
    cat ${tmp_template} >> ${output_file}

    rm -f ${tmp_template}

    #
    # 6. macOS file cleanup
    #
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}

function generate_certificate_cr() {
    local namespace=$1
    local domain_name=$2
    local output_dir=$3
    local cert_file="${output_dir}/cpd-tls-certificate.yaml"
    
    info "Generating Certificate CR for TLS secret..."
    
    cat > "${cert_file}" << EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cpd-ingress-tls
  namespace: ${namespace}
spec:
  secretName: cpd-ingress-tls-secret
  issuerRef:
    name: zen-tls-issuer
    kind: Issuer
  dnsNames:
    - ${namespace}-cpd.${domain_name}
  usages:
    - digital signature
    - key encipherment
    - server auth
EOF
    
    success "Certificate CR created at: ${cert_file}"
}

function apply_certificate_and_wait() {
    local namespace=$1
    local cert_file=$2
    local secret_name="cpd-ingress-tls-secret"
    
    info "Applying Certificate CR to create TLS secret..."
    ${CLI_CMD} apply -f "${cert_file}"
    
    if [ $? -ne 0 ]; then
        warning "Failed to apply Certificate CR. Please check cert-manager is installed and zen-tls-issuer exists."
        return 1
    fi
    
    info "Waiting for cert-manager to create the TLS secret..."
    local max_wait=120
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if ${CLI_CMD} get secret ${secret_name} -n ${namespace} >/dev/null 2>&1; then
            success "TLS secret ${secret_name} created successfully!"
            return 0
        fi
        echo -n "."
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    printf "\n"
    warning "Timeout waiting for TLS secret to be created. Please check cert-manager logs."
    return 1
}

function update_tls_secret_with_fullchain() {
    local namespace=$1
    local secret_name="cpd-ingress-tls-secret"
    
    info "Updating ${secret_name} with full certificate chain..."
    
    # Check if the secret exists
    if ! ${CLI_CMD} get secret ${secret_name} -n ${namespace} >/dev/null 2>&1; then
        warning "Secret ${secret_name} not found in namespace ${namespace}. Skipping certificate chain update."
        return 1
    fi
    
    # Extract certificates to temporary files
    ${CLI_CMD} -n ${namespace} get secret ${secret_name} -o json | \
      jq -r '.data["tls.crt"]' | base64 -d > /tmp/leaf.crt
    
    if [[ ! -s /tmp/leaf.crt ]]; then
        warning "Failed to extract tls.crt from secret ${secret_name}."
        rm -f /tmp/leaf.crt
        return 1
    fi
    
    ${CLI_CMD} -n ${namespace} get secret ${secret_name} -o json | \
      jq -r '.data["ca.crt"]' | base64 -d > /tmp/ca.crt
    
    if [[ ! -s /tmp/ca.crt ]]; then
        warning "Failed to extract ca.crt from secret ${secret_name}."
        rm -f /tmp/leaf.crt /tmp/ca.crt
        return 1
    fi
    
    # Concatenate leaf and CA certificates to create full chain
    cat /tmp/leaf.crt /tmp/ca.crt > /tmp/fullchain.crt
    
    info "Applying full certificate chain to secret..."
    
    # Update the secret with the full certificate chain
    ${CLI_CMD} -n ${namespace} create secret tls ${secret_name} \
      --cert=/tmp/fullchain.crt \
      --key=<(${CLI_CMD} -n ${namespace} get secret ${secret_name} -o json | jq -r '.data["tls.key"]' | base64 -d) \
      --dry-run=client -o yaml | ${CLI_CMD} apply -f -
    
    if [ $? -eq 0 ]; then
        success "Successfully updated ${secret_name} with full certificate chain!"
        
        # Verify the update
        local cert_count=$(${CLI_CMD} get secret ${secret_name} -n ${namespace} -o jsonpath='{.data.tls\.crt}' | base64 -d | grep -c "BEGIN CERTIFICATE")
        info "Certificate chain now contains ${cert_count} certificate(s)"
    else
        warning "Failed to update ${secret_name} with full certificate chain."
        rm -f /tmp/leaf.crt /tmp/ca.crt /tmp/fullchain.crt
        return 1
    fi
    
    # Clean up temporary files
    rm -f /tmp/leaf.crt /tmp/ca.crt /tmp/fullchain.crt
    return 0
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
    
    # If TLS termination is enabled, create Certificate CR and update secret before generating ingress
    if [[ "${tls_termination}" = true ]]; then
        output_dir=$(dirname "${output_file}")
        
        # Generate Certificate CR
        generate_certificate_cr "${baw_namespace}" "${domain_name}" "${output_dir}"
        
        # Apply Certificate CR and wait for secret creation
        if apply_certificate_and_wait "${baw_namespace}" "${output_dir}/cpd-tls-certificate.yaml"; then
            # Update the secret with full certificate chain
            update_tls_secret_with_fullchain "${baw_namespace}"
        else
            warning "Failed to create or update TLS secret. Continuing with ingress generation..."
        fi
    fi
    
    # Generate ingress templates
    replace

}
