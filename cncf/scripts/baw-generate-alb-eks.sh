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
    # Clean up stale temp files from any previous run to avoid using old certs
    rm -f /tmp/tls.crt /tmp/tls.key

    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo "${YELLOW_TEXT}AWS Certificate Configuration${RESET_TEXT}"
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    echo "For ALB to terminate TLS, an AWS Certificate ARN (ACM or IAM) is required."
    echo ""
    echo "The script will auto-generate a server certificate signed by the cluster's"
    echo "trusted root CA (icp4a-root-ca) so that PFS operator natively trusts it."
    echo ""
    echo "${CYAN_TEXT}# Manual command to generate a CA-signed IAM certificate:${RESET_TEXT}"
    echo "export NAMESPACE=\"${baw_namespace}\""
    echo "export DOMAIN_NAME=\"${baw_namespace}-cpd.${domain_name}\""
    echo ""
    echo "${CYAN_TEXT}# Extract the cluster root CA${RESET_TEXT}"
    echo "kubectl get secret icp4a-root-ca -n \${NAMESPACE} -o jsonpath='{.data.tls\\.crt}' | base64 -d > ca.crt"
    echo "kubectl get secret icp4a-root-ca -n \${NAMESPACE} -o jsonpath='{.data.tls\\.key}' | base64 -d > ca.key"
    echo ""
    echo "${CYAN_TEXT}# Generate server cert signed by icp4a-root-ca${RESET_TEXT}"
    echo "cat > san.conf <<SANEOF"
    echo "[req]"
    echo "default_bits = 2048"
    echo "prompt = no"
    echo "default_md = sha256"
    echo "distinguished_name = dn"
    echo "req_extensions = v3_req"
    echo "[dn]"
    echo "CN=\${DOMAIN_NAME}"
    echo "O=BAW Testing"
    echo "[v3_req]"
    echo "subjectAltName = DNS:\${DOMAIN_NAME}"
    echo "SANEOF"
    echo "openssl req -new -newkey rsa:2048 -nodes -keyout tls.key -out server.csr -config san.conf"
    echo "openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial \\"
    echo "  -out tls.crt -days 365 -extensions v3_req -extfile san.conf"
    echo ""
    echo "aws iam upload-server-certificate \\"
    echo "  --server-certificate-name baw-test-cert-\$(date +%s) \\"
    echo "  --certificate-body file://tls.crt \\"
    echo "  --private-key file://tls.key"
    echo ""
    echo "${YELLOW_TEXT}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET_TEXT}"
    echo ""
    read -rp "Enter your AWS Certificate ARN (or press Enter to auto-generate a test IAM cert): " cert_arn

    if [[ -z "$cert_arn" ]]; then
        local cert_domain="${baw_namespace}-cpd.${domain_name}"
        local cert_name="baw-test-cert-$(date +%s)"
        local san_conf
        san_conf=$(mktemp /tmp/san.conf.XXXXXX)
        local ca_signed="false"

        # Try to use the cluster trusted root CA (icp4a-root-ca) to sign the server cert.
        # This is REQUIRED for PFS operator to natively trust the ALB certificate.
        if ${CLI_CMD} get secret icp4a-root-ca -n "${baw_namespace}" &>/dev/null; then
            info "Found icp4a-root-ca secret. Generating server certificate signed by cluster root CA..."
            local ca_crt
            local ca_key
            ca_crt=$(mktemp /tmp/ca.crt.XXXXXX)
            ca_key=$(mktemp /tmp/ca.key.XXXXXX)
            ${CLI_CMD} get secret icp4a-root-ca -n "${baw_namespace}" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${ca_crt}" 2>/dev/null || true
            ${CLI_CMD} get secret icp4a-root-ca -n "${baw_namespace}" -o jsonpath='{.data.tls\.key}' | base64 -d > "${ca_key}" 2>/dev/null || true

            if [[ -s "${ca_crt}" && -s "${ca_key}" ]]; then
                cat > "${san_conf}" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req
[dn]
CN=${cert_domain}
O=BAW Testing
[v3_req]
subjectAltName = DNS:${cert_domain}
EOF
                local server_csr
                server_csr=$(mktemp /tmp/server.csr.XXXXXX)
                openssl req -new -newkey rsa:2048 -nodes -keyout /tmp/tls.key -out "${server_csr}" -config "${san_conf}" 2>/dev/null
                if openssl x509 -req -in "${server_csr}" -CA "${ca_crt}" -CAkey "${ca_key}" -CAcreateserial \
                    -out /tmp/tls.crt -days 365 -extensions v3_req -extfile "${san_conf}" 2>/dev/null; then
                    ca_signed="true"
                    success "Server certificate signed by cluster root CA (icp4a-root-ca)"
                    # Verify the cert was signed correctly
                    local issuer
                    issuer=$(openssl x509 -in /tmp/tls.crt -noout -issuer 2>/dev/null)
                    info "Certificate issuer: ${issuer}"
                fi
                rm -f "${server_csr}" "${ca_crt}" "${ca_key}" "${san_conf}"
            else
                warning "icp4a-root-ca secret exists but tls.crt or tls.key is empty"
                rm -f "${ca_crt}" "${ca_key}"
            fi
        else
            warning "icp4a-root-ca secret not found in namespace ${baw_namespace}"
            echo ""
            echo "${YELLOW_TEXT}NOTE: The icp4a-root-ca secret may not have been created yet.${RESET_TEXT}"
            echo "${YELLOW_TEXT}If you just deployed the namespace, wait for the CP4BA operator to create it,${RESET_TEXT}"
            echo "${YELLOW_TEXT}then re-run this script.${RESET_TEXT}"
            echo ""
        fi

        # Fallback: self-signed cert (will NOT be trusted by PFS operator)
        if [[ ! -s /tmp/tls.crt || ! -s /tmp/tls.key ]]; then
            echo ""
            warning "================================================================"
            warning "FALLING BACK TO SELF-SIGNED CERTIFICATE"
            warning "================================================================"
            warning "PFS operator will NOT trust this certificate because it is not"
            warning "signed by icp4a-root-ca. This means:"
            warning "  - Secret 'bawdeploy-bawins1-baw' will NOT be created"
            warning "  - PFS federated system probe will fail with TLS errors"
            warning ""
            warning "To fix this later, re-run the script after icp4a-root-ca exists,"
            warning "or manually generate a CA-signed cert using the instructions above."
            warning "================================================================"
            echo ""
            read -rp "Continue with self-signed certificate? (yes/no, default: no): " self_signed_continue
            if [[ "$self_signed_continue" != "yes" && "$self_signed_continue" != "y" ]]; then
                info "Aborting. Please wait for icp4a-root-ca to be available and re-run."
                exit 0
            fi

            info "Generating self-signed SAN certificate for: ${cert_domain}"
            cat > "${san_conf}" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req
