#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# Rancher/RKE2-specific Gateway API generation script for BAW Standalone deployment

function check_prereqs_rancher_gateway() {
    info "Checking prerequisites for Rancher/RKE2 Gateway API generation..."
    
    licensing_namespace=$(${CLI_CMD} get sub -A 2>/dev/null | grep ibm-licensing-operator-app | cut -d ' ' -f1)
    if [[ -z ${licensing_namespace} ]]; then
        licensing_namespace="ibm-licensing"
        warning "Could not detect licensing namespace, using default: ibm-licensing"
    fi

    cp_console_hostname=$(${CLI_CMD} get cm ibmcloud-cluster-info -n ${baw_namespace} -o jsonpath='{.data.cluster_address}' 2>/dev/null)
    if [[ -z ${cp_console_hostname} ]]; then
        error "Cannot find cluster_address value in ibmcloud-cluster-info config map in namespace ${baw_namespace}. Check that BAW is installed under ${baw_namespace}."
        exit 1
    fi

    domain_name=$(${CLI_CMD} get cm ibm-cpp-config -n ${baw_namespace} -o jsonpath='{.data.domain_name}' 2>/dev/null)
    if [[ -z ${domain_name} ]]; then
        domain_name=$(echo "${cp_console_hostname}" | sed -E 's/^[^.]+\.//')
    fi
    if [[ -z ${domain_name} ]]; then
        error "Cannot find domain_name value in ibm-cpp-config config map or derive from cluster_address in namespace ${baw_namespace}."
        exit 1
    fi
    
    # Prompt for GatewayClass name
    echo ""
    info "Configuring Gateway API GatewayClass..."
    echo ""
    echo "Available GatewayClasses in your cluster:"
    ${CLI_CMD} get gatewayclass -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName --no-headers 2>/dev/null || echo "  (none found)"
    echo ""
    
    default_gc="traefik"
    read -rp "Enter the GatewayClass name to use (default: ${default_gc}): " gateway_class_input
    if [[ -z "$gateway_class_input" ]]; then
        GATEWAY_CLASS_NAME="${default_gc}"
    else
        GATEWAY_CLASS_NAME="${gateway_class_input}"
    fi
    
    # Verify the GatewayClass exists
    if ! ${CLI_CMD} get gatewayclass "${GATEWAY_CLASS_NAME}" >/dev/null 2>&1; then
        warning "GatewayClass '${GATEWAY_CLASS_NAME}' not found in the cluster."
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            error "Exiting. Please ensure the GatewayClass exists in your cluster."
            exit 1
        fi
    else
        success "GatewayClass '${GATEWAY_CLASS_NAME}' found and will be used."
    fi
}

function get_client_id_rancher_gateway() {
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${baw_namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z ${client_id} ]]; then
        error "Cannot retrieve client_ID from ibm-iam-bindinfo-platform-oidc-credentials secret. Check if the BAW Standalone Custom Resource file has status marked as ready."
        exit 1
    fi
}

function patch_services_for_https() {
    info "Patching services to add appProtocol: https..."
    echo ""
    
    ${CLI_CMD} patch svc platform-auth-service -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "https"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc platform-identity-provider -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "https"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc platform-identity-management -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "https"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc ibm-nginx-svc -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "https"}]' 2>/dev/null || true
    
    success "Services patched with appProtocol: https"
}

function replace_rancher_gateway() {
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Writing Rancher Gateway API manifests to ${output_file}"
    
    template_file="gateway_api_template_rancher_traefik_base.yaml"
    
    cp "${current_dir}/${template_file}" ${output_file}
    
    # Replacements using | as delimiter
    ${SED_COMMAND} "s|NAMESPACE|${baw_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|HOST|${cp_console_hostname}|g" ${output_file}
    ${SED_COMMAND} "s|DOMAIN|${domain_name}|g" ${output_file}
    ${SED_COMMAND} "s|CLIENT_ID|${client_id}|g" ${output_file}
    ${SED_COMMAND} "s|LICENSING_NS|${licensing_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|GATEWAY_CLASS|${GATEWAY_CLASS_NAME}|g" ${output_file}
    
    # Clean up mac sed artifacts
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}

