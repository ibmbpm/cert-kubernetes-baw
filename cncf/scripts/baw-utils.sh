#!/usr/bin/env bash

# Function to check if a specific command is present
function check_command() {
    local command=$1

    if [[ -z "$(command -v ${command} 2> /dev/null)" ]]; then
        error "${command} command not available"
    else
        success "${command} command available"
    fi
}

# Helper function used to the functions that check for a specific resource to be ready
function wait_for_condition() {
    local condition=$1
    local retries=$2
    local sleep_time=$3
    local wait_message=$4
    local success_message=$5
    local error_message=$6

    info "${wait_message}"
    while true; do
        result=$(eval "${condition}")

        if [[ ( ${retries} -eq 0 ) && ( -z "${result}" ) ]]; then
            error "${error_message}"
            exit 2
        fi

        result=$(eval "${condition}")

        if [[ -z "${result}" ]]; then
            info "RETRYING: ${wait_message} (${retries} left)"
            retries=$(( retries - 1 ))
            sleep ${sleep_time}
        else
            break
        fi
    done

    if [[ ! -z "${success_message}" ]]; then
        success "${success_message}"
    fi
}

# Helper function that check for a configmap to be ready
function wait_for_configmap() {
    local namespace=$1
    local name=$2
    local condition="${CLI_CMD} -n ${namespace} get cm --no-headers --ignore-not-found | grep ^${name}"
    local retries=12
    local sleep_time=10
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for ConfigMap ${name} in namespace ${namespace} to be made available"
    local success_message="ConfigMap ${name} in namespace ${namespace} is available"
    local error_message="Timeout after ${total_time_mins} minutes waiting for ConfigMap ${name} in namespace ${namespace} to become available"

    wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

# Helper function that check for a pod to be ready
function wait_for_pod() {
    local namespace=$1
    local name=$2
    local condition="${CLI_CMD} -n ${namespace} get po --no-headers --ignore-not-found | grep -E 'Running|Completed|Succeeded' | grep ^${name}"
    local retries=30
    local sleep_time=30
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for pod ${name} in namespace ${namespace} to be running"
    local success_message="Pod ${name} in namespace ${namespace} is running"
    local error_message="Timeout after ${total_time_mins} minutes waiting for pod ${name} in namespace ${namespace} to be running"

    wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

# Helper function that check for a operator to be ready
function wait_for_operator() {
    local namespace=$1
    local operator_name=$2
    local condition="${CLI_CMD} -n ${namespace} get csv --no-headers --ignore-not-found | grep -E 'Succeeded' | grep ^${operator_name}"
    local retries=50
    local sleep_time=10
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for operator ${operator_name} in namespace ${namespace} to be made available"
    local success_message="Operator ${operator_name} in namespace ${namespace} is available"
    local error_message="Timeout after ${total_time_mins} minutes waiting for ${operator_name} in namespace ${namespace} to become available"

    wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

# Helper function that check for a service account to be ready
function wait_for_service_account() {
    local namespace=$1
    local name=$2
    local condition="${CLI_CMD} -n ${namespace} get sa ${name} --no-headers --ignore-not-found"
    local retries=20
    local sleep_time=10
    local total_time_mins=$(( sleep_time * retries / 60))
    local wait_message="Waiting for service account ${name} to be created"
    local success_message="Service account ${name} is created"
    local error_message="Timeout after ${total_time_mins} minutes waiting for service account ${name} to be created"

    wait_for_condition "${condition}" ${retries} ${sleep_time} "${wait_message}" "${success_message}" "${error_message}"
}

# Function that creates all catalog sources required for BAW-Standalone on rancher.
function create_all_catalog_sources(){
    local baw_namespace=$1
    local dev=$2
    catalog_source_file_name=${TEMP_FOLDER}/.catalog_source.yaml

    if [[ ! -f ${catalog_source_file_name} ]]; then
      cp ${CATALOG_SOURCE_FILENAME} ${catalog_source_file_name}
    fi
    catalog_names=()

    # Read catalog names into the array
    while IFS= read -r name; do
        catalog_names+=("$name")
    done < <(${YQ_CMD} r -d* "$catalog_source_file_name" 'metadata.name')

    # Iterate over the catalog names
    for name in "${catalog_names[@]}"; do
        # Get the document index of the catalog source (by name)
        doc_index=$( ${YQ_CMD} r -d* "$catalog_source_file_name" 'metadata.name' | grep -n "^$name$" | cut -d: -f1 )

        if [[ "$name" == "ibm-cert-manager-catalog" ]]; then
            
            ${YQ_CMD} w -i "$catalog_source_file_name" -d "$((doc_index - 1))" "metadata.namespace" "ibm-cert-manager"
        elif [[ "$name" == "ibm-licensing-catalog" ]]; then
            
            ${YQ_CMD} w -i "$catalog_source_file_name" -d "$((doc_index - 1))" "metadata.namespace" "ibm-licensing"
        else
            
            ${YQ_CMD} w -i "$catalog_source_file_name" -d "$((doc_index - 1))" "metadata.namespace" "$baw_namespace"
        fi

        # For dev mode the image for the catalog source has to be in cp.stg.icr.io and a secrets field has to be added
        if [[ "$dev" == true ]]; then
            # temporarily adding ibm-zen-operator-catalog because as of March 13th 2025 zen has not GAed
            if [[ "$name" == "ibm-cp4a-operator-catalog" || "$name" == "ibm-fncm-operator-catalog" ]]; then
#                ${YQ_CMD} w -i "$catalog_source_file_name" -d "$((doc_index - 1))"  "spec.secrets[+]" "ibm-staging-entitlement-key"
                # Extract the current image value
                current_image=$(${YQ_CMD} r -d "$((doc_index - 1))" "$catalog_source_file_name" 'spec.image')

                if [[ -n "$current_image" && "$current_image" == icr.io/cpopen/* ]]; then
                    # Modify the repository path
                    updated_image=${current_image/icr.io\/cpopen\//cp.stg.icr.io\/cp/}

                    # Update the image field in the YAML
                    ${YQ_CMD} w -i "$catalog_source_file_name" -d "$((doc_index - 1))" "spec.image" "$updated_image"
                fi
            fi
        fi

    done

    info "Applying all required Catalog Sources for BAW-Standalone on Rancher"
    ${CLI_CMD} apply -f ${catalog_source_file_name}
    for catalog in "${catalog_names[@]}"; do
        if [[ "$catalog" == "ibm-cert-manager-catalog"  ]]; then 
            wait_for_pod "ibm-cert-manager" "${catalog}"
        elif [[ "$catalog" == "ibm-licensing-catalog" ]]; then 
            wait_for_pod "ibm-licensing" "${catalog}"
        else
            wait_for_pod ${baw_namespace} "${catalog}"
        fi
    done
}

## No longer needed
#function create_catalog_source() {
#    local name=$1
#    local displayName=$2
#    local image=$3
#    local olm_namespace=$4
#    local is_openshift=$5
#
#    info "Creating catalog source ${name}..."
#    ${CLI_CMD} -n ${olm_namespace} delete catalogsource ${name} --ignore-not-found
#
#    if ${is_openshift}; then # No grpcPodConfig
#    ${CLI_CMD} apply -f - << EOF
#  apiVersion: operators.coreos.com/v1alpha1
#  kind: CatalogSource
#  metadata:
#    name: ${name}
#    namespace: ${olm_namespace}
#    annotations:
#      bedrock_catalogsource_priority: '1'
#  spec:
#    displayName: ${displayName}
#    publisher: IBM
#    sourceType: grpc
#    image: ${image}
#    updateStrategy:
#      registryPoll:
#        interval: 45m
#    priority: 100
#EOF
#    else
    # Adding grpcPodConfig
#    ${CLI_CMD} apply -f - << EOF
#  apiVersion: operators.coreos.com/v1alpha1
#  kind: CatalogSource
#  metadata:
#    name: ${name}
#    namespace: ${olm_namespace}
#    annotations:
#      bedrock_catalogsource_priority: '1'
#  spec:
#    displayName: ${displayName}
#    publisher: IBM
#    sourceType: grpc
#    grpcPodConfig:
#      securityContextConfig: restricted
#    image: ${image}
#    updateStrategy:
#      registryPoll:
#        interval: 45m
#    priority: 100
#EOF
#    fi
#    if [[ $? -ne 0 ]]; then
#          error "Error creating catalog source ${name}."
#    fi
#    wait_for_pod ${olm_namespace} "${name}"
#}


# Function used to create the ibm-cert-manager and ibm-licensing namespaces during the operator setup
function create_namespace() {
    local namespace=$1

    ns=$(${CLI_CMD} get ns ${namespace} -o=jsonpath={.metadata.name} 2>/dev/null)
    if [[ -z ${ns} ]]; then
      info "Creating namespace ${namespace}"
      ${CLI_CMD} create namespace ${namespace}
    fi
}

# Function that checks if a specific subscription exists
function is_sub_exist() {
    local package_name=$1
    if [ $# -eq 2 ]; then
        local namespace=$2
        local name=$(${CLI_CMD} get subscription.operators.coreos.com -n ${namespace} -o yaml -o jsonpath='{.items[*].spec.name}')
    else
        local name=$(${CLI_CMD} get subscription.operators.coreos.com -A -o yaml -o jsonpath='{.items[*].spec.name}')
    fi
    is_exist=$(echo "$name" | grep -w "$package_name")
}

# Function that patches the csv with the cp.stg.icr.io image
# THIS FUNCTION IS ONLY USED FOR DEV MODE
function patch_csv() {
    local csv_prefix=$1
    local namespace=$2
    local max_retries=20
    local retry_delay=20
    # Function to find a CSV that starts with the given prefix
    function get_csv_by_prefix() {
        ${CLI_CMD} get csv -n "$namespace" --no-headers -o custom-columns=":metadata.name" | grep -E "^$csv_prefix" | head -n 1
    }
    # Check if the CSV exists, retry up to max_retries times
    
    for ((i=1; i<=max_retries; i++)); do
        csv_name=$(get_csv_by_prefix)
        if [[ -n "$csv_name" ]]; then
            info "Found matching CSV: $csv_name"
            break
        fi

        if [[ "$i" -eq "$max_retries" ]]; then
            error "CSV $csv_name not found after $max_retries attempts. Exiting..."
            exit 1
        fi

        echo "CSV $csv_name not found. Retrying in $retry_delay seconds... ($i/$max_retries)"
        sleep "$retry_delay"
    done

    # Get the current image
    image=$(${CLI_CMD} get csv "$csv_name" -n "$namespace" -o json | ${YQ_CMD} r - 'spec.install.spec.deployments[0].spec.template.spec.containers[0].image')

    if [[ -z "$image" ]]; then
        error "No image found in CSV $csv_name"
        exit 1
    fi

    # Transform the image path
    updated_image=$(echo "$image" | sed -E 's|^icr.io/cpopen/|cp.stg.icr.io/cp/|')
    #if [[ "$csv_name" == "ibm-ba-insights-engine-operator"* ]]; then
    #    ${CLI_CMD} scale deployment $(${CLI_CMD} get deployments -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^ibm-bai-insights-engine-operator') --replicas=0
    #fi
    #if [[ "$csv_name" == "ibm-bai-foundation-operator"* ]]; then
    #    ${CLI_CMD} scale deployment $(${CLI_CMD} get deployments -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep '^ibm-bai-foundation-operator') --replicas=0
    #fi

    sleep 5
    # Patch the CSV with the new image
    ${CLI_CMD} patch csv "$csv_name" -n "$namespace" --type='json' -p="[{'op': 'replace', 'path': '/spec/install/spec/deployments/0/spec/template/spec/containers/0/image', 'value': '$updated_image'}]"

    initContainersImage=$(${CLI_CMD} get csv "$csv_name" -n "$namespace" -o jsonpath='{.spec.install.spec.deployments[0].spec.template.spec.initContainers[0].image}')
    if [ -n "$initContainersImage" ]; then
      ${CLI_CMD} patch csv "$csv_name" -n "$namespace" --type='json' -p="[{'op': 'replace', 'path': '/spec/install/spec/deployments/0/spec/template/spec/initContainers/0/image', 'value': '$updated_image'}]"
    fi

    #Patch the CSV with the image pull secret which has the staging credentials
    ${CLI_CMD} patch csv "$csv_name" -n "$namespace" --type='json' -p="[
    {
        \"op\": \"add\",
        \"path\": \"/spec/install/spec/deployments/0/spec/template/spec/imagePullSecrets\",
        \"value\": [
        {
            \"name\": \"ibm-staging-entitlement-key\"
        }
        ]
    }
    ]"

    ${CLI_CMD} delete deployment $csv_prefix
    success "The $csv_name CSV has been patched successfully!"
}

# Function to create the BAW-Standalone Operator subscription.
# Uses the file in descriptors folder 
function create_baw_subscription() {
    local namespace=$1
    local channel=$2
    local dev_mode=$3
    subscription_file_name=${TEMP_FOLDER}/.subscription.yaml
    cp ${SUBSCRIPTION_FILENAME} ${subscription_file_name}
    ${SED_COMMAND} "s/REPLACE_NAMESPACE/$baw_namespace/g" ${subscription_file_name}
    ${SED_COMMAND} "s/openshift-marketplace/$baw_namespace/g" ${subscription_file_name}
    printf "\n"
    info "Creating BAW subscription ..."
    ${CLI_CMD} apply -f ${subscription_file_name}
    if [[ $? -ne 0 ]]; then
        error "BAW Operator subscription could not be created."
    fi

    printf "\n"
    info "Waiting for BAW subscription to become active."

    patch_csv "ibm-content-operator" $namespace
    patch_csv "ibm-cp4a-operator" $namespace
    patch_csv "ibm-cp4a-wfps-operator" $namespace
    patch_csv "ibm-dpe-operator" $namespace
    patch_csv "ibm-insights-engine-operator" $namespace
    patch_csv "ibm-odm-operator" $namespace
    patch_csv "ibm-pfs-operator" $namespace
    patch_csv "ibm-workflow-operator" $namespace
    patch_csv "icp4a-foundation-operator" $namespace

    wait_for_operator "${namespace}" "ibm-common-service-operator"
    wait_for_operator "${namespace}" "operand-deployment-lifecycle-manager"
    wait_for_operator "${namespace}" "ibm-content-operator"
    wait_for_operator "${namespace}" "ibm-cp4a-operator"
    wait_for_operator "${namespace}" "ibm-cp4a-wfps-operator"
    wait_for_operator "${namespace}" "ibm-dpe-operator"
    wait_for_operator "${namespace}" "ibm-insights-engine-operator"
    wait_for_operator "${namespace}" "ibm-odm-operator"
    wait_for_operator "${namespace}" "ibm-pfs-operator"
    wait_for_operator "${namespace}" "ibm-workflow-operator"
    wait_for_operator "${namespace}" "icp4a-foundation-operator"
}

# Function to create the IBM Licensing Operator subscription.
function create_licensing_service_subscription() {
  local namespace=$1
  local licensing_manager_namespace=$2
  local channel=$3

  ${CLI_CMD} apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-licensing-operator-app
  namespace: ${namespace}
spec:
  channel: ${channel}
  installPlanApproval: Automatic
  name: ibm-licensing-operator-app
  source: ibm-licensing-catalog
  sourceNamespace: ${licensing_manager_namespace}
EOF

  if [[ $? -ne 0 ]]; then
    error "Error creating ibm-licensing subscription."
  fi

  info "Waiting for ibm-licensing subscription to become active."
  wait_for_operator ${namespace} ibm-licensing-operator
}

# Function to create the IBM Cert Manager subscription.
function create_ibm_certificate_manager_subscription() {
  local cert_manager_namespace=$1
  local channel=$2

  ${CLI_CMD} apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-cert-manager-operator
  namespace: ibm-cert-manager
spec:
  channel: ${channel}
  installPlanApproval: Automatic
  name: ibm-cert-manager-operator
  source: ibm-cert-manager-catalog
  sourceNamespace: ${cert_manager_namespace}
EOF
  if [[ $? -ne 0 ]]; then
      error "Error creating ibm-cert-manager subscription."
  fi

  info "Waiting for ibm-cert-manager subscription to become active."
  wait_for_operator ibm-cert-manager ibm-cert-manager-operator
}

# Function to get the licensing service version
function get_licensing_service_version() {
    local namespace=$1
    get_type_from_label "csv" "app.kubernetes.io/name=ibm-licensing" "{.items[0].spec.version}" "${namespace}"
}

# Function to get the cert manager version, used to detect if we need to install cert manager or if it is already installed
function get_cert_manager_version() {
    local namespace=$1
    local path="{.spec.version}"

    local csv_name=$(${CLI_CMD} get csv -n ${namespace} | grep ibm-cert-manager-operator | cut -d ' ' -f1)

    if [[ -z ${csv_name} ]]; then
        echo "unknown"
    else
    ${CLI_CMD} get csv -n ${namespace} ${csv_name} -o jsonpath="${path}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo $(${CLI_CMD} get csv -n ${namespace} ${csv_name} -o jsonpath="${path}")
    else
        echo "unknown"
    fi
    fi
}


function get_type_from_label() {
    local type=$1
    local label=$2
    local path=$3
    local namespace=$4
    local namespace_opt="-A"

    if [[ ! -z "$namespace" ]]; then
    namespace_opt="-n ${namespace}"
    fi

    ${CLI_CMD} get "${type}" ${namespace_opt} -l "${label}" -o jsonpath="${path}" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
    echo $(${CLI_CMD} get "${type}" ${namespace_opt} -l "${label}" -o jsonpath="${path}")
    else
    echo "unknown"
    fi
}


# This function is currently not used, but potentially can be enhanced when we support upgrade
function upgrade_bai_subscription() {
    local old_channel=$1
    local new_channel=$2

    local sub=$(${CLI_CMD} get sub ibm-bai-${old_channel} -n ${bai_namespace} -o jsonpath='{.metadata.name}')
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}

    sub=$(${CLI_CMD} get sub -n ${bai_namespace} | grep ibm-common-service-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}

    sub=$(${CLI_CMD} get sub -n ${bai_namespace} | grep ibm-im-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}

    sub=$(${CLI_CMD} get sub -n ${bai_namespace} | grep ibm-idp-config-ui-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}

    sub=$(${CLI_CMD} get sub -n ${bai_namespace} | grep ibm-platformui-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}

    sub=$(${CLI_CMD} get sub -n ${bai_namespace} | grep operand-deployment-lifecycle-manager | cut -d ' ' -f 1)
    ${CLI_CMD} delete sub ${sub} -n ${bai_namespace}
    
    local csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep ibm-bai-kn-operator.${old_channel} | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep ibm-common-service-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep ibm-commonui-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep ibm-iam-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep ibm-zen-operator | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    csv=$(${CLI_CMD} get csv -n ${bai_namespace} | grep operand-deployment-lifecycle-manager | cut -d ' ' -f 1)
    ${CLI_CMD} delete csv ${csv} -n ${bai_namespace}

    create_bai_subscription ${bai_namespace} ${new_channel} 
}

function semver_compare() {
    version1=$1
    version2=$2

    if [[ "${version1}" == "${version2}" ]]; then
        echo "0"
        return
    fi

    version1_major=$(printf %s "$version1" | cut -d'.' -f 1)
    version1_minor=$(printf %s "$version1" | cut -d'.' -f 2)
    version1_patch=$(printf %s "$version1" | cut -d'.' -f 3)

    version2_major=$(printf %s "$version2" | cut -d'.' -f 1)
    version2_minor=$(printf %s "$version2" | cut -d'.' -f 2)
    version2_patch=$(printf %s "$version2" | cut -d'.' -f 3)

    res=$(compare_number "$version1_major" "$version2_major")
    if [[ "${res}" != "0" ]]; then
        echo "${res}"
        return
    fi

    res=$(compare_number "$version1_minor" "$version2_minor")
    if [[ "${res}" != "0" ]]; then
        echo "${res}"
        return
    fi

    echo $(compare_number "$version1_patch" "$version2_patch")
}

function compare_number() {
    number1=$1
    number2=$2

    if [[ "${number1}" -gt "${number2}" ]]; then
        echo "1"
        return
    elif [[ "${number1}" -lt "${number2}" ]]; then
        echo "-1"
        return
    fi
    echo "0"
}

# Helper function used while creating operator groups
function add_target_namespace_to_operator_group() {
    local namespace=$1
    local operator_group_name=$2
    local operator_group_namespace=$3

    # extract target namespaces and convert the json array to a bash array
    target_namespaces=($(echo $(${CLI_CMD} get operatorgroup -n ${operator_group_namespace} ${operator_group_name} -o jsonpath='{.spec.targetNamespaces}') | tr -d '[]" ' | sed 's/,/ /g'))

    # check if already contains the namespace
    for i in "${target_namespaces[@]}"
    do
      if [[ $i == ${namespace} ]]; then
        value_found=true
        break
      fi
    done
    if [[ -z ${value_found+x} ]]; then
      info "Updating operator group ..."
      ${CLI_CMD} patch operatorgroup -n ${operator_group_namespace} ${operator_group_name} -p "[{'op':'add','path':'/spec/targetNamespaces/-','value': ${namespace}}]" --type=json

      if [[ $? -ne 0 ]]; then
        error "Error updating operator group."
      fi
    else
      info "target namespaces of the operator group already contain the namespace ${namespace}"
    fi
}