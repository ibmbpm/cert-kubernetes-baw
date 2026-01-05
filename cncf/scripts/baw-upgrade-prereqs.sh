#!/usr/bin/env bash

# Don't use nounset until after sourcing common.sh
# set -o nounset

# Initialize variables before sourcing common.sh
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." >/dev/null 2>&1 && pwd )"

# Initialize step counter for title function
step=1

# Set dummy parameter for common.sh (it expects $1 for PREREQUISITES_FOLDER)
set -- "dummy"
source ${CUR_DIR}/../../scripts/helper/common.sh
source ${CUR_DIR}/baw-utils.sh

# Now enable nounset
set -o nounset

# Define variables needed for upgrade checks
licensing_service_target_version="${LICENSING_SERVICE_TARGET_VERSION}"
cert_manager_target_version="${CERT_MANAGER_TARGET_VERSION}"

function show_help() {
    echo "Usage: $0 [-h]"
    echo ""
    echo "This script upgrades IBM Business Automation Workflow prerequisites:"
    echo "  - IBM Licensing Service to version ${LICENSING_SERVICE_TARGET_VERSION}"
    echo "  - IBM Cert Manager to version ${CERT_MANAGER_TARGET_VERSION}"
    echo ""
    echo "Options:"
    echo "  -h    Show this help message"
    echo ""
    echo "Note: To upgrade BAW itself, use baw-deployment.sh with -m upgradeOperator mode"
}

is_openshift=false

while getopts "h?" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    esac
done

function check_prereqs() {
    title "Checking prerequisites ..."
    check_command kubectl

    oc_version=$(kubectl get clusterversion version -o=jsonpath={.status.desired.version} 2>/dev/null)
    if [[ ! -z ${oc_version} ]]; then
      info "OpenShift version ${oc_version} detected."
      is_openshift=true
    fi

    ## Check OLM
    if ${is_openshift}; then
      olm_namespace="openshift-marketplace"
    else
      olm_namespace=$(kubectl get deployment -A | grep olm-operator | awk '{print $1}')
      if [[ -z "$olm_namespace" ]]; then
        error "Cannot find OLM installation."
        exit 1
      fi
      success "OLM available under namespace ${olm_namespace}."
    fi
}

function upgrade_prerequisites() {
    title "Upgrading prerequisites (licensing and cert-manager)..."
    
    # Check current versions
    local vls=$(get_licensing_service_version "")
    local vcm=$(get_cert_manager_version "ibm-cert-manager")
    
    info "Current licensing service version: ${vls}"
    info "Target licensing service version: ${licensing_service_target_version}"
    
    if [[ "$vls" != "unknown" ]] && [[ $(semver_compare ${vls} ${licensing_service_target_version}) == "-1" ]]; then
        info "Upgrading licensing service from ${vls} to ${licensing_service_target_version}..."
        
        # Update subscription to correct sourceNamespace and channel
        kubectl patch subscription ibm-licensing-operator-app -n ibm-licensing \
            --type='merge' \
            -p "{\"spec\":{\"channel\":\"${LICENSING_SERVICE_CHANNEL}\",\"sourceNamespace\":\"ibm-licensing\"}}"
        
        if [[ $? -eq 0 ]]; then
            success "Licensing subscription updated"
            
            # Delete old resources to trigger upgrade
            info "Deleting old install plan and CSV to trigger upgrade..."
            kubectl delete installplan -n ibm-licensing --all 2>/dev/null
            kubectl delete csv -n ibm-licensing -l operators.coreos.com/ibm-licensing-operator-app.ibm-licensing 2>/dev/null
            
            info "Waiting for licensing operator to upgrade (this may take a few minutes)..."
            sleep 30
            
            # Wait for new CSV to appear
            local retries=20
            while [[ $retries -gt 0 ]]; do
                local new_vls=$(get_licensing_service_version "")
                if [[ "$new_vls" != "unknown" ]] && [[ $(semver_compare ${new_vls} ${vls}) != "-1" ]]; then
                    success "Licensing service upgraded to version ${new_vls}"
                    break
                fi
                info "Waiting for upgrade to complete... (${retries} retries left)"
                sleep 15
                retries=$((retries - 1))
            done
            
            if [[ $retries -eq 0 ]]; then
                warning "Licensing upgrade may still be in progress. Check with: kubectl get csv -n ibm-licensing"
            fi
        else
            error "Failed to update licensing subscription"
        fi
    else
        success "Licensing service is already at version ${vls}"
    fi
    
    # Upgrade cert-manager if needed
    if [[ "$vcm" != "unknown" ]] && [[ $(semver_compare ${vcm} ${cert_manager_target_version}) == "-1" ]]; then
        info "Upgrading cert-manager from ${vcm} to ${cert_manager_target_version}..."
        
        kubectl patch subscription ibm-cert-manager-operator -n ibm-cert-manager \
            --type='merge' \
            -p "{\"spec\":{\"channel\":\"${CERT_MANAGER_CHANNEL}\",\"sourceNamespace\":\"ibm-cert-manager\"}}"
        
        if [[ $? -eq 0 ]]; then
            success "Cert-manager subscription updated"
            kubectl delete installplan -n ibm-cert-manager --all 2>/dev/null
            kubectl delete csv -n ibm-cert-manager -l operators.coreos.com/ibm-cert-manager-operator.ibm-cert-manager 2>/dev/null
            info "Waiting for cert-manager to upgrade..."
            sleep 30
        fi
    else
        success "Cert-manager is already at version ${vcm}"
    fi
}

# --- Run ---
check_prereqs
upgrade_prerequisites

success "Prerequisites upgrade completed!"
info "You can now proceed with BAW installation or upgrade."
