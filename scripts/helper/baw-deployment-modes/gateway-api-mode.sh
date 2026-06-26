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


# This file is a helper script used to store all functions that are used by the baw-deployment.sh when the Gateway API flag is passed
# Example : baw-deployment.sh -m generateGatewayAPITemplate -n <baw-namespace> --platform aks

#### Start - Functions being called by the generate_gateway_api_templates function ####

# function used to generate the Gateway API templates for AKS
function generate_aks_gateway_api_templates(){
    info "Generating Gateway API files required for a BAW Standalone deployment on AKS..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the Gateway API generation, make sure the ZenService CR is ready by using: kubectl get ZenService ${RESET_TEXT}"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Ensure that Gateway API is enabled on your AKS cluster and the required GatewayClass exists${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating Gateway API templates required for a BAW Standalone deployment on AKS (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "Gateway API templates for a BAW Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of Gateway API templates for a BAW Standalone deployment on AKS"
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
    source $BAW_CNCF_FOLDER/baw-generate-gateway-api-aks.sh
    rm -rf $GENERATED_GATEWAY_API_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_GATEWAY_API_FILE_FOLDER >/dev/null 2>&1
    baw_aks_generate_gateway_api "$TARGET_PROJECT_NAME" "$GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-aks.yaml"
    
    printf "\n"
    success "The Gateway API files have been created successfully at: ${GREEN_TEXT}$GENERATED_GATEWAY_API_FILE_FOLDER/${RESET_TEXT}"
    printf "\n"
    info "${YELLOW_TEXT}Next Steps:${RESET_TEXT}"
    echo "  1. Patch services with appProtocol: HTTPS (REQUIRED):"
    echo "     ${GREEN_TEXT}$GENERATED_GATEWAY_API_FILE_FOLDER/patch-services-for-gateway-api.sh${RESET_TEXT}"
    printf "\n"
    echo "  2. Review the Gateway API manifest:"
    echo "     ${GREEN_TEXT}cat $GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-aks.yaml${RESET_TEXT}"
    printf "\n"
    echo "  3. Apply the Gateway API resources:"
    echo "     ${GREEN_TEXT}kubectl apply -f $GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-aks.yaml${RESET_TEXT}"
    printf "\n"
    echo "  4. Monitor Gateway provisioning (takes 3-7 minutes):"
    echo "     ${GREEN_TEXT}kubectl get gateway baw-auth-gateway -n $TARGET_PROJECT_NAME -w${RESET_TEXT}"
    printf "\n"
    echo "  5. Configure DNS with the Gateway address"
    printf "\n"
    echo "  6. Delete the default zen-ingress to ensure everything works smoothly:"
    echo "     ${GREEN_TEXT}kubectl delete ingress zen-ingress -n $TARGET_PROJECT_NAME${RESET_TEXT}"
    printf "\n"
    exit
}

# function used to generate the Gateway API templates for GKE
function generate_gke_gateway_api_templates(){
    info "Generating Gateway API files required for a BAW Standalone deployment on GKE..."
    printf "\n"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Before proceeding with the Gateway API generation, make sure the ZenService CR is ready by using: kubectl get ZenService ${RESET_TEXT}"
    echo "${RED_TEXT}[WARNING]${RESET_TEXT}: ${YELLOW_TEXT}Ensure that Gateway API is enabled on your GKE cluster${RESET_TEXT}"
    attempt=0

    while (( attempt < 3 )); do
        read -rp "Confirm if you want to proceed with generating Gateway API templates required for a BAW Standalone deployment on GKE (Yes/No, default: No): " answer
        answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase

        if [[ -z "$answer" || "$answer" == "no" || "$answer" = "n" ]]; then
            echo "Gateway API templates for a BAW Standalone deployment will not be created. Exiting the script.."
            exit
        elif [[ "$answer" == "yes" ||  "$answer" == "y" ]]; then
            info "Proceeding with the generation of Gateway API templates for a BAW Standalone deployment on GKE"
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
    source $BAW_CNCF_FOLDER/baw-generate-gateway-api-gke.sh
    rm -rf $GENERATED_GATEWAY_API_FILE_FOLDER >/dev/null 2>&1
    mkdir -p $GENERATED_GATEWAY_API_FILE_FOLDER >/dev/null 2>&1
    baw_gke_generate_gateway_api "$TARGET_PROJECT_NAME" "$GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-gke.yaml"
    
    printf "\n"
    success "The Gateway API files have been created successfully at: ${GREEN_TEXT}$GENERATED_GATEWAY_API_FILE_FOLDER/${RESET_TEXT}"
    printf "\n"
    info "${YELLOW_TEXT}Next Steps:${RESET_TEXT}"
    echo "  1. Review the Gateway API manifest:"
    echo "     ${GREEN_TEXT}cat $GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-gke.yaml${RESET_TEXT}"
    printf "\n"
    echo "  2. Apply the Gateway API resources:"
    echo "     ${GREEN_TEXT}kubectl apply -f $GENERATED_GATEWAY_API_FILE_FOLDER/gateway-api-gke.yaml${RESET_TEXT}"
    printf "\n"
    echo "  3. Monitor Gateway provisioning:"
    echo "     ${GREEN_TEXT}kubectl get gateway baw-auth-gateway -n $TARGET_PROJECT_NAME -w${RESET_TEXT}"
    printf "\n"
    echo "  4. Configure DNS with the Gateway address"
    printf "\n"
    echo "  5. Delete the default zen-ingress to ensure everything works smoothly:"
    echo "     ${GREEN_TEXT}kubectl delete ingress zen-ingress -n $TARGET_PROJECT_NAME${RESET_TEXT}"
    printf "\n"
    exit
}

#### END - Functions being called by the generate_gateway_api_templates function ####

# The main function that calls the platform specific Gateway API generation function
function generate_gateway_api_templates(){
    if [[ "$GATEWAY_API_PLATFORM" == "aks" ]]; then
        generate_aks_gateway_api_templates
    elif [[ "$GATEWAY_API_PLATFORM" == "gke" ]]; then
        generate_gke_gateway_api_templates
    else
        error "Invalid platform specified. Supported platforms: aks, gke"
        echo ""
        echo "${YELLOW_TEXT}Note:${RESET_TEXT} For EKS, use the following command instead:"
        echo "  ./baw-deployment.sh -m generateIngress -n <namespace> --ingress eks"
        exit 1
    fi
}

# Made with Bob
