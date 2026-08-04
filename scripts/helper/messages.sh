#!/bin/bash

###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2021. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
## This files contains various functions that contain messages used in the scripts
#CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
#PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
# Import common utilities and environment variables
# source ${CUR_DIR}/common.sh


function displayUpgradeOperatorMessage() {
  local tmp_message=$1
  local tmp_target_project_name=$2
  local tmp_original_cp4ba_csv_ver=$3
  warning "$tmp_message"
  echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try upgrade again after fixing the issue of IBM Cloud Pak foundational services."
  echo "           ${GREEN_TEXT}# ./baw-deployment.sh -m upgradeOperator -n $tmp_target_project_name --cpfs-upgrade-mode <migration mode> --original-cp4ba-csv-ver <cp4ba-csv-version-before-upgrade>${RESET_TEXT}"
  echo "           Usage:"
  echo "           --cpfs-upgrade-mode     : The migration mode for IBM Cloud Pak foundational services, the valid values [shared2shared/shared2dedicated/dedicated2dedicated]"
  echo "           --original-cp4ba-csv-ver: The version of csv for CP4BA operator before upgrade such as $tmp_original_cp4ba_csv_ver"
  echo "           Example command: "
  echo "           # ./baw-deployment.sh -m upgradeOperator -n $tmp_target_project_name --cpfs-upgrade-mode dedicated2dedicated --original-cp4ba-csv-ver $tmp_original_cp4ba_csv_ver"
}

function displayEdbMigrationRetryMessage() {
  local tmp_phase_name=$1
  local tmp_target_project_name=$2
  local tmp_original_cp4ba_csv_ver=$3
  warning "EDB to IBM CloudNativePG migration failed at phase: $tmp_phase_name"
  echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run the following command to retry the migration after fixing the issue."
  echo "           ${GREEN_TEXT}# ./baw-deployment.sh -m upgradeOperator -n $tmp_target_project_name --original-cp4ba-csv-ver <cp4ba-csv-version-before-upgrade>${RESET_TEXT}"
  echo "           Usage:"
  echo "           --original-cp4ba-csv-ver: The version of CSV for CP4BA operator before upgrade such as $tmp_original_cp4ba_csv_ver"
  echo "           Example command: "
  echo "           # ./baw-deployment.sh -m upgradeOperator -n $tmp_target_project_name --original-cp4ba-csv-ver $tmp_original_cp4ba_csv_ver"
  echo ""
  info "The EDB to IBM CloudNativePG migration will automatically resume from the failed phase."
  echo
  info " Migration state is tracked in ConfigMap: edb-cnpg-migration"
}

function next_steps_for_major_upgrade_after_upgrade_operator_mode() {
  local namespace=$1
  local css_flag=$2
  local cur_dir=$3
  
  printf "\n"
  echo "${YELLOW_TEXT}[NEXT ACTIONS]:${RESET_TEXT}"
  step_num=1
  echo "  - STEP ${step_num} ${YELLOW_TEXT}(Optional)${RESET_TEXT}: You can run ${GREEN_TEXT}\"${cur_dir}/baw-deployment.sh -m upgradeOperatorStatus -n $namespace\"${RESET_TEXT} to check whether the upgrade of the BAW operator and its dependencies is successful."
  step_num=$((step_num + 1))

  if [[ $css_flag == "true" ]]; then
    echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You have Content Search Services (CSS) installed. Make sure you stop the IBM Content Search Services index dispatcher. Refer to the FileNet P8 Platform Documentation for more details."
    echo "    ${YELLOW_TEXT}* Stopping the IBM Content Search Services index dispatcher.${RESET_TEXT}"
    echo "      1. Log in to the Administration Console for Content Platform Engine."
    echo "      2. In the navigation pane, select the domain icon."
    echo "      3. In the edit pane, click the Text Search Subsystem tab and clear the Enable indexing check box."
    echo "      4. Click Save to apply your changes."
    step_num=$((step_num + 1))
  fi
  echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You need to run ${GREEN_TEXT}\"${cur_dir}/baw-deployment.sh -m upgradeDeployment -n $namespace\"${RESET_TEXT} to upgrade BAW deployment."
  echo "    ${RED_TEXT}[ATTENTION]: ${RESET_TEXT}${YELLOW_TEXT}When you run the [upgradeDeployment] mode of the baw-deployment.sh script, the updated custom resource (CR) must be manually applied that all required additional actions can be completed before the upgrade process begins. Refer to the Knowledge Center: \"Updating the custom resource for each capability in your deployment\" topic to complete the REQUIRED steps for the installed pattern(s).${RESET_TEXT}"
  step_num=$((step_num + 1))
  echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You can run ${GREEN_TEXT}\"${cur_dir}/baw-deployment.sh -m upgradeDeploymentStatus -n $namespace\"${RESET_TEXT} to check whether the upgrade of the BAW deployment was successful."
  printf "\n"
}

function displayClusterAdminMessage() {
  local tmp_message=$1
  local cp4ba_csv_version=$2
  error "$tmp_message"
  echo "${YELLOW_TEXT}[ATTENTION]:${RESET_TEXT} You can run follow command to try to install the BAW $cp4ba_csv_version Operators again after fixing the issues described in the error messages."
  echo "           ${GREEN_TEXT}# ./baw-clusteradmin-setup.sh ${RESET_TEXT}"
}



function displayManualStrimziPodsetPatchingMessage(){
  local operator_namespace=$1
  local services_namespace=$2

  echo "===================================================================================="
  echo " ${YELLOW_TEXT}[IMPORTANT] Manual Steps to Patch Strimzi PodSet:${RESET_TEXT}"
  echo "===================================================================================="
  echo
  echo "1. Verify the Events Operator is running:"
  echo "     ${CLI_CMD} get pods -n ${operator_namespace} | grep ibm-events-operator"
  echo
  echo "2. Check the StrimziPodSet exists:"
  echo "     ${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n ${services_namespace}"
  echo
  echo "3. Get the current kafka version annotation:"
  echo "     KAFKA_VERSION=\$(${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n ${services_namespace} -o jsonpath='{.metadata.annotations.strimzi\.io/kafka-version}')"
  echo
  echo "4. Apply the patch manually:"
  echo "     ${CLI_CMD} patch strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n ${services_namespace} --type=merge -p \"{\\\"metadata\\\":{\\\"annotations\\\":{\\\"strimzi.io/kafka-version\\\":null,\\\"ibmevents.ibm.com/kafka-version\\\":\\\"\$KAFKA_VERSION\\\"}}}\""
  echo
  echo "5. If there are issues with patching the iaf-system-kafka strimzipodset, you must reach out to the IBM CloudPak Foundation Services Team for further assistance."
  echo
  echo "================================================================================"
}
