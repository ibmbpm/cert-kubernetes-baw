#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# GKE-specific Gateway API generation script for BAW Standalone deployment
# This script generates Gateway API resources using GKE Gateway controller

function check_prereqs_gke_gateway() {
    info "Checking prerequisites for GKE Gateway API generation..."
    
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
        error "Cannot find domain_name value in ibm-cpp-config config map in namespace ${baw_namespace}. Check that BAW is installed under ${baw_namespace}."
        exit 1
    fi
    
    # Prompt for GatewayClass name
    echo ""
    info "Configuring Gateway API GatewayClass..."
    echo ""
    echo "Available GatewayClasses in your cluster:"
    ${CLI_CMD} get gatewayclass -o custom-columns=NAME:.metadata.name,CONTROLLER:.spec.controllerName --no-headers 2>/dev/null || echo "  (none found)"
    echo ""
    read -rp "Enter the GatewayClass name to use: " gateway_class_input
    if [[ -z "$gateway_class_input" ]]; then
        error "GatewayClass name is required"
        exit 1
    fi
    GATEWAY_CLASS_NAME="${gateway_class_input}"
    
    # Verify the GatewayClass exists
    if ! ${CLI_CMD} get gatewayclass "${GATEWAY_CLASS_NAME}" >/dev/null 2>&1; then
        warning "GatewayClass '${GATEWAY_CLASS_NAME}' not found in the cluster."
        echo ""
        echo "To enable Gateway API on GKE with gke-l7-global-external-managed, run:"
        echo ""
        echo "  gcloud container clusters update <CLUSTER_NAME> --region <REGION> --gateway-api=standard"
        echo ""
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            error "Exiting. Please ensure the GatewayClass exists in your cluster."
            exit 1
        fi
    else
        success "GatewayClass '${GATEWAY_CLASS_NAME}' found and will be used."
    fi
    
    # Check for cert-manager
    if ! ${CLI_CMD} get pods -n cert-manager >/dev/null 2>&1; then
        warning "cert-manager not found. Gateway API requires cert-manager for TLS certificates."
        echo ""
        echo "Install cert-manager: https://cert-manager.io/docs/installation/"
        echo ""
    fi
    
    # Check for zen-tls-issuer
    if ! ${CLI_CMD} get issuer zen-tls-issuer -n ${baw_namespace} >/dev/null 2>&1; then
        warning "zen-tls-issuer not found in namespace ${baw_namespace}."
        echo "This issuer is typically created by IBM Cloud Pak installation."
        echo ""
    fi
}

function get_client_id_gke_gateway() {
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${baw_namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z ${client_id} ]]; then
        error "Cannot retrieve client_ID from ibm-iam-bindinfo-platform-oidc-credential secret. Check if the BAW Standalone Custom Resource file has the status marked as ready."
        exit 1
    fi
}

