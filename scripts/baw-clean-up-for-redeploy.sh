#!/bin/bash
#set -x
###############################################################################
#
# Licensed Materials - Property of IBM
# (C) Copyright IBM Corp. 2023. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
# Import common utilities and environment variables
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CLI_CMD=""
PLATFORM_SELECTED=""
IS_EMBEDDED_DB=""
CLEAN_PVC=""
CLEAN_SECRET=""
delete_pvc_cm_secrets_flag=false
uninstall_BAW_operators_flag=false
source ${CUR_DIR}/helper/common.sh

#Options
HELP=false
DEV=false


# Function to check which platform is to be used for deletion, based on this the CLI_CMD is different
function select_platform(){
    printf "\n"
    # clear
    COLUMNS=12
    echo -e "\x1B[1mSelect the cloud platform where BAW Standalone has been deployed: \x1B[0m"

    # Adding the Rancher / Tanzu option
    # DBACLD-168151
    otherOption="Other - Cloud Native Computing Foundation ( CNCF )"
    options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "$otherOption")
    PS3='Enter a valid option [1 to 3]: '
    

    # if [[ "${SCRIPT_MODE}" == "OLM" ]]; then
    #     options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
    #     PS3='Enter a valid option [1 to 2]: '
    # else
    #     options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
    #     PS3='Enter a valid option [1 to 3]: '
    # fi


    # Adding the Rancher / Tanzu option
    # DBACLD-168151
    select opt in "${options[@]}"
    do
        case $opt in
            "RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud")
                PLATFORM_SELECTED="ROKS"
                break
                ;;
            "Openshift Container Platform (OCP) - Private Cloud")
                PLATFORM_SELECTED="OCP"
                break
                ;;
            "$otherOption")
                PLATFORM_SELECTED="other"
                break
                ;;
            *) echo "invalid option $REPLY";;
        esac
    done
    
    
    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        CLI_CMD=oc
    elif [[ "$PLATFORM_SELECTED" == "other" ]]; then
        CLI_CMD=kubectl
    fi
}

function select_db_type() {
    # Get Operand namespace from user
    if [ -z "$IS_EMBEDDED_DB" ]; then
        max_retries=0 
        while [ $max_retries -lt 4 ]; do
            echo -e "\x1B[33;5m\nATTENTION: \x1B[0m\x1B[1;31mMake sure you backup your embedded db data before proceeding. \x1B[0m"
            printf "\x1B[1m\nDid you clean deploy BAW with embedded database? (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            # If the user provides no input, set the default to 'No'
            if [ -z "$ans" ]; then
                IS_EMBEDDED_DB="No"
            fi

            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
            case "$ans" in
                "y"|"yes"|"")
                    IS_EMBEDDED_DB="Yes"
                    break
                ;;
                "n"|"no")
                    IS_EMBEDDED_DB="No"
                    break
                ;;
                *)
                error "Answer must be 'Yes' or 'No'"
                max_retries=$(($max_retries + 1))
            esac
        done
        if [[ $max_retries == 4 ]]; then
            error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
            exit
        fi
    fi
}

function clean_pvc() {
    # Get Operand namespace from user
    if [ -z "$CLEAN_PVC" ]; then
        max_retries=0 
        while [ $max_retries -lt 4 ]; do
            echo -e "\x1B[33;5m\nATTENTION: \x1B[0m\x1B[1;31mMake sure you backup your PVC data . \x1B[0m"
            printf "\x1B[1m\nDo you want to clean all PVC? (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            # If the user provides no input, set the default to 'No'
            if [ -z "$ans" ]; then
                CLEAN_PVC="No"
            fi

            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
            case "$ans" in
                "y"|"yes"|"")
                    CLEAN_PVC="Yes"
                    break
                ;;
                "n"|"no")
                    CLEAN_PVC="No"
                    break
                ;;
                *)
                error "Answer must be 'Yes' or 'No'"
                max_retries=$(($max_retries + 1))
            esac
        done
        if [[ $max_retries == 4 ]]; then
            error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
            exit
        fi
    fi
}

function clean_configmaps() {
    if [ -z "$CLEAN_CONFIGMAP" ]; then
        max_retries=0
        while [ $max_retries -lt 4 ]; do
            echo -e "\x1B[33;5m\nATTENTION: \x1B[0m\x1B[1;31mEnsure you're not removing operator-related ConfigMaps.\x1B[0m"
            printf "\x1B[1m\nDo you want to clean BAW CR-related configmaps? (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            if [ -z "$ans" ]; then
                CLEAN_CONFIGMAP="No"
            fi
            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
            case "$ans" in
                "y"|"yes"|"")
                    CLEAN_CONFIGMAP="Yes"
                    break
                ;;
                "n"|"no")
                    CLEAN_CONFIGMAP="No"
                    break
                ;;
                *)
                    error "Answer must be 'Yes' or 'No'"
                    max_retries=$(($max_retries + 1))
            esac
        done
        if [[ $max_retries == 4 ]]; then
            error "Maximum retries exceeded."
            exit 1
        fi
    fi
}

