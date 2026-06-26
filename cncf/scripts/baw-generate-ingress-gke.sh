#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

# GKE-specific ingress generation script for BAW Standalone deployment
# This script generates ingress resources using GKE's built-in GCE Ingress Controller

function check_prereqs_gke() {
    info "Checking prerequisites for GKE ingress generation..."
    
    licensing_namespace=$(${CLI_CMD} get sub -A 2>/dev/null | grep ibm-licensing-operator-app | cut -d ' ' -f1)

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
    
    # Check if running on GKE
    info "Verifying GKE environment..."
    if ! ${CLI_CMD} get ingressclass gce >/dev/null 2>&1; then
        warning "GCE IngressClass not found. This might not be a GKE cluster."
        echo ""
        echo "To create the GCE IngressClass, run:"
        echo ""
        echo "kubectl apply -f - <<EOF"
        echo "apiVersion: networking.k8s.io/v1"
        echo "kind: IngressClass"
        echo "metadata:"
        echo "  name: gce"
        echo "spec:"
        echo "  controller: k8s.io/ingress-gce"
        echo "EOF"
        echo ""
        read -rp "Do you want to continue anyway? (yes/no, default: no): " continue_anyway
        continue_anyway=$(echo "$continue_anyway" | tr '[:upper:]' '[:lower:]')
        if [[ "$continue_anyway" != "yes" && "$continue_anyway" != "y" ]]; then
            error "Exiting. Please create the GCE IngressClass first or run this script on a GKE cluster."
            exit 1
        fi
    else
        success "GCE IngressClass found. Running on GKE cluster."
    fi
}

function get_client_id_gke() {
    client_id=$(${CLI_CMD} get secret ibm-iam-bindinfo-platform-oidc-credentials -n ${baw_namespace} -o jsonpath='{.data.WLP_CLIENT_ID}' 2>/dev/null | base64 --decode)
    if [[ -z ${client_id} ]]; then
        error "Cannot retrieve client_ID from ibm-iam-bindinfo-platform-oidc-credential secret. Check if the BAW Standalone Custom Resource file has the status marked as ready."
        exit 1
    fi
}