function prompt_optional_components() {
    echo ""
    info "Configuring optional components (OpenSearch and Kafka)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    INCLUDE_OPENSEARCH="false"
    INCLUDE_KAFKA="false"
    
    # Ask about OpenSearch (user-prompted, not auto-detected)
    echo "${YELLOW_TEXT}OpenSearch Configuration:${RESET_TEXT}"
    echo ""
    read -rp "Include OpenSearch in Gateway API configuration? (yes/no, default: no): " answer
    answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
    if [[ "$answer" == "yes" || "$answer" == "y" ]]; then
        INCLUDE_OPENSEARCH="true"
        success "OpenSearch will be included in the Gateway API configuration"
    else
        info "OpenSearch will NOT be included"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ask about Kafka (user-prompted, not auto-detected)
    echo "${YELLOW_TEXT}Kafka Configuration:${RESET_TEXT}"
    echo ""
    read -rp "Include Kafka in Gateway API configuration? (yes/no, default: no): " kafka_answer
    kafka_answer=$(echo "$kafka_answer" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$kafka_answer" == "yes" || "$kafka_answer" == "y" ]]; then
        INCLUDE_KAFKA="true"
        success "Kafka will be included in the configuration"
        echo ""
        
        # Check ICP4ACluster CR sc_ingress_type setting for Kafka
        info "Checking ICP4ACluster CR configuration for Kafka..."
        sc_ingress_type=$(${CLI_CMD} get icp4acluster -n ${baw_namespace} -o jsonpath='{.items[0].spec.shared_configuration.sc_ingress_type}' 2>/dev/null)
        
        if [[ -n "$sc_ingress_type" && "$sc_ingress_type" == "loadbalancer" ]]; then
            success "ICP4ACluster CR has sc_ingress_type set to: ${sc_ingress_type}"
            echo ""
            echo "${YELLOW_TEXT}NOTE:${RESET_TEXT} For Kafka with Gateway API, you can use either:"
            echo "  1. Gateway API (recommended) - Keep sc_ingress_type: loadbalancer"
            echo "  2. NGINX Ingress - Remove sc_ingress_type: loadbalancer from CR"
            echo ""
        else
            warning "ICP4ACluster CR does not have sc_ingress_type: loadbalancer"
            echo ""
            echo "${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} For Kafka with Gateway API, update your ICP4ACluster CR with:"
            echo ""
            echo "  spec:"
            echo "    shared_configuration:"
            echo "      sc_ingress_type: loadbalancer"
            echo ""
            echo "${YELLOW_TEXT}NOTE:${RESET_TEXT} If you prefer to use NGINX for Kafka instead, you can skip this setting."
            echo ""
        fi
    else
        INCLUDE_KAFKA="false"
        info "Kafka will NOT be included"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

function patch_services_for_https() {
    info "Patching services to add appProtocol: HTTPS..."
    echo ""
    
    # Patch auth services
    ${CLI_CMD} patch svc platform-auth-service -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc platform-identity-provider -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc platform-identity-management -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    ${CLI_CMD} patch svc ibm-nginx-svc -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    # Patch licensing service
    ${CLI_CMD} patch svc ibm-licensing-service-instance -n ${licensing_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    # Add NEG annotations to all services
    ${CLI_CMD} annotate service platform-auth-service -n ${baw_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
    
    ${CLI_CMD} annotate service platform-identity-provider -n ${baw_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
    
    ${CLI_CMD} annotate service platform-identity-management -n ${baw_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
    
    ${CLI_CMD} annotate service ibm-nginx-svc -n ${baw_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
    
    ${CLI_CMD} annotate service ibm-licensing-service-instance -n ${licensing_namespace} \
      cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
    
    # Handle OpenSearch if included
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        info "Adding NEG annotation to OpenSearch service..."
        ${CLI_CMD} annotate service opensearch -n ${baw_namespace} \
          cloud.google.com/neg='{"ingress":true}' --overwrite 2>/dev/null || true
        
        # Verify if appProtocol is set
        opensearch_app_protocol=$(${CLI_CMD} get svc opensearch -n ${baw_namespace} -o jsonpath='{.spec.ports[1].appProtocol}' 2>/dev/null)
        if [[ "$opensearch_app_protocol" == "HTTPS" ]]; then
            success "OpenSearch service already has appProtocol: HTTPS on port 9200"
        else
            warning "OpenSearch service does NOT have appProtocol: HTTPS on port 9200"
            echo "Please ensure the OpenSearch Cluster CR has the appProtocol: HTTPS configuration via spec.patches."
            echo ""
        fi
    fi
    
    success "Services patched with appProtocol: HTTPS and NEG annotations"
}

function replace_gke_gateway() {
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Writing GKE Gateway API manifests to ${output_file}"
    
    # Select the appropriate template based on optional components
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        template_file="gateway_api_template_gke_with_optional.yaml"
    else
        template_file="gateway_api_template_gke_base.yaml"
    fi
    
    cp "${current_dir}/${template_file}" ${output_file}
    
    # Basic replacements using | as delimiter to avoid issues with / in values
    ${SED_COMMAND} "s|NAMESPACE|${baw_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|HOST|${cp_console_hostname}|g" ${output_file}
    ${SED_COMMAND} "s|DOMAIN|${domain_name}|g" ${output_file}
    ${SED_COMMAND} "s|CLIENT_ID|${client_id}|g" ${output_file}
    ${SED_COMMAND} "s|LICENSING_NS|${licensing_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|GATEWAY_CLASS|${GATEWAY_CLASS_NAME}|g" ${output_file}
    
    # Note: GATEWAY_IP_NAME placeholder will be replaced by user or left as-is for manual update
    
    # Workaround for Mac sed creating extra files
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}


function baw_gke_generate_gateway_api() {
    local baw_namespace=$1
    local output_file=$2
    
    # GKE-specific variables
    INCLUDE_OPENSEARCH="false"
    INCLUDE_KAFKA="false"
    GATEWAY_CLASS_NAME=""
    
    # Set output directory
    output_dir=$(dirname "${output_file}")
    
    # Check prerequisites
    check_prereqs_gke_gateway
    
    # Get client ID
    get_client_id_gke_gateway
    
    # Prompt for optional components
    prompt_optional_components
    
    # Patch services
    echo ""
    info "Patching services for HTTPS backend protocol..."
    patch_services_for_https
    
    # Generate Gateway API manifest
    echo ""
    info "Generating GKE Gateway API manifest..."
    replace_gke_gateway
    
    # Set final output path
    final_output="${output_dir}/gateway-api-gke.yaml"
    
    # Only copy if source and destination are different
    if [[ "${output_file}" != "${final_output}" ]]; then
        cp "${output_file}" "${final_output}"
    fi
    
    # Summary
    echo ""
    success "GKE Gateway API resources generated successfully!"
}