function clean_secrets() {
    if [ -z "$CLEAN_SECRET" ]; then
        max_retries=0
        while [ $max_retries -lt 4 ]; do
            echo -e "\x1B[33;5m\nATTENTION: \x1B[0m\x1B[1;31mEnsure no dependent BAW components are running before removing secrets.\x1B[0m"
            printf "\x1B[1m\nDo you want to clean BAW CR-related secrets? (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            if [ -z "$ans" ]; then
                CLEAN_SECRET="No"
            fi
            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
            case "$ans" in
                "y"|"yes"|"")
                    CLEAN_SECRET="Yes"
                    break
                ;;
                "n"|"no")
                    CLEAN_SECRET="No"
                    break
                ;;
                *)
                    error "Answer must be 'Yes' or 'No'"
                    max_retries=$(($max_retries + 1))
            esac
        done
        if [[ $max_retries == 4 ]]; then
            error "Maximum retries exceeded."
            exit 1
        fi
    fi
}

# Function to check if the required cli is installed
function cli_check(){
    # Check if OpenShift CLI/Kubetcl is installed
    if ! [ -x "$(command -v ${CLI_CMD} )" ]; then
        error "OpenShift/Kubectl CLI is not installed. Please install OpenShift/Kubectl CLI before running this script."
        exit 1
    fi
}

# function that gets the namespace to be used for clean up/uninstall
function get_namespace() {
    # BAW Namespace check
    attempts=0
    max_attempts=3

    while [ -z "$BAW_NAMESPACE" ] && [ $attempts -lt $max_attempts ]; do
        printf "\x1B[1mEnter namespace of your BAW deployment: \x1B[0m"
        read -rp "" ans
        BAW_NAMESPACE=$ans
        if [[ $CLI_CMD == "kubectl" ]]; then
            namespace_check_command="${CLI_CMD} get namespace ${BAW_NAMESPACE} -o name"
        else
            namespace_check_command="${CLI_CMD} get project ${BAW_NAMESPACE} -o name"
        fi
        if [ -z "$($namespace_check_command 2>/dev/null)" ]; then
            echo -e "\x1B[1;31mError: Namespace ${BAW_NAMESPACE} does not exist. Please re-enter the namespace.\x1B[0m"
            BAW_NAMESPACE=""
            attempts=$((attempts + 1))
        fi
        echo
    done

    if [ $attempts -eq $max_attempts ]; then
        error -e "\x1B[1;31mMaximum attempts reached. Exiting...\x1B[0m"
        exit
    fi
}

# function that checks if the OCP/ROKS platform based deployment has seperate operator and services namespaces
function separation_of_duties_check() {
    # Get Operand namespace from user
    if [ -z "$BAW_SERVICE_NAMESPACE" ]; then
        # For https://jsw.ibm.com/browse/DBACLD-157622
        # Update the default answer for Seperation of Duties to No
        #fixes a potential scenario of no input passed to the next step
        max_retries=0
        while [ $max_retries -lt 4 ]; do
            printf "\x1B[1m\nDid you install BAW Standalone with Separation of Duties? (Yes/No, default: No) \x1B[0m"
            read -rp "" ans
            # If the user provides no input, set the default to 'No'
            if [ -z "$ans" ]; then
                ans="No"
            fi

            ans=$(echo "${ans}" | tr '[:upper:]' '[:lower:]')
            case "$ans" in
                "y"|"yes"|"")
                    max_counter=0
                    while [ $max_counter -lt 4 ]; do
                        printf "\x1B[1mEnter Operand namespace of your BAW deployment: \x1B[0m"
                        read -rp "" ans 
                        BAW_SERVICE_NAMESPACE=$ans
                        if [ -z "$(${CLI_CMD} get project "${BAW_SERVICE_NAMESPACE}" 2>/dev/null)" ]; then
                            echo -e "\x1B[1;31mError: Namespace ${BAW_SERVICE_NAMESPACE} does not exist. Please re-enter the namespace.\x1B[0m"
                            BAW_SERVICE_NAMESPACE=""
                            max_counter=$(($max_counter + 1))
                        else
                            break
                        fi
                        echo
                    done
                    if [[ -z "$BAW_SERVICE_NAMESPACE" ]]; then
                        error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
                        exit
                    fi
                    echo -e "\x1B[1mGetting Operator Namespace... \x1B[0m"
                    BAW_NAMESPACE=$(${CLI_CMD} get cm ibm-cp4ba-common-config -n $BAW_SERVICE_NAMESPACE --ignore-not-found -o jsonpath="{ .data.operators_namespace}")
                    if [[ -z "$BAW_NAMESPACE" ]]; then
                        echo -e "\x1B[31;5mError: ibm-cp4ba-common-config ConfigMap not found in ${BAW_SERVICE_NAMESPACE} \x1B[0m\n"
                        exit 1
                    fi
                    break
                ;;
                "n"|"no")
                    BAW_SERVICE_NAMESPACE=$BAW_NAMESPACE
                    break
                ;;
                *)
                error "Answer must be 'Yes' or 'No'"
                max_retries=$(($max_retries + 1))
            esac
        done
        if [[ $max_retries == 4 ]]; then
            error "Maximum retries for incorrect inputs exceeded. The script will now exit.."
            exit
        fi
    fi
}

