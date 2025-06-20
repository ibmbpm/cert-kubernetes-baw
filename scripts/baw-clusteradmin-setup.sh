#!/bin/bash
#set -x
###############################################################################
#
# Licensed Materials - Property of IBM
# (C) Copyright IBM Corp. 2021, 2025. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# Import common utilities and environment variables
source ${CUR_DIR}/helper/common.sh
RUNTIME_MODE=$1
TEMP_FOLDER=${CUR_DIR}/.tmp
INSTALL_BAI=""
CRD_FILE=${PARENT_DIR}/descriptors/ibm_cp4a_crd.yaml
SA_FILE=${PARENT_DIR}/descriptors/service_account.yaml
# CLUSTER_ROLE_FILE=${PARENT_DIR}/descriptors/cluster_role.yaml
# CLUSTER_ROLE_BINDING_FILE=${PARENT_DIR}/descriptors/cluster_role_binding.yaml
# CLUSTER_ROLE_BINDING_FILE_TEMP=${TEMP_FOLDER}/.cluster_role_binding.yaml
ROLE_FILE=${PARENT_DIR}/descriptors/role.yaml
ROLE_BINDING_FILE=${PARENT_DIR}/descriptors/role_binding.yaml
BRONZE_STORAGE_CLASS=${PARENT_DIR}/descriptors/cp4a-bronze-storage-class.yaml
SILVER_STORAGE_CLASS=${PARENT_DIR}/descriptors/cp4a-silver-storage-class.yaml
GOLD_STORAGE_CLASS=${PARENT_DIR}/descriptors/cp4a-gold-storage-class.yaml
LOG_FILE=${CUR_DIR}/prepare_install.log
PLATFORM_SELECTED=""
OTHER_PLATFROM_TYPE=""
PLATFORM_VERSION=""
PROJ_NAME=""
PROJ_NAME_ALL_NAMESPACE="openshift-operators"
DOCKER_RES_SECRET_NAME="ibm-entitlement-key"
DOCKER_RES_SECRET_NAME_STG="ibm-staging-entitlement-key"
REGISTRY_IN_FILE="cp.icr.io"
STG_REGISTRY_IN_FILE="cp.stg.icr.io"
OPERATOR_FILE=${PARENT_DIR}/descriptors/operator.yaml
OPERATOR_FILE_TMP=$TEMP_FOLDER/.operator_tmp.yaml
CNCF_OLM_NAMESPACE="olm"
WFPS_CNCF_CATALOG_NAMESPACE="olm" ## CNCF reuse olm namespace to deploy catalog source
WFPS_CNCF_PROJ_NAME_ALL_NAMESPACE="operators" ## CNCF namespace to support watch all namespace
CNCF_DOMAIN_NAME=""

# OPERATOR_PVC_FILE=${PARENT_DIR}/descriptors/operator-shared-pvc.yaml
# OPERATOR_PVC_FILE_TMP1=${TEMP_FOLDER}/.operator-shared-pvc_tmp1.yaml
# OPERATOR_PVC_FILE_TMP=${TEMP_FOLDER}/.operator-shared-pvc_tmp.yaml
# OPERATOR_PVC_FILE_BAK=${TEMP_FOLDER}/.operator-shared-pvc.yaml
JDBC_DRIVER_DIR=${CUR_DIR}/jdbc

COMMON_SERVICES_CRD_DIRECTORY_OCP311=${PARENT_DIR}/descriptors/common-services/scripts
COMMON_SERVICES_CRD_DIRECTORY=${PARENT_DIR}/descriptors/common-services/crds
COMMON_SERVICES_OPERATOR_ROLES=${PARENT_DIR}/descriptors/common-services/roles
COMMON_SERVICES_TEMP_DIR=$TMEP_FOLDER
COMMON_SERVICES_CM_NAMESPACE="kube-public"
COMMON_SERVICES_CM_DEDICATED_NAME="common-service-maps"
COMMON_SERVICES_CM_SHARED_NAME="ibm-common-services-status"
COMMON_SERVICES_NAME="IBM Cloud Pak foundational services"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE="common-service-maps-update.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME="common-service-maps.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME}"
COMMON_SERVICES_CM_DEDICATE_FILE_UPDATE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE}"

BAW_FULL_NAME="IBM Business Automation Workflow"

mkdir -p $TEMP_FOLDER >/dev/null 2>&1

function prompt_wfps_license(){
    clear
    echo -e "\x1B[1;31mIMPORTANT: Review the IBM Process Flow license information here: \n\x1B[0m"
	# TODO update license link
    echo -e "\x1B[1;31mhttps://www14.software.ibm.com/cgi-bin/weblap/lap.pl?li_formnum=L-FNHF-F9RU7N\n\x1B[0m"

    printf "\n"
    while true; do
        if [ -z "$AUTO_LICENSE_ACCEPT" ]; then
            printf "\x1B[1mDo you accept the IBM Process Flow license (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                printf "\n"
                echo -e "done"
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo -e "Exiting...\n"
                exit 0
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        else
            printf "\x1B[1mDo you accept the IBM Process Flow license (Yes/No, default: No): \x1B[0m"
            case "$AUTO_LICENSE_ACCEPT" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                printf "\n"
                echo -e "done"
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo -e "Exiting...\n"
                exit 0
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                exit 1
                ;;
            esac
        fi
    done
}

#echo "creating temp folder"
# During the development cycle we will need to apply cp4a_catalogsource_dev.yaml
# catalog_source.yaml is the final deliver yaml.
if [[ $RUNTIME_MODE == "dev" ]];then
    OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
    OLM_OPT_GROUP=${PARENT_DIR}/descriptors/op-olm/operator_group.yaml
    OLM_SUBSCRIPTION=${PARENT_DIR}/descriptors/op-olm/subscription.yaml
else
    OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
    OLM_OPT_GROUP=${PARENT_DIR}/descriptors/op-olm/operator_group.yaml
    OLM_SUBSCRIPTION=${PARENT_DIR}/descriptors/op-olm/subscription.yaml
fi
online_source="ibm-cp4a-operator-catalog"

OLM_CATALOG_TMP=${TEMP_FOLDER}/.catalog_source.yaml
OLM_OPT_GROUP_TMP=${TEMP_FOLDER}/.operator_group.yaml
OLM_SUBSCRIPTION_TMP=${TEMP_FOLDER}/.subscription.yaml


echo '' > $LOG_FILE

# Function to validate the CLI based on platform type
function validate_cli(){
    if [ -z $BAW_AUTO_PLATFORM ]; then
    clear
    fi

    if [[ "${SCRIPT_MODE}" == "OLM" ]];then
        echo -e "\x1B[1mThis script prepares the OLM for the deployment of some $BAW_FULL_NAME capabilities \x1B[0m"
    else
        echo -e "\x1B[1mThis script prepares the environment for the deployment of some $BAW_FULL_NAME capabilities \x1B[0m"
    fi
    echo
    if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
        which oc &>/dev/null
        [[ $? -ne 0 ]] && \
            echo "Unable to locate the OpenShift CLI. You must install it to run this script." && \
            exit 1
    fi
    if  [[ $PLATFORM_SELECTED == "other" ]]; then
        which kubectl &>/dev/null
        [[ $? -ne 0 ]] && \
            echo "Unable to locate the Kubernetes CLI. You must install it to run this script." && \
            exit 1
    fi
}

function install_cert_license_operator(){
    info "Applying the latest $BAW_FULL_NAME Operator catalog source..."
    if [[ $PRIVATE_CATALOG == "No" ]]; then
        
        OLM_CATALOG=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
        kubectl apply -f $OLM_CATALOG >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            success "The $BAW_FULL_NAME Operator catalog source has been successfully updated!"

        else
            fail "The $BAW_FULL_NAME Operator catalog source update has failed"
            exit 1
        fi
    else
        local baw_namespace=""

        catalog_names=()

        # Read catalog names into the array
        while IFS= read -r name; do
            catalog_names+=("$name")
        done < <(${YQ_CMD} r -d* "$OLM_CATALOG_TMP" 'metadata.name')

        # Iterate over the catalog names
        for name in "${catalog_names[@]}"; do
            # Get the document index of the catalog source (by name)
            doc_index=$( ${YQ_CMD} r -d* "$OLM_CATALOG_TMP" 'metadata.name' | grep -n "^$name$" | cut -d: -f1 )

            if [[ "$name" == "ibm-cert-manager-catalog" ]]; then

                ${YQ_CMD} w -i "$OLM_CATALOG_TMP" -d "$((doc_index - 1))" "metadata.namespace" "ibm-cert-manager"
            elif [[ "$name" == "ibm-licensing-catalog" ]]; then

                ${YQ_CMD} w -i "$OLM_CATALOG_TMP" -d "$((doc_index - 1))" "metadata.namespace" "ibm-licensing"
            else
                ${YQ_CMD} w -i "$OLM_CATALOG_TMP" -d "$((doc_index - 1))" "metadata.namespace" "$project_name"
            fi

            # temporarily adding ibm-zen-operator-catalog because as of March 13th 2025 zen has not GAed
            if [[ "$name" == "ibm-cp4a-operator-catalog" || "$name" == "ibm-fncm-operator-catalog" ]]; then
#                ${YQ_CMD} w -i "$OLM_CATALOG_TMP" -d "$((doc_index - 1))"  "spec.secrets[+]" "ibm-staging-entitlement-key"
                # Extract the current image value
                current_image=$(${YQ_CMD} r -d "$((doc_index - 1))" "$OLM_CATALOG_TMP" 'spec.image')

                if [[ -n "$current_image" && "$current_image" == icr.io/cpopen/* ]]; then
                    # Modify the repository path
                    updated_image=${current_image/icr.io\/cpopen\//cp.stg.icr.io\/cp/}

                    # Update the image field in the YAML
                    ${YQ_CMD} w -i "$OLM_CATALOG_TMP" -d "$((doc_index - 1))" "spec.image" "$updated_image"
                fi
            fi

        done

        kubectl apply -f $OLM_CATALOG_TMP >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            success "The $BAW_FULL_NAME Operator catalog source has been successfully updated!"
        else
            fail "The $BAW_FULL_NAME Operator catalog source update has failed."
            exit 1
        fi            
    fi
    printf "\n"
    info "Starting the installation of IBM Cert Manager and IBM Licensing Operator ..."

    # which yq &>/dev/null
    # [[ $? -ne 0 ]] && \
    # fail "Unable to locate the yq CLI. You must install latest one from https://github.com/mikefarah/yq/ manually" && \
    # exit 1
    
    # Checking ibm-cert-manager/ibm-licensing catalog soure pod
    maxRetry=10
    for ((retry=0;retry<=${maxRetry};retry++)); do
        if [[ $PRIVATE_CATALOG == "No" ]]; then
            cert_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
            license_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-licensing-catalog -n openshift-marketplace -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        else
            cert_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-cert-manager-catalog -n ibm-cert-manager -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
            license_catalog_pod_name=$(kubectl get pod -l=olm.catalogSource=ibm-licensing-catalog -n ibm-licensing -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
        fi
        if [[ ( -z $cert_catalog_pod_name) || (-z $license_catalog_pod_name) ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                if [[ $PRIVATE_CATALOG == "Yes" && -z $cert_catalog_pod_name ]]; then
                    warning "Timeout while waiting for the ibm-cert-manager-catalog pod to be ready under the project.  \"ibm-cert-manager\""
                elif [[ $PRIVATE_CATALOG == "Yes" && -z $license_catalog_pod_name ]]; then
                    warning "Timeout while waiting for the ibm-licensing-catalog pod to be ready under the project.  \"ibm-licensing\""
                elif [[ $PRIVATE_CATALOG == "No" ]]; then
                    warning "Timeout while waiting for the ibm-licensing-catalog/ibm-cert-manager-catalog pod to be ready under the project.  \"openshift-marketplace\""
                fi
                exit 1
            else
                sleep 30
                echo -n "..."
                continue
            fi
        else
            success "The ibm-licensing-catalog/ibm-cert-manager-catalog pod is ready!"
            break
        fi
    done

    # Install IBM Cert Manager/Licensing operator
    if [[ $PRIVATE_CATALOG == "No" ]]; then
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --enable-licensing --license-accept --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
    else
        $COMMON_SERVICES_SCRIPT_FOLDER/setup_singleton.sh --enable-licensing --license-accept --enable-private-catalog -cmNs ibm-cert-manager -licensingNs ibm-licensing --yq "$CPFS_YQ_PATH" -c $CERT_LICENSE_CHANNEL_VERSION
    fi
    printf "\n"
    maxRetry=30
    info "Waiting for IBM Cert Manager Operator to be ready..."
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReadyWebhook=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-webhook -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers| grep 'Running' | grep 'true' | awk '{print $1}')
        isReadyCertmanager=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-controller -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers| grep 'Running' | grep 'true' | awk '{print $1}')
        isReadyCainjector=$(kubectl get pod -l=app.kubernetes.io/instance=cert-manager,app.kubernetes.io/name=ibm-cert-manager-cainjector -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers| grep 'Running' | grep 'true' | awk '{print $1}')
        isReadyCertmanagerOperator=$(kubectl get pod -l=app.kubernetes.io/name=cert-manager,app.kubernetes.io/instance=ibm-cert-manager-operator -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers --ignore-not-found | grep 'Running' | grep 'true' | awk '{print $1}')

        if [[ -z $isReadyWebhook || -z $isReadyCertmanager || -z $isReadyCainjector || -z $isReadyCertmanagerOperator ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                fail "Timeout to wait for IBM Cert Manager Operator to be ready"
                exit 1
            else
                sleep 20
                echo -n "..."
                continue                        
            fi
        else
            success "IBM Cert Manager Operator is running: "
            # info "Pod: $isReadyCertmanagerOperator"
            info "Pod: $isReadyCertmanager"
            echo "            $isReadyWebhook"
            echo "            $isReadyCainjector"
            echo "            $isReadyCertmanagerOperator"
            break
        fi
    done

    info "Waiting for IBM Licensing Operator to be ready..."
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReadyLicenseOperator=$(kubectl get pod -l=app.kubernetes.io/name=ibm-licensing,name=ibm-licensing-operator -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers| grep 'Running' | grep 'true' | awk '{print $1}')
        isReadyLicenseService=$(kubectl get pod -l=app.kubernetes.io/name=ibm-licensing-service-instance,app=ibm-licensing-service-instance -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready' --all-namespaces --no-headers| grep 'Running' | grep 'true' | awk '{print $1}')

        if [[ -z $isReadyLicenseOperator || -z $isReadyLicenseService ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                fail "Timeout to wait for IBM Licensing Operator ready"
                exit 1
            else
                sleep 20
                echo -n "..."
                continue                        
            fi
        else
            success "IBM Licensing Operator is running: "
            # info "Pod: $isReadyCertmanagerOperator"
            info "Pod: $isReadyLicenseOperator"
            echo "            $isReadyLicenseService"
            break
        fi
    done

}

# Function that asks the customer if they wish to deploy IBM BAW Standalone with a private or a global catalog
function select_private_catalog(){
    printf "\n"
    echo "${YELLOW_TEXT}[NOTES] You can install the $BAW_FULL_NAME deployment as either a private catalog (namespace scope) or the global catalog namespace (GCN). The private option uses the same target namespace of the CP4BA deployment, the GCN uses the openshift-marketplace namespace.${RESET_TEXT}"
    while true; do
        if [[ -z "$BAW_AUTO_PRIVATE_CATALOG" ]]; then
            printf "\x1B[1mWould you like to deploy $BAW_FULL_NAME using private catalog? (Yes/No, default: Yes): \x1B[0m"
            read -rp "" ans
        else
            printf "\x1B[1mWould you like to deploy $BAW_FULL_NAME using private catalog? (Yes/No, default: Yes): $BAW_AUTO_PRIVATE_CATALOG\x1B[0m\n"
            ans=$BAW_AUTO_PRIVATE_CATALOG
        fi
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            PRIVATE_CATALOG="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            PRIVATE_CATALOG="No"
            break
            ;;
        *)
            PRIVATE_CATALOG=""
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
    # for defect https://jsw.ibm.com/browse/DBACLD-153503 where we had to update the script to set private catalog as the default option

    #handing the default case
    if [ -z "$ans" ]; then
        PRIVATE_CATALOG="Yes"
    fi
}

# Function to ask the customer if they wish to use a seperation of duties option for the installation of BAI Standalone operators
function select_separate_operator(){
    printf "\n"
    echo "${YELLOW_TEXT}[NOTES] $BAW_FULL_NAME deployment supports separation of operators and operands, the script can deploy BAW operators and BAW runtime pods in different projects.${RESET_TEXT}"
    while true; do
        if [[ -z "$BAW_AUTO_SEPARATE_OPERATOR" ]]; then
            printf "\x1B[1mWould you like to deploy $BAW_FULL_NAME with the separation of operators and operands? (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
        else
            printf "\x1B[1mWould you like to deploy $BAW_FULL_NAME with the separation of operators and operands? (Yes/No, default: No): $BAW_AUTO_SEPARATE_OPERATOR\x1B[0m\n"
            ans=$BAW_AUTO_SEPARATE_OPERATOR
        fi
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            SEPARATE_OPERATOR="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            SEPARATE_OPERATOR="No"
            break
            ;;
        *)
            SEPARATE_OPERATOR=""
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done

    MULTIPLE_DEPLOYMENT="No"
}

# Function to select the project namespace to deploy the operators
# The function also checks to make sure the project name is valid and not some of the namespaces used by the platform
# The Function calls create_project function to create the namespace if required
function select_project(){

   if [[ ! -f $OLM_CATALOG_TMP ]]; then
      cp ${OLM_CATALOG} ${OLM_CATALOG_TMP}
   fi
    
    while [[ $project_name == "" ]];
    do
        if [ -z "$BAW_AUTO_NAMESPACE" ]; then
            echo
            echo -e "\x1B[1mWhere would you like to deploy $BAW_FULL_NAME?\x1B[0m"
            read -p "Enter the name for a new namespace or an existing namespace: " project_name
        else
            if [[ "$BAW_AUTO_NAMESPACE" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name should not be 'openshift' or start with 'openshift'. \x1B[0m"
                exit 1
            elif [[ "$BAW_AUTO_NAMESPACE" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name should not be 'kube' or start with 'kube'. \x1B[0m"
                exit 1
            fi
            project_name=$BAW_AUTO_NAMESPACE
        fi
        if [ -z "$project_name" ]; then
            echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name cannot be blank.\x1B[0m"
        elif [[ "$project_name" == openshift* ]]; then
            echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name should not be 'openshift' or start with 'openshift'. \x1B[0m"
            project_name=""
        elif [[ "$project_name" == kube* ]]; then
            echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name should not be 'kube' or start with 'kube'. \x1B[0m"
            project_name=""
        else
            verify_existing_csv $project_name
            create_project $project_name
            ${CLI_CMD} create namespace ibm-cert-manager > /dev/null 2>&1
            ${CLI_CMD} create namespace ibm-licensing > /dev/null 2>&1
            
        fi
    done

    if [[ $PRIVATE_CATALOG == "Yes" ]]; then  
        info "Creating project \"$CERT_MANAGER_PROJECT\" for IBM Cert Manager operator catalog."
        create_project "$CERT_MANAGER_PROJECT"

        info "Creating project \"$LICENSE_MANAGER_PROJECT\" for IBM Licensing operator catalog."
        create_project "$LICENSE_MANAGER_PROJECT"
        sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
        # replace all other catalogs with <CP4BA NS> namespaces 
        ${SED_COMMAND} "s|namespace: .*|namespace: \"$project_name\"|g" ${OLM_CATALOG_TMP}
        # replace openshift-marketplace for ibm-cert-manager-catalog with ibm-cert-manager
        ${SED_COMMAND} "/name: ibm-cert-manager-catalog/{n;s/namespace: .*/namespace: $CERT_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}
        # replace openshift-marketplace for ibm-licensing-catalog with ibm-licensing
        ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: $LICENSE_MANAGER_PROJECT/;}" ${OLM_CATALOG_TMP}
    fi

}

function set_separate_operator_project(){
    while [[ $project_name_operator == "" ]];
    do
        if [ -z "$BAW_AUTO_OPERATOR_NAMESPACE" ]; then
            echo
            echo -e "\x1B[1mWhere do you want to deploy $BAW_FULL_NAME operators? \x1B[0m"
            read -p "Enter the name for a new project or an existing project (namespace): " project_name_operator
        else
            if [[ "$BAW_AUTO_OPERATOR_NAMESPACE" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                exit 1
            elif [[ "$BAW_AUTO_OPERATOR_NAMESPACE" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                exit 1
            fi
            project_name_operator=$BAW_AUTO_OPERATOR_NAMESPACE
        fi
        if [ -z "$project_name_operator" ]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name can not be blank.\x1B[0m"
        elif [[ "$project_name_operator" == openshift* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
            project_name_operator=""
        elif [[ "$project_name_operator" == kube* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
            project_name_operator=""
        else
            verify_existing_csv $project_name_operator
            create_project $project_name_operator
            if [[ ! ("$RUNTIME_MODE" == "baw" || $RUNTIME_MODE == "baw-dev" || "$RUNTIME_MODE" == "process-flow" || $RUNTIME_MODE == "process-flow-dev") ]]; then
                ${CLI_CMD} create namespace ibm-cert-manager > /dev/null 2>&1
                ${CLI_CMD} create namespace ibm-licensing > /dev/null 2>&1
            fi
        fi
    done

    if [[ $PRIVATE_CATALOG == "Yes" ]]; then        
        sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
        # replace all other catalogs with <BAI NS> namespaces 
        ${SED_COMMAND} "s|namespace: .*|namespace: $PROJ_NAME|g" ${OLM_CATALOG_TMP} # PROJ_NAME is set by create_project
        # replace openshift-marketplace for ibm-cert-manager-catalog with ibm-cert-manager
        ${SED_COMMAND} "/name: ibm-cert-manager-catalog/{n;s/namespace: .*/namespace: ibm-cert-manager/;}" ${OLM_CATALOG_TMP}
        # replace openshift-marketplace for ibm-licensing-catalog with ibm-licensing
        ${SED_COMMAND} "/name: ibm-licensing-catalog/{n;s/namespace: .*/namespace: ibm-licensing/;}" ${OLM_CATALOG_TMP}
    fi
    project_name=$project_name_operator
}

#function to create the project where services will be deployed
function set_separate_cpfs_service_project(){
    while [[ $project_name_cs_service == "" ]];
    do
        if [ -z "$BAW_AUTO_CS_SERVICE_NAMESPACE" ]; then
            echo
            echo -e "\x1B[1mhere would you like to deploy $BAW_FULL_NAME deployment and its services? \x1B[0m"
            read -p "Enter the name for a new project or an existing project (namespace): " project_name_cs_service
        else
            if [[ "$BAW_AUTO_CS_SERVICE_NAMESPACE" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
                exit 1
            elif [[ "$BAW_AUTO_CS_SERVICE_NAMESPACE" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
                exit 1
            elif [[ "$project_name_cs_service" == "$project_name_operator" ]]; then
                fail "\x1B[1;31mThe project name for CPfs services (IM Services) should NOT same as the project name \"$project_name_operator\" for BAW operators. \x1B[0m"
                exit 1
            fi
            project_name_cs_service=$BAW_AUTO_CS_SERVICE_NAMESPACE
        fi


        if [ -z "$project_name_cs_service" ]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name can not be blank.\x1B[0m"
        elif [[ "$project_name_cs_service" == openshift* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
            project_name_cs_service=""
        elif [[ "$project_name_cs_service" == kube* ]]; then
            echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
            project_name_cs_service=""
        elif [[ "$project_name_cs_service" == "$project_name_operator" ]]; then
            fail "\x1B[1;31mThe project name for the CPfs services (IM Services) should NOT be the same as the project name \"$project_name_operator\" for the BAW operators. \x1B[0m"
            project_name_cs_service=""
        else
            # verify_existing_csv $project_name_operator
            create_project $project_name_cs_service
        fi
    done
}

# Function to create the ibm-cp4ba-common-config configMap which consists of the operators and services namespaces for the deployment
function create_common_service_configmap(){
    local project_name_operator=$1
    local project_name_cs_service=$2
    # Adding network type and network cidr value to the common service configmap 
    # This was introduced because of the RBAC changes we made in 25.0.0
    # https://jsw.ibm.com/browse/DBACLD-173602
    local network_type_value=$3
    local network_cidr_value=$4
    info "Creating ibm-cp4ba-common-config configMap for this IBM Business Automation Workflow deployment in the project \"$project_name_cs_service\""
    mkdir -p $TEMP_FOLDER >/dev/null 2>&1

cat << EOF > ${TEMP_FOLDER}/ibm-cp4ba-common-config-configmap.yaml
# YAML template for ibm-cp4ba-common-config
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: ibm-cp4ba-common-config
  namespace: $project_name_cs_service
data:
  operators_namespace: "$project_name_operator"
  services_namespace: "$project_name_cs_service"
  network_type: "$network_type_value"
  network_cidr: "$network_cidr_value"
EOF
    ${CLI_CMD} delete -f ${TEMP_FOLDER}/ibm-cp4ba-common-config-configmap.yaml >/dev/null 2>&1
    ${CLI_CMD} apply -f ${TEMP_FOLDER}/ibm-cp4ba-common-config-configmap.yaml >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        success "The ibm-cp4ba-common-config ConfigMap for the $BAW_FULL_NAME deployment in the project \"$project_name_cs_service\" has been created."
        sleep 3
    else
        warning "Failed to create the ibm-cp4ba-common-config ConfigMap for the $BAW_FULL_NAME deployment in the project \"$project_name_cs_service\"!"
        exit 1
    fi
}

#commented out for now, might revist this later
# function set_separate_baw_service_project(){
#     while [[ $project_name_baw_service == "" ]];
#     do
#         if [ -z "$BAW_AUTO_SERVICE_NAMESPACE" ]; then
#             printf "\n"
#             echo -e "${YELLOW_TEXT}[NOTES] When you want to have multiple deployments of BAW in the same cluster sharing one namespace for operators. You can input key with comma-separated lists (for example: baw-ns1,baw-ns2,baw-ns3)${RESET_TEXT}"
#             printf "\x1B[1mWhere do you want to deploy $BAW_FULL_NAME components/services? \x1B[0m\n"
#             read -rp "The project name(s): " project_name_baw_service
#         else
#             OIFS=$IFS
#             IFS=',' read -ra project_baw_service_array <<< "$BAW_AUTO_SERVICE_NAMESPACE"
#             IFS=$OIFS

#             for item in "${project_baw_service_array[@]}"; do
#                 item=$(sed -e 's/^"//' -e 's/"$//' <<<"$item")
#                 if [[ "$item" == openshift* ]]; then
#                     echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
#                     exit 1
#                 elif [[ "$item" == kube* ]]; then
#                     echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
#                     exit 1
#                 elif [[ "$item" == "$project_name_operator" ]]; then
#                     fail "\x1B[1;31mThe project name for BAW capabilities deployment should not same as project name \"$project_name_operator\" for BAW operator. \x1B[0m"
#                     exit 1
#                 elif [[ "$item" == "$project_name_cs_service" ]]; then
#                     fail "\x1B[1;31mThe project name for BAW capabilities deployment should not same as project name \"$project_name_cs_service\" for CPfs services (IM Services). \x1B[0m"
#                     exit 1
#                 fi
#                 project_name_baw_service=$BAW_AUTO_SERVICE_NAMESPACE
#             done
#         fi

#         OIFS=$IFS
#         IFS=',' read -ra project_baw_service_array <<< "$project_name_baw_service"
#         IFS=$OIFS

#         for item in "${project_baw_service_array[@]}"; do
#             item=$(sed -e 's/^"//' -e 's/"$//' <<<"$item")
#             if [ -z "$item" ]; then
#                 echo -e "\x1B[1;31mEnter a valid project name, project name can not be blank\x1B[0m"
#             elif [[ "$item" == openshift* ]]; then
#                 echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'openshift' or start with 'openshift' \x1B[0m"
#                 project_name_baw_service=""
#             elif [[ "$item" == kube* ]]; then
#                 echo -e "\x1B[1;31mEnter a valid project name, project name should not be 'kube' or start with 'kube' \x1B[0m"
#                 project_name_baw_service=""
#             elif [[ "$item" == "$project_name_operator" ]]; then
#                 fail "\x1B[1;31mThe project name for BAW capabilities deployment should not same as project name \"$project_name_operator\" for BAW operator. \x1B[0m"
#                 project_name_baw_service=""
#             elif [[ "$item" == "$project_name_cs_service" ]]; then
#                 fail "\x1B[1;31mThe project name for BAW capabilities deployment should not same as project name \"$project_name_cs_service\" for CPfs services (IM Services). \x1B[0m"
#                 project_name_baw_service=""
#             else
#                 create_project $item
#             fi
#         done
#     done
# }

function collect_input() {
    if [[ $PRIVATE_CATALOG == "No" ]]; then
        while [[ $project_name == "" ]];
        do
            if [ -z "$BAW_AUTO_NAMESPACE" ]; then
                echo
                echo -e "\x1B[1mWhere do you want to deploy $BAW_FULL_NAME?\x1B[0m"
                read -p "Enter the name for a new project or an existing project (namespace): " project_name
            else
                if [[ "$BAW_AUTO_NAMESPACE" == openshift* ]]; then
                    echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
                    exit 1
                elif [[ "$BAW_AUTO_NAMESPACE" == kube* ]]; then
                    echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
                    exit 1
                fi
                project_name=$BAW_AUTO_NAMESPACE
            fi
            if [ -z "$project_name" ]; then
                echo -e "\x1B[1;31mEnter a valid project name. The project name can not be blank.\x1B[0m"
            elif [[ "$project_name" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
                project_name=""
            elif [[ "$project_name" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
                project_name=""
            else
                verify_existing_csv
                create_project $project_name
            fi
        done
    fi
    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        user_name=""
        select_user
    fi
}

function check_common_services_cm() {

   cs_dedicated=$(${CLI_CMD} get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_DEDICATED_NAME} | awk '{print $1}')

   cs_shared=$(${CLI_CMD} get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  | grep ${COMMON_SERVICES_CM_SHARED_NAME} | awk '{print $1}')

   if [[ "$cs_shared" != ""  ]] ; then
     #Code snippet to check if the common-services config map is still present and if so will be deleted
     isEmpty="$(${CLI_CMD} get cm -n ${COMMON_SERVICES_CM_NAMESPACE} ${COMMON_SERVICES_CM_SHARED_NAME} -o jsonpath='{ .data }' )"
     if [[ "$isEmpty" == "" ]]; then
        ${CLI_CMD} delete cm -n ${COMMON_SERVICES_CM_NAMESPACE} ${COMMON_SERVICES_CM_SHARED_NAME}
        cs_shared=""
     fi
   fi

   if [[ "$cs_dedicated" != "" && "$cs_shared" != ""  ]] ; then
     control_namespace=$( ${CLI_CMD} get cm -n ${COMMON_SERVICES_CM_NAMESPACE}  ${COMMON_SERVICES_CM_DEDICATED_NAME} -o jsonpath='{ .data.common-service-maps\.yaml }' | grep  'controlNamespace' )
   fi

  # Going to disable prompting the end user
  # for shared and dedicated Cloud Pak foundational services
  if false ;
  then
   if [[ "$cs_dedicated" == "" && "$cs_shared" == ""  ]] ;
   then

     echo -e "\x1B[1mUnable to detect a ${COMMON_SERVICES_NAME}.\x1B[0m"
     while true; do
       printf "\n"
        echo -e "\x1B[1mWould you like to continue with a dedicated ${COMMON_SERVICES_NAME} instance? (Yes/No, default: Yes)\x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"YeS"|"yES"|"YEs"|"")
           echo -e "The control namespace is a shared namespace for deploying cluster-scope resources."
           echo -e "This namespace must not be the same as any IBM Cloud Pak or foundational services instance namespace."
           echo -e "You cannot change the namespace after installing the foundational services."
           while true; do
           echo -e "Enter the control namespace for deploying cluster-scope resources."
           read -rp "" ctrl_nm
           case "$ctrl_nm" in
           "")
             echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name can not be blank.\x1B[0m"
             ;;
           "openshift"*)
              echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
             ;;
           "kube"*)
              echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
              ;;
           *)
             CTRL_NAMESPACE=$ctrl_nm
             DEDICATED_PROJECT=$project_name
              echo -e "The cluster-scope resources will be installed in $CTRL_NAMESPACE"
              while true; do
                echo -e "Do you wish to change the default dedicated project ${DEDICATED_PROJECT} where ${COMMON_SERVICES_NAME} is going to be installed?(Yes/No default: No)"
                read -rp "" change_dedicated
                case "$change_dedicated" in
                "y"|"Y"|"yes"|"Yes"|"YES"|"YeS"|"yES"|"YEs")
                  while true; do
                    echo -e "Enter the project where you want ${COMMON_SERVICES_NAME} to be installed."
                    read -rp "" new_dedicated
                    case "$new_dedicated" in
                    "")
                      echo -e "\x1B[1;31mEnter a valid namespace name. The namespace name can not be blank.\x1B[0m"
                      ;;
                    "openshift"*)
                      echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'openshift' or start with 'openshift'. \x1B[0m"
                      ;;
                    "kube"*)
                      echo -e "\x1B[1;31mEnter a valid project name. The project name should not be 'kube' or start with 'kube'. \x1B[0m"
                      ;;
                     *)
                      DEDICATED_PROJECT=$new_dedicated
                      break
                      ;;
                    esac
                  done
                  ;;
                "n"|"N"|"no"|"No"|"NO"|"nO"|"")
                  echo -e "${COMMON_SERVICES_NAME} is going to be installed in the dedicated project ${DEDICATED_PROJECT}"
                  sed -e "s/CONTROL_NAMESPACE/${CTRL_NAMESPACE}/g;s/REQUESTED_NAMESPACE/${project_name}/g;s/MAP_TO_COMMON_SERVICES_NAMESPACE/${DEDICATED_PROJECT}/g" ${COMMON_SERVICES_CM_DEDICATE_FILE} > ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME}
                  ${CLI_CMD} apply -f ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME} >> ${LOG_FILE}
                  break
                  ;;
                *)
                  echo -e "Answer must be 'Yes' or 'No'\n"
                esac
              done
             break
             ;;
           esac
           done
           break
           ;;
        "n"|"N"|"no"|"No"|"NO")
           echo -e "Continue...\n"
           break
           ;;
        *)
           echo -e "Answer must be 'Yes' or 'No'\n"
        esac
     done
   fi
  fi

   DEDICATED_PROJECT=$project_name

   if [[ "$cs_dedicated" == "" && "$cs_shared" == ""  ]] ;
   then
     sed -e "s/REQUESTED_NAMESPACE/${project_name}/g;s/MAP_TO_COMMON_SERVICES_NAMESPACE/${DEDICATED_PROJECT}/g" ${COMMON_SERVICES_CM_DEDICATE_FILE} > ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME}
     ${CLI_CMD} apply -f ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME} >> ${LOG_FILE}
     rm -fr ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME} >> ${LOG_FILE}
   elif [[ "$cs_dedicated" != "" && "$cs_shared" == "" ]] || [[ "$cs_dedicated" != "" && "$cs_shared" != "" && "$control_namespace" != "" ]];
   then
     ${CLI_CMD} get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} -n ${COMMON_SERVICES_CM_NAMESPACE} -o yaml > ${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE}
     isMetaSection=false
     requestExists=false
     rm -fr ${TEMP_FOLDER}/common-service-patch.yaml >> ${LOG_FILE}
     ${CLI_CMD} get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} -n ${COMMON_SERVICES_CM_NAMESPACE} -o jsonpath='{ .data.common-service-maps\.yaml}' > ${TEMP_FOLDER}/output-data.yaml
     while IFS='' read -r line
     do
       if [ "$line" == "  - ${project_name}" ]; then
           requestExists=true
       fi
     done < ${TEMP_FOLDER}/output-data.yaml

     rm -fr ${TEMP_FOLDER}/output-data.yaml >> ${LOG_FILE}

     if ! $requestExists ; then
       while IFS='' read -r line
       do
         if [[ "$line" == *"metadata:"* ]] ;
         then
           isMetaSection=true
        #    echo "$isMetaSection"
         fi
         if [[ "$line" == *"namespaceMapping:"*  ]] && ! $isMetaSection ;

         then
           echo "$line" >> ${TEMP_FOLDER}/common-service-patch.yaml
           printf "%-3s - requested-from-namespace:\n" >> ${TEMP_FOLDER}/common-service-patch.yaml
           printf "%-5s - ${project_name}\n" >> ${TEMP_FOLDER}/common-service-patch.yaml
           printf "%-5s map-to-common-service-namespace: ${project_name}\n" >> ${TEMP_FOLDER}/common-service-patch.yaml
         else
           echo "$line"  >> ${TEMP_FOLDER}/common-service-patch.yaml
         fi
       done < "${TEMP_FOLDER}/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE}"
       ${CLI_CMD} apply -f ${TEMP_FOLDER}/common-service-patch.yaml >>  ${LOG_FILE}
       rm -fr ${TEMP_FOLDER}/common-service-patch.yaml >> ${LOG_FILE}
     fi
   fi
}

function validate_cncf_olm(){
    if ${CLI_CMD} get deployment packageserver -n $CNCF_OLM_NAMESPACE > /dev/null 2>&1; then
       echo "OLM is already installed in $CNCF_OLM_NAMESPACE namespace, continue..."
    else

    printf "\n"
    printf "\n"
    echo -e "\x1B[1;31mDo not find Operator Lifecycle Manager (OLM) installed in namespace \"$CNCF_OLM_NAMESPACE\", which is a requirement for deployment. If the Kubernetes cluster connects to internet, the script can help install it with community version v0.20.0.\x1B[0m"
    printf "\n"

    while true; do
        printf "\x1B[1mWould you like to deploy the Operator Lifecycle Manager (OLM) in namespace \"${CNCF_OLM_NAMESPACE}\"? (Yes/No, default: No) \x1B[0m"
        if [ -z "$AUTO_INSTALL_OLM" ]; then
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                echo -e "Continue....\n"
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo -e "\x1B[1;31mYou choose not to install Operator Lifecycle Manager (OLM) automatically, Install OLM under namespace \"$CNCF_OLM_NAMESPACE\" manually...\x1B[0m"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        else
            case "$AUTO_INSTALL_OLM" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                echo -e "Continue....\n"
                break
                ;;
            "n"|"N"|"no"|"No"|"NO"|"")
                echo -e "\x1B[1;31mYou choose not to install Operator Lifecycle Manager (OLM) automatically, Install OLM under namespace \"$CNCF_OLM_NAMESPACE\" manually...\x1B[0m"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                exit 1
                ;;
            esac
        fi
     done

      echo "Installing OLM..."
      isProjExists=`kubectl get namespace $CNCF_OLM_NAMESPACE --ignore-not-found | wc -l`  >/dev/null 2>&1
      if [ $isProjExists -ne 2 ] ; then
          kubectl create namespace $CNCF_OLM_NAMESPACE
      fi
      # Must be privileged PSP because OLM util container run as root
      kubectl create rolebinding olm-admin-rolebinding --clusterrole admin --group 'system:serviceaccounts:olm' -n $CNCF_OLM_NAMESPACE

      curl -L https://github.com/operator-framework/operator-lifecycle-manager/releases/download/v0.20.0/install.sh -o olm_install.sh
      chmod +x olm_install.sh
      ./olm_install.sh v0.20.0
      echo "OLM installation completes..."
      rm -rf olm_install.sh

      while [ $(${CLI_CMD} get deployment packageserver -n $CNCF_OLM_NAMESPACE |wc -l) -lt 1 ]
      do
        echo "Wait for OLM deployment packageserver created, sleep 5 seconds"
        sleep 5
      done
    fi
}

# Create a namespace if the project entered is not a namespace found on the
function create_project() {

    local project_name=$1
    project_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$project_name")
    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        isProjExists=`${CLI_CMD} get project $project_name --ignore-not-found | wc -l`  >/dev/null 2>&1

        if [ $isProjExists -ne 2 ] ; then
            ${CLI_CMD} new-project ${project_name} >> ${LOG_FILE}
            returnValue=$?
            if [ "$returnValue" == 1 ]; then
                if [ -z "$BAW_AUTO_NAMESPACE" ]; then
                    echo -e "\x1B[1;31mInvalid project name, Enter a valid name...\x1B[0m"
                    project_name=""
                else
                    echo -e "\x1B[1;31mInvalid project name \"$BAW_AUTO_NAMESPACE\", Set a valid name...\x1B[0m"
                    exit 1
                fi
            else
                echo -e "\x1B[1mUsing project ${project_name}...\x1B[0m"
            fi
        else
            echo -e "\x1B[1mProject \"${project_name}\" already exists! Continue...\x1B[0m"
        fi
    elif [[ "$PLATFORM_SELECTED" == "other" ]]
    then
        isProjExists=`kubectl get namespace $project_name --ignore-not-found | wc -l`  >/dev/null 2>&1

        if [ $isProjExists -ne 2 ] ; then
            kubectl create namespace ${project_name} >> ${LOG_FILE}
            returnValue=$?
            if [ "$returnValue" == 1 ]; then
                if [ -z "$BAW_AUTO_NAMESPACE" ]; then
                    echo -e "\x1B[1;31mInvalid namespace name, Enter a valid name...\x1B[0m"
                    project_name=""
                else
                    echo -e "\x1B[1;31mInvalid namespace name \"$BAW_AUTO_NAMESPACE\", Set a valid name...\x1B[0m"
                    exit 1
                fi
            else
                echo -e "\x1B[1mUsing namespace ${project_name}...\x1B[0m"
            fi
        else
            echo -e "\x1B[1mName space \"${project_name}\" already exists! Continue...\x1B[0m"
        fi
    fi
    PROJ_NAME=${project_name}
}

function verify_existing_csv(){

    ${CLI_CMD} get csv --all-namespaces|grep ibm-cp4a-operator.v >/dev/null 2>&1
    exist_csv_project_array=($(${CLI_CMD} get csv --all-namespaces|grep ibm-cp4a-operator.v|awk '{print $1}'))
    returnValue=$?

    if [ "${#exist_csv_project_array[@]}" -eq "0" ]; then
        printf "\n"
        echo -e "\x1B[1mThe $BAW_FULL_NAME Operator (Pod, CSV, Subscription) not found in cluster\x1B[0m\nContinue....\n"

    else

        printf "\n"
        echo -e "\x1B[1;31mFound the existing $BAW_FULL_NAME Operator (Pod, CSV, Subscription) in different project \"${exist_csv_project_array[*]}\"! \x1B[0m\n"

        if [ -z "$BAW_AUTO_NAMESPACE" ]; then
            while true; do
                printf "\x1B[1mWould you like to deploy another $BAW_FULL_NAME Operator in new project \"${project_name}\"? (Yes/No, default: No) \x1B[0m"
                read -rp "" ans
                case "$ans" in
                "y"|"Y"|"yes"|"Yes"|"YES")
                    echo -e "Continue....\n"
                    break
                    ;;
                "n"|"N"|"no"|"No"|"NO"|"")
                    echo -e "Exit....\n"
                    exit 1
                    ;;
                *)
                    echo -e "Answer must be \"Yes\" or \"No\"\n"
                    ;;
                esac
            done
        else
            printf "\x1B[1mWould you like to deploy another $BAW_FULL_NAME Operator in new project \"${project_name}\"? (Yes/No, default: No) Yes\n\x1B[0m"
        fi
    fi
}

function verify_sc(){
    local sc="$1"
    VERIFY_SC_CMD="${CLI_CMD} get sc ${sc}"
    if $VERIFY_SC_CMD >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

function check_user_exist() {
    ${CLI_CMD} get user | grep "${user_name}" >/dev/null 2>&1
    returnValue=$?
    if [ "$returnValue" == 1 ] ; then
        echo -e "\x1B[1mUser \"${user_name}\" NOT exists! Enter an existing username in your cluster...\x1B[0m"
        user_name=""
    else
        echo -e "\x1B[1mUser \"${user_name}\" exists! Continue...\x1B[0m"
    fi
}

function bind_scc() {
    echo
    echo -ne Binding the 'privileged' role to the 'default' service account...
    dba_scc=$(${CLI_CMD} get scc privileged | awk '{print $1}' )
    if [ -n "$dba_scc" ]; then
        ${CLI_CMD} adm policy add-scc-to-user privileged -z default  >>  ${LOG_FILE}
    else
        echo "The 'privileged' security context constraint (SCC) does not exist in the cluster. Make sure that you update your environment to include this SCC."
        exit 1
    fi
    echo "Done"
}

function prepare_install() {
    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        ${CLI_CMD} project ${project_name} >> ${LOG_FILE}
    fi
    # sed -e "s/<NAMESPACE>/${project_name}/g" ${CLUSTER_ROLE_BINDING_FILE} > ${CLUSTER_ROLE_BINDING_FILE_TEMP}
    echo
    echo -ne "Creating the custom resource definition (CRD) and a service account that has the permissions to manage the resources..."
    ${CLI_CMD} apply -f ${CRD_FILE} -n ${project_name} --validate=false >/dev/null 2>&1
    echo " Done!"
    # if [[ "$DEPLOYMENT_TYPE" == "starter" ]];then
    #     ${CLI_CMD} apply -f ${CLUSTER_ROLE_FILE} --validate=false >> ${LOG_FILE}
    #     ${CLI_CMD} apply -f ${CLUSTER_ROLE_BINDING_FILE_TEMP} --validate=false >> ${LOG_FILE}
    # fi
    ${CLI_CMD} apply -f ${SA_FILE} -n ${project_name} --validate=false >> ${LOG_FILE}
    ${CLI_CMD} apply -f ${ROLE_FILE} -n ${project_name} --validate=false >> ${LOG_FILE}

    echo -n "Creating ibm-cp4a-operator role ..."
    while true ; do
        result=$(${CLI_CMD} get role -n $project_name| grep ibm-cp4a-operator)
        if [[ "$result" == "" ]] ; then
            sleep 5
            echo -n "..."
        else
            echo " Done!"
            break
        fi
    done
    echo -n "Creating ibm-cp4a-operator role binding ..."
    ${CLI_CMD} apply -f ${ROLE_BINDING_FILE} -n ${project_name} --validate=false >> ${LOG_FILE}
        echo "Done!"
        if [[ $NON_ADMIN == "false" && $user_name != "Cluster Admin" ]]; then
            if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
            echo
            echo -ne Adding the user ${user_name} to the ibm-cp4a-operator role...
            ${CLI_CMD} project ${project_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user edit ${user_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user registry-editor ${user_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user ibm-cp4a-operator ${user_name} >/dev/null 2>&1
            ${CLI_CMD} adm policy add-role-to-user ibm-cp4a-operator ${user_name} >> ${LOG_FILE}
            if [[ "$DEPLOYMENT_TYPE" == "starter" ]];then
                ${CLI_CMD} adm policy add-cluster-role-to-user ibm-cp4a-operator ${user_name} >> ${LOG_FILE}
            fi
            echo "Done!"
        fi
    fi
    echo
    echo -ne Label the default namespace to allow network policies to open traffic to the ingress controller using a namespaceSelector...
    ${CLI_CMD} label --overwrite namespace default 'network.openshift.io/policy-group=ingress'
    echo "Done!"
}


function apply_cp4a_operator(){
    ${COPY_CMD} -rf ${OPERATOR_FILE} ${OPERATOR_FILE_TMP}

    printf "\n"
    if [[ ("$SCRIPT_MODE" != "review") && ("$SCRIPT_MODE" != "OLM") ]]; then
        echo -e "\x1B[1mInstalling the $BAW_FULL_NAME operator...\x1B[0m"
    fi
    # set db2_license
    ${SED_COMMAND} '/baw_license/{n;s/value:.*/value: accept/;}' ${OPERATOR_FILE_TMP}
    # Set operator image pull secret
    ${SED_COMMAND} "s|ibm-entitlement-key|$DOCKER_RES_SECRET_NAME|g" ${OPERATOR_FILE_TMP}
    ${SED_COMMAND} "s|admin.registrykey|$DOCKER_RES_SECRET_NAME|g" ${OPERATOR_FILE_TMP}
    # Set operator image registry
    new_operator="$REGISTRY_IN_FILE\/cp\/cp4a"

    if [ "$use_entitlement" = "yes" ] ; then
        ${SED_COMMAND} "s/$REGISTRY_IN_FILE/$DOCKER_REG_SERVER/g" ${OPERATOR_FILE_TMP}
    else
        ${SED_COMMAND} "s/$new_operator/$CONVERT_LOCAL_REGISTRY_SERVER/g" ${OPERATOR_FILE_TMP}
    fi
    # if [[ "${OCP_VERSION}" == "3.11" ]];then
    #     ${SED_COMMAND} "s/\# runAsUser\: 1001/runAsUser\: 1001/g" ${OPERATOR_FILE_TMP}
    # fi

    # if [[ $INSTALLATION_TYPE == "new" ]]; then
    #     ${CLI_CMD} delete -f ${OPERATOR_FILE_TMP} >/dev/null 2>&1
    #     sleep 5
    # fi
    INSTALL_OPERATOR_CMD="${CLI_CMD} apply -f ${OPERATOR_FILE_TMP} -n $project_name"
    sleep 5
    if $INSTALL_OPERATOR_CMD ; then
        echo -e "\x1B[1mDone\x1B[0m"
    else
        echo -e "\x1B[1;31mFailed\x1B[0m"
    fi

    # ${COPY_CMD} -rf ${OPERATOR_FILE_TMP} ${OPERATOR_FILE_BAK}
    printf "\n"
    # Check deployment rollout status every 5 seconds (max 10 minutes) until complete.
    info "Waiting for the $BAW_FULL_NAME operator to be ready. This might take a few minutes..."
    ATTEMPTS=0
    ROLLOUT_STATUS_CMD="${CLI_CMD} rollout status deployment/ibm-cp4a-operator -n $project_name"
    until $ROLLOUT_STATUS_CMD || [ $ATTEMPTS -eq 120 ]; do
        $ROLLOUT_STATUS_CMD
        ATTEMPTS=$((ATTEMPTS + 1))
        sleep 5
    done
    if $ROLLOUT_STATUS_CMD ; then
        echo -e "\x1B[1mDone\x1B[0m"
    else
        echo -e "\x1B[1;31mFailed\x1B[0m"
    fi
    printf "\n"
}

function wait_for_pods_active() {

    source $BAW_CNCF_FOLDER/baw-utils.sh

    printf "\n"
    info "Waiting for BAW subscription to become active."

    if [[ $RUNTIME_MODE == "dev" ]];then
        patch_csv "ibm-content-operator" $project_name
        patch_csv "ibm-cp4a-operator" $project_name
        patch_csv "ibm-cp4a-wfps-operator" $project_name
        patch_csv "ibm-dpe-operator" $project_name
    	patch_csv "ibm-insights-engine-operator" $project_name
    	patch_csv "ibm-odm-operator" $project_name
    	patch_csv "ibm-pfs-operator" $project_name
    	patch_csv "ibm-workflow-operator" $project_name
    	patch_csv "icp4a-foundation-operator" $project_name
    fi

    wait_for_operator "${project_name}" "ibm-common-service-operator"
    wait_for_operator "${project_name}" "operand-deployment-lifecycle-manager"
    wait_for_operator "${project_name}" "ibm-content-operator"
    wait_for_operator "${project_name}" "ibm-cp4a-operator"
    wait_for_operator "${project_name}" "ibm-cp4a-wfps-operator"
    wait_for_operator "${project_name}" "ibm-dpe-operator"
    wait_for_operator "${project_name}" "ibm-insights-engine-operator"
    wait_for_operator "${project_name}" "ibm-odm-operator"
    wait_for_operator "${project_name}" "ibm-pfs-operator"
    wait_for_operator "${project_name}" "ibm-workflow-operator"
    wait_for_operator "${project_name}" "icp4a-foundation-operator"
}

# Function to install the BAW Standalone Operators
function prepare_olm_install() {
    printf "\n"
    echo -e "\x1B[1mWaiting for the $BAW_FULL_NAME operator to be ready. This might take a few minutes... \x1B[0m"
    printf "\n"

    local maxRetry=30
    if [[ $SEPARATE_OPERATOR == "Yes"  ]]; then
        project_name=$project_name_operator
    fi

    if [[ $PRIVATE_CATALOG == "Yes" ]]; then
        CATALOG_NAMESPACE=$project_name
    else
        CATALOG_NAMESPACE="openshift-marketplace"
    fi
    local temp_project_name=$project_name
    if [[ ( "$RUNTIME_MODE" == "process-flow" || $RUNTIME_MODE == "process-flow-dev" ) && "$PLATFORM_SELECTED" == "other" ]]; then
      CATALOG_NAMESPACE=$WFPS_CNCF_CATALOG_NAMESPACE
      # create docker pull secret under catalog source namespaces
      isNsExists=`${CLI_CMD} get secret "catalog-pull-secret" -n "$CATALOG_NAMESPACE" | wc -l`  >/dev/null 2>&1
      if [[ isNsExists -eq 2 ]]; then
        ${CLI_CMD} delete secret "catalog-pull-secret" -n "$CATALOG_NAMESPACE" >/dev/null 2>&1
      fi
      ${CLI_CMD} create secret docker-registry "catalog-pull-secret" --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com -n $CATALOG_NAMESPACE
    fi

    if ${CLI_CMD} get catalogsource -n $CATALOG_NAMESPACE | grep $online_source; then
        echo "Found existing ibm operator catalog source, updating it"

        if [[ $PRIVATE_CATALOG == "No" ]]; then
            sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
        fi
        ${CLI_CMD} apply -f $OLM_CATALOG_TMP
        if [ $? -eq 0 ]; then
            echo "IBM Operator Catalog source updated!"
        else
            echo "Generic Operator catalog source update failed"
            exit 1
        fi
    else
        if [[ $PRIVATE_CATALOG == "No" ]]; then
            sed "s/REPLACE_CATALOG_SOURCE_NAMESPACE/$CATALOG_NAMESPACE/g" ${OLM_CATALOG} > ${OLM_CATALOG_TMP}
        fi
        ${CLI_CMD} apply -f $OLM_CATALOG_TMP
        if [ $? -eq 0 ]; then
            echo "IBM Operator Catalog source created!"
        else
            echo "Generic Operator catalog source creation failed"
            exit 1
        fi
    fi

    info "Waiting for $BAW_FULL_NAME Operator Catalog pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        podCount=$(${CLI_CMD} get pod -n $CATALOG_NAMESPACE --no-headers | grep $online_source | grep "Running" | wc -l)
        if [[ $podCount -eq 0 ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                echo "Timeout Waiting for $BAW_FULL_NAME Operator Catalog pod to start"
                echo -e "\x1B[1mCheck the status of Pod by issue cmd: \x1B[0m"
                echo "oc describe pod $(oc get pod -n $CATALOG_NAMESPACE|grep "$online_source"|awk '{print $1}') -n $CATALOG_NAMESPACE"
                exit 1
            else
                sleep 30
                echo -n "..."
                continue
            fi
        else
            info "$BAW_FULL_NAME Operator Catalog is running..."
            ${CLI_CMD} get pod -n $CATALOG_NAMESPACE --no-headers | grep $online_source
            break
        fi
    done

    if [[ $(${CLI_CMD} get og -n "${temp_project_name}" -o=go-template --template='{{len .items}}' ) -gt 0 ]]; then
        echo "Found operator group"
        ${CLI_CMD} get og -n "${temp_project_name}"
    else
        sed "s/REPLACE_NAMESPACE/$temp_project_name/g" ${OLM_OPT_GROUP} > ${OLM_OPT_GROUP_TMP}
        ${CLI_CMD} apply -f ${OLM_OPT_GROUP_TMP}
        if [ $? -eq 0 ]
            then
            echo "$BAW_FULL_NAME Operator Group Created!"
        else
            echo "$BAW_FULL_NAME Operator Operator Group creation failed"
        fi
    fi

    sed "s/REPLACE_NAMESPACE/$temp_project_name/g" ${OLM_SUBSCRIPTION} > ${OLM_SUBSCRIPTION_TMP}

    if [[ $PRIVATE_CATALOG == "Yes" ]]; then
        ${SED_COMMAND} "s/sourceNamespace: .*/sourceNamespace: $temp_project_name/g" ${OLM_SUBSCRIPTION_TMP}
    fi

    ${YQ_CMD} w -i ${OLM_SUBSCRIPTION_TMP} spec.source $online_source

    ${CLI_CMD} apply -f ${OLM_SUBSCRIPTION_TMP}
    if [ $? -eq 0 ]
        then
        info "$BAW_FULL_NAME Operator Subscription Created!"
    else
        fail "$BAW_FULL_NAME Operator Subscription creation failed"
        exit 1
    fi

   printf "\n"
   info "Waiting for $BAW_FULL_NAME operator pod initialization"
   for ((retry=0;retry<=${maxRetry};retry++)); do
        #checking if ibm-dpe-operator is present and if so checking if the pod is running
        # DPE only support x86 so check the target cluster arch type
        #arch_type=$(kubectl get cm cluster-config-v1 -n kube-system -o yaml | grep -i architecture|tail -1| awk '{print $2}')
        #if [[ "$arch_type" == "amd64" ]]; then
        #    ibmDpePodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-dpe-operator | wc -l)
        #    if [[ $ibmDpePodPresent -eq 1 ]]; then
        #        ibmDpePodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-dpe-operator | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}' | wc -l)
        #    else
        #        ibmDpePodCount=0
        #    fi
        #else
        #    ibmDpePodCount=1
        #fi

        #checking if ibm-insights-engine-operator is present and if so checking if the pod is running
        #ibmInsightsEnginePodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-insights-engine-operator | wc -l)
        #if [[ $ibmInsightsEnginePodPresent -eq 1 ]]; then
        #    ibmInsightsEnginePodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-insights-engine-operator | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}' | wc -l)
        #else
        #    ibmInsightsEnginePodCount=0
        #fi

        #checking if ibm-ads-operator is present and if so checking if the pod is running
        #ibmADSOperatorPodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-ads-operator | wc -l)
        #if [[ $ibmADSOperatorPodPresent -eq 1 ]]; then
        #    ibmADSOperatorPodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-ads-operator | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}' | wc -l)
        #else
        #    ibmADSOperatorPodCount=0
        #fi

        #checking if ibm-common-service-operator is present and if so checking if the pod is running
        ibmCommonServicesPodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-common-service-operator | wc -l)
        if [[ $ibmCommonServicesPodPresent -eq 1 ]]; then
            ibmCommonServicesPodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-common-service-operator | head -1 | awk '{print $1}' | wc -l)
        else
            ibmCommonServicesPodCount=0
        fi

        #checking if ibm-odm-operator is present and if so checking if the pod is running
        #ibmODMPodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-odm-operator | wc -l)
        #if [[ $ibmODMPodPresent -eq 1 ]]; then
        #    ibmODMPodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-odm-operator | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}' | wc -l)
        #else    
        #    ibmODMPodCount=0
        #fi
        
        #checking if ibm-pfs-operator is present and if so checking if the pod is running
        ibmPFSPodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep ibm-pfs-operator | wc -l)
        if [[ $ibmPFSPodPresent -eq 1 ]]; then
            ibmPFSPodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep ibm-pfs-operator |  head -1 | awk '{print $1}' | wc -l)
        else    
            ibmPFSPodCount=0
        fi

        #checking if icp4a-foundation-operator is present and if so checking if the pod is running
        foundationPodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep icp4a-foundation-operator | wc -l)
        if [[ $foundationPodPresent -eq 1 ]]; then
            foundationPodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep icp4a-foundation-operator | head -1 | awk '{print $1}' | wc -l)
        else   
            foundationPodCount=0
        fi

        #checking if operand-deployment-lifecycle-manager is present and if so checking if the pod is running
        operandLifeCyclePodPresent=$(${CLI_CMD} get pod -n "$temp_project_name" --no-headers --ignore-not-found | grep operand-deployment-lifecycle-manager | wc -l)
        if [[ $operandLifeCyclePodPresent -eq 1 ]]; then
            operandLifeCyclePodCount=$(oc get pod -n "$temp_project_name" -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep operand-deployment-lifecycle-manager | head -1 | awk '{print $1}' | wc -l)
        else    
            operandLifeCyclePodCount=0
        fi    
        podList=($podCount $ibmCommonServicesPodCount $ibmPFSPodCount $foundationPodCount $operandLifeCyclePodCount)
         

      #if any of the podCounts are zero then that means all pods are not ready and we need to wait for them to get ready
      if echo "${podList[@]}" | grep -qw 0; then
        if [[ $retry -eq ${maxRetry} ]]; then
          echo "Timeout waiting for $BAW_FULL_NAME operator to start"
          echo -e "\x1B[1mCheck the status of Pod by issue cmd:\x1B[0m"
        echo "oc describe pod $(oc get pod -n $temp_project_name|grep ibm-cp4a-operator|awk '{print $1}') -n $temp_project_name"
        printf "\n"
        echo -e "\x1B[1mCheck the status of ReplicaSet by issue cmd:\x1B[0m"
        echo "oc describe rs $(oc get rs -n $temp_project_name|grep ibm-cp4a-operator|awk '{print $1}') -n $temp_project_name"
          
        #   printf "\n"
        #   echo -e "\x1B[1mPlease check the status of PVC by issue cmd:\x1B[0m"
        #   echo "oc describe pvc $(oc get pvc -n $temp_project_name|grep operator-shared-pvc|awk '{print $1}') -n $temp_project_name"
        #   echo "oc describe pvc $(oc get pvc -n $temp_project_name|grep cp4a-shared-log-pvc|awk '{print $1}') -n $temp_project_name"
          exit 1
        else
          sleep 30
          echo -n "..."
          continue
        fi
      else

        wait_for_pods_active

        printf "\n"
        echo "$BAW_FULL_NAME operator is running..."
        ${CLI_CMD} get pod -n "$temp_project_name" -l=name=ibm-cp4a-operator -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}'
        break
      fi
    done

    echo
    if [[ $NON_ADMIN == "false" && $user_name != "Cluster Admin" ]]; then
        echo -ne Adding the user ${user_name} to the ibm-cp4a-operator role...
        role_name_olm=$(${CLI_CMD} get role -n "$temp_project_name" --no-headers|grep ibm-cp4a-operator.v|awk '{print $1}')
        if [[ -z $role_name_olm ]]; then
            echo "No role found for $BAW_FULL_NAME operator"
            exit 1
        else
            ${CLI_CMD} project ${temp_project_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user edit ${user_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user registry-editor ${user_name} >> ${LOG_FILE}
            ${CLI_CMD} adm policy add-role-to-user $role_name_olm ${user_name} >/dev/null 2>&1
            ${CLI_CMD} adm policy add-role-to-user $role_name_olm ${user_name} >> ${LOG_FILE}
            echo "Done!"
        fi
    fi
    echo
    echo -ne Label the default namespace to allow network policies to open traffic to the ingress controller using a namespaceSelector...
    ${CLI_CMD} label --overwrite namespace default 'network.openshift.io/policy-group=ingress'
    echo "Done"
}

function setup_separate_operator(){
    if [[ $MULTIPLE_DEPLOYMENT = "No" ]]; then
        if [[ $PRIVATE_CATALOG == "Yes" ]]; then
            info "Setting up the separation of operator and services for $BAW_FULL_NAME."
            $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $project_name_operator --services-namespace $project_name_cs_service --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog --license-accept
            success "Finished setting up the separate of operator and service for $BAW_FULL_NAME."
        else
            info "Setting up the separation of operator and services for $BAW_FULL_NAME."
            $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $project_name_operator --services-namespace $project_name_cs_service --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -n openshift-marketplace --license-accept
            success "Finished setting up the separate of operator and service for $BAW_FULL_NAME."
        fi
    elif [[ $MULTIPLE_DEPLOYMENT = "Yes" ]]; then
        local namespace_number=${#project_name_cp4ba_service[@]}
        delim=""
        baw_service_namespace_joined=""
        for ((j=0;j<${namespace_number};j++)); do
            baw_service_namespace_joined="$baw_service_namespace_joined$delim${project_service_array[j]}"
            delim=","
        done

        if [[ $PRIVATE_CATALOG == "Yes" ]]; then
            info "Setting up the separation of operator and services for $BAW_FULL_NAME."
            $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $project_name_operator --services-namespace $project_name_cs_service --tethered-namespaces $baw_service_namespace_joined --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION --enable-private-catalog --license-accept
            success "Finished setting up the separation of operator and services for $BAW_FULL_NAME."
        else
            info "Setting up the separation of operator and services for $BAW_FULL_NAME."
            $COMMON_SERVICES_SCRIPT_FOLDER/setup_tenant.sh --operator-namespace $project_name_operator --services-namespace $project_name_cs_service --tethered-namespaces $baw_service_namespace_joined --yq "$CPFS_YQ_PATH" -c $CS_CHANNEL_VERSION -s $CS_CATALOG_VERSION -n openshift-marketplace --license-accept
            success "Finished setting up the separation of operator and services for $BAW_FULL_NAME."
        fi
    fi
}

function check_existing_sc(){
# Check existing storage class
    sc_result=$(${CLI_CMD} get sc 2>&1)

    sc_substring="No resources found"
    if [[ $sc_result == *"$sc_substring"* ]];
    then
        clear
        echo -e "\x1B[1;31mAt least one dynamic storage class must be available in order to proceed.\n\x1B[0m"
        echo -e "\x1B[1;31mRefer to the README for the requirements and instructions.  The script will now exit!.\n\x1B[0m"
        exit 1
    fi
}


# Function to display the airgap mode prerequisites and also give the user an option to continue or rerun the script
function display_airgap_prerequisites(){
    printf "\n"
    echo "${YELLOW_TEXT}ATTENTION:${RESET_TEXT}"
    printf "\x1B[1;31mMake sure that you have completed the following checklist items before proceeding with the offline/airgap cluster setup mode\n\x1B[0m"
    printf "\x1B[1;31m1) Mirroring of Images to the Private Registry \n\x1B[0m"
    printf "\x1B[1;31m2) Update Global Pull Secret to include login credentials to the Private Registry images have been mirrored into \n\x1B[0m"
    printf "\x1B[1;31m3) Creation of appropriate Image Content Source Policy that reflects the Private Registry \n\x1B[0m"
    printf "\n"
    printf "\x1B[1;31mFollow the instructions to complete the above steps if required \n\x1B[0m"
    printf "\n" # TODO update link
    printf "\x1B[1;31mhttps://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/24.0.0?topic=icmppd-option-2-preparing-your-cluster-air-gapped-offline-deployment \n\x1B[0m"
    printf "\n"
    printf "\x1B[1mDo you want to proceed with the offline/airgap cluster setup (Yes/No, default: No): \x1B[0m"
    read -rp "" ans
    printf "\n"
    case "$ans" in
    "y"|"Y"|"yes"|"Yes"|"YES")
        printf "Starting with the offline/airgap cluster setup process...."
        break
        ;;
    "n"|"N"|"no"|"No"|"NO"|"")
        echo "Complete the offline/airgap prerequisite steps and re-run the script"
        printf "\n"
        echo "Exiting....."
        exit 1
        break
        ;;
    *)
        echo -e "Answer must be \"Yes\" or \"No\"\n"
        ;;
    esac


}

function verify_entitlement_key(){

  local DOCKER_REG_SERVER=$1

  ATTEMPTS=0
  while [[ $entitlement_key == '' ]]
  do
      if [ -z "$BAW_AUTO_ENTITLEMENT_KEY" ]; then
          read -rsp "" entitlement_key
      else
          entitlement_key=$BAW_AUTO_ENTITLEMENT_KEY
      fi
      if [ -z "$entitlement_key" ]; then
          printf "\n"
          echo -e "\x1B[1;31mEnter a valid Entitlement Registry key\x1B[0m"
      else
          if  [[ $entitlement_key == iamapikey:* ]] ;
          then
              DOCKER_REG_USER="iamapikey"
              reg_key="${entitlement_key#*:}"
          else
              DOCKER_REG_USER="cp"
              reg_key=$entitlement_key

          fi

          if [[ "$DOCKER_REG_SERVER" == "cp.stg.icr.io" ]]
          then
            DOCKER_REG_KEY_STG=$reg_key
            DOCKER_REG_USER_STG=$DOCKER_REG_USER
          else
            DOCKER_REG_KEY=$reg_key
          fi

          entitlement_verify_passed=""
          while [[ $entitlement_verify_passed == '' ]]
          do
              printf "\n"
              printf "\x1B[1mVerifying the Entitlement Registry key...\n\x1B[0m"

              if [[ $PODMAN_FOUND == "No" ]]; then
              cli_command="docker"
              else
              cli_command="podman"
              fi

              if $cli_command login -u "$DOCKER_REG_USER" -p "$reg_key" "$DOCKER_REG_SERVER"; then
                  printf 'Entitlement Registry key is valid.\n'
                  entitlement_verify_passed="passed"
              else
                  printf '\x1B[1;31mThe Entitlement Registry key failed. Try again...\n\x1B[0m'
                  ATTEMPTS=$((ATTEMPTS + 1))
                  if [[ $ATTEMPTS -eq 10 ]]; then
                      printf '\x1B[1mEnter a valid Entitlement Registry key. Exiting ...\n\x1B[0m'
                      exit 1
                  fi
                  entitlement_key=''
                  entitlement_verify_passed="failed"
              fi
          done
      fi
  done

  if [[ $entitlement_verify_passed != $PASSED ]]; then
        printf "\x1B[1;31m Entitlement Key is not Valid!, exiting...\n\x1B[0m"
        exit 1
    fi

  echo "$entitlement_verify_passed"

}


# Function that asks for the entitlement key and verifies it
# For dev mode it verifies against icr.io
function get_entitlement_registry(){

    if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
    then
        get_stg_entitlement_registry
    fi

    # For Entitlement Registry key
    entitlement_key=""
    printf "\n"
    printf "\n"
    printf "\x1B[1;31mFollow the instructions on how to get your Entitlement Key: \n\x1B[0m" # TODO update link
    printf "\x1B[1;31m https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE?topic=deployment-getting-access-images-from-public-entitled-registry\n\x1B[0m"
    printf "\n"
    while true; do
        if [[ ! -z "$BAW_AUTO_ENTITLEMENT_KEY" && ! -z "$BAW_AUTO_LOCAL_REGISTRY" ]]; then
            echo -e "\x1B[1;31mSet one the following environment variables [BAW_AUTO_ENTITLEMENT_KEY] or [BAW_AUTO_LOCAL_REGISTRY]\x1B[0m"
            echo -e "Exiting..."
            exit 1
        fi

        if [[ -z "$BAW_AUTO_ENTITLEMENT_KEY" && ! -z "$BAW_AUTO_LOCAL_REGISTRY" ]]; then
            printf "\x1B[1mDo you have a $BAW_FULL_NAME Entitlement Registry key (Yes/No, default: No):\x1B[0m No"
            ans="No"
        fi
        if [[ -z "$BAW_AUTO_LOCAL_REGISTRY" && ! -z "$BAW_AUTO_ENTITLEMENT_KEY" ]]; then
            printf "\x1B[1mDo you have a $BAW_FULL_NAME Entitlement Registry key (Yes/No, default: No):\x1B[0m Yes"
            ans="Yes"
        fi

        if [[ -z "$BAW_AUTO_ENTITLEMENT_KEY" && -z "$BAW_AUTO_LOCAL_REGISTRY" ]]; then
            printf "\x1B[1mDo you have a $BAW_FULL_NAME Entitlement Registry key (Yes/No, default: No): \x1B[0m"
            read -rp "" ans
        fi

        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            use_entitlement="yes"
            printf "\n"
            printf "\x1B[1mEnter your Entitlement Registry key: \x1B[0m"
            # During dev, OLM uses stage image repo
            DOCKER_REG_SERVER="cp.icr.io"
            PASSED="passed"

            # During dev, OLM uses stage image repo
            verify_entitlement_key $DOCKER_REG_SERVER
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            use_entitlement="no"
            DOCKER_REG_KEY="None"
            if [[ $PRIVATE_CATALOG == "No" ]]; then
                if [[ "$PLATFORM_SELECTED" == "ROKS" || "$PLATFORM_SELECTED" == "OCP" ]]; then
                    printf "\n"
                    printf "\x1B[1;31mIBM $BAW_FULL_NAME only supports the Entitlement Registry on \"${PLATFORM_SELECTED}\", exiting...\n\x1B[0m"
                    exit 1
                else
                    break
                fi
            else
                break
            fi
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

# Function that asks for the stg entitlement key and verifies it
# For dev mode it verifies against cp.stg.icr.io
function get_stg_entitlement_registry(){

    # For Entitlement Registry key
    entitlement_key=""

    while true; do

        printf "\x1B[1mDo you have a $BAW_FULL_NAME Staging Entitlement Registry key (Yes/No, default: No): \x1B[0m"
        read -rp "" ans

        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            use_entitlement="yes"
            printf "\n"
            printf "\x1B[1mEnter your Staging Entitlement Registry key: \x1B[0m"
            # During dev, OLM uses stage image repo
            DOCKER_REG_SERVER="cp.stg.icr.io"
            PASSED="passed"

            verify_entitlement_key $DOCKER_REG_SERVER
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            use_entitlement="no"
            DOCKER_REG_KEY="None"
            if [[ $PRIVATE_CATALOG == "No" ]]; then
                if [[ "$PLATFORM_SELECTED" == "ROKS" || "$PLATFORM_SELECTED" == "OCP" ]]; then
                    printf "\n"
                    printf "\x1B[1;31mIBM $BAW_FULL_NAME only supports the Entitlement Registry on \"${PLATFORM_SELECTED}\", exiting...\n\x1B[0m"
                    exit 1
                else
                    break
                fi
            else
                break
            fi
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

function get_domain_name(){
    valiateIngress=false

    # For Entitlement Registry key
    domain_name=""
    if [ $validateIngress ] ; then
      printf "\n"
      printf "\n"
      printf "\x1B[1;31mYou need to setup ingress controller on Kubernetes cluster, you can follow below instruction with ingress NGINX controller.  \n\x1B[0m"
      printf "\x1B[1;31mhttps://github.com/kubernetes/ingress-nginx\n\x1B[0m"
    fi

    printf "\n"

    while [[ $domain_name == '' ]]
    do
        if [ -z "$AUTO_DOMAIN_NAME" ]; then
            read -p "Enter your domain name(for none 443 port), Also append port number, such as domain_name:port): " domain_name
        else
            domain_name=$AUTO_DOMAIN_NAME
        fi
        if [ -z "$domain_name" ]; then
            printf "\n"
            echo -e "\x1B[1;31mEnter a valid domain name: \x1B[0m"
        else
          CNCF_DOMAIN_NAME=$domain_name

          if [ $validateIngress ] ; then
            echo -e "\x1B[1mPreparing the ingress testing environment...\x1B[0m"
            hostname=$(echo "$domain_name" | sed 's|:.*||')
            # validate domain name works
            # prepare test ingress controller
            isNsExists=`kubectl get namespace "ingress-free-test" --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ $isNsExists -eq 2 ] ; then
              ${CLI_CMD} delete namespace "ingress-free-test" >/dev/null 2>&1
            fi
            ${CLI_CMD} create namespace "ingress-free-test" >/dev/null 2>&1
            if ${CLI_CMD} get ingress demo -n ingress-free-test > /dev/null 2>&1; then
              echo "ingress test prepare ready, skip prepare"
            else
              ${CLI_CMD} create deployment demo --image=httpd --port=80 -n ingress-free-test
              ${CLI_CMD} expose deployment demo -n ingress-free-test
              ${CLI_CMD} create ingress demo --class=nginx --rule=demo.$hostname/*=demo:80 -n ingress-free-test
            fi
            # test the ingress works
            set +e
            count=5
            curl https://demo.$domain_name --insecure |grep 'It works!'
            curl_result=$?
            echo "curl command execution result is: $curl_result"
            while [ ! $curl_result -eq 0 ]
            do
              echo "Ingress do not work, sleep 5 seconds, try max $count times"
              count=$(( count-1 ))
              sleep 5
              if [ $count -eq 0 ]
              then
                printf "\x1B[1;31mIngress controller is not deployed properly, Check the Details.  \n\x1B[0m"
                exit 1
              fi
              curl https://demo.$domain_name --insecure |grep 'It works!'
              curl_result=$?
            done
            echo "Ingress test passed, continue..."
            CNCF_DOMAIN_NAME=$domain_name
            # delete ingress test namespace
            ${CLI_CMD} delete namespace "ingress-free-test" >/dev/null 2>&1
            set -e
          fi
        fi
    done
}

function create_secret_entitlement_registry(){
    # Create docker-registry secret for Entitlement Registry Key in target project
    if [[ $SEPARATE_OPERATOR == "No" || -z $SEPARATE_OPERATOR ]]; then
        printf "\x1B[1mCreating docker-registry secret for Entitlement Registry key in project $project_name...\n\x1B[0m"

        ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" -n "${project_name}" >/dev/null 2>&1

        if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
        then
            ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME_STG" -n "${project_name}" >/dev/null 2>&1
        fi

        CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com -n $project_name"

        if $CREATE_SECRET_CMD ; then
            echo -e "\x1B[1mDone\x1B[0m"
        else
            echo -e "\x1B[1mFailed\x1B[0m"
        fi

        if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
        then
            CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME_STG --docker-server=$STG_REGISTRY_IN_FILE --docker-username=$DOCKER_REG_USER_STG --docker-password=$DOCKER_REG_KEY_STG --docker-email=ecmtest@ibm.com -n $project_name"

            if $CREATE_SECRET_CMD ; then
                echo -e "\x1B[1mDone\x1B[0m"
            else
                echo -e "\x1B[1mFailed\x1B[0m"
            fi
        fi
    else
        # Create docker registry key in the seperate operator scenario
        printf "\x1B[1mCreating docker-registry secret for Entitlement Registry key in project $project_name_operator...\n\x1B[0m"
        ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" -n "${project_name_operator}" >/dev/null 2>&1

        CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com -n $project_name_operator"
        if $CREATE_SECRET_CMD ; then
            echo -e "\x1B[1mDone\x1B[0m"
        else
            echo -e "\x1B[1mFailed\x1B[0m"
        fi

        if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
        then
            printf "\x1B[1mCreating docker-registry secret for staging Entitlement Registry key in project $project_name_operator...\n\x1B[0m"
            CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME_STG --docker-server=$STG_REGISTRY_IN_FILE --docker-username=$DOCKER_REG_USER_STG --docker-password=$DOCKER_REG_KEY_STG --docker-email=ecmtest@ibm.com -n $project_name_operator"

            if $CREATE_SECRET_CMD ; then
                echo -e "\x1B[1mDone\x1B[0m"
            else
                echo -e "\x1B[1mFailed\x1B[0m"
            fi
        fi

        printf "\x1B[1mCreating docker-registry secret for Entitlement Registry key in project $project_name_cs_service...\n\x1B[0m"
        ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" -n "${project_name_cs_service}" >/dev/null 2>&1

        CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com -n $project_name_cs_service"
        if $CREATE_SECRET_CMD ; then
            echo -e "\x1B[1mDone\x1B[0m"
        else
            echo -e "\x1B[1mFailed\x1B[0m"
        fi

        if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
        then
            printf "\x1B[1mCreating docker-registry secret for staging Entitlement Registry key in project $project_name_cs_service...\n\x1B[0m"
            CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME_STG --docker-server=$STG_REGISTRY_IN_FILE --docker-username=$DOCKER_REG_USER_STG --docker-password=$DOCKER_REG_KEY_STG --docker-email=ecmtest@ibm.com -n $project_name_cs_service"

            if $CREATE_SECRET_CMD ; then
                echo -e "\x1B[1mDone\x1B[0m"
            else
                echo -e "\x1B[1mFailed\x1B[0m"
            fi
        fi
    fi
    if [[ $MULTIPLE_DEPLOYMENT = "Yes" ]]; then
        for item in "${project_baw_service_array[@]}"; do
            printf "\x1B[1mCreating docker-registry secret for Entitlement Registry key in project $item...\n\x1B[0m"
            ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME" -n "${item}" >/dev/null 2>&1

            if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
            then
                ${CLI_CMD} delete secret "$DOCKER_RES_SECRET_NAME_STG" -n "${item}" >/dev/null 2>&1
            fi

            CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$DOCKER_REG_SERVER --docker-username=$DOCKER_REG_USER --docker-password=$DOCKER_REG_KEY --docker-email=ecmtest@ibm.com -n $item"
            if $CREATE_SECRET_CMD ; then
                echo -e "\x1B[1mDone\x1B[0m"
            else
                echo -e "\x1B[1mFailed\x1B[0m"
            fi

            if [[ "$RUNTIME_MODE" == "dev" || $RUNTIME_MODE == "baw-dev" || $RUNTIME_MODE == "process-flow-dev" ]]
            then
                printf "\x1B[1mCreating docker-registry secret for staging Entitlement Registry key in project $item...\n\x1B[0m"
                CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME_STG --docker-server=$STG_REGISTRY_IN_FILE --docker-username=$DOCKER_REG_USER_STG --docker-password=$DOCKER_REG_KEY_STG --docker-email=ecmtest@ibm.com -n $item"

                if $CREATE_SECRET_CMD ; then
                    echo -e "\x1B[1mDone\x1B[0m"
                else
                    echo -e "\x1B[1mFailed\x1B[0m"
                fi
            fi

        done
    fi
}

function get_storage_class_name(){
    if [[ $PLATFORM_SELECTED == "other" || $PLATFORM_SELECTED == "OCP" ]]; then
        check_existing_sc
    fi
    check_storage_class
}
function display_storage_classes() {
    echo
    echo "Storage classes are needed to run the deployment script. For a "Production" deployment, the deployment script will ask for three (3) storage classes to meet the "slow", "medium", and "fast" storage for the configuration of $BAW_FULL_NAME components.  If you don't have three (3) storage classes, you can use the same one for "slow", "medium", or fast.  Note that you can get the existing storage class(es) in the environment by running the following command: oc get storageclass. Take note of the storage classes that you want to use for deployment. "
	${CLI_CMD} get storageclass
}

function display_storage_classes_existing() {
    echo
    echo -e "\x1B[1mThe existing storage classes in the cluster: \x1B[0m"
	${CLI_CMD} get storageclass
}

function display_node_name() {
    echo
    if  [[ $PLATFORM_VERSION == "3.11" ]];
    then
        echo "Below is the host name of the Infrastructure Node for the environment, which is required as an input during the execution of the deployment script for the creation of routes in OCP.  You can also get the host name by running the following command: ${CLI_CMD} get nodes --selector node-role.kubernetes.io/infra=true -o custom-columns=":metadata.name". Take note of the host name. "
	${CLI_CMD} get nodes --selector node-role.kubernetes.io/infra=true -o custom-columns=":metadata.name"
    elif  [[ $PLATFORM_VERSION == "4.4OrLater" ]];
    then
        echo "Below is the route host name for the environment, which is required as an input during the execution of the deployment script for the creation of routes in OCP. You can also get the host name by running the following command: oc get IngressController default -n openshift-ingress-operator -o yaml|grep \" domain\". Take note of the host name. "
        ${CLI_CMD} get IngressController default -n openshift-ingress-operator -o yaml|grep " domain" | head -1 | cut -d ' ' -f 4
    fi
}


function create_scc() {
    ${CLI_CMD} create serviceaccount ibm-pfs-es-service-account
    ${CLI_CMD} create -f ibm-pfs-privileged-scc.yaml
    ${CLI_CMD} adm policy add-scc-to-user ibm-pfs-privileged-scc -z ibm-pfs-es-service-account
}


function clean_up(){
    local files=()
    if [[ -d $TEMP_FOLDER ]]; then
        files=($(find $TEMP_FOLDER -name '*.yaml'))
        for item in ${files[*]}
        do
            rm -rf $item >/dev/null 2>&1
        done

        files=($(find $TEMP_FOLDER -name '*.swp'))
        for item in ${files[*]}
        do
            rm -rf $item >/dev/null 2>&1
        done
    fi
}

#Function to ask if customer wants to set up cluster in airgap mode
function check_airgap_mode(){
    printf "\n"
    # clear
    if [ -z "$BAW_AUTO_AIGRAP_MODE" ]; then
        COLUMNS=12
        echo -e "\x1B[1mWould you like to set up the cluster for an online based $BAW_FULL_NAME deployment or for an airgap/offline based BAW deployment: \x1B[0m"


        options=("Online" "Offline/Airgap")
        PS3='Enter a valid option [1 to 2]: '

        select opt in "${options[@]}"
        do
            case $opt in
                "Offline/Airgap")
                    AIRGAP_INSTALL="Yes"
                    break
                    ;;
                "Online")
                    AIRGAP_INSTALL="No"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        AIRGAP_INSTALL=$BAW_AUTO_AIGRAP_MODE
        echo -e "\x1B[1mWould you like to set up the cluster for an online based $BAW_FULL_NAME deployment or for an airgap/offline based BAW deployment :\x1B[0m $BAW_AUTO_AIGRAP_MODE"
    fi
}

function select_platform(){
    printf "\n"
    # clear
    if [ -z "$BAW_AUTO_PLATFORM" ]; then
        COLUMNS=12
        echo -e "\x1B[1mSelect the cloud platform to deploy: \x1B[0m"
        
        #Adding support for the other type of platform
        # DBACLD-168151
        otherOption="Other ( Rancher Kubernetes Engine (RKE) / VMware Tanzu Kubernetes Grid Integrated Edition (TKGI) )"
      options=("Openshift Container Platform (OCP) - Private Cloud")
      PS3='Enter a valid option [1 to 2]: '
        # For airgap deployment only ROKS and OCP is supported
        if [[ $AIRGAP_INSTALL == "Yes" ]]; then
            #options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
            options=("Openshift Container Platform (OCP) - Private Cloud" "$otherOption")
            PS3='Enter a valid option [1 to 2]: '
        else
            #Adding support for the other type of platform
            # DBACLD-168151
            otherOption="Other ( Rancher Kubernetes Engine (RKE) / VMware Tanzu Kubernetes Grid Integrated Edition (TKGI) )"
            #options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "$otherOption")
            options=("Openshift Container Platform (OCP) - Private Cloud" "$otherOption")
            PS3='Enter a valid option [1 to 2]: '
        fi

        # if [[ "${SCRIPT_MODE}" == "OLM" ]]; then
        #     options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud")
        #     PS3='Enter a valid option [1 to 2]: '
        # else
        #     options=("RedHat OpenShift Kubernetes Service (ROKS) - Public Cloud" "Openshift Container Platform (OCP) - Private Cloud" "Other ( Certified Kubernetes Cloud Platform / CNCF)")
        #     PS3='Enter a valid option [1 to 3]: '
        # fi
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
                #Adding support for the other type of platform
                # DBACLD-168151
                "$otherOption")
                    PLATFORM_SELECTED="other"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        PLATFORM_SELECTED=$BAW_AUTO_PLATFORM
        echo -e "\x1B[1mWhat type of cloud platform is selected?\x1B[0m $BAI_AUTO_PLATFORM"
    fi

    # For other type of platform we also ask what type of other type of platform
    # This helps us identify if we need different tanzu and rancher related setup and conditions
    # DBACLD-168151
    if [[ "$PLATFORM_SELECTED" == "other" ]]; then
        SCRIPT_MODE="OLM"
        CLI_CMD=kubectl
        echo -e "\x1B[1mSpecify the other type of cloud platform to deploy: \x1B[0m"
        otheroption1="VMware Tanzu Kubernetes Grid Integrated Edition (TKGI)"
        otheroption2="Rancher Kubernetes Engine (RKE)"
        options=("$otheroption1" "$otheroption2")
        PS3='Enter a valid option [1 to 2]: '
        select opt in "${options[@]}"
        do
            case $opt in
                "$otheroption1")
                    OTHER_PLATFROM_TYPE="tanzu"
                    break
                    ;;
                "$otheroption2")
                    OTHER_PLATFROM_TYPE="rancher"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    fi 
    if [[ "$PLATFORM_SELECTED" == "OCP" || "$PLATFORM_SELECTED" == "ROKS" ]]; then
        SCRIPT_MODE="OLM"
        CLI_CMD=oc
    elif [[ "$PLATFORM_SELECTED" == "other" ]]
    then
        SCRIPT_MODE="OLM"
        CLI_CMD=kubectl
    fi
}


function select_deployment_type(){
    printf "\n"
    DEPLOYMENT_TYPE="production"
    info "${YELLOW_TEXT}$BAW_FULL_NAME only supports production deployment.${RESET_TEXT}"

}

function select_user(){
    user_result=$(${CLI_CMD} get user 2>&1)
    user_substring="No resources found"
    user_forbidden="cannot list resource"
    NON_ADMIN="false"
    if [[ $user_result == *"$user_substring"* ]];
    then
        clear
        echo -e "\x1B[1m[INFO] No user found in cluster.\n\x1B[0m"
        echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1mWhen running the baw-deployment.sh script, Use the cluster admin user.\n\x1B[0m"
        NON_ADMIN="true"
        sleep 5
    fi
    if [[ $user_result == *"$user_forbidden"* ]];
    then
        clear
        echo -e "\x1B[1;31mLog in to the target cluster as the <cluster-admin> user.\n\x1B[0m"
        echo -e "\x1B[1;31mThe script will now exit...!\n\x1B[0m"
        exit 1
    fi
    echo
    if [[ $NON_ADMIN == "false" ]]; then
        if [ -z "$BAW_AUTO_CLUSTER_USER" ]; then
            userlist=$(${CLI_CMD} get user|awk '{if(NR>1){if(NR==2){ arr=$1; }else{ arr=arr" "$1; }} } END{ print arr }')
            COLUMNS=12
            echo -e "\x1B[1mHere are the existing users on this cluster: \x1B[0m"
            options=($userlist)
            options=( "Cluster Admin" "${options[@]}" )
            usernum=${#options[*]}
            PS3='Enter an existing username in your cluster, valid option [1 to '${usernum}'], non-admin is suggested: '
            select opt in "${options[@]}"
            do
                if [[ -n "$opt" && "${options[@]}" =~ $opt ]]; then
                    user_name=$opt
                    break
                else
                    echo "invalid option $REPLY"
                fi
            done
            if [ "$user_name" == "Cluster Admin" ]; then
                echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1mWhen running the baw-deployment.sh script, Use the cluster admin user.\x1B[0m"
                sleep 5
            fi
        else
            ${CLI_CMD} get user ${BAW_AUTO_CLUSTER_USER} >/dev/null 2>&1
            returnValue=$?
            if [ "$returnValue" == 1 ]; then
                echo -e "\x1B[1;31mNo found user \"${BAW_AUTO_CLUSTER_USER}\"!\n\x1B[0m"
                echo -e "\x1B[33;5mATTENTION: \x1B[0m\x1B[1mWhen running the baw-deployment.sh script, Use the cluster admin user.\n\x1B[0m"
                sleep 5
            else
                user_name=$BAW_AUTO_CLUSTER_USER
                echo -e "\x1B[1mSelected the existing users: \x1B[0m${BAW_AUTO_CLUSTER_USER}"
            fi
        fi
    fi
}

function display_installationprompt(){

    echo "IBM Cloud Pak foundational services, along with Metering & Licensing components, will be installed."

    NAMESPACE_ODLM="common-service"
    ${CLI_CMD} project $NAMESPACE_ODLM >/dev/null 2>&1 || ${CLI_CMD} new-project $NAMESPACE_ODLM >/dev/null 2>&1
}


function check_storage_class() {
    if [[ $PLATFORM_SELECTED == "ROKS" ]];
    then
        # echo ""
        # echo "Applying no_root_squash for demo DB2 deployment on ROKS using CLI"
        # oc get no -l node-role.kubernetes.io/worker --no-headers -o name | xargs -I {} --  oc debug {} -- chroot /host sh -c 'grep "^Domain = slnfsv4.coms" /etc/idmapd.conf || ( sed -i "s/.*Domain =.*/Domain = slnfsv4.com/g" /etc/idmapd.conf; nfsidmap -c; rpc.idmapd )' >> ${LOG_FILE}
       printf "\n"
       echo -e "\x1B[1mUse the available storage classes.\x1B[0m"
    fi
    display_storage_classes_existing
}

function create_storage_classes_roks() {
    echo
    echo -ne "\x1B[1mCreate storage classes for deployment: \x1B[0m"
    ${CLI_CMD} apply -f ${BRONZE_STORAGE_CLASS} --validate=false >/dev/null 2>&1
    ${CLI_CMD} apply -f ${SILVER_STORAGE_CLASS} --validate=false >/dev/null 2>&1
    ${CLI_CMD} apply -f ${GOLD_STORAGE_CLASS} --validate=false >/dev/null 2>&1
    echo -e "\x1B[1mDone \x1B[0m"

}

function display_storage_classes_roks() {
    sc_bronze_name=cp4a-file-retain-bronze-gid
    sc_silver_name=cp4a-file-retain-silver-gid
    sc_gold_name=cp4a-file-retain-gold-gid
    echo -e "\x1B[1;31m    $sc_bronze_name \x1B[0m"
    echo -e "\x1B[1;31m    $sc_silver_name \x1B[0m"
    echo -e "\x1B[1;31m    $sc_gold_name \x1B[0m"
}

function check_platform_version(){
    currentver=$(kubectl  get nodes | awk 'NR==2{print $5}')
    requiredver="v1.17.1"
    if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
        PLATFORM_VERSION="4.4OrLater"
    else
        # PLATFORM_VERSION="3.11"
        PLATFORM_VERSION="4.4OrLater"
        echo -e "\x1B[1;31mIMPORTANT: Only support OCp4.4 or Later, exit...\n\x1B[0m"
        exit 1
    fi
    # OpenShift 4.0-4.2, install Cloud Pak foundational services 3.3
    # OpenShift >= 4.3, install Cloud Pak foundational services 3.4
    cs_install_ver="v1.17.1"
    if [ "$(printf '%s\n' "$cs_install_ver" "$currentver" | sort -V | head -n1)" = "$cs_install_ver" ]; then
        CS_VERSION="3.4"
    else
        CS_VERSION="3.3"
    fi
}

function prepare_common_service(){

    echo
    echo -e "\x1B[1mThe script is preparing the custom resources (CR) files for OCP Cloud Pak foundational services.  You are required to update (fill out) the necessary values in the CRs and deploy Cloud Pak foundational services prior to the deployment. \x1B[0m"
    echo -e "The prepared CRs for IBM Cloud Pak foundational services are located here: "${COMMON_SERVICES_CRD_DIRECTORY}
    echo -e "After making changes to the CRs, execute the 'deploy_CS.sh' script to install Cloud Pak foundational services."
    echo -e "Done"
}

# TODO check if below functions are used and still needed as BAW dows not have any old CS and BAI deployment
function install_common_service_34(){

    if [ "$INSTALL_BAI" == "Yes" ] ; then
    echo -e "Preparing full Cloud Pak foundational services Release 3.4 CR for BAI Deployment.."
        func_operand_request_cr_bai_34

    else
    echo -e "Preparing minimal Cloud Pak foundational services Release 3.4 CR for non-BAI Deployment.."
        func_operand_request_cr_nonbai_34
    fi

     ## TODO: start to install common service
    echo -e "\x1B[1mThe installation of Cloud Pak foundational services has started.\x1B[0m"
    #sh ./deploy_CS3.4.sh
    nohup ${PARENT_DIR}/scripts/deploy_CS3.4.sh  &
    echo -e "Done"
}

function install_common_service_33(){

        func_operand_request_cr_nonbai_33
    echo -e "\x1B[1mThe installation of Cloud Pak foundational services Release 3.3 for OCP 4.2+ has started.\x1B[0m"
    sh ${PARENT_DIR}/scripts/deploy_CS3.3.sh

    echo -e "Done"
}

function func_operand_request_cr_bai_34()
{

   echo "Creating Cloud Pak foundational services V3.4 Operand Request for BAI deployments on OCP 4.3+ ..\x1B[0m" >> ${LOG_FILE}
   operator_source_path=${PARENT_DIR}/descriptors/common-services/crds/operator_operandrequest_cr.yaml
 cat << ENDF > ${operator_source_path}
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ibm-common-services
spec:
  requests:
  - registry: common-service
    registryNamespace: ibm-common-services
    operands:
        - name: ibm-licensing-operator
        - name: ibm-iam-operator
        - name: ibm-monitoring-exporters-operator
        - name: ibm-monitoring-prometheusext-operator
        - name: ibm-monitoring-grafana-operator
        - name: ibm-metering-operator
        - name: ibm-management-ingress-operator
        - name: ibm-commonui-operator
ENDF
}


function func_operand_request_cr_nonbai_34()
{

   echo "Creating Common-Services V3.4 Operand Request for non-BAI deployments on OCP 4.3 ..\x1B[0m" >> ${LOG_FILE}
   operator_source_path=${PARENT_DIR}/descriptors/common-services/crds/operator_operandrequest_cr.yaml
 cat << ENDF > ${operator_source_path}
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
  namespace: ibm-common-services
spec:
  requests:
  - registry: common-service
    registryNamespace: ibm-common-services
    operands:
        - name: ibm-licensing-operator
        - name: ibm-metering-operator
        - name: ibm-commonui-operator
        - name: ibm-management-ingress-operator
        - name: ibm-iam-operator
        - name: ibm-platform-api-operator


ENDF
}


function func_operand_request_cr_bai_33()
{

   echo "Creating Cloud Pak foundational services V3.3 Operand Request for BAI deployments on OCP 4.2+ ..\x1B[0m" >> ${LOG_FILE}
   operator_source_path=${PARENT_DIR}/descriptors/common-services/crds/operator_operandrequest_cr.yaml
 cat << ENDF > ${operator_source_path}
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
spec:
  requests:
  - registry: common-service
    operands:
        - name: ibm-cert-manager-operator
        - name: ibm-mongodb-operator
        - name: ibm-iam-operator
        - name: ibm-monitoring-exporters-operator
        - name: ibm-monitoring-prometheusext-operator
        - name: ibm-monitoring-grafana-operator
        - name: ibm-management-ingress-operator
        - name: ibm-licensing-operator
        - name: ibm-metering-operator
        - name: ibm-commonui-operator
ENDF
}


function func_operand_request_cr_nonbai_33()
{

   echo "Creating Cloud Pak foundational services V3.3 Request Operand for non-BAW deployments on OCP 4.2+ ..\x1B[0m" >> ${LOG_FILE}
   operator_source_path=${PARENT_DIR}/descriptors/common-services/crds/operator_operandrequest_cr.yaml
 cat << ENDF > ${operator_source_path}
apiVersion: operator.ibm.com/v1alpha1
kind: OperandRequest
metadata:
  name: common-service
spec:
  requests:
  - registry: common-service
    operands:
        - name: ibm-cert-manager-operator
        - name: ibm-mongodb-operator
        - name: ibm-iam-operator
        - name: ibm-management-ingress-operator
        - name: ibm-licensing-operator
        - name: ibm-metering-operator
        - name: ibm-commonui-operator
ENDF
}


function show_summary(){

    printf "\n"
    echo -e "\x1B[1m*******************************************************\x1B[0m"
    echo -e "\x1B[1m                    Summary of input                   \x1B[0m"
    echo -e "\x1B[1m*******************************************************\x1B[0m"
    if [[ ${PLATFORM_VERSION} == "4.4OrLater" ]]; then
        echo -e "\x1B[1;31m1. Cloud platform to deploy: ${PLATFORM_SELECTED} 4.X\x1B[0m"
    else
        echo -e "\x1B[1;31m1. Cloud platform to deploy: ${PLATFORM_SELECTED} ${PLATFORM_VERSION}\x1B[0m"
    fi
    echo -e "\x1B[1;31m2. Project to deploy: ${project_name}\x1B[0m"
    echo -e "\x1B[1;31m3. User selected: ${user_name}\x1B[0m"
    if  [[ $PLATFORM_SELECTED == "ROKS" ]];
    then
        echo -e "\x1B[1;31m5. Storage Class created: \x1B[0m"
        display_storage_classes_roks
    fi
    echo -e "\x1B[1m*******************************************************\x1B[0m"
}

function check_csoperator_exists()
{

project="common-service"

check_project=`${CLI_CMD} get namespace $project --ignore-not-found | wc -l`  >/dev/null 2>&1
check_operator=$(${CLI_CMD} get csv --all-namespaces |grep "ibm-common-service-operator")
if [ -n "$check_operator" ]; then
    echo ""
    echo "Found an Existing Installation of IBM Cloud Pak foundational services.  The current installation of IBM Cloud Pak foundational services will be skipped."  >> ${LOG_FILE}
    echo "Found an Existing Installation of IBM Cloud Pak foundational services.  The current installation of IBM Cloud Pak foundational services will be skipped."

    CS_INSTALL="NO"
    exit 1
fi

}

function select_ocp_olm(){
    printf "\n"
    while true; do
        printf "\x1B[1mAre you using the OCP Catalog (OLM) to perform this install? (Yes/No, default: No) \x1B[0m"

        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            SCRIPT_MODE="OLM"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO"|"")
            break
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}


function get_local_registry_server(){
    # For internal/external Registry Server
    OCP_VERSION="4.4OrLater"
    printf "\n"
    if [[ "${REGISTRY_TYPE}" == "internal" && ("${OCP_VERSION}" == "4.4OrLater") ]];then
        #This is required for docker/podman login validation.
        printf "\x1B[1mEnter the public image registry or route (e.g., default-route-openshift-image-registry.apps.<hostname>). \n\x1B[0m"
        printf "\x1B[1mThis is required for docker/podman login validation: \x1B[0m"
        local_public_registry_server=""
        while [[ $local_public_registry_server == "" ]]
        do
            read -rp "" local_public_registry_server
            if [ -z "$local_public_registry_server" ]; then
            echo -e "\x1B[1;31mEnter a valid service name or the URL for the docker registry.\x1B[0m"
            fi
        done
    fi

    if [[ "${OCP_VERSION}" == "3.11" && "${REGISTRY_TYPE}" == "internal" ]];then
        printf "\x1B[1mEnter the OCP docker registry service name, for example: docker-registry.default.svc:5000/<project-name>: \x1B[0m"
    elif [[ "${REGISTRY_TYPE}" == "internal" && "${OCP_VERSION}" == "4.4OrLater" ]]
    then
        printf "\n"
        printf "\x1B[1mEnter the local image registry (e.g., image-registry.openshift-image-registry.svc:5000/<project>)\n\x1B[0m"
        printf "\x1B[1mThis is required to pull container images and Kubernetes secret creation: \x1B[0m"
        builtin_dockercfg_secrect_name=($(${CLI_CMD} get secret -n $project_name --no-headers --ignore-not-found | grep default-dockercfg | awk '{print $1}'))

        if [ -z "$builtin_dockercfg_secrect_name" ]; then
            DOCKER_RES_SECRET_NAME="ibm-entitlement-key"
        else
            DOCKER_RES_SECRET_NAME=( "${builtin_dockercfg_secrect_name[@]}" )
        fi
    elif [[ "${REGISTRY_TYPE}" == "external" || $PLATFORM_SELECTED == "other" ]]
    then
        if [ -z $BAW_AUTO_LOCAL_REGISTRY ]; then
            printf "\x1B[1mEnter the URL to the docker registry, for example: abc.xyz.com: \x1B[0m"
        fi
    fi
    if [ -z $BAW_AUTO_LOCAL_REGISTRY ]; then
        local_registry_server=""
        while [[ $local_registry_server == "" ]]
        do
            read -rp "" local_registry_server
            if [ -z "$local_registry_server" ]; then
                echo -e "\x1B[1;31mEnter a valid service name or the URL for the docker registry.\x1B[0m"
            fi
        done
    else
        echo -e "\x1B[1mEnter the URL to the docker registry, for example: abc.xyz.com: \x1B[0m$BAW_AUTO_LOCAL_REGISTRY"
        local_registry_server=$BAW_AUTO_LOCAL_REGISTRY
    fi
    LOCAL_REGISTRY_SERVER=${local_registry_server}
    # convert docker-registry.default.svc:5000/project-name
    # to docker-registry.default.svc:5000\/project-name
    OIFS=$IFS
    IFS='/' read -r -a docker_reg_url_array <<< "$local_registry_server"
    delim=""
    joined=""
    for item in "${docker_reg_url_array[@]}"; do
            joined="$joined$delim$item"
            delim="\/"
    done
    IFS=$OIFS
    CONVERT_LOCAL_REGISTRY_SERVER=${joined}
}

function get_local_registry_user(){
    # For Local Registry User
    printf "\n"
    if [ -z "$BAW_AUTO_LOCAL_REGISTRY_USER" ]; then
        printf "\x1B[1mEnter the user name for your docker registry: \x1B[0m"
        local_registry_user=""
        while [[ $local_registry_user == "" ]]
        do
            read -rp "" local_registry_user
            if [ -z "$local_registry_user" ]; then
            echo -e "\x1B[1;31mEnter a valid user name.\x1B[0m"
            fi
        done
    else
        echo -e "\x1B[1mEnter the user name for your docker registry: \x1B[0m$BAW_AUTO_LOCAL_REGISTRY_USER"
        local_registry_user=$BAW_AUTO_LOCAL_REGISTRY_USER
    fi
    LOCAL_REGISTRY_USER=${local_registry_user}
}

function get_local_registry_password(){
    printf "\n"
    if [ -z "$BAW_AUTO_LOCAL_REGISTRY_PASSWORD" ]; then
        printf "\x1B[1mEnter the password for your docker registry: \x1B[0m"
        local_registry_password=""
        while [[ $local_registry_password == "" ]];
        do
        read -rsp "" local_registry_password
        if [ -z "$local_registry_password" ]; then
        echo -e "\x1B[1;31mEnter a valid password\x1B[0m"
        fi
        done
    else
        printf "\x1B[1mEnter the password for your docker registry: \x1B[0m\n"
        local_registry_password=$BAW_AUTO_LOCAL_REGISTRY_PASSWORD
    fi
    LOCAL_REGISTRY_PWD=${local_registry_password}
    printf "\n"
}

function verify_local_registry_password(){
    # require to preload image for CP4A image and ldap/db2 image for demo
    printf "\n"
    while true; do
        if [ -z "$BAW_AUTO_PUSH_IMAGE_LOCAL_REGISTRY" ]; then
            printf "\x1B[1mHave you pushed the images to the local registry using 'loadimages.sh' ($BAW_FULL_NAME images) (Yes/No)? \x1B[0m"
            read -rp "" ans
        else
            case "$BAW_AUTO_PUSH_IMAGE_LOCAL_REGISTRY" in
            "y"|"Y"|"yes"|"Yes"|"YES"|"True"|"TRUE"|"true")
                echo -e "\x1B[1mHave you pushed the images to the local registry using 'loadimages.sh' ($BAW_FULL_NAME images) (Yes/No)? \x1B[0m$BAW_AUTO_PUSH_IMAGE_LOCAL_REGISTRY"
                ans="Yes"
                ;;
            "n"|"N"|"no"|"No"|"NO"|"false"|"False"|"FALSE")
                echo -e "\x1B[1mHave you pushed the images to the local registry using 'loadimages.sh' ($BAW_FULL_NAME images) (Yes/No)? \x1B[0m$BAW_AUTO_PUSH_IMAGE_LOCAL_REGISTRY"
                echo -e "\x1B[1;31mPull the images to the local images to proceed.\n\x1B[0m"
                ans="No"
                exit 1
                ;;
            *)
                echo -e "Answer must be \"Yes\" or \"No\"\n"
                ;;
            esac
        fi
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES")
            PRE_LOADED_IMAGE="Yes"
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            echo -e "\x1B[1;31mPull the images to the local images to proceed.\n\x1B[0m"
            exit 1
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done

    # Select which type of image registry to use.
    if [[ "${PLATFORM_SELECTED}" == "OCP" || "${PLATFORM_SELECTED}" == "ROKS" ]]; then
        printf "\n"
        echo -e "\x1B[1mSelect the type of image registry to use: \x1B[0m"
        COLUMNS=12
        options=("Openshift Container Platform (OCP) - Internal image registry" "Other ( External image registry: abc.xyz.com )")

        PS3='Enter a valid option [1 to 1]: '
        select opt in "${options[@]}"
        do
            case $opt in
                "Openshift Container Platform (OCP) - Internal image registry")
                    REGISTRY_TYPE="internal"
                    break
                    ;;
                "Other ( External image registry: abc.xyz.com )")
                    REGISTRY_TYPE="external"
                    break
                    ;;
                *) echo "invalid option $REPLY";;
            esac
        done
    else
        REGISTRY_TYPE="external"
    fi

    while [[ $verify_passed == "" && $PRE_LOADED_IMAGE == "Yes" ]]
    do
        get_local_registry_server
        get_local_registry_user
        get_local_registry_password

        if [[ $LOCAL_REGISTRY_SERVER == docker-registry* || $LOCAL_REGISTRY_SERVER == image-registry* || $LOCAL_REGISTRY_SERVER == default-route-openshift-image-registry* ]] ;
        then
            if [[ $OCP_VERSION == "3.11" ]];then
                if docker login -u "$LOCAL_REGISTRY_USER" -p $(${CLI_CMD} whoami -t) "$LOCAL_REGISTRY_SERVER"; then
                    printf 'Verifying Local Registry passed...\n'
                    verify_passed="passed"
                else
                    printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                    verify_passed=""
                    local_registry_user=""
                    local_registry_server=""
                    echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                fi
            elif [[ "$machine" == "Mac" ]]
            then
                if docker login "$local_public_registry_server" -u "$LOCAL_REGISTRY_USER" -p $(${CLI_CMD} whoami -t); then
                    printf 'Verifying Local Registry passed...\n'
                    verify_passed="passed"
                else
                    printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                    verify_passed=""
                    local_registry_user=""
                    local_registry_server=""
                    local_public_registry_server=""
                    echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                fi
            elif [[ $OCP_VERSION == "4.4OrLater" ]]
            then
                which podman &>/dev/null
                if [[ $? -eq 0 ]];then
                    if podman login "$local_public_registry_server" -u "$LOCAL_REGISTRY_USER" -p $(${CLI_CMD} whoami -t) --tls-verify=false; then
                        printf 'Verifying Local Registry passed...\n'
                        verify_passed="passed"
                    else
                        printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                        verify_passed=""
                        local_registry_user=""
                        local_registry_server=""
                        local_public_registry_server=""
                        echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                    fi
                else
                     if docker login "$local_public_registry_server" -u "$LOCAL_REGISTRY_USER" -p $(${CLI_CMD} whoami -t); then
                        printf 'Verifying Local Registry passed...\n'
                        verify_passed="passed"
                    else
                        printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                        verify_passed=""
                        local_registry_user=""
                        local_registry_server=""
                        local_public_registry_server=""
                        echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                    fi
                fi
            fi
        else
            which podman &>/dev/null
            if [[ $? -eq 0 ]];then
                if podman login -u "$LOCAL_REGISTRY_USER" -p "$LOCAL_REGISTRY_PWD"  "$LOCAL_REGISTRY_SERVER" --tls-verify=false; then
                    printf 'Verifying the information for the local docker registry...\n'
                    verify_passed="passed"
                else
                    printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                    echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                    if [ -z "$BAW_AUTO_LOCAL_REGISTRY" ]; then
                        verify_passed=""
                        local_registry_user=""
                        local_registry_server=""
                    else
                        exit 1
                    fi
                fi
            else
                if docker login -u "$LOCAL_REGISTRY_USER" -p "$LOCAL_REGISTRY_PWD"  "$LOCAL_REGISTRY_SERVER"; then
                    printf 'Verifying the information for the local docker registry...\n'
                    verify_passed="passed"
                else
                    printf '\x1B[1;31mLogin failed...\n\x1B[0m'
                    echo -e "\x1B[1;31mCheck the local docker registry information and try again.\x1B[0m"
                    if [ -z "$BAW_AUTO_LOCAL_REGISTRY" ]; then
                        verify_passed=""
                        local_registry_user=""
                        local_registry_server=""
                    else
                        exit 1
                    fi
                fi
            fi
        fi
     done

}

function create_secret_local_registry(){
    echo -e "\x1B[1mCreating the secret based on the local docker registry information...\x1B[0m"
    # Create docker-registry secret for local Registry Key
    # echo -e "Create docker-registry secret for Local Registry...\n"
    if [[ $LOCAL_REGISTRY_SERVER == docker-registry* || $LOCAL_REGISTRY_SERVER == image-registry.openshift-image-registry* ]] ;
    then
        builtin_dockercfg_secrect_name=($(${CLI_CMD} get secret -n $project_name --no-headers --ignore-not-found | grep default-dockercfg | awk '{print $1}'))
        DOCKER_RES_SECRET_NAME=( "${builtin_dockercfg_secrect_name[@]}" )
        # CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $DOCKER_RES_SECRET_NAME --docker-server=$LOCAL_REGISTRY_SERVER --docker-username=$LOCAL_REGISTRY_USER --docker-password=$(${CLI_CMD} whoami -t) --docker-email=ecmtest@ibm.com"
    else
        for item in "${DOCKER_RES_SECRET_NAME[@]}"; do
            ${CLI_CMD} delete secret "$item" -n $project_name >/dev/null 2>&1
            CREATE_SECRET_CMD="${CLI_CMD} create secret docker-registry $item --docker-server=$LOCAL_REGISTRY_SERVER --docker-username=$LOCAL_REGISTRY_USER --docker-password=$LOCAL_REGISTRY_PWD --docker-email=ecmtest@ibm.com -n $project_name"
            if $CREATE_SECRET_CMD ; then
                echo -e "\x1B[1mDone\x1B[0m"
            else
                echo -e "\x1B[1;31mFailed\x1B[0m"
            fi
        done
    fi
}

function verify_silence_install(){
    if [[ ! -z "${BAW_AUTO_PLATFORM}" || ! -z "${BAW_AUTO_DEPLOYMENT_TYPE}" ]]; then
        local platform_array=("OCP" "ROKS" "other")
        local deployment_type_array=("production")
        echo           "==========================================================================="
        echo -e "\x1B[1mStarting silent installation for $BAW_FULL_NAME Operator\x1B[0m"
        echo           "==========================================================================="
        #support for only production deployment type
        if [[ ! " ${deployment_type_array[@]} " =~ " ${BAW_AUTO_DEPLOYMENT_TYPE} " ]]; then
            echo -e "\x1B[1;31mOnly \"Production\" deployment type is supported and is the only valid value for environment variable [BAW_AUTO_DEPLOYMENT_TYPE].\n\x1B[0m"
            exit 1
        fi
        if [[ ! " ${platform_array[@]} " =~ " ${BAW_AUTO_PLATFORM} " ]]; then
            echo -e "\x1B[1;31mOnly \"OCP\" or \"ROKS\" or \"other\" is valid value for environment variable [BAW_AUTO_PLATFORM].\n\x1B[0m"
            exit 1
        fi

    fi

}

# Function to retrieve domain name from the customer so that the cpp-configmap can be created
# DBACLD-168151
function retrieve_domain_name(){
    local attempts=0
    local max_attempts=3
    OTHER_PLATFROM_TYPE_DOMAIN=""

    while [ $attempts -lt $max_attempts ]; do
        printf "\x1B[1mProvide the domain name for your cluster (This is the ingress that must be created and provided as a prerequisite for the deployment): \x1B[0m"
        read -rp "" OTHER_PLATFROM_TYPE_DOMAIN
        
        if [[ -z "$OTHER_PLATFROM_TYPE_DOMAIN" ]]; then
            warning "It is mandatory to provide a domain name for any deployment on $OTHER_PLATFROM_TYPE."
        else
            if ping -c 1 -W 2 "$OTHER_PLATFROM_TYPE_DOMAIN" >/dev/null 2>&1; then
                success "The Domain '$OTHER_PLATFROM_TYPE_DOMAIN' is reachable."
            else
                warning "The domain '$OTHER_PLATFROM_TYPE_DOMAIN' does not seem reachable.  Please make sure this is a valid domain before proceeding further."
            fi
            return 0
        fi
    
        ((attempts++))
    done
    if [[ -z "$OTHER_PLATFROM_TYPE_DOMAIN" ]]; then
        error "Maximum number of retries exceeded for entering a valid Domain name.The script will exit now...."
        exit
    fi

}

# Function that does the cluster setup for TANZU or Rancher
# DBACLD-168151
function setup_other_type_platform()
{
    source $BAW_CNCF_FOLDER/baw-utils.sh
    source $BAW_CNCF_FOLDER/baw-install-prereqs.sh
    check_cncf_rancher_prereqs  # function definition in baw-install-prereqs
    select_project
    get_entitlement_registry
    SEPARATE_OPERATOR="No"
    create_secret_entitlement_registry
    retrieve_domain_name
    create_common_service_configmap $project_name $project_name

    # This function call is used to install catalog sources and the cert manager and ibm-licensing services
    if [[ $CNCF_DEV == "Yes" ]]; then
        baw_cncf_rancher_prereq_install "ibm-licensing" "$project_name" true
    else
        baw_cncf_rancher_prereq_install "ibm-licensing" "$project_name" false
    fi
    
    source $BAW_CNCF_FOLDER/baw-install.sh
    # This function call is used to install the BAW operators
    if [[ $CNCF_DEV == "Yes" ]]; then
        baw_cncf_rancher_install "$project_name" "$OTHER_PLATFROM_TYPE_DOMAIN" true
    else
        baw_cncf_rancher_install "$project_name" "$OTHER_PLATFROM_TYPE_DOMAIN" false
    fi
    success " $BAW_FULL_NAME Standalone Operators have been installed! "
    exit


}

################################################
#### Begin - Main step for install operator ####
################################################
save_log "baw-script-logs" "baw-clusteradmin-setup-log"
trap cleanup_log EXIT

if [[ $1 == "dev" || $1 == "baw-dev" ]]
then
    CS_INSTALL="YES"
    CNCF_DEV="Yes"

else
    CS_INSTALL="NO"
    CNCF_DEV="No"

fi

clear
info "Setting up the cluster for $BAW_FULL_NAME"

verify_silence_install
check_airgap_mode
select_platform

validate_docker_podman_cli

#Function that handles the platform type rancher or tanzu
if [[ "$OTHER_PLATFROM_TYPE" == "rancher" || "$OTHER_PLATFROM_TYPE" == "tanzu" ]]; then
    setup_other_type_platform
fi

# Check cluster login
check_cluster_login

select_deployment_type

select_private_catalog

if [[ $DEPLOYMENT_TYPE == "production" ]]; then
    select_separate_operator
fi

if [[ $SEPARATE_OPERATOR == "No" ]]; then
    select_project
    # Function that retrieves the networktype and network cidr range
    # https://jsw.ibm.com/browse/DBACLD-173602
    retrieve_network_details "fresh_install"
    create_common_service_configmap $project_name $project_name $network_type $network_cidr
else
    set_separate_operator_project
    set_separate_cpfs_service_project
    #if [[ $MULTIPLE_DEPLOYMENT = "Yes" ]]; then
    #    set_separate_baw_service_project # see doc of set_separate_baw_service_project
    #fi
    # Function that retrieves the networktype and network cidr range
    # https://jsw.ibm.com/browse/DBACLD-173602
    retrieve_network_details "fresh_install"
    create_common_service_configmap $project_name_operator $project_name_cs_service $network_type $network_cidr
fi

validate_cli
if [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
    check_platform_version
fi

# All namespaces type deployment is not supported for BAW S
ALL_NAMESPACE="No"

collect_input
# create_project
# bind_scc

if [[ $SCRIPT_MODE == "OLM" ]];then
    ${CLI_CMD} project $project_name >/dev/null 2>&1

    if [[ $AIRGAP_INSTALL == "Yes" ]]; then
        display_airgap_prerequisites
    else
        get_entitlement_registry
        # get_storage_class_name
        if [[ "$use_entitlement" == "no" ]]; then
            verify_local_registry_password
        fi
        get_storage_class_name
        if [[ "$use_entitlement" == "yes" ]]; then
            create_secret_entitlement_registry
        fi
        if [[ "$use_entitlement" == "no" ]]; then
            create_secret_local_registry
        fi
        # allocate_operator_pvc_olm_or_cncf
        if [[ $PLATFORM_SELECTED == "other" && ( "$RUNTIME_MODE" == "process-flow" || $RUNTIME_MODE == "process-flow-dev" ) ]]; then
            validate_cncf_olm

            get_domain_name

            # for cncf platform, need to create configmap $DEDICATED_COMMON_PROJECT/ibm-cpp-config for common service
            # $DEDICATED_COMMON_PROJECT is the common service namespace corresponding to $DEDICATED_PROJECT.
            if [[ $CNCF_DOMAIN_NAME != "" ]]; then

            ${CLI_CMD} get cm ${COMMON_SERVICES_CM_DEDICATED_NAME} -n ${COMMON_SERVICES_CM_NAMESPACE} -o jsonpath='{ .data.common-service-maps\.yaml}' > ${TEMP_FOLDER}/cm-data.yaml
            dedicate_tmp=$(${YQ_CMD} r ${TEMP_FOLDER}/cm-data.yaml  --printMode p "namespaceMapping[*].requested-from-namespace.(.==$DEDICATED_PROJECT)")
            if [[ $dedicate_tmp == "" ]]; then
                echo -e "\x1B[1;31mCan not find namespace $DEDICATED_PROJECT in the configmap ${COMMON_SERVICES_CM_DEDICATED_NAME} in the namespace ${COMMON_SERVICES_CM_NAMESPACE}  .\n\x1B[0m"
                exit 1
            fi
            DEDICATED_COMMON_PROJECT=$(${YQ_CMD} r ${TEMP_FOLDER}/cm-data.yaml "${dedicate_tmp:0:20}.map-to-common-service-namespace")

            rm -fr ${TEMP_FOLDER}/cm-data.yaml >> ${LOG_FILE}

            echo -e "\x1B[1mCreating the configmap required by common service...\x1B[0m"
            isNsExists=`kubectl get namespace $DEDICATED_COMMON_PROJECT --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ $isNsExists -ne 2 ] ; then
                ${CLI_CMD} create namespace $DEDICATED_COMMON_PROJECT >/dev/null 2>&1
            fi
            cat <<EOF | kubectl apply -f -
            apiVersion: v1
            kind: ConfigMap
            metadata:
                name: ibm-cpp-config
                namespace: $DEDICATED_COMMON_PROJECT
            data:
                kubernetes_cluster_type: cncf
                # modify it according for your worker node ip address
                # if you expose nginx ingress controller with NodePort service
                domain_name: $CNCF_DOMAIN_NAME
EOF
            fi
        fi
    fi
    # Checking the IBM Cert Manager Operator ready or not
    if [[ ! ("$RUNTIME_MODE" == "baw" || $RUNTIME_MODE == "baw-dev" || "$RUNTIME_MODE" == "process-flow" || $RUNTIME_MODE == "process-flow-dev") ]]; then
        install_cert_license_operator
    fi

    if [[ $SEPARATE_OPERATOR == "No" ]]; then
        prepare_olm_install
    else
        prepare_olm_install
        setup_separate_operator
    fi
else
    if [[ $PLATFORM_SELECTED == "other" ]]; then
        get_entitlement_registry
    fi
    if [[ "$use_entitlement" == "no" ]]; then
        verify_local_registry_password
    fi
    get_storage_class_name
    if [[ "$use_entitlement" == "yes" ]]; then
        create_secret_entitlement_registry
    fi
    if [[ "$use_entitlement" == "no" ]]; then
        create_secret_local_registry
    fi
    # allocate_operator_pvc_olm_or_cncf
    # Checking the IBM Cert Manager Operator ready or not
    if [[ ! ("$RUNTIME_MODE" == "baw" || $RUNTIME_MODE == "baw-dev" || "$RUNTIME_MODE" == "process-flow" || $RUNTIME_MODE == "process-flow-dev") ]]; then
        install_cert_license_operator
    fi
    prepare_install
    apply_cp4a_operator
fi

# create_scc
display_storage_classes

# if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]];
# then
#     display_node_name
# fi

if [[ $SCRIPT_MODE != "OLM" ]]; then
    show_summary
    check_csoperator_exists

    if [[ $PLATFORM_SELECTED == "OCP" ||  $PLATFORM_SELECTED == "ROKS" ]] && [[ $PLATFORM_VERSION == "4.4OrLater" ]] && [[ $CS_VERSION == "3.4" ]];
    then

        if [ "$CS_INSTALL" != "YES" ]; then
            display_installationprompt
            echo ""

                nohup ${PARENT_DIR}/scripts/deploy_CS3.4.sh  >> ${LOG_FILE} 2>&1 &
        else
        echo "Review mode: IBM Cloud Pak foundational services will be skipped.."
        fi
    fi

    # Deploy CS 3.3 if OCP 4.2 or 3.11 as per requirements.  The components for CS 3.3 in this case will only be Licensing and Metering (also CommonUI as a base requirment)
    #if  [[[ $PLATFORM_SELECTED == "OCP" ]] && [ $PLATFORM_VERSION == "4.2" ]]] || [[[ $PLATFORM_SELECTED == "OCP" ] && [ $PLATFORM_VERSION == "3.11" ]]]

    if  [[ $PLATFORM_SELECTED == "OCP" ||  $PLATFORM_SELECTED == "ROKS" ]] && [[ $PLATFORM_VERSION == "4.4OrLater" ]] && [[ $CS_VERSION == "3.3" ]];
    then
        echo "IBM Cloud Pak foundational services, along with Metering & Licensing components, will be installed."
            if [ "$CS_INSTALL" != "YES" ]; then
            nohup ${PARENT_DIR}/scripts/deploy_CS3.3.sh >> ${LOG_FILE} 2>&1 &
            else
        echo "Review mode: IBM Cloud Pak foundational services will be skipped.."
            echo ""
        fi
    fi

    # Deploy CS 3.3 if OCP 3.11
    if  [[ $PLATFORM_SELECTED == "OCP" ]] && [[ $PLATFORM_VERSION == "3.11" ]];
    then
            echo "IBM Cloud Pak foundational services, along with Metering & Licensing components, will be installed."
            if [ "$CS_INSTALL" != "YES" ]; then
                COMMON_SERVICES_INSTALL_DIRECTORY_OCP311=${PARENT_DIR}/descriptors/common-services/scripts/common-services.sh
                sh ${COMMON_SERVICES_INSTALL_DIRECTORY_OCP311} install --async
            else
                echo "Review mode: IBM Cloud Pak foundational services will be skipped.."
            fi
    fi
fi

clean_up
#set the project context back to the user generated one
if  [[ $PLATFORM_SELECTED == "OCP" ||  $PLATFORM_SELECTED == "ROKS" ]];
then
  ${CLI_CMD} project ${PROJ_NAME} > /dev/null
fi
