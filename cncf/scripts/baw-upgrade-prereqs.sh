#!/usr/bin/env bash

set -o nounset

# Initialize variables before sourcing common.sh
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." >/dev/null 2>&1 && pwd )"

# Initialize step counter for title function
step=1

source ${CUR_DIR}/../../scripts/helper/common.sh
source ${CUR_DIR}/baw-utils.sh

# Define variables needed for upgrade checks (lowercase versions from common.sh)
licensing_service_target_version="${LICENSING_SERVICE_TARGET_VERSION}"
cert_manager_target_version="${CERT_MANAGER_TARGET_VERSION}"
baw_channel="v25.0"

function show_help() {
    echo "Usage: $0 [-h] -n <baw-namespace>"
    echo "  -n <baw-namespace>    Namespace where BAW is installed"
}

baw_namespace=""
is_openshift=false

while getopts "h?n:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    n)  baw_namespace=$OPTARG
        ;;
    esac
done

if [[ -z ${baw_namespace} ]]; then
    error "BAW namespace is mandatory."
    show_help
    exit 1
fi

function check_prereqs() {
    title "Checking prereqs ..."
    check_command kubectl

    oc_version=$(kubectl get clusterversion version -o=jsonpath={.status.desired.version} 2>/dev/null)
    if [[ ! -z ${oc_version} ]]; then
      info "openshift version ${oc_version} detected."
      is_openshift=true
    fi

    ## Check OLM
    if ${is_openshift}; then
      olm_namespace="openshift-marketplace"
    else
      olm_namespace=$(kubectl get deployment -A | grep olm-operator | awk '{print $1}')
      if [[ -z "$olm_namespace" ]]; then
        error "Cannot find OLM installation. Are you targetting a cluster where BAW is installed?"
        exit 1
      fi
      success "OLM available under namespace ${olm_namespace}."
    fi

    # Check if licensing service version is the one we target
    local vls=$(get_licensing_service_version "")
    if [[ "$vls" == "unknown" ]]; then
        error "Cannot find licensing version in your cluster. Please use baw-install-prereqs.sh script to install it."
        exit 1
    else
       success "Licensing service v${vls} found."
    fi

    ## Check certificate manager
    local vcm=$(get_cert_manager_version ${baw_namespace})
    if [[ "$vcm" == "unknown" ]]; then
        info "Not using IBM cert manager."
    else
        success "IBM certificate manager ${vcm} found."
    fi

    # Check Common services version
    local vcs=$(get_common_service_version ${baw_namespace})
    if [[ "$vcs" == "unknown" ]]; then
        error "Cannot find common services version in namespace ${baw_namespace}, is BAW installed in this namespace?"
        exit 1
    elif [[ $(semver_compare ${vcs} ${cs_minimal_version_for_ifix}) == "-1" ]]; then
        error "Detected common services version ${vcs} in namespace ${baw_namespace} which is not greater or equals to version ${cs_minimal_version_for_ifix}, are you upgrading from a 24.0.0 version?"
        exit 1
    elif [[ $(semver_compare ${vcs} ${cs_maximal_version_for_ifix}) != "-1" ]]; then
        error "Detected common services version ${vcs} in namespace ${baw_namespace} which is not lower to version ${cs_maximal_version_for_ifix}, are you upgrading from a 24.0.0 version?"
        exit 1
    else
        success "Detected common services version ${vcs}."
    fi
}

function check_subscription() {
    local channel=$(kubectl get sub ibm-baw-${baw_channel} -n ${baw_namespace} -o jsonpath='{.spec.channel}')
    if [ "${channel}" = "${baw_channel}" ]; then
        info "Found BAW subscription to the expected channel."
    else
        error "Cannot find BAW subscription in namespace ${baw_namespace} or its channel is not ${baw_channel}. Are you upgrading for an ifix of the same BAW version?"
        exit 1
    fi
}

function upgrade_licensing_and_cert_manager() {
    info "Upgrading licensing service to version ${LICENSING_SERVICE_TARGET_VERSION}..."
    
    # Update licensing subscription to use the latest channel
    kubectl patch subscription ibm-licensing-operator-app -n ibm-licensing --type='merge' -p "{\"spec\":{\"channel\":\"${LICENSING_SERVICE_CHANNEL}\"}}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        success "Licensing service subscription updated to channel ${LICENSING_SERVICE_CHANNEL}"
        info "Waiting for licensing operator to upgrade..."
        sleep 10
        wait_for_operator ibm-licensing ibm-licensing-operator
    else
        warning "Could not update licensing subscription, it may not exist or already be at the correct version"
    fi
    
    # Update cert-manager subscription to use the latest channel
    info "Upgrading cert-manager to version ${CERT_MANAGER_TARGET_VERSION}..."
    kubectl patch subscription ibm-cert-manager-operator -n ibm-cert-manager --type='merge' -p "{\"spec\":{\"channel\":\"${CERT_MANAGER_CHANNEL}\"}}" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        success "Cert-manager subscription updated to channel ${CERT_MANAGER_CHANNEL}"
        info "Waiting for cert-manager operator to upgrade..."
        sleep 10
        wait_for_operator ibm-cert-manager ibm-cert-manager-operator
    else
        warning "Could not update cert-manager subscription, it may not exist or already be at the correct version"
    fi
}

function upgrade_to_ifix() {
    upgrade_licensing_and_cert_manager
    check_prereqs
    check_subscription
    create_baw_catalog_sources
    upgrade_baw_subscription ${baw_channel} ${baw_channel} # keep same channel
}

# --- Run ---
upgrade_to_ifix
