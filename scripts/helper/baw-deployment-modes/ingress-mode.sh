#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2025. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################


# This file is a helper script used to store all functions that are used by the baw-deployment.sh when the ingress flag is passed
# Example : baw-deployment.sh -m generateIngress--ingress rancher -n <baw-namespace>

#### Start - Functions being called by the generate_ingress_templates function ####

# function used to generate the ingress templates for rancher
function generate_cncf_ingress_templates(){
    local tls_enable="$1"
    info "Generating Ingress files required for a BAW Standalone deployment..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the ingress generation, make sure the ZenService CR is ready by using: kubectl get ZenService ${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating ingress templates required for a BAW Standalone deployment (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "Ingress templates for a BAW Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of Ingress templates for a BAW Standalone deployment"
            break
        else
            echo "Invalid input. Please enter 'yes' or 'no'."
        fi

        ((attempt++))
    done
    if [[ "$attempt" == 3 ]]; then
        error "maximum number of incorrect answers exceeded, exiting..."
        exit
    fi
    source $BAW_CNCF_FOLDER/baw-utils.sh
    source $BAW_CNCF_FOLDER/baw-generate-ingress.sh
    rm -rf $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    baw_cncf_generate_ingress "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml" "$tls_enable"
    
    printf "\n"
    success "The ingress file has been created successfully at: ${GREEN_TEXT}$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml${RESET_TEXT}"
    
    if [[ "$tls_enable" = true ]]; then
        success "Certificate CR has been created at: ${GREEN_TEXT}$GENERATED_INGRESS_FILE_FOLDER/cpd-tls-certificate.yaml${RESET_TEXT}"
        printf "\n"
        info "${YELLOW_TEXT}TLS Secret Setup:${RESET_TEXT}"
        echo "  ✓ Certificate CR has been applied"
        echo "  ✓ TLS secret (cpd-ingress-tls-secret) has been created by cert-manager"
        echo "  ✓ Certificate chain has been updated with full chain (leaf + CA)"
        printf "\n"
        info "${YELLOW_TEXT}Next Steps:${RESET_TEXT}"
        echo "  1. Review and apply the ingress YAML:"
        echo "     ${GREEN_TEXT}kubectl apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml${RESET_TEXT}"
        printf "\n"
        echo "  2. Verify the certificate chain (should show 2 certificates):"
        echo "     ${GREEN_TEXT}kubectl get secret cpd-ingress-tls-secret -n $TARGET_PROJECT_NAME -o jsonpath='{.data.tls\.crt}' | base64 -d | grep -c \"BEGIN CERTIFICATE\"${RESET_TEXT}"
        printf "\n"
    else
        printf "\n"
        info "After reviewing the file, apply the yaml file using the command:"
        echo "  ${GREEN_TEXT}kubectl apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml${RESET_TEXT}"
        printf "\n"
    fi
    exit
}

#### END - Functions being called by the generate_ingress_templates function ####

# function used to generate the ingress templates for GKE
function generate_gke_ingress_templates(){
    info "Generating GKE Ingress files required for a BAW Standalone deployment..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the ingress generation, make sure the ZenService CR is ready by using: kubectl get ZenService ${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating GKE ingress templates required for a BAW Standalone deployment (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "GKE Ingress templates for a BAW Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of GKE Ingress templates for a BAW Standalone deployment"
            break
        else
            echo "Invalid input. Please enter 'yes' or 'no'."
        fi

        ((attempt++))
    done
    if [[ "$attempt" == 3 ]]; then
        error "maximum number of incorrect answers exceeded, exiting..."
        exit
    fi
    
    # Ask if user wants to use NGINX ingress (default is GCE)
    printf "\n"
    info "By default, GKE uses GCE ingress (Google Cloud's native L7 load balancer)."
    info "Alternatively, you can use NGINX ingress controller for more flexible configuration."
    printf "\n"
    
    ingress_type="gce"  # Default to GCE
    attempt=0
    
    while (( attempt < 3 )); do
        read -rp "Do you want to use NGINX ingress? (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        if [[ -z "$answer" || "$answer" == "no" || "$answer" == "n" ]]; then
            ingress_type="gce"
            info "Using GCE ingress (default)"
            break
        elif [[ "$answer" == "yes" || "$answer" == "y" ]]; then
            ingress_type="nginx"
            info "Using NGINX ingress"
            break
        else
            echo "Invalid input. Please enter 'yes' or 'no'."
        fi
        
        ((attempt++))
    done
    
    if [[ "$attempt" == 3 ]]; then
        error "Maximum number of incorrect answers exceeded, exiting..."
        exit 1
    fi
    
    printf "\n"
    
    source $BAW_CNCF_FOLDER/baw-utils.sh
    rm -rf $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    
    if [[ "$ingress_type" == "gce" ]]; then
        source $BAW_CNCF_FOLDER/baw-generate-ingress-gke.sh
        baw_gke_generate_ingress "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/ingress_gke.yaml"
        success "The GKE ingress file has been created successfully. After reviewing the file, apply the yaml file using the command ${GREEN_TEXT}\"kubectl apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_gke.yaml\"${RESET_TEXT}"
    elif [[ "$ingress_type" == "nginx" ]]; then
        source $BAW_CNCF_FOLDER/baw-generate-ingress.sh
        baw_cncf_generate_ingress "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml" "true"
        success "The NGINX ingress file has been created successfully. After reviewing the file, apply the yaml file using the command ${GREEN_TEXT}\"kubectl apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml\"${RESET_TEXT}"
    fi
    
    exit
}