function create_ibm_iaf_ca_secret() {
    info "Creating IBM CA secrets for Traefik backend TLS verification..."
    info "  IBM CP4BA uses two internal CAs:"
    info "    ibm-iaf-ca  (CN=IBM Automation Foundation CA) -> signs ibm-nginx-svc"
    info "    ibm-cs-ca   (CN=cs-ca-certificate)            -> signs platform-auth, idp, idm"

    # --- ibm-iaf-ca: CN=IBM Automation Foundation CA ---
    # Source: external-tls-secret.ca.crt in the CP4BA namespace
    local iaf_ca_data
    iaf_ca_data=$(${CLI_CMD} get secret external-tls-secret -n "${baw_namespace}" \
        -o jsonpath='{.data.ca\.crt}' 2>/dev/null)

    if [[ -z "${iaf_ca_data}" ]]; then
        warning "external-tls-secret not found in ${baw_namespace}. ibm-iaf-ca secret will not be created."
        warning "Create it manually:"
        warning "  kubectl get secret external-tls-secret -n ${baw_namespace} -o jsonpath='{.data.ca\\.crt}' | base64 -d > /tmp/iaf-ca.crt"
        warning "  kubectl create secret generic ibm-iaf-ca -n ${baw_namespace} --from-file=tls.crt=/tmp/iaf-ca.crt"
    else
        echo "${iaf_ca_data}" | base64 --decode > /tmp/ibm-iaf-ca.crt
        ${CLI_CMD} create secret generic ibm-iaf-ca \
            -n "${baw_namespace}" \
            --from-file=tls.crt=/tmp/ibm-iaf-ca.crt \
            --dry-run=client -o yaml | ${CLI_CMD} apply -f - 2>/dev/null
        rm -f /tmp/ibm-iaf-ca.crt
        success "ibm-iaf-ca secret created/updated in namespace ${baw_namespace}"
    fi

    # --- ibm-cs-ca: CN=cs-ca-certificate ---
    # Source: cs-ca-certificate-secret.ca.crt in the CP4BA namespace
    local cs_ca_data
    cs_ca_data=$(${CLI_CMD} get secret cs-ca-certificate-secret -n "${baw_namespace}" \
        -o jsonpath='{.data.ca\.crt}' 2>/dev/null)

    if [[ -z "${cs_ca_data}" ]]; then
        warning "cs-ca-certificate-secret not found in ${baw_namespace}. ibm-cs-ca secret will not be created."
        warning "Create it manually:"
        warning "  kubectl get secret cs-ca-certificate-secret -n ${baw_namespace} -o jsonpath='{.data.ca\\.crt}' | base64 -d > /tmp/cs-ca.crt"
        warning "  kubectl create secret generic ibm-cs-ca -n ${baw_namespace} --from-file=tls.crt=/tmp/cs-ca.crt"
    else
        echo "${cs_ca_data}" | base64 --decode > /tmp/ibm-cs-ca.crt
        ${CLI_CMD} create secret generic ibm-cs-ca \
            -n "${baw_namespace}" \
            --from-file=tls.crt=/tmp/ibm-cs-ca.crt \
            --dry-run=client -o yaml | ${CLI_CMD} apply -f - 2>/dev/null
        rm -f /tmp/ibm-cs-ca.crt
        success "ibm-cs-ca secret created/updated in namespace ${baw_namespace}"
    fi
}

function baw_rancher_generate_gateway_api() {
    local baw_namespace=$1
    local output_file=$2
    
    GATEWAY_CLASS_NAME=""
    output_dir=$(dirname "${output_file}")
    
    # Check prerequisites
    check_prereqs_rancher_gateway
    
    # Get client ID
    get_client_id_rancher_gateway
    
    # Patch services
    echo ""
    patch_services_for_https
    
    # Create IBM IAF CA secret for Traefik ServersTransport TLS verification
    echo ""
    create_ibm_iaf_ca_secret
    
    # Generate Gateway API manifest
    echo ""
    info "Generating Rancher Gateway API manifest..."
    replace_rancher_gateway
    
    final_output="${output_dir}/gateway-api-rancher.yaml"
    if [[ "${output_file}" != "${final_output}" ]]; then
        cp "${output_file}" "${final_output}"
    fi
    
    echo ""
    success "Rancher Gateway API resources generated successfully at ${final_output}!"
}