function prompt_gke_options() {
    echo ""
    info "GKE Ingress Configuration Options"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ask about static IP
    echo "1. Static IP Configuration"
    echo "   GKE can use a reserved static IP address for your ingress."
    echo "   This ensures your IP address doesn't change if you recreate the ingress."
    echo ""
    echo "   ${YELLOW_TEXT}Note: Static IP is OPTIONAL. Your ingress will work fine without it.${RESET_TEXT}"
    echo "   ${YELLOW_TEXT}Without static IP, GKE assigns an ephemeral IP automatically.${RESET_TEXT}"
    echo ""
    read -rp "   Do you want to use a static IP? (yes/no, default: no): " use_static_ip
    use_static_ip=$(echo "$use_static_ip" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$use_static_ip" == "yes" || "$use_static_ip" == "y" ]]; then
        echo ""
        echo "   You can create a static IP using:"
        echo "   ${GREEN_TEXT}gcloud compute addresses create baw-static-ip --global${RESET_TEXT}"
        echo ""
        read -rp "   Enter the name of your static IP (or press Enter to skip): " static_ip_name
        if [[ -n "$static_ip_name" ]]; then
            USE_STATIC_IP="true"
            STATIC_IP_NAME="$static_ip_name"
            success "   Will use static IP: $static_ip_name"
        else
            USE_STATIC_IP="false"
            info "   Skipping static IP configuration"
        fi
    else
        USE_STATIC_IP="false"
        info "   Will use ephemeral IP address (assigned automatically by GKE)"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Ask about Google-managed certificates
    echo "2. SSL/TLS Certificate Configuration"
    echo "   GKE can automatically provision and manage SSL certificates for your domain."
    echo "   This requires:"
    echo "   - A registered domain name"
    echo "   - DNS A record pointing to the ingress IP"
    echo "   - Certificate provisioning takes 15-60 minutes"
    echo ""
    echo "   ${YELLOW_TEXT}Note: You can also manage certificates manually using cert-manager.${RESET_TEXT}"
    echo ""
    read -rp "   Do you want to use Google-managed SSL certificates? (yes/no, default: no): " use_managed_cert
    use_managed_cert=$(echo "$use_managed_cert" | tr '[:upper:]' '[:lower:]')
    
    if [[ "$use_managed_cert" == "yes" || "$use_managed_cert" == "y" ]]; then
        echo ""
        read -rp "   Enter your domain name (e.g., baw.example.com): " cert_domain
        if [[ -n "$cert_domain" ]]; then
            USE_MANAGED_CERT="true"
            CERT_DOMAIN="$cert_domain"
            success "   Will create managed certificate for: $cert_domain"
            echo ""
            info "   ${YELLOW_TEXT}IMPORTANT:${RESET_TEXT} After applying the ingress:"
            echo "   1. Get the ingress IP: ${GREEN_TEXT}kubectl get ingress -n ${baw_namespace}${RESET_TEXT}"
            echo "   2. Create DNS A record pointing $cert_domain to that IP"
            echo "   3. Wait 15-60 minutes for certificate provisioning"
            echo "   4. Check status: ${GREEN_TEXT}kubectl describe managedcertificate -n ${baw_namespace}${RESET_TEXT}"
        else
            USE_MANAGED_CERT="false"
            info "   Skipping managed certificate configuration"
        fi
    else
        USE_MANAGED_CERT="false"
        info "   Will not configure managed certificates"
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

function replace_gke() {
    if [[ -z ${output_file} ]]; then
        output_file=$(mktemp)
    fi

    info "Writing GKE ingress manifests to ${output_file}"
    cp "${current_dir}/ingress_template_gke.yaml" ${output_file}
    
    # Basic replacements
    ${SED_COMMAND} "s/NAMESPACE/${baw_namespace}/g" ${output_file}
    ${SED_COMMAND} "s/HOST/${cp_console_hostname}/g" ${output_file}
    ${SED_COMMAND} "s/DOMAIN/${domain_name}/g" ${output_file}
    ${SED_COMMAND} "s/CLIENT_ID/${client_id}/g" ${output_file}
    ${SED_COMMAND} "s/LICENSING_NS/${licensing_namespace}/g" ${output_file}

    # Add static IP annotation to zen-ingress only if configured
    if [[ "$USE_STATIC_IP" == "true" && -n "$STATIC_IP_NAME" ]]; then
        info "Static IP will be configured on zen-ingress"
        # Note: Static IP annotation will be added to zen-ingress in the next section
    fi
    
    # Add managed certificate if configured
    if [[ "$USE_MANAGED_CERT" == "true" && -n "$CERT_DOMAIN" ]]; then
        info "Adding managed certificate configuration"
        
        # Append ManagedCertificate resource
        cat >> ${output_file} << EOF

---
apiVersion: networking.gke.io/v1
kind: ManagedCertificate
metadata:
  name: baw-managed-cert
  namespace: ${baw_namespace}
spec:
  domains:
    - ${CERT_DOMAIN}
EOF
    fi

    # Add zen ingress with GKE-specific configurations
    echo "" >> ${output_file}
    echo "---" >> ${output_file}

    tmp_zen_ingress=$(mktemp)

    if ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} >/dev/null 2>&1; then
        # Get existing zen-ingress and modify it
        ${CLI_CMD} get ingress zen-ingress -n ${baw_namespace} -o yaml | \
        ${CLI_CMD} patch -f - -p '{"metadata":{"creationTimestamp": null, "generation": null, "ownerReferences": null, "resourceVersion": null, "uid": null}, "status":null}' --type=merge --dry-run='client' -o yaml | \
        ${CLI_CMD} patch -f - -p '{"spec":{"ingressClassName":"gce"}}' --type=merge --dry-run='client' -o yaml | \
        ${CLI_CMD} patch -f - -p '{"metadata":{"annotations":{"kubernetes.io/ingress.class":null}}}' --type=merge --dry-run='client' -o yaml \
        > ${tmp_zen_ingress}
        
        # Add static IP annotation if configured
        if [[ "$USE_STATIC_IP" == "true" && -n "$STATIC_IP_NAME" ]]; then
            ${CLI_CMD} patch -f ${tmp_zen_ingress} -p '{"metadata":{"annotations":{"kubernetes.io/ingress.global-static-ip-name":"'${STATIC_IP_NAME}'"}}}' --type=merge --dry-run='client' -o yaml > ${tmp_zen_ingress}.new
            mv ${tmp_zen_ingress}.new ${tmp_zen_ingress}
        fi
        
        # Add managed certificate annotation if configured
        if [[ "$USE_MANAGED_CERT" == "true" ]]; then
            ${CLI_CMD} patch -f ${tmp_zen_ingress} -p '{"metadata":{"annotations":{"networking.gke.io/managed-certificates":"baw-managed-cert"}}}' --type=merge --dry-run='client' -o yaml > ${tmp_zen_ingress}.new
            mv ${tmp_zen_ingress}.new ${tmp_zen_ingress}
        fi
    else
        info "zen-ingress not found in namespace ${baw_namespace}. Skipping."
    fi

    cat ${tmp_zen_ingress} >> ${output_file}
    rm ${tmp_zen_ingress}
    
    # Workaround for Mac sed creating extra files
    if [[ -f "$output_file\"\"" ]]; then
        rm -f "${output_file}\"\"" 2>/dev/null
    fi
}

function baw_gke_generate_ingress() {
    baw_namespace=$1
    output_file=$2
    client_id=""
    cp_console_hostname=""
    domain_name=""
    licensing_namespace=""
    
    # GKE-specific variables
    USE_STATIC_IP="false"
    STATIC_IP_NAME=""
    USE_MANAGED_CERT="false"
    CERT_DOMAIN=""

    check_prereqs_gke
    get_client_id_gke
    prompt_gke_options
    
    template_file="ingress_template_gke.yaml"
    replace_gke
    
    echo ""
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    success "GKE Ingress file created successfully!"
    success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "File location: ${GREEN_TEXT}${output_file}${RESET_TEXT}"
    echo ""
    info "Next steps:"
    echo "1. Review the generated file: ${GREEN_TEXT}cat ${output_file}${RESET_TEXT}"
    echo "2. Apply the ingress: ${GREEN_TEXT}kubectl apply -f ${output_file}${RESET_TEXT}"
    echo "3. Get the ingress IP: ${GREEN_TEXT}kubectl get ingress zen-ingress -n ${baw_namespace} -o jsonpath='{.status.loadBalancer.ingress[0].ip}'${RESET_TEXT}"
    echo "4. Create DNS A record pointing your domain to the ingress IP"
    
    if [[ "$USE_STATIC_IP" == "true" ]]; then
        echo ""
        info "${YELLOW_TEXT}Static IP Configuration:${RESET_TEXT}"
        echo "   - Verify static IP exists: ${GREEN_TEXT}gcloud compute addresses describe ${STATIC_IP_NAME} --global${RESET_TEXT}"
        echo "   - The static IP is configured on zen-ingress"
    fi
    
    if [[ "$USE_MANAGED_CERT" == "true" ]]; then
        echo ""
        info "${YELLOW_TEXT}Managed Certificate Configuration:${RESET_TEXT}"
        echo "   - Create DNS A record pointing ${CERT_DOMAIN} to the ingress IP"
        echo "   - Wait 15-60 minutes for certificate provisioning"
        echo "   - Check certificate status: ${GREEN_TEXT}kubectl describe managedcertificate baw-managed-cert -n ${baw_namespace}${RESET_TEXT}"
    fi
    
    echo ""
    info "${YELLOW_TEXT}Important Notes:${RESET_TEXT}"
    echo "   - GKE Ingress provisions a Google Cloud HTTP(S) Load Balancer (Layer 7)"
    echo "   - It may take 5-10 minutes for the load balancer to be fully provisioned"
    echo "   - Health checks are automatically configured"
    echo "   - Monitor ingress events: ${GREEN_TEXT}kubectl describe ingress -n ${baw_namespace}${RESET_TEXT}"
    echo ""
}

# Made with Bob