# Function to generate EKS ingress templates with NGINX or ALB choice
function generate_eks_ingress_templates(){
    info "Generating EKS Ingress files required for a BAW Standalone deployment..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the ingress generation, make sure the ZenService CR is ready by using: kubectl get ZenService ${RESET_TEXT}"
    
    # Ask user to choose between NGINX and ALB
    echo ""
    info "Select the ingress controller type for EKS:"
    echo "  1. NGINX Ingress Controller"
    echo "  2. AWS Application Load Balancer (ALB)"
    echo ""
    
    attempt=0
    while (( attempt < 3 )); do
        read -rp "Enter your choice (1 for NGINX, 2 for ALB): " choice
        
        case "$choice" in
            1)
                info "Selected: NGINX Ingress Controller"
                EKS_INGRESS_TYPE="nginx"
                break
                ;;
            2)
                info "Selected: AWS Application Load Balancer (ALB)"
                EKS_INGRESS_TYPE="alb"
                break
                ;;
            *)
                echo "Invalid input. Please enter 1 or 2."
                ((attempt++))
                ;;
        esac
    done
    
    if [[ "$attempt" == 3 ]]; then
        error "Maximum number of incorrect answers exceeded, exiting..."
        exit 1
    fi
    
    # Confirm before proceeding
    attempt=0
    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating EKS ingress templates (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
        
        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "EKS Ingress templates will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of EKS Ingress templates"
            break
        else
            echo "Invalid input. Please enter 'yes' or 'no'."
        fi
        
        ((attempt++))
    done
    
    if [[ "$attempt" == 3 ]]; then
        error "Maximum number of incorrect answers exceeded, exiting..."
        exit 1
    fi
    
    source $BAW_CNCF_FOLDER/baw-utils.sh
    rm -rf $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_INGRESS_FILE_FOLDER >/dev/null 2>&1
    
    if [[ "$EKS_INGRESS_TYPE" == "nginx" ]]; then
        # Generate NGINX ingress
        source $BAW_CNCF_FOLDER/baw-generate-ingress.sh
        baw_cncf_generate_ingress "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml" "true"
        
        printf "\n"
        success "The NGINX ingress file has been created successfully at: ${GREEN_TEXT}$GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml${RESET_TEXT}"
        success "Certificate CR has been created at: ${GREEN_TEXT}$GENERATED_INGRESS_FILE_FOLDER/cpd-tls-certificate.yaml${RESET_TEXT}"
        printf "\n"
        info "${YELLOW_TEXT}Next Steps:${RESET_TEXT}"
        echo "  1. Review and apply the ingress YAML:"
        echo "     ${GREEN_TEXT}kubectl apply -f $GENERATED_INGRESS_FILE_FOLDER/ingress_nginx.yaml${RESET_TEXT}"
        printf "\n"
    else
        # Generate ALB ingress
        source $BAW_CNCF_FOLDER/baw-generate-alb-eks.sh
        baw_eks_generate_alb "$TARGET_PROJECT_NAME" "$GENERATED_INGRESS_FILE_FOLDER/alb-ingress-eks.yaml"
        
        printf "\n"
        success "The ALB ingress file has been created successfully at: ${GREEN_TEXT}$GENERATED_INGRESS_FILE_FOLDER/alb-ingress-eks.yaml${RESET_TEXT}"
        printf "\n"
    fi
    
    exit
}

# The main function that calls the platform specific ingress generation function
function generate_ingress_templates(){
    tls_enable=$1
    if [[ "$INGRESS_MODE" == "tanzu" ]]; then
        generate_cncf_ingress_templates "$tls_enable"
    elif [[ "$INGRESS_MODE" == "rancher"  ]]; then
        generate_cncf_ingress_templates "$tls_enable"
    elif [[ "$INGRESS_MODE" == "gke"  ]]; then
        generate_gke_ingress_templates
    elif [[ "$INGRESS_MODE" == "eks"  ]]; then
        generate_eks_ingress_templates
    elif [[ "$INGRESS_MODE" == "aks"  ]]; then
        generate_cncf_ingress_templates "$tls_enable"
    fi
}