function check_namespace_validity(){
    # Check for namespace to prvent accidental deletion to other important namespaces.
    if [[ "$BAW_SERVICE_NAMESPACE" == openshift* ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'openshift' or start with 'openshift'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == kube* ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'kube' or start with 'kube'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "services" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'services'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "default" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'default'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "calico-system" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'calico-system'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "ibm-cert-store" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'ibm-cert-store'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "ibm-observe" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'ibm-observe'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "ibm-odf-validation-webhook" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'default'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    elif [[ "$BAW_SERVICE_NAMESPACE" == "ibm-system" ]]; then
        echo -e "\x1B[1;31mThe current namespace should not be 'ibm-system'. It should be the namespace where BAW is installed. The script aborted. \x1B[0m"
        exit 1
    fi
}

function delete_resource() {
	local RESOURCE_NAME=$1
	local NAMESPACE_NAME=$2
	${CLI_CMD} get "${RESOURCE_NAME}" -n "${NAMESPACE_NAME}" --ignore-not-found=true &>/dev/null
	if [ $? -eq 0 ]; then
		for i in $(${CLI_CMD} get "${RESOURCE_NAME}" --no-headers -n "${NAMESPACE_NAME}" --ignore-not-found=true | awk '{print $1}'); do
			${CLI_CMD} patch "${RESOURCE_NAME}"/"$i" -n "${NAMESPACE_NAME}" -p '{"metadata":{"finalizers":[]}}' --type=merge
			${CLI_CMD} delete "${RESOURCE_NAME}" "$i" -n "${NAMESPACE_NAME}" --ignore-not-found=true
		done
	fi
}

function force_delete() {
    local request=$1
    local type=$2
    local NAMESPACE_NAME=$3
    info "Force deleting ${request} ..."
    ${CLI_CMD} -n ${NAMESPACE_NAME} patch ${type} ${request} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]'
    ${CLI_CMD} -n ${NAMESPACE_NAME} delete ${type} ${request} --ignore-not-found --timeout=10s
}


# function that deletes the BAW operand requests
# DBACLD-168151
function delete_BAW_operand_requests() {
    local namespace=$1
    info "Deleting Operand Requests ..."

    if [[ ! -z "$(${CLI_CMD} get crd | grep operandrequests)" ]]; then
    for request in $(${CLI_CMD} -n ${namespace} get operandrequests -o name); do
        info "Deleting ${request} ..."
        ${CLI_CMD} -n ${namespace} delete ${request} --ignore-not-found --timeout=60s
    done

    for request in $(${CLI_CMD} -n ${namespace} get operandrequests -o name); do
        info "Force deleting ${request} ..."
        ${CLI_CMD} -n ${namespace} patch ${request} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]'
        ${CLI_CMD} -n ${namespace} delete ${request} --ignore-not-found --timeout=10s
    done
    fi
    success "Deletion of Operand Requests is completed"
}


# function to delete the BAW operator subscription and csvs
# function is called only after a confirmation is received
# currently only for other type platform
# DBACLD-168151
function delete_BAW_operators() {
    local namespace=$1
    title "Deleting BAW foundation and Insights Engine Operators..."
    insightsengine_sub=$(${CLI_CMD} get sub --no-headers --ignore-not-found -n ${namespace}|grep insights-engine |awk '{print $1}')
    force_delete $insightsengine_sub "sub" ${namespace}
    foundation_sub=$(${CLI_CMD} get sub --no-headers --ignore-not-found -n ${namespace}|grep foundation |awk '{print $1}')
    force_delete $foundation_sub "sub" ${namespace}
    insightsengine_csv=$(${CLI_CMD} get csv --no-headers --ignore-not-found -n ${namespace}|grep insights-engine |awk '{print $1}')
    force_delete $insightsengine_csv "csv" ${namespace}
    foundation_csv=$(${CLI_CMD} get csv --no-headers --ignore-not-found -n ${namespace}|grep BAW-foundation |awk '{print $1}')
    force_delete $foundation_csv "csv" ${namespace}

    success "Deletion of BAW foundation and Insights Engine operators is completed..."
}

# Handler Function that handles the uninstall the BAW operators
# This function calls delete_BAW_operators only after a confirmation is received
# currently only for other type platform
# DBACLD-168151
function uninstall_BAW_operators(){
    local namespace=$1
    uninstall_BAW_operators_flag=false
    info " The script will now proceed to uninstalling the BAW Standalone Operators. This step will not uninstall any CPFS operators"
    printf "\n"
    printf "\x1B[1mDo you want to proceed with the uninstallation of BAW Standalone Operators (Yes/No, default: No): \x1B[0m"
    read -rp "" ans
    case "$ans" in
    "y"|"Y"|"yes"|"Yes"|"YES")
        uninstall_BAW_operators_flag=true
        printf "\n"
        echo -e "Proceeding with uninstalling the BAW Standalone Operators... "
        printf "\n"
        ;;
    "n"|"N"|"no"|"No"|"NO"|"")
        echo -e "Skipping the uninstall of BAW Standalone Operators......"
        printf "\n"
        ;;
    *)
        error -e "Answer must be \"Yes\" or \"No\"\n"
        ;;
    esac
    if [[ "$uninstall_BAW_operators_flag" == true ]]; then
        delete_BAW_operators $namespace
        delete_BAW_operand_requests $namespace
        ${CLI_CMD} delete operatorgroup --all -n ${namespace}
    fi
}

# Function to delete a specific resource type
# DBACLD-168151
function delete_resource_type() {
    local resource_type=$1
    local namespace=$2
    title "Deleting $resource_type ..."

    if [[ ! -z "$(${CLI_CMD} get $resource_type -n ${namespace} )" ]]; then

    for request in $(${CLI_CMD} -n ${namespace} get $resource_type -o name); do
        info "Deleting ${request} ..."
        ${CLI_CMD} -n ${namespace} patch ${request} --type="json" -p '[{"op": "remove", "path":"/metadata/finalizers"}]'
        ${CLI_CMD} -n ${namespace} delete ${request} --ignore-not-found --timeout=10s
    done
    fi
    success "$resource_type deletion completed!"
}

# Function to delete PV PVC Configmaps and secrets from the namespace
# DBACLD-168151
function pv_pvc_cm_secrets_to_delete(){
    local namespace=$1
    # Fetch resources
    delete_pvc_cm_secrets_flag=false
    pvcs=$(${CLI_CMD} get pvc -n "$namespace" --no-headers -o custom-columns=":metadata.name")
    pvs=$(${CLI_CMD} get pv -n "$namespace" --no-headers -o custom-columns=":metadata.name")
    cms=$(${CLI_CMD} get cm --no-headers -o custom-columns=":metadata.name")
    secrets=$(${CLI_CMD} get secrets -n "$namespace" --no-headers -o custom-columns=":metadata.name")

    # Display in a table format
    printf "\n\x1B[1;33mResources to be deleted:\x1B[0m\n"
    printf "%-25s %-15s\n" "Resource Type" "Name"
    printf "%-25s %-15s\n" "-------------" "----"

    for pvc in $pvcs; do printf "%-25s %-15s\n" "PersistentVolumeClaims" "$pvc"; done
    for pv in $pvs; do printf "%-25s %-15s\n" "PersistentVolumeClaims" "$pv"; done
    for cm in $cms; do printf "%-25s %-15s\n" "ConfigMaps" "$cm"; done
    for secret in $secrets; do printf "%-25s %-15s\n" "Secrets" "$secret"; done

    # Ask for confirmation
    printf "\x1B[1mDo you want to proceed with deleting these resources (Yes/No, default: No): \x1B[0m"
    read -rp "" confirm
    if [[ "$confirm" == "yes" || "$confirm" == "y" || "$confirm" == "Y"|| "$confirm" == "yes" || "$confirm" == "Yes" || "$confirm" == "YES" ]]; then
        info "Proceeding with the deletion of Secrets , PVs,PVCs and Service Accounts...."
        delete_resource_type "pvc" "$namespace"
        delete_resource_type "pv" "$namespace"
        delete_resource_type "secret" "$namespace"
        delete_resource_type "configmap" "$namespace"
        ${CLI_CMD} delete serviceaccounts --all -n ${namespace}
        delete_pvc_cm_secrets_flag=true
    fi
}

# Function to delete all catalog sources
# Currently only for other type platform
function delete_catalog_sources() {
    namespace="$1"

    info "Fetching all catalog sources in namespace: $namespace"

    catalog_source=$(kubectl get catalogsources -n "$namespace" -o custom-columns=":metadata.name" --no-headers)

    if [[ -z "$catalog_source" ]]; then
        echo "No catalog sources found in namespace: $namespace"
        return 0
    fi

    info "Deleting the following catalog sources:"
    echo "$catalog_source"

    for source in $catalog_source; do
        ${CLI_CMD} delete catalogsource "$source" -n "$namespace"
    done

    success "Catalog sources cleanup completed in namespace: $namespace"
}

# Clean up ibm-cert-manager resources, only executed for dev mode
# Currently only for other type platform
# DBACLD-168151
function cleanup_ibm_cert_manager() {
    local CERT_MANAGER_NAMESPACE=$1

    echo "Setting namespace to: $CERT_MANAGER_NAMESPACE"

    echo "Deleting all CertManagerConfig instances..."
    ${CLI_CMD} get certmanagerconfig -n "$CERT_MANAGER_NAMESPACE" --no-headers -o custom-columns=":metadata.name" | while read -r cmc; do
        ${CLI_CMD} delete certmanagerconfig "$cmc" -n "$CERT_MANAGER_NAMESPACE"
    done

    echo "Uninstalling the IBM Cert Manager operator subscription..."
    ${CLI_CMD} delete subscription ibm-cert-manager-operator -n "$CERT_MANAGER_NAMESPACE" --ignore-not-found

    echo "Uninstalling the IBM Cert Manager operator group..."
    ${CLI_CMD} delete operatorgroup --all -n $CERT_MANAGER_NAMESPACE

    echo "Checking for IBM Cert Manager CSV..."
    CSV_NAME=$(${CLI_CMD} get csv -n "$CERT_MANAGER_NAMESPACE" | grep ibm-cert-manager | awk '{print $1}')
    if [[ -n "$CSV_NAME" ]]; then
        echo "Deleting CSV: $CSV_NAME"
        ${CLI_CMD} delete csv "$CSV_NAME" -n "$CERT_MANAGER_NAMESPACE"
    else
        echo "No IBM Cert Manager CSV found."
    fi

    echo "Verifying IBM Cert Manager resource cleanup..."
    ${CLI_CMD} get deployments -n "$CERT_MANAGER_NAMESPACE" -l app.kubernetes.io/component=cert-manager
    ${CLI_CMD} get service -n "$CERT_MANAGER_NAMESPACE" -l app=ibm-cert-manager-webhook
    ${CLI_CMD} get mutatingwebhookconfiguration | grep cert-manager-webhook || true
    ${CLI_CMD} get validatingwebhookconfiguration | grep cert-manager-webhook || true

    echo "Cleaning up webhook configurations if they exist..."
    ${CLI_CMD} delete mutatingwebhookconfiguration cert-manager-webhook --ignore-not-found
    ${CLI_CMD} delete validatingwebhookconfiguration cert-manager-webhook --ignore-not-found

    #echo "Cleaning up the crds related to cert manager...."
    #for crd in $(kubectl get crd | grep cert-manager | awk '{print $1}'); do
    #    kubectl patch crd $crd -p '{"metadata":{"finalizers":[]}}' --type=merge
    #    kubectl delete crd $crd
    #done

    echo "IBM Cert Manager cleanup completed in namespace: $CERT_MANAGER_NAMESPACE"
}

# Clean up ibm-licensing resources, only executed for dev mode
# Currently only for other type platform
# DBACLD-168151
function cleanup_ibm_licensing() {
    IBM_LICENSING_NAMESPACE=$1

    echo "Cleaning up IBM Licensing in namespace: $IBM_LICENSING_NAMESPACE"

    # Delete all IBM Licensing instances
    echo "Deleting all IBM Licensing instances..."
    ${CLI_CMD} get ibmlicensing -n "$IBM_LICENSING_NAMESPACE" --no-headers -o custom-columns=":metadata.name" | while read -r instance; do
        ${CLI_CMD} delete ibmlicensing "$instance" -n "$IBM_LICENSING_NAMESPACE"
    done

    # Delete CSV if present
    CSV_NAME=$(${CLI_CMD} get csv -n "$IBM_LICENSING_NAMESPACE" --no-headers | awk '/ibm-licensing-operator/ {print $1}')
    if [[ -n "$CSV_NAME" ]]; then
        echo "Deleting CSV: $CSV_NAME"
        ${CLI_CMD} delete csv "$CSV_NAME" -n "$IBM_LICENSING_NAMESPACE"
    else
        echo "No IBM Licensing CSV found."
    fi
    # Delete CSV if present
    CSV_NAME=$(${CLI_CMD} get csv -n "$BAW_SERVICE_NAMESPACE" --no-headers | awk '/ibm-licensing-operator/ {print $1}')
    if [[ -n "$CSV_NAME" ]]; then
        echo "Deleting CSV: $CSV_NAME"
        ${CLI_CMD} delete csv "$CSV_NAME" -n "$BAW_SERVICE_NAMESPACE"
    else
        echo "No IBM Licensing CSV found."
    fi

    # Delete Subscription
    SUB_NAME=$(${CLI_CMD} get subscription -n "$IBM_LICENSING_NAMESPACE" --no-headers | awk '/ibm-licensing-operator-app/ {print $1}')
    if [[ -n "$SUB_NAME" ]]; then
        echo "Deleting Subscription: $SUB_NAME"
        ${CLI_CMD} delete subscription "$SUB_NAME" -n "$IBM_LICENSING_NAMESPACE"
    else
        echo "No IBM Licensing Subscription found."
    fi

    # Delete Subscription
    SUB_NAME=$(${CLI_CMD} get subscription -n "$BAW_SERVICE_NAMESPACE" --no-headers | awk '/ibm-licensing-operator-app/ {print $1}')
    if [[ -n "$SUB_NAME" ]]; then
        echo "Deleting Subscription: $SUB_NAME"
        ${CLI_CMD} delete subscription "$SUB_NAME" -n "$BAW_SERVICE_NAMESPACE"
    else
        echo "No IBM Licensing Subscription found."
    fi

    kubectl get IBMLicensing -n ibm-licensing

    echo "IBM Licensing cleanup completed in namespace: $IBM_LICENSING_NAMESPACE"
}

# Function to clean up CPFS resources
# only for DEV
# DBACLD-168151
function cleanup_ibm_foundational_services() {
    local OPERATOR_NAMESPACE=$1
    local SERVICES_NAMESPACE=$2

    echo "Cleaning up IBM Cloud Pak foundational services in namespace: $OPERATOR_NAMESPACE"
    
    
    if [[ -z "$SERVICES_NAMESPACE" ]]; then
        echo "No servicesNamespace found, defaulting to operator namespace."
        SERVICES_NAMESPACE="$OPERATOR_NAMESPACE"
    fi

    echo "Service namespace identified as: $SERVICES_NAMESPACE"

    # Delete CommonService APIs
    ${CLI_CMD} delete commonservice common-service -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete commonservice common-service -n "$SERVICES_NAMESPACE"

    # Uninstall the IBM Cloud Pak foundational services operator
    ${CLI_CMD} delete csv -l operators.coreos.com/ibm-common-service-operator."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete subscription -l operators.coreos.com/ibm-common-service-operator."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"

    # Delete OperandRequest instances
    ${CLI_CMD} delete operandrequest --all -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete operandrequest --all -n "$SERVICES_NAMESPACE"

    # Delete OperandConfig instances
    ${CLI_CMD} delete operandconfig --all -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete operandconfig --all -n "$SERVICES_NAMESPACE"

    # Delete OperandRegistry instances
    ${CLI_CMD} delete operandregistry --all -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete operandregistry --all -n "$SERVICES_NAMESPACE"

    # Delete NamespaceScope instances
    ${CLI_CMD} delete namespacescope --all -n "$OPERATOR_NAMESPACE"

    # Uninstall the Operand Deployment Lifecycle Manager operator
    ${CLI_CMD} delete csv -l operators.coreos.com/ibm-odlm."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete subscription -l operators.coreos.com/ibm-odlm."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"

    # Uninstall the IBM NamespaceScope operator
    ${CLI_CMD} delete csv -l operators.coreos.com/ibm-namespace-scope-operator."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"
    ${CLI_CMD} delete subscription -l operators.coreos.com/ibm-namespace-scope-operator."$OPERATOR_NAMESPACE" -n "$OPERATOR_NAMESPACE"

    echo "IBM Cloud Pak foundational services cleanup completed in namespace: $OPERATOR_NAMESPACE"
}


### Beginning of Uninstall script ###

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) 
            BAW_NAMESPACE="$2"
            shift 2 
            ;;
        -s) 
            BAW_SERVICE_NAMESPACE="$2"
            shift 2 
            ;;
        -h) 
            HELP=true
            shift 
            ;;
        dev)
            DEV=true
            shift 
            ;;
        *) 
            HELP=true
            shift 
            ;;
    esac
done

if [[ $HELP == true ]]; then
	echo "This script cleans up resources that are stuck in terminating state or would cause failure in re-deployment."
	echo "Usage: $0 -h -n"
	echo "  -h  Display help"
	echo "  -n  Enter BAW namespace for clean up."
	exit 0
fi

select_platform
cli_check
# Check cluster login
if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
    check_cluster_login
fi
get_namespace
select_db_type
clean_pvc
clean_configmaps
clean_secrets
# Separation of Duties check
if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
    separation_of_duties_check
    # Validate BAW_NAMESPACE env var is for existing namespace
    if [ -z "$(${CLI_CMD} get project "${BAW_SERVICE_NAMESPACE}" 2>/dev/null)" ]; then
        echo -e "\x1B[1;31mError: Namespace ${BAW_SERVICE_NAMESPACE} does not exist. Specify an existing namespace where BAW is deployed.\x1B[0m" && exit 1
    fi
else
    BAW_SERVICE_NAMESPACE=$BAW_NAMESPACE
fi
check_namespace_validity

if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
    echo -e "The BAW namespace entered: ${BAW_SERVICE_NAMESPACE}"
    if [[ "$BAW_SERVICE_NAMESPACE" != "$BAW_NAMESPACE" ]]; then
        echo -e "The BAW operator namespace is ${BAW_NAMESPACE}\n"
    fi
fi

echo -e "\x1B[1mNote: Please make sure you are using the namespace you intent to clean up.\n\x1B[0m"
echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1;31mThis clean-up script is only intended to be run after you have deleted your ICP4ACluster CR instance for your BAW deployment. This clean-up script will delete all Client CRs, Optional components and zenExtensions, and some secrets that would cause failure in re-deployment. \x1B[0m"

# Confirm to clean up
echo -e "\x1B[1mPlease confirm if you would like to proceed with this clean up.\x1B[0m"
read -p "Enter Y or y to continue: " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "\nYou did not confirm to proceed with this clean up. Exit clean-up script.\n"
    exit 0
  fi
  echo -e "You have confirmed to continue this clean up.\n"
  sleep 2


# Clean up clients
echo -e "\x1B[1mCleaning up Clients... \x1B[0m\n"
delete_resource client "${BAW_SERVICE_NAMESPACE}"
${CLI_CMD} delete client zenclient-"${BAW_SERVICE_NAMESPACE}" -n "${BAW_SERVICE_NAMESPACE}" --ignore-not-found=true
echo -e "\n\x1B[1mFinsished cleaning up all Clients. \x1B[0m\n"

# Clean up additional operators
echo -e "\x1B[1mCleaning up Additional Operators... \x1B[0m\n"
${CLI_CMD} delete operator ibm-commonui-operator-app."${BAW_SERVICE_NAMESPACE}" -n ${BAW_SERVICE_NAMESPACE} --ignore-not-found=true
${CLI_CMD} delete operator ibm-iam-operator."${BAW_SERVICE_NAMESPACE}" -n ${BAW_SERVICE_NAMESPACE} --ignore-not-found=true
echo -e "\n\x1B[1mFinsished cleaning up all Additional Operators. \x1B[0m\n"

# Clean up additional SVCs
echo -e "\x1B[1mCleaning up Additional SVCs... \x1B[0m\n"
${CLI_CMD} delete svc meta-api-svc --ignore-not-found=true
echo -e "\n\x1B[1mFinsished cleaning up all Additional SVCs. \x1B[0m\n"

# Clean up zenExtension
echo -e "\x1B[1mCleaning up zenExtensions... \x1B[0m\n"
delete_resource zenextension "${BAW_SERVICE_NAMESPACE}"
${CLI_CMD} delete zenextension bawdeploy-cmis-zen-extension --ignore-not-found=true
${CLI_CMD} delete zenextension bawdeploy-cp4ba-zen-extension --ignore-not-found=true
${CLI_CMD} delete zenextension bawdeploy-cpe-zen-extension --ignore-not-found=true
${CLI_CMD} delete zenextension bawdeploy-graphql-zen-extension --ignore-not-found=true
${CLI_CMD} delete zenextension common-web-ui-zen-extension --ignore-not-found=true
echo -e "\n\x1B[1mFinished cleaning up all zenExtensions. \x1B[0m\n"
# Clean up zen-metastore-edb secret
echo -e "\x1B[1mCleaning up zen-metastore-edb secrets... \x1B[0m\n"
for i in $(${CLI_CMD} get secrets --no-headers|awk '{print $1}'| grep 'zen-metastore-edb'); do
    ${CLI_CMD} delete secret "$i" -n "$BAW_SERVICE_NAMESPACE"
done
echo -e "\n\x1B[1mFinished cleaning up all zen-metastore-edb related secrets. \x1B[0m\n"

# Clean up cs-ca-certificate secret
echo -e "\x1B[1mCleaning up cs-ca-certificate-secret secret... \x1B[0m\n"
${CLI_CMD} delete secret cs-ca-certificate-secret -n "$BAW_SERVICE_NAMESPACE"
echo -e "\n\x1B[1mFinished cleaning up cs-ca-certificate-secret secret. \x1B[0m\n"


if [[ "$IS_EMBEDDED_DB" == "Yes" ]]; then
    # delete Embedded postgres svc
    echo -e "\n\x1B[1mDeleting Embedded Postgres SVCs \x1B[0m\n"
    ${CLI_CMD} get svc -n "$BAW_SERVICE_NAMESPACE" --no-headers | awk '$1 ~ /^postgres-.*-(r|ro|rw)$/{print $1}' | xargs -r -n1 ${CLI_CMD} delete svc -n "$BAW_SERVICE_NAMESPACE"
    ${CLI_CMD} get pod -n "$BAW_SERVICE_NAMESPACE" --no-headers | awk '$1 ~ /^postgres-.*-[0-9]+$/{print $1}' | xargs -r -n1 ${CLI_CMD} delete pod -n "$BAW_SERVICE_NAMESPACE"
    echo -e "\n\x1B[1mFinished deleting Embedded Postgres svc. \x1B[0m\n"
fi

if [[ "$CLEAN_PVC" == "Yes" ]]; then
    # delete Embedded postgres svc
    echo -e "\n\x1B[1mDeleting PVCs \x1B[0m\n"
    ${CLI_CMD} delete pvc -n "$BAW_SERVICE_NAMESPACE" --all --ignore-not-found=true
    echo -e "\n\x1B[1mFinished deleting pvc. \x1B[0m\n"
fi

if [[ "$CLEAN_SECRET" == "Yes" ]]; then
    echo -e "\n\x1B[1mDeleting CR-created secrets...\x1B[0m\n"
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" common-service-db-replica-tls-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" common-service-db-zen-tls-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" cpd-oidcclient-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" cs-ca-certificate-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" iaf-system-automationui-aui-zen-ca --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" iaf-system-automationui-aui-zen-cert --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" ibm-ban-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" ibm-fncm-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" ibm-zen-objectstore-cert --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" icp4adeploy-bas-admin-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" identity-provider-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" ldap-bind-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" platform-identity-management --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" postgresql-operator-controller-manager-config --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" saml-auth-secret --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" zen-metastore-edb-replica-client --ignore-not-found
    ${CLI_CMD} delete secret -n "$BAW_SERVICE_NAMESPACE" zen-metastore-edb-server --ignore-not-found
    echo -e "\n\x1B[1mFinished deleting secrets.\x1B[0m\n"
fi


if [[ "$CLEAN_CONFIGMAP" == "Yes" ]]; then
    echo -e "\n\x1B[1mDeleting CR-created configmaps...\x1B[0m\n"
    ${CLI_CMD} get cm -n "$BAW_SERVICE_NAMESPACE" -o name | grep -E 'workflow|ads|fncm|icc|bai' | xargs -r ${CLI_CMD} delete -n "$BAW_SERVICE_NAMESPACE"
    echo -e "\n\x1B[1mFinished deleting configmaps.\x1B[0m\n"
fi


delete_resource FlinkDeployment $BAW_SERVICE_NAMESPACE
# <https://jsw.ibm.com/browse/DBACLD-156830?> - Need to add a full name for flinkdeployments, as there could be another flinkdeployment CRD
delete_resource flinkdeployments.flink.ibm.com $BAW_SERVICE_NAMESPACE
delete_resource flinkdeployments.flink.apache.org $BAW_SERVICE_NAMESPACE


# delete common service
delete_resource CommonService ${BAW_SERVICE_NAMESPACE}
delete_resource CommonService ${BAW_NAMESPACE}

#Uninstall additional resources and currently only for BAW on Other type of platform
# DBACLD-168151
if [[ "$PLATFORM_SELECTED" == "other" && "$DEV" == true ]]; then
    uninstall_BAW_operators "$BAW_SERVICE_NAMESPACE"
    if [[ "$uninstall_BAW_operators_flag" == true ]]; then
        pv_pvc_cm_secrets_to_delete "$BAW_SERVICE_NAMESPACE"
    fi
    if [[ "$uninstall_BAW_operators_flag" == true && "$delete_pvc_cm_secrets_flag" == true ]]; then
        delete_catalog_sources ${BAW_SERVICE_NAMESPACE}
        cleanup_ibm_cert_manager "ibm-cert-manager"
        cleanup_ibm_licensing "ibm-licensing"
        cleanup_ibm_foundational_services ${BAW_SERVICE_NAMESPACE}
        ${CLI_CMD} delete namespace ${BAW_SERVICE_NAMESPACE}
        ${CLI_CMD} delete namespace ibm-cert-manager
        ${CLI_CMD} delete namespace ibm-licensing
    fi

fi


success "\x1B[1m BAW clean up has completed.\x1B[0m\n"


### End of Uninstall script ###