[dn]
CN=${cert_domain}
O=BAW Testing
[v3_req]
subjectAltName = DNS:${cert_domain}
EOF
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /tmp/tls.key -out /tmp/tls.crt \
                -config "${san_conf}" -extensions v3_req 2>/dev/null
            rm -f "${san_conf}"
        fi

        if [[ ! -s /tmp/tls.crt ]]; then
            error "openssl failed to generate certificate"
            exit 1
        fi
        success "Certificate generated: /tmp/tls.crt"

        info "Uploading certificate to AWS IAM as: ${cert_name}"
        aws iam upload-server-certificate \
            --server-certificate-name "${cert_name}" \
            --certificate-body file:///tmp/tls.crt \
            --private-key file:///tmp/tls.key

        if [[ $? -ne 0 ]]; then
            error "Failed to upload certificate to AWS IAM"
            exit 1
        fi

        # Fetch the ARN automatically
        cert_arn=$(aws iam get-server-certificate \
            --server-certificate-name "${cert_name}" \
            --query 'ServerCertificate.ServerCertificateMetadata.Arn' \
            --output text 2>/dev/null)

        if [[ -z "$cert_arn" ]]; then
            error "Could not retrieve certificate ARN after upload"
            exit 1
        fi
        success "Certificate uploaded. ARN: ${cert_arn}"

        if [[ "$ca_signed" == "true" ]]; then
            success "This certificate is signed by icp4a-root-ca and will be natively trusted by PFS operator"
        else
            warning "This is a self-signed certificate. PFS operator will NOT trust it."
            warning "Re-run this script after icp4a-root-ca is available to generate a trusted certificate."
        fi
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
    opensearch_answer="${opensearch_answer,,}"
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
    kafka_answer="${kafka_answer,,}"
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
    sed -i.bak "s|CLIENT_ID|${client_id}|g" "${output_file}"
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
    
    # Extract OIDC CLIENT_ID for ingress redirect_uri substitution
    info "Retrieving OIDC CLIENT_ID..."
    local client_id
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${baw_namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z "$client_id" ]]; then
        warning "Cannot retrieve CLIENT_ID from ibm-iam-bindinfo-platform-oidc-credentials secret."
        warning "Check if the BAW Standalone Custom Resource is marked as ready."
        warning "Using placeholder CLIENT_ID - you will need to update it manually in the generated ingress."
        client_id="CLIENT_ID_PLACEHOLDER"
    else
        success "OIDC CLIENT_ID retrieved: ${client_id}"
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
            echo "  • Ensure ICP4ACluster CR has: sc_ingress_type: loadbalancer"
            echo "  • OpenSearch Cluster CR must configure appProtocol: HTTPS via spec.patches"
            echo "  • To patch ICP4ACluster CR:"
            echo "    ${GREEN_TEXT}kubectl patch icp4acluster \$(kubectl get icp4acluster -n ${baw_namespace} -o jsonpath='{.items[0].metadata.name}') \\"
            echo "      -n ${baw_namespace} --type=merge \\"
            echo "      -p '{\"spec\":{\"shared_configuration\":{\"sc_ingress_type\":\"loadbalancer\"}}}'${RESET_TEXT}"
            echo ""
        fi
        
        if [[ "$INCLUDE_KAFKA" == "nlb" ]]; then
            echo "${YELLOW_TEXT}Kafka (Network Load Balancer):${RESET_TEXT}"
            echo "  • Kafka uses AWS Network Load Balancers (NOT ALB)"
            echo "  • Ensure ICP4ACluster CR has: sc_ingress_type: loadbalancer"
            echo "  • Kafka CR must have: spec.kafka.listeners[].type: loadbalancer"
            echo "  • Separate DNS configuration required for each Kafka broker"
            echo "  • To patch ICP4ACluster CR:"
            echo "    ${GREEN_TEXT}kubectl patch icp4acluster \$(kubectl get icp4acluster -n ${baw_namespace} -o jsonpath='{.items[0].metadata.name}') \\"
            echo "      -n ${baw_namespace} --type=merge \\"
            echo "      -p '{\"spec\":{\"shared_configuration\":{\"sc_ingress_type\":\"loadbalancer\"}}}'${RESET_TEXT}"
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
    echo "4. Delete the existing zen-ingress (ALB will provision its own):"
    echo "   ${GREEN_TEXT}kubectl delete ingress zen-ingress -n ${baw_namespace}${RESET_TEXT}"
    echo ""
    echo "5. Apply the ALB Ingress resources:"
    echo "   ${GREEN_TEXT}kubectl apply -f ${output_file}${RESET_TEXT}"
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