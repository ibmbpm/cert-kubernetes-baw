#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# AKS-specific Gateway API generation script for BAW Standalone deployment
# This script generates Gateway API resources using Azure Application Gateway for Containers

function check_prereqs_aks_gateway() {
    info "Checking prerequisites for AKS Gateway API generation..."
    
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
    
    # Check ICP4ACluster CR sc_ingress_type setting
    echo ""
    info "Checking ICP4ACluster CR configuration..."
    sc_ingress_type=$(${CLI_CMD} get icp4acluster -n ${baw_namespace} -o jsonpath='{.items[0].spec.shared_configuration.sc_ingress_type}' 2>/dev/null)
    if [[ -n "$sc_ingress_type" ]]; then
        if [[ "$sc_ingress_type" == "loadbalancer" ]]; then
            success "ICP4ACluster CR has sc_ingress_type set to: ${sc_ingress_type}"
        else
            warning "ICP4ACluster CR sc_ingress_type is set to: ${sc_ingress_type}"
            echo ""
            echo "Recommended setting for Gateway API:"
            echo "  sc_ingress_type: loadbalancer"
            echo ""
        fi
    else
        warning "ICP4ACluster CR does not have sc_ingress_type set"
        echo ""
        echo "${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} Update your ICP4ACluster CR with:"
        echo ""
        echo "  spec:"
        echo "    shared_configuration:"
        echo "      sc_ingress_type: loadbalancer"
        echo ""
        echo "${YELLOW_TEXT}NOTE:${RESET_TEXT} If planning to use NGINX for Kafka, you can remove sc_ingress_type: loadbalancer"
        echo ""
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            error "Exiting. Please configure sc_ingress_type in your ICP4ACluster CR first."
            exit 1
        fi
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
        echo "To enable Gateway API on AKS with azure-alb-external, run:"
        echo ""
        echo "  az aks update --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME> \\"
        echo "    --enable-gateway-api --enable-application-load-balancer"
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
    
    # Prompt for ALB resource ID (required for BYO deployment strategy)
    echo ""
    info "Configuring Application Gateway for Containers (ALB) reference..."
    echo ""
    echo "${YELLOW_TEXT}Azure ALB controller requires an annotation on the Gateway to reference${RESET_TEXT}"
    echo "${YELLOW_TEXT}the Application Gateway for Containers resource.${RESET_TEXT}"
    echo ""
    
    export NEEDS_ALB_CREATION="false"
    export ALB_NAME_TO_CREATE=""
    export ALB_SUBNET_ID_TO_CREATE=""
    
    # Try to auto-detect ALB Name from ApplicationLoadBalancer CRs
    detected_alb_name=""
    alb_cr_name=$(${CLI_CMD} get applicationloadbalancer -n "$TARGET_PROJECT_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$alb_cr_name" ]]; then
        alb_cr_name=$(${CLI_CMD} get applicationloadbalancer -A -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi
    if [[ -n "$alb_cr_name" ]]; then
        detected_alb_name="$alb_cr_name"
        echo "Detected ApplicationLoadBalancer resource:"
        echo "  ${GREEN_TEXT}${detected_alb_name}${RESET_TEXT}"
        echo ""
        read -rp "Use this ALB? (yes/no, default: yes): " use_detected
        use_detected=$(echo "$use_detected" | tr '[:upper:]' '[:lower:]')
        if [[ -z "$use_detected" || "$use_detected" == "yes" || "$use_detected" == "y" ]]; then
            ALB_NAME="$detected_alb_name"
        else
            detected_alb_name=""
        fi
    fi
    
    if [[ -z "$detected_alb_name" ]]; then
        echo "The Gateway resource requires a reference to an Application Gateway for Containers (ALB)."
        echo ""
        
        # ALB Name
        echo "No existing ApplicationLoadBalancer resources were found in the cluster."
        echo "Enter a name to use for the new Application Gateway for Containers (Traffic Controller)."
        echo "You can pick a new name (e.g., 'baw-alb') and the script will"
        echo "give you the 'kubectl' command to create it at the end."
        echo ""
        read -rp "ALB Name: " alb_name
        if [[ -z "$alb_name" ]]; then
            error "ALB Name is required. Exiting."
            exit 1
        fi
        
        ALB_NAME="$alb_name"
        
        # Subnet ID (Required for ALB creation in Azure)
        echo ""
        echo "Enter the full Azure Resource ID of the Subnet you want to use for the Application Gateway."
        echo "This subnet must be delegated to 'Microsoft.ServiceNetworking/trafficControllers'."
        echo "Format: /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>"
        echo ""
        echo "${YELLOW_TEXT}Tip: How to find your Subnet ID${RESET_TEXT}"
        echo "  ${CYAN_TEXT}Option 1 (Azure Portal):${RESET_TEXT}"
        echo "    Navigate to Virtual Networks > [Your VNet] > Subnets > click your ALB subnet > Properties > Resource ID"
        echo "  ${CYAN_TEXT}Option 2 (Azure CLI):${RESET_TEXT}"
        echo "    Run this command (no Resource Group or VNet name required!):"
        echo "    az network vnet list --query \"[].subnets[?delegations[0].serviceName=='Microsoft.ServiceNetworking/trafficControllers'].id\" -o tsv"
        echo ""
        read -rp "Subnet Resource ID: " alb_subnet_id
        
        if [[ -z "$alb_subnet_id" ]]; then
            error "Subnet Resource ID is required to provision the Application Gateway. Exiting."
            exit 1
        fi
        
        # We will need to remind the user to create the ALB
        export NEEDS_ALB_CREATION="true"
        export ALB_NAME_TO_CREATE="$alb_name"
        export ALB_SUBNET_ID_TO_CREATE="$alb_subnet_id"
    fi
    
    success "Application Gateway for Containers (ALB) reference configured."
    
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

function get_client_id_aks_gateway() {
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
    echo "Are you planning to enable OpenSearch in your BAW deployment?"
    echo ""
    echo "${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} If yes, ensure OpenSearch Cluster CR has appProtocol: HTTPS via spec.patches field:"
    echo ""
    echo "  spec:"
    echo "    patches:"
    echo "      - kind: Service"
    echo "        name: opensearch"
    echo "        patch:"
    echo "          spec:"
    echo "            ports:"
    echo "              - name: opensearch"
    echo "                port: 9200"
    echo "                appProtocol: HTTPS"
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
    echo "Are you planning to enable Kafka in your BAW deployment?"
    echo ""
    read -rp "Enable Kafka? (yes/no, default: no): " kafka_answer
    kafka_answer=$(echo "$kafka_answer" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$kafka_answer" == "yes" || "$kafka_answer" == "y" ]]; then
        INCLUDE_KAFKA="true"
        success "Kafka will be included in the configuration"
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
    
    # Patch ibm-nginx-svc:
    # - Mark the existing port 443 entry with appProtocol: HTTPS
    # - Add a second port entry at 8443 (also appProtocol: HTTPS)
    # AGC connects directly to pod endpoints bypassing kube-proxy, so it must be able to
    # reference port 8443 (the pod's actual TLS port). The HTTPRoute, BackendTLSPolicy,
    # and HealthCheckPolicy all use port 8443 for this reason.
    ${CLI_CMD} patch svc ibm-nginx-svc -n ${baw_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"},
           {"op": "add", "path": "/spec/ports/-", "value": {"name": "ibm-nginx-8443-port", "port": 8443, "protocol": "TCP", "targetPort": 8443, "appProtocol": "HTTPS"}}]' 2>/dev/null || true
    
    # Patch licensing service
    ${CLI_CMD} patch svc ibm-licensing-service-instance -n ${licensing_namespace} --type='json' \
      -p='[{"op": "add", "path": "/spec/ports/0/appProtocol", "value": "HTTPS"}]' 2>/dev/null || true
    
    # OpenSearch uses a non-headless wrapper service generated by the template (NAMESPACE-opensearch-svc).
    # The headless opensearch service is left untouched — AGC cannot use headless services as backends.
    
    success "Services patched with appProtocol: HTTPS"
}

function replace_aks_gateway() {
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Writing AKS Gateway API manifests to ${output_file}"
    
    # Select the appropriate template based on optional components
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        template_file="gateway_api_template_aks_with_optional.yaml"
    else
        template_file="gateway_api_template_aks_base.yaml"
    fi
    
    cp "${current_dir}/${template_file}" ${output_file}
    
    # Replace placeholders used in AKS templates
    # Note: Only replace placeholders that actually exist in the AKS templates.
    # Do NOT replace HOST or CLIENT_ID here - they are not used in AKS templates
    # and HOST would corrupt HTTPS strings (HOST is a substring of HTTPS).
    ${SED_COMMAND} "s|LICENSING_NS|${licensing_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|NAMESPACE|${baw_namespace}|g" ${output_file}
    ${SED_COMMAND} "s|DOMAIN|${domain_name}|g" ${output_file}
    ${SED_COMMAND} "s|GATEWAY_CLASS|${GATEWAY_CLASS_NAME}|g" ${output_file}
    ${SED_COMMAND} "s|ALB_NAME|${ALB_NAME}|g" ${output_file}
    
    # Workaround for Mac sed creating extra files
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}




function baw_aks_generate_gateway_api() {
    baw_namespace=$1
    output_file=$2
    client_id=""
    cp_console_hostname=""
    domain_name=""
    licensing_namespace=""
    
    # AKS-specific variables
    INCLUDE_OPENSEARCH="false"
    INCLUDE_KAFKA="false"
    GATEWAY_CLASS_NAME=""
    ALB_RESOURCE_ID=""

    check_prereqs_aks_gateway
    get_client_id_aks_gateway
    prompt_optional_components
    
    # Create output directory
    output_dir=$(dirname "${output_file}")
    mkdir -p "${output_dir}"
    
    # Patch services with appProtocol: HTTPS (inline, like GKE)
    echo ""
    info "Patching services for HTTPS backend protocol..."
    patch_services_for_https
    
    # Generate the main Gateway API manifest
    replace_aks_gateway
    
    echo ""
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "AKS Gateway API manifests created successfully!"
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "Generated files:"
    echo "  1. Gateway API manifest: ${GREEN_TEXT}${output_file}${RESET_TEXT}"
    echo ""
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Made with Bob