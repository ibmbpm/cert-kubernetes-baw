#!/usr/bin/env bash

set -o nounset

current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

accept_license=false
baw_namespace=""
domain_name=""
is_openshift=false

# Function that creates the common services cpp configmap
function create_cs_config_map() {
    printf "\n"
    info "Creating the common services configmap ..."

    #ns=$(kubectl get ns ${baw_namespace} -o=jsonpath={.metadata.name} 2>/dev/null)
    #if [[ -z ${ns} ]]; then
    #  info "Creating namespace ${baw_namespace}"
    #  kubectl create namespace ${baw_namespace}
    #fi

    kubectl -n ${baw_namespace} delete cm ibm-cpp-config --ignore-not-found

   if ${is_openshift}; then
     kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ibm-cpp-config
  namespace: ${baw_namespace}
data:
  commonwebui.standalone: "true"
EOF
  else
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ibm-cpp-config
  namespace: ${baw_namespace}
data:
  kubernetes_cluster_type: cncf
  commonwebui.standalone: "true"
  domain_name: ${domain_name}
EOF
  fi
  if [[ $? -ne 0 ]]; then
        error "Error creating ibm-cpp-config config map in ${baw_namespace} namespace."
  fi
}

# Function that creates the insights engine operator group
function create_baw_operator_group() {
    existing_og_name=$(kubectl get operatorgroup -n ${baw_namespace} -o name | awk -F "/" '{print $NF}')
    if [[ ! -z ${existing_og_name} ]]; then
        info "Operator Group '${existing_og_name}' detected in namespace '${baw_namespace}'."
        
        add_target_namespace_to_operator_group ${baw_namespace} ${existing_og_name} ${baw_namespace}

    else
        info "Creating Operator Group for BAW-Standalone Operator..."
        operatorgroup_file_name=${TEMP_FOLDER}/catalog_sources.yaml
        cp ${OPERATOR_GROUP_FILENAME} ${operatorgroup_file_name}
        ${SED_COMMAND} "s/REPLACE_NAMESPACE/$baw_namespace/g" ${operatorgroup_file_name}
        kubectl apply -f ${operatorgroup_file_name}

        if [[ $? -ne 0 ]]; then
            error "Error creating operator group."
        fi
    fi
}

# Function to check prereqs like domain name, presence of cert manager and licensing manager
function check_prereqs() {
    printf "\n"
    info "Checking the prerequisites for install the BAW Standalone Operators before proceeding ..."
    check_command kubectl

    oc_version=$(kubectl get clusterversion version -o=jsonpath={.status.desired.version} 2>/dev/null)
    if [[ ! -z ${oc_version} ]]; then
      info "openshift version ${oc_version} detected."
      is_openshift=true
    fi

    ## Check domain name presence
    if ! ${is_openshift}; then
      if [[ -z ${domain_name} ]]; then
          error "Domain name is mandatory,Exiting..."
          exit 1
      fi
    else
      if [[ ! -z ${domain_name} ]]; then
          info "Ignoring domain ${domain_name} as openshift cluster is detected."
      fi
    fi

    ## Check OLM
    if ${is_openshift}; then
      olm_namespace="openshift-marketplace"
    else
      olm_namespace=$(kubectl get deployment -A | grep olm-operator | awk '{print $1}')
      if [[ -z "$olm_namespace" ]]; then
        error "Cannot find OLM installation. Rerun baw-clusteradmin-setup.sh to install one."
        exit 1
      fi
      success "OLM available under namespace ${olm_namespace}."
    fi

    ## Check license service
    printf "\n"
    info "Checking if IBM Licensing service is installed in the cluster ..."

    # Check if licensing service version is the one we target
    local vls=$(get_licensing_service_version "")
    if [[ "$vls" == "unknown" ]]; then
        error "Cannot find licensing version in your cluster. Please use baw-install-prereqs.sh script to install it."
        exit 1
    elif [[ $(semver_compare ${vls} ${LICENSING_SERVICE_TARGET_VERSION}) == "-1" ]]; then
        error "Detected licensing service version ${vls} which is not ${LICENSING_SERVICE_TARGET_VERSION}. Please upgrade pre-requisites with baw-upgrade-prereqs.sh script."
        exit 1
    else
       success "Licensing service v${vls} found."
    fi

    ## Check certificate manager
    printf "\n"
    info "Checking if a IBM Cert Manager is installed in the cluster ..."
    kubectl get crd | grep cert-manager
    if [[ $? -ne 0 ]] ; then
       error "No IBM Cert Manager is detected, re-run the baw-clusteradmin-setup.sh script to install one."
       exit 1
    else

      local vcm=$(get_cert_manager_version ${baw_namespace})
      if [[ "$vcm" == "unknown" ]]; then
          info "Not using IBM cert manager."
      elif [[ $(semver_compare ${vcm} ${CERT_MANAGER_TARGET_VERSION}) == "-1" ]]; then
          error "Detected IBM certificate manager version ${vcm} which is not greater or equals to version ${CERT_MANAGER_TARGET_VERSION}. Please upgrade pre-requisites with baw-upgrade-prereqs.sh script."
          exit 1
      else
        success "IBM certificate manager ${vcm} found."
      fi
    fi
}


#This is the main function in this script
#The baw-clusteradmin-setup.sh script calls this function when the BAW and CPFS operators are to be installed
#The function requires 3 arguments
# baw_namespace -> namespace to deploy the operators
# domain_name -> domain name of the cluster used to create ibm-cpp-config configMap
# dev mode -> the dev mode which should be true if we are pulling the images from staging registry and false for production ER
function baw_cncf_rancher_install() {
    # Setting the baseline variables
    accept_license=false
    baw_namespace=""
    domain_name=""
    is_openshift=false
    
    baw_namespace=$1
    domain_name=$2
    dev_mode=$3
    if [[ -z ${baw_namespace} ]]; then
        error "BAW namespace is mandatory."
        exit 1
    fi
    current_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
    check_prereqs
    create_cs_config_map
    #create_baw_catalog_sources
    create_baw_operator_group
    create_baw_subscription ${baw_namespace} "" ${dev_mode}
}

# --- Run ---
#install
