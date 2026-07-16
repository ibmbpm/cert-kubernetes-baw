#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# EKS-specific ALB Ingress generation script for BAW Standalone deployment
# This script generates native Kubernetes Ingress resources with AWS ALB Controller annotations

function check_prereqs_eks_alb() {
    info "Checking prerequisites for EKS ALB Ingress generation..."
    
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
            echo "Recommended setting for ALB:"
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
    fi
    
    # Check for AWS Load Balancer Controller
    echo ""
    info "Checking for AWS Load Balancer Controller..."
    alb_controller=$(${CLI_CMD} get deployment -n kube-system aws-load-balancer-controller 2>/dev/null)
    if [[ -z "$alb_controller" ]]; then
        warning "AWS Load Balancer Controller not found in kube-system namespace"
        echo ""
        echo "Please ensure AWS Load Balancer Controller v2.14+ is installed:"
        echo "  https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html"
        echo ""
    else
        success "AWS Load Balancer Controller found"
    fi
    
    # Check for IngressClass 'alb'
    echo ""
    info "Checking for IngressClass 'alb'..."
    alb_ingress_class=$(${CLI_CMD} get ingressclass alb 2>/dev/null)
    if [[ -z "$alb_ingress_class" ]]; then
        warning "IngressClass 'alb' not found"
        echo ""
        echo "The AWS Load Balancer Controller should create this automatically."
        echo "If missing, verify the controller installation."
        echo ""
    else
        success "IngressClass 'alb' found"
    fi
}

function prompt_iam_certificate() {
    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo "${YELLOW_TEXT}AWS IAM Certificate Configuration${RESET_TEXT}"
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    echo "For ALB to terminate TLS, you need an AWS certificate."
    echo ""
    echo "Options:"
    echo "  1. AWS Certificate Manager (ACM) - for production domains with DNS validation"
    echo "  2. AWS IAM Server Certificate - for testing domains "
    echo ""
    echo "For testing domains that cannot pass ACM DNS validation, use IAM certificates:"
    echo ""
    echo "${CYAN_TEXT}# Generate and upload IAM certificate:${RESET_TEXT}"
    echo "export DOMAIN_NAME=\"${baw_namespace}-cpd.${domain_name}\""
    echo "openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\"
    echo "  -keyout tls.key -out tls.crt \\"
    echo "  -subj \"/CN=\${DOMAIN_NAME}/O=BAW Testing\""
    echo ""
    echo "aws iam upload-server-certificate \\"
    echo "  --server-certificate-name baw-test-cert-\$(date +%s) \\"
    echo "  --certificate-body file://tls.crt \\"
    echo "  --private-key file://tls.key"
    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    
    read -rp "Enter your AWS Certificate ARN (ACM or IAM): " cert_arn
    if [[ -z "$cert_arn" ]]; then
        error "Certificate ARN is required for ALB TLS termination"
        exit 1
    fi
    
    # Validate ARN format
    if [[ ! "$cert_arn" =~ ^arn:aws:iam::[0-9]+:server-certificate/.+ ]] && \
       [[ ! "$cert_arn" =~ ^arn:aws:acm:[a-z0-9-]+:[0-9]+:certificate/.+ ]]; then
        warning "Certificate ARN format may be invalid"
        echo "Expected format:"
        echo "  IAM: arn:aws:iam::ACCOUNT_ID:server-certificate/NAME"
        echo "  ACM: arn:aws:acm:REGION:ACCOUNT_ID:certificate/ID"
        echo ""
        read -rp "Continue anyway? (yes/no): " continue_anyway
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            exit 1
        fi
    fi
}

function prompt_optional_components() {
    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo "${YELLOW_TEXT}Optional Components${RESET_TEXT}"
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    
    # Ask about OpenSearch
    read -rp "Enable OpenSearch? (yes/no, default: no): " opensearch_answer
    if [[ "$opensearch_answer" == "yes" || "$opensearch_answer" == "y" ]]; then
        INCLUDE_OPENSEARCH="true"
        
        # Get OpenSearch cluster name
        echo ""
        info "Detecting OpenSearch cluster name..."
        opensearch_cluster_name=$(${CLI_CMD} get cluster -n ${baw_namespace} -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        if [[ -z "$opensearch_cluster_name" ]]; then
            warning "Could not auto-detect OpenSearch cluster name"
            echo ""
            echo "To find your OpenSearch cluster name, run:"
            echo "  ${GREEN_TEXT}${CLI_CMD} get cluster -n ${baw_namespace}${RESET_TEXT}"
            echo ""
            echo "Press Enter without a value to skip OpenSearch."
            read -rp "Enter OpenSearch cluster name (or press Enter to skip): " opensearch_cluster_name
            if [[ -z "$opensearch_cluster_name" ]]; then
                warning "No OpenSearch cluster name provided — skipping OpenSearch ingress"
                INCLUDE_OPENSEARCH="false"
            fi
        else
            success "Detected OpenSearch cluster: ${opensearch_cluster_name}"
        fi
    else
        INCLUDE_OPENSEARCH="false"
    fi
    
    # Ask about Kafka
    echo ""
    read -rp "Enable Kafka? (yes/no, default: no): " kafka_answer
    if [[ "$kafka_answer" == "yes" || "$kafka_answer" == "y" ]]; then
        echo ""
        echo "Kafka access options:"
        echo "  1. NGINX Ingress - Traditional approach"
        echo "  2. AWS Network Load Balancer - Cloud-native (requires sc_ingress_type: loadbalancer)"
        echo ""
        read -rp "Which approach for Kafka? (nginx/nlb, default: nlb): " kafka_type
        if [[ "$kafka_type" == "nginx" ]]; then
            INCLUDE_KAFKA="nginx"
        else
            INCLUDE_KAFKA="nlb"
        fi
    else
        INCLUDE_KAFKA="false"
    fi
    
    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
}

function generate_alb_manifest() {
    local template_file=$1
    local output_file=$2
    
    info "Generating ALB Ingress manifest from template: ${template_file}"
    
    # Copy template to output file
    cp "${template_file}" "${output_file}"
    
    # Replace placeholders
    sed -i.bak "s|BAW_NAMESPACE|${baw_namespace}|g" "${output_file}"
    sed -i.bak "s|DOMAIN_NAME|${baw_namespace}-cpd.${domain_name}|g" "${output_file}"
    sed -i.bak "s|IAM_CERT_ARN|${cert_arn}|g" "${output_file}"
    sed -i.bak "s|LICENSING_NAMESPACE|${licensing_namespace}|g" "${output_file}"
    
    # Generate licensing domain (typically licensing.domain.com)
    licensing_domain="licensing.${domain_name#*.}"
    sed -i.bak "s|LICENSING_DOMAIN|${licensing_domain}|g" "${output_file}"
    
    # Replace OpenSearch cluster name if included
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        sed -i.bak "s|OPENSEARCH_CLUSTER_NAME|${opensearch_cluster_name}|g" "${output_file}"
    fi
    
    # Remove backup file
    rm -f "${output_file}.bak"
    
    success "ALB Ingress manifest generated: ${output_file}"
}

function generate_cert_manager_certificate() {
    local output_dir=$1
    local cert_file="${output_dir}/cert-manager-certificate.yaml"
    
    info "Generating cert-manager Certificate for internal TLS..."
    
    cat > "${cert_file}" <<EOF
---
# cert-manager Certificate for Internal TLS
# This creates the cpd-ingress-tls-secret required by BAW microservices
# when NGINX Ingress Controller is not present
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cpd-ingress-tls-cert
  namespace: ${baw_namespace}
spec:
  secretName: cpd-ingress-tls-secret
  issuerRef:
    name: zen-tls-issuer
    kind: Issuer
  commonName: ${baw_namespace}-cpd.${domain_name}
  dnsNames:
    - ${baw_namespace}-cpd.${domain_name}
EOF
    
    success "cert-manager Certificate generated: ${cert_file}"
}

function generate_alb_rewrite_proxy() {
    local output_dir=$1
    local proxy_file="${output_dir}/alb-rewrite-proxy.yaml"
    local proxy_template="${current_dir}/alb_rewrite_proxy_template.yaml"
    
    info "Generating ALB Rewrite Proxy manifest..."
    
    # Copy template to output file
    cp "${proxy_template}" "${proxy_file}"
    
    # Replace namespaces
    sed -i.bak "s|BAW_NAMESPACE|${baw_namespace}|g" "${proxy_file}"
    rm -f "${proxy_file}.bak"
    
    success "ALB Rewrite Proxy manifest generated: ${proxy_file}"
}

function baw_eks_generate_alb() {
    local baw_namespace=$1
    local output_file=$2
    
    check_prereqs_eks_alb
    prompt_iam_certificate
    prompt_optional_components
    
    # Determine which template to use
    local template_file
    if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
        template_file="${current_dir}/alb_ingress_template_eks_with_optional.yaml"
    else
        template_file="${current_dir}/alb_ingress_template_eks_base.yaml"
    fi
    
    if [[ ! -f "$template_file" ]]; then
        error "Template file not found: ${template_file}"
        exit 1
    fi
    
    # Create output directory
    output_dir=$(dirname "${output_file}")
    mkdir -p "${output_dir}"
    
    # Generate the ALB manifest
    generate_alb_manifest "${template_file}" "${output_file}"
    
    # Generate cert-manager Certificate
    generate_cert_manager_certificate "${output_dir}"
    
    # Generate ALB rewrite proxy
    generate_alb_rewrite_proxy "${output_dir}"
    
    # Display summary
    echo ""
    echo "${GREEN_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo "${GREEN_TEXT}ALB Ingress Generation Complete${RESET_TEXT}"
    echo "${GREEN_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    echo "  • ${GREEN_TEXT}${output_file}${RESET_TEXT}"
    echo "  • ${GREEN_TEXT}${output_dir}/cert-manager-certificate.yaml${RESET_TEXT}"
    echo "  • ${GREEN_TEXT}${output_dir}/alb-rewrite-proxy.yaml${RESET_TEXT}"
    echo ""
    
    # Show configuration notes if optional components are included
    if [[ "$INCLUDE_OPENSEARCH" == "true" || "$INCLUDE_KAFKA" == "nlb" || "$INCLUDE_KAFKA" == "nginx" ]]; then
        echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
        echo "${YELLOW_TEXT}IMPORTANT CONFIGURATION NOTES${RESET_TEXT}"
        echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
        echo ""
        
        if [[ "$INCLUDE_OPENSEARCH" == "true" ]]; then
            echo "${YELLOW_TEXT}OpenSearch:${RESET_TEXT}"
            echo "  • Ensure ICP4ACluster CR has: sc_ingress_type: gatewayapi"
            echo "  • OpenSearch Cluster CR must configure appProtocol: HTTPS via spec.patches"
            echo ""
        fi
        
        if [[ "$INCLUDE_KAFKA" == "nlb" ]]; then
            echo "${YELLOW_TEXT}Kafka (Network Load Balancer):${RESET_TEXT}"
            echo "  • Kafka uses AWS Network Load Balancers (NOT ALB)"
            echo "  • Ensure ICP4ACluster CR has: sc_ingress_type: loadbalancer"
            echo "  • Kafka CR must have: spec.kafka.listeners[].type: loadbalancer"
            echo "  • Separate DNS configuration required for each Kafka broker"
            echo ""
        elif [[ "$INCLUDE_KAFKA" == "nginx" ]]; then
            echo "${YELLOW_TEXT}Kafka (NGINX Ingress):${RESET_TEXT}"
            echo "  • Kafka will use NGINX Ingress for external access"
            echo "  • No special sc_ingress_type configuration needed for Kafka with NGINX"
            echo "  • Configure NGINX Ingress separately for Kafka access"
            echo ""
        fi
        
        echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
        echo ""
    fi
    
    info "Next steps:"
    echo ""
    echo "1. ${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} Create internal TLS secret using cert-manager"
    echo "   ${GREEN_TEXT}kubectl apply -f ${output_dir}/cert-manager-certificate.yaml${RESET_TEXT}"
    echo ""
    echo "2. Review the ALB Ingress manifest:"
    echo "   ${GREEN_TEXT}cat ${output_file}${RESET_TEXT}"
    echo ""
    echo "3. Apply the ALB Rewrite Proxy resources:"
    echo "   ${GREEN_TEXT}kubectl apply -f ${output_dir}/alb-rewrite-proxy.yaml${RESET_TEXT}"
    echo ""
    echo "4. Apply the ALB Ingress resources:"
    echo "   ${GREEN_TEXT}kubectl apply -f ${output_file}${RESET_TEXT}"
    echo ""
    echo "5. Wait for ALB provisioning (2-5 minutes):"
    echo "   ${GREEN_TEXT}kubectl get ingress zen-ingress -n ${baw_namespace} -w${RESET_TEXT}"
    echo ""
    echo "6. Get the ALB DNS name:"
    echo "   ${GREEN_TEXT}kubectl get ingress zen-ingress -n ${baw_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'${RESET_TEXT}"
    echo ""
    echo "7. Configure DNS:"
    echo "   • For production: Create CNAME record pointing to ALB DNS"
    echo "   • For testing: Use nslookup to get ALB IP and update A record"
    echo ""
    echo "8. Verify ALB routing:"
    echo "   ${CYAN_TEXT}ALB_DNS=\$(kubectl get ingress zen-ingress -n ${baw_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')${RESET_TEXT}"
    echo "   ${CYAN_TEXT}curl -k -s -o /dev/null -w '%{http_code}' https://\$ALB_DNS/ -H \"Host: ${domain_name}\"${RESET_TEXT}"
    echo ""
    echo "${GREEN_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
}

# Made with Bob