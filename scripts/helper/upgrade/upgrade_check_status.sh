#!/bin/bash
# set -x
###############################################################################
#
# LICENSED MATERIALS - PROPERTY OF IBM
#
# (C) COPYRIGHT IBM CORP. 2023. ALL RIGHTS RESERVED.
#
# US GOVERNMENT USERS RESTRICTED RIGHTS - USE, DUPLICATION OR
# DISCLOSURE RESTRICTED BY GSA ADP SCHEDULE CONTRACT WITH IBM CORP.
#
###############################################################################
UPGRADE_CHECK_CUR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Import common utilities and environment variables
source "${UPGRADE_CHECK_CUR_DIR}/../common.sh" "${TARGET_PROJECT_NAME:-}"

#list of versions for which direct upgrade to 26.0.0 is not supported
upgrade_blocked_versions=("21.3." "23.1." "22.1." "22.2." "23.2.")

#list of versions for which direct upgrade to 26.0.0 is supported
upgrade_valid_versions=("25.0." "25.1." "26.0.")

#Determine if it's an Ifix to ifix upgrade or a n-1 upgrade using CSV
# Format of CSV x.y.z where x is major version, y is minor version and z is ifix version
# For example:
# - 24.0.1 version will have 24.1.0 in the CSV
# - 24.0.1-IF002 version will 24.1.1 in the CSV
# - 26.0.0-GA wversion will have 26.0.0 in the CSV
# The rules are:
# 1. n-1 upgrade: Use the desired major version such as 24 from the CP4BA_CSV_VERSION in the common.sh  to compare with the current install version
#   - If x version of the current CSV is equal to the desired major version, then it's a n-1 upgrade.  For example, if the current version is 24.0.0-IF003 (24.0.3) and the desired version is 24.0.1 (24.1.0), then it's a n-1 upgrade
#   - If x version of the current CSV is equal to the desired major version (x+1), then it's the n-1 upgrade. For example, if the current version is 24.x and the desired version is 25.x, then it's a n-1 upgrade
# 2. Ifix to Ifix upgrade: Use the desired major version such as 24 from the CP4BA_CSV_VERSION in the common.sh  to compare with the current install version
#   - If x.y version of the current CSV is equal to x.y of the desired major version, then it's an Ifix to Ifix upgrade. For example, if the current version is 24.0.0-IF003 (24.0.3) and the desired version is 24.0.0-IF004 (24.0.4), then it's an Ifix to Ifix upgrade
# The function will set the is_ifix_to_ifix_upgrade flag to 1 if it's an Ifix to Ifix upgrade and 0 if it's a n-1 upgrade
function determine_type_of_upgrade() {
    info "Determining the type of upgrade"
    local current_version=$1
    local current_version_major=$(echo $current_version | cut -d'.' -f1)
    local current_version_minor=$(echo $current_version | cut -d'.' -f2)
    local desired_version="${CP4BA_CSV_VERSION//v/}"
    local desired_version_major=$(echo $desired_version | cut -d'.' -f1)
    local desired_version_minor=$(echo $desired_version | cut -d'.' -f2)
    if [[ $current_version_major"."$current_version_minor == $desired_version_major"."$desired_version_minor ]]; then
        export is_ifix_to_ifix_upgrade="true"
        info "This is an upgrade from $current_version to $desired_version which is an Ifix to Ifix upgrade"
    else
        export is_ifix_to_ifix_upgrade="false"
        info "This is an upgrade from $current_version to $desired_version which is an n-1 to n upgrade"
    fi

}

# function for checking operator version
function check_cp4ba_operator_version(){
    local project_name=$1
    local allow_direct_upgrade=$2
    local ALL_NAMESPACE_NAME="openshift-operators"
    local maxRetry=5
    info "Checking the version of IBM Cloud Pak for Business Automation Operator"

    cp4a_operator_csv_name_target_ns=$(${CLI_CMD} get csv -n $project_name --no-headers --ignore-not-found | grep "IBM Cloud Pak for Business Automation" | awk '{print $1}' | head -n 1)
    cp4a_operator_csv_name_allnamespace_ns=$(${CLI_CMD} get csv -n $ALL_NAMESPACE_NAME --no-headers --ignore-not-found | grep "IBM Cloud Pak for Business Automation" | awk '{print $1}' | head -n 1)

    if [[ -z $cp4a_operator_csv_name_allnamespace_ns && -z $cp4a_operator_csv_name_target_ns ]]; then
        fail "No found IBM Cloud Pak for Business Automation Operator in both \"$project_name\" and \"$ALL_NAMESPACE_NAME\" project."
        warning "Please input correct project name for CP4BA."
        exit 1
    fi
    for ((retry=0;retry<=${maxRetry};retry++)); do
        valid_version=false  #this is flag to check if a valid for direct upgrade CP4BA operator version was found
        if [[ -z $cp4a_operator_csv_name_allnamespace_ns && (! -z $cp4a_operator_csv_name_target_ns) ]]; then
            success "Found IBM Cloud Pak for Business Automation Operator deployed in the project \"$project_name\"."
            ALL_NAMESPACE_FLAG="No"
            TEMP_OPERATOR_PROJECT_NAME=$project_name
        elif [[ (! -z $cp4a_operator_csv_name_allnamespace_ns) && (! -z $cp4a_operator_csv_name_target_ns) ]]; then
            success "Found IBM Cloud Pak for Business Automation Operator deployed as AllNamespace mode in the project \"$ALL_NAMESPACE_NAME\"."
            ALL_NAMESPACE_FLAG="Yes"
            project_name="openshift-operators"
            TEMP_OPERATOR_PROJECT_NAME="openshift-operators"
        fi

        cp4a_operator_csv_version=$(${CLI_CMD} get csv $cp4a_operator_csv_name_target_ns -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')

        if [[ ! -z $CP4BA_ORIGINAL_CSV_VERSION ]]; then
            CP4BA_ORIGINAL_CSV_VERSION=$(sed -e 's/^"//' -e 's/"$//' <<<"$CP4BA_ORIGINAL_CSV_VERSION")
            cp4a_operator_csv_version=$CP4BA_ORIGINAL_CSV_VERSION
        fi
        # For 24.0.1 , we only support upgrades from 24.0.0 GA or a newer IFIX
        if [[ "$cp4a_operator_csv_version" == "${CP4BA_CSV_VERSION//v/}" ]]; then
            success "The current IBM Cloud Pak for Business Automation Operator is already ${CP4BA_CSV_VERSION//v/}"
            break
        fi
        # Checking if the current operator version belongs to any of the versions we support upgrade to this specific version
        for valid_version in "${upgrade_valid_versions[@]}"; do
            if [[ "$cp4a_operator_csv_version" == "$valid_version"* ]]; then
                info "The version of IBM Cloud Pak for Business Automation Operator found is \"$cp4a_operator_csv_version\" ."
                valid_version=true
                break
            fi
        done
        # Checking if the current operator version belongs to any of the versions we don't support upgrade to this specific version
        for blocked_version in "${upgrade_blocked_versions[@]}"; do

            if [[ "$cp4a_operator_csv_version" == "$blocked_version"*  && "$allow_direct_upgrade" == 1 ]]; then
                info "The version of IBM Cloud Pak for Business Automation Operator found is \"$cp4a_operator_csv_version\" ."
                valid_version=true
            elif [[ "$cp4a_operator_csv_version" == "$blocked_version"* ]]; then
                info "The version of IBM Cloud Pak for Business Automation Operator found is \"$cp4a_operator_csv_version\" ."
                fail "Please upgrade to CP4BA v26.0.0 or a later iFix first before you can upgrade to CP4BA $CP4BA_CSV_VERSION"
                exit 1
            fi
        done
        # Calling determine_type_of_upgrade function to determine the type of upgrade
        determine_type_of_upgrade "$cp4a_operator_csv_version"
        if [[ "$valid_version" == true ]]; then
            break
        fi
        if [[ "$cp4a_operator_csv_version" != "${CP4BA_CSV_VERSION//v/}" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                info "Timeout Checking for the version of IBM Cloud Pak for Business Automation in the project \"$project_name\""
                exit 1
            else
                sleep 2
                echo -n "..."
                continue
            fi
        fi
    done
    # success "Found the IBM Cloud Pak for Business Automation Operator $cp4a_operator_csv_version \n"
}

# function for checking operator version
function check_content_operator_version(){
    local project_name=$1
    local maxRetry=5
    info "Checking the version of IBM CP4BA FileNet Content Manager Operator"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        cp4a_content_operator_csv_name=$(${CLI_CMD} get csv -n $project_name --no-headers --ignore-not-found | grep "IBM CP4BA FileNet Content Manager" | awk '{print $1}' | head -n 1)
        cp4a_content_operator_csv_version=$(${CLI_CMD} get csv $cp4a_content_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')

        if [[ "$cp4a_content_operator_csv_version" == "${CP4BA_CSV_VERSION//v/}" ]]; then
            success "The current IBM CP4BA FileNet Content Manager Operator is already ${CP4BA_CSV_VERSION//v/}"
            break
        elif [[ "$cp4a_content_operator_csv_version" == "22.2."* ]]; then
            cp4a_content_operator_csv=$(${CLI_CMD} get csv $cp4a_content_operator_csv_name -n $project_name --no-headers --ignore-not-found -o 'jsonpath={.spec.version}')
            # cp4a_operator_csv="22.2.2"
            requiredver="22.2.2"
            if [ ! "$(printf '%s\n' "$requiredver" "$cp4a_content_operator_csv" | sort -V | head -n1)" = "$requiredver" ]; then
                fail "Please upgrade to CP4BA 22.0.2-IF002 or later iFix first before you can upgrade to CP4BA $CP4BA_CSV_VERSION"
                exit 1
            else
                info "Found IBM CP4BA FileNet Content Manager Operator is \"$cp4a_content_operator_csv_version\" version."
                break
            fi
        elif [[ "$cp4a_content_operator_csv_version" == "23.1."* ]]; then
            fail "Please upgrade to CP4BA 23.0.2 or later iFix first before you can upgrade to CP4BA $CP4BA_CSV_VERSION"
            exit 1
        elif [[ "$cp4a_content_operator_csv_version" == "22.1."* ]]; then
            fail "Please upgrade to CP4BA 22.0.2 or later iFix first before you can upgrade to CP4BA $CP4BA_CSV_VERSION"
            exit 1
        elif [[ "$cp4a_content_operator_csv_version" != "${CP4BA_CSV_VERSION//v/}" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                info "Timeout Checking for the version of IBM CP4BA FileNet Content Manager Operator in the project \"$project_name\""
                exit 1
            else
                sleep 2
                echo -n "..."
                continue
            fi
        fi
    done
    # success "Found the IBM CP4BA FileNet Content Manager Operator $cp4a_content_operator_csv_version \n"
}

function check_operator_status(){
    local maxRetry=60
    local project_name=$1
    local check_mode=$2 # full or part
    local check_channel=$3
    CHECK_CP4BA_OPERATOR_RESULT=()

    # Check Common Service Operator 4.0
    if [[ "$check_mode" == "full" ]]; then
        local maxRetry=30
        echo "****************************************************************************"
        info "Checking for IBM Cloud Pak foundational operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-common-service-operator.$CS_OPERATOR_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM Cloud Pak foundational operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-common-service-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-common-service-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM Cloud Pak foundational Operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM Cloud Pak foundational Operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
        
        # Check Usage metering service Operator upgrade status
        echo "****************************************************************************"
        info "Checking for IBM Usage Metering operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-usage-metering-operator.$UMS_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            if [[ -z $isReady ]]; then
                csv_version=""
                csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-usage-metering-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
                if [[ "v$csv_version" != $UMS_CSV_VERSION ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        warning "Failed to find IBM Usage Metering operator version $UMS_CSV_VERSION in the project \"$project_name\". This is optional and can be ignored if UMS is not being used."
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                fi
            elif [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    printf "\n"
                    warning "Timeout waiting for IBM Usage Metering operator to start. This is optional and can be ignored if UMS is not being used."
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                if [[ "$check_channel" != "channel" ]]; then
                    pod_name=$(${CLI_CMD} get pod -l=name=ibm-usage-metering-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    if [ -z $pod_name ]; then
                        warning "IBM Usage Metering operator pod is NOT running. This is optional and can be ignored if UMS is not being used."
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    else
                        success "IBM Usage Metering operator is running"
                        info "Pod: $pod_name"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    fi
                elif [[ "$check_channel" == "channel" ]]; then
                    success "IBM Usage Metering operator is in the phase of \"$isReady\"!"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi

    # if [[ "$check_mode" == "full" ]]; then
    #     if [[ (" ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai") || $bai_flag == "true" ]]; then
    #         # Check IBM Events Operator $EVENTS_OPERATOR_VERSION
    #         local maxRetry=10
    #         echo "****************************************************************************"
    #         info "Checking for IBM Events operator pod initialization"
    #         for ((retry=0;retry<=${maxRetry};retry++)); do
    #             isReady=$(${CLI_CMD} get csv ibm-events-operator.$EVENTS_OPERATOR_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
    #             # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine $CP4BA_RELEASE_BASE")
    #             if [[ $isReady != "Succeeded" ]]; then
    #                 if [[ $retry -eq ${maxRetry} ]]; then
    #                 printf "\n"
    #                 warning "Timeout waiting for IBM Events operator to start"
    #                 echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
    #                 echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-events-operator|awk '{print $1}') -n $project_name"
    #                 printf "\n"
    #                 echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
    #                 echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-events-operator|awk '{print $1}') -n $project_name"
    #                 printf "\n"
    #                 exit 1
    #                 else
    #                 sleep 30
    #                 echo -n "..."
    #                 continue
    #                 fi
    #             elif [[ $isReady == "Succeeded" ]]; then
    #                 pod_name=$(${CLI_CMD} get pod -l=name=ibm-events-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
    #                 if [ -z $pod_name ]; then
    #                     error "IBM Events Operator pod is NOT running"
    #                     CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
    #                     break
    #                 else
    #                     success "IBM Events Operator is running"
    #                     info "Pod: $pod_name"
    #                     CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
    #                     break
    #                 fi
    #             fi
    #         done
    #         echo "****************************************************************************"
    #     fi
    # fi

    # Check CP4BA operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        local maxRetry=30
        echo "****************************************************************************"
        info "Checking for IBM Cloud Pak for Business Automation (CP4BA) multi-pattern operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-cp4a-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ -z $isReady ]]; then
                fail "Failed to upgrade the IBM Cloud Pak for Business Automation (CP4BA) multi-pattern operator to ibm-cp4a-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                exit 1
            elif [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM Cloud Pak for Business Automation (CP4BA) multi-pattern operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-cp4a-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-cp4a-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                if [[ "$check_channel" != "channel" ]]; then
                    pod_name=$(${CLI_CMD} get pod -l=name=ibm-cp4a-operator,release=23.0.1 -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    if [ -z $pod_name ]; then
                        error "IBM Cloud Pak for Business Automation (CP4BA) multi-pattern Operator pod is NOT running"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                        break
                    else
                        success "IBM Cloud Pak for Business Automation (CP4BA) multi-pattern Operator is running"
                        info "Pod: $pod_name"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    fi
                elif [[ "$check_channel" == "channel" ]]; then
                    success "IBM Cloud Pak for Business Automation (CP4BA) multi-pattern Operator is in the phase of \"$isReady\"!"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi

    # Check IBM CP4BA FileNet Content Manager operator upgrade status
    echo "****************************************************************************"
    info "Checking for IBM CP4BA FileNet Content Manager operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-content-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-content-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA FileNet Content Manager operator to ibm-content-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM CP4BA FileNet Content Manager operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-content-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-content-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
            else
                sleep 30
                echo -n "..."
                continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-content-operator,release=$CP4BA_RELEASE_BASE --no-headers --ignore-not-found -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA FileNet Content Manager operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA FileNet Content Manager operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA FileNet Content Manager operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"

    # Check CP4BA Foundation operator upgrade status
    echo "****************************************************************************"
    info "Checking for CP4BA Foundation operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv icp4a-foundation-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep icp4a-foundation-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA Foundation operator to icp4a-foundation-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for CP4BA Foundation operator to start"
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep icp4a-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep icp4a-foundation-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=icp4a-foundation-operator,release=$CP4BA_RELEASE_BASE --no-headers --ignore-not-found -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA Foundation operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA Foundation operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA Foundation operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"

    # Check IBM CP4BA Automation Decision Service operator upgrade status
    echo "****************************************************************************"
    info "Checking for IBM CP4BA Automation Decision Service operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-ads-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-ads-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA Automation Decision Service operator to ibm-ads-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for IBM CP4BA Automation Decision Service operator to start"
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-ads-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-ads-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-ads-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA Automation Decision Service operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA Automation Decision Service operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA Automation Decision Service operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"


    # Check IBM Operational Decision Manager operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        echo "****************************************************************************"
        info "Checking for IBM Operational Decision Manager operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-odm-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ -z $isReady ]]; then
                csv_version=""
                csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-odm-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
                if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        fail "Failed to upgrade the IBM Operational Decision Manager operator to ibm-odm-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                        msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                        exit 1
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                fi
            elif [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM Operational Decision Manager operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-odm-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-odm-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                if [[ "$check_channel" != "channel" ]]; then
                    pod_name=$(${CLI_CMD} get pod -l=name=ibm-odm-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    if [ -z $pod_name ]; then
                        error "IBM Operational Decision Manager pod is NOT running"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                        break
                    else
                        success "IBM Operational Decision Manager operator is running"
                        info "Pod: $pod_name"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    fi
                elif [[ "$check_channel" == "channel" ]]; then
                    success "IBM Operational Decision Manager operator is in the phase of \"$isReady\"!"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi

    # Check IBM Document Processing Engine operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        # Check the target cluster arch type

        arch_type=$(${CLI_CMD} get cm cluster-config-v1 -n kube-system --no-headers --ignore-not-found -o yaml | grep -i architecture|tail -1| awk '{print $2}')
        if [[ "$arch_type" == "amd64" ]]; then
            echo "****************************************************************************"
            info "Checking for IBM Document Processing Engine operator pod initialization"
            for ((retry=0;retry<=${maxRetry};retry++)); do
                isReady=$(${CLI_CMD} get csv ibm-dpe-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
                # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
                if [[ -z $isReady ]]; then
                    csv_version=""
                    csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-dpe-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
                    if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                        if [[ $retry -eq ${maxRetry} ]]; then
                            fail "Failed to upgrade the IBM Document Processing Engine operator to ibm-dpe-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                            msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                            exit 1
                        else
                            sleep 30
                            echo -n "..."
                            continue
                        fi
                    fi
                elif [[ $isReady != "Succeeded" ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                    printf "\n"
                    warning "Timeout waiting for IBM Document Processing Engine operator to start"
                    echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                    echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-dpe-operator|awk '{print $1}') -n $project_name"
                    printf "\n"
                    echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                    echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-dpe-operator|awk '{print $1}') -n $project_name"
                    printf "\n"
                    exit 1
                    else
                    sleep 30
                    echo -n "..."
                    continue
                    fi
                elif [[ $isReady == "Succeeded" ]]; then
                    if [[ "$check_channel" != "channel" ]]; then
                        pod_name=$(${CLI_CMD} get pod -l=name=ibm-dpe-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                        if [ -z $pod_name ]; then
                            error "IBM Document Processing Engine pod is NOT running"
                            CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                            break
                        else
                            success "IBM Document Processing Engine operator is running"
                            info "Pod: $pod_name"
                            CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                            break
                        fi
                    elif [[ "$check_channel" == "channel" ]]; then
                        success "IBM Document Processing Engine operator is in the phase of \"$isReady\"!"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    fi
                fi
            done
            echo "****************************************************************************"
        fi
    fi

    # Check IBM CP4BA Workflow Process Service operator upgrade status
    echo "****************************************************************************"
    info "Checking for IBM CP4BA Workflow Process Service operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-cp4a-wfps-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-cp4a-wfps-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA Workflow Process Service operator to ibm-cp4a-wfps-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for IBM CP4BA Workflow Process Service operator to start"
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-cp4a-wfps-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-cp4a-wfps-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-cp4a-wfps-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA Workflow Process Service operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA Workflow Process Service operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA Workflow Process Service operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"

    # Check IBM CP4BA Insights Engine operator upgrade status
    if [[ "$check_mode" == "full" ]]; then
        echo "****************************************************************************"
        info "Checking for IBM CP4BA Insights Engine operator pod initialization"
        for ((retry=0;retry<=${maxRetry};retry++)); do
            isReady=$(${CLI_CMD} get csv ibm-insights-engine-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
            # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
            if [[ -z $isReady ]]; then
                csv_version=""
                csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-insights-engine-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
                if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                    if [[ $retry -eq ${maxRetry} ]]; then
                        fail "Failed to upgrade the IBM CP4BA Insights Engine operator to ibm-insights-engine-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                        msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                        exit 1
                    else
                        sleep 30
                        echo -n "..."
                        continue
                    fi
                fi
            elif [[ $isReady != "Succeeded" ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for IBM CP4BA Insights Engine operator to start"
                echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
                echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-insights-engine-operator|awk '{print $1}') -n $project_name"
                printf "\n"
                exit 1
                else
                sleep 30
                echo -n "..."
                continue
                fi
            elif [[ $isReady == "Succeeded" ]]; then
                if [[ "$check_channel" != "channel" ]]; then
                    pod_name=$(${CLI_CMD} get pod -l=name=ibm-insights-engine-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                    if [ -z $pod_name ]; then
                        error "IBM CP4BA Insights Engine operator pod is NOT running"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                        break
                    else
                        success "IBM CP4BA Insights Engine operator is running"
                        info "Pod: $pod_name"
                        CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                        break
                    fi
                elif [[ "$check_channel" == "channel" ]]; then
                    success "IBM CP4BA Insights Engine operator is in the phase of \"$isReady\"!"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            fi
        done
        echo "****************************************************************************"
    fi

    # Check CP4BA IBM CP4BA Process Federation Server operator upgrade status
    echo "****************************************************************************"
    info "Checking for IBM CP4BA Process Federation Server operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-pfs-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-pfs-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA Process Federation Server operator to ibm-pfs-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for IBM CP4BA Process Federation Server operator to start"
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-pfs-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-pfs-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-pfs-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA Process Federation Server operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA Process Federation Server operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA Process Federation Server operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"


    # Check CP4BA IBM CP4BA Workflow operator upgrade status
    echo "****************************************************************************"
    info "Checking for IBM CP4BA Workflow operator pod initialization"
    for ((retry=0;retry<=${maxRetry};retry++)); do
        isReady=$(${CLI_CMD} get csv ibm-workflow-operator.$CP4BA_CSV_VERSION --no-headers --ignore-not-found -n $project_name -o jsonpath='{.status.phase}')
        # isReady=$(${CLI_CMD} exec $cpe_pod_name -c ${meta_name}-cpe-deploy -n $project_name -- cat /opt/ibm/version.txt |grep -F "P8 Content Platform Engine 23.0.1")
        if [[ -z $isReady ]]; then
            csv_version=""
            csv_version=$(${CLI_CMD} get csv $(${CLI_CMD} get csv --no-headers --ignore-not-found -n $project_name | grep ibm-workflow-operator.v |awk '{print $1}' | head -n 1) --no-headers --ignore-not-found -n $project_name -o jsonpath='{.spec.version}')
            if [[ "v$csv_version" != $CP4BA_CSV_VERSION ]]; then
                if [[ $retry -eq ${maxRetry} ]]; then
                    fail "Failed to upgrade the IBM CP4BA Workflow operator to ibm-workflow-operator.$CP4BA_CSV_VERSION in the project \"$project_name\""
                    msg "Check the Subscription and ClusterServiceVersions and then fix issue first."
                    exit 1
                else
                    sleep 30
                    echo -n "..."
                    continue
                fi
            fi
        elif [[ $isReady != "Succeeded" ]]; then
            if [[ $retry -eq ${maxRetry} ]]; then
            printf "\n"
            warning "Timeout waiting for IBM CP4BA Workflow operator to start"
            echo -e "\x1B[1mPlease check the status of Pod by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe pod $(${CLI_CMD} get pod -n $project_name|grep ibm-workflow-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            echo -e "\x1B[1mPlease check the status of ReplicaSet by issue cmd:\x1B[0m"
            echo "${CLI_CMD} describe rs $(${CLI_CMD} get rs -n $project_name|grep ibm-workflow-operator|awk '{print $1}') -n $project_name"
            printf "\n"
            exit 1
            else
            sleep 30
            echo -n "..."
            continue
            fi
        elif [[ $isReady == "Succeeded" ]]; then
            if [[ "$check_channel" != "channel" ]]; then
                pod_name=$(${CLI_CMD} get pod -l=name=ibm-workflow-operator -n $project_name -o 'custom-columns=NAME:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[0].ready,DELETED:.metadata.deletionTimestamp' --no-headers --ignore-not-found | grep 'Running' | grep 'true' | grep '<none>' | head -1 | awk '{print $1}')
                if [ -z $pod_name ]; then
                    error "IBM CP4BA Workflow operator pod is NOT running"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "FAIL" )
                    break
                else
                    success "IBM CP4BA Workflow operator is running"
                    info "Pod: $pod_name"
                    CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                    break
                fi
            elif [[ "$check_channel" == "channel" ]]; then
                success "IBM CP4BA Workflow operator is in the phase of \"$isReady\"!"
                CHECK_CP4BA_OPERATOR_RESULT=( "${CHECK_CP4BA_OPERATOR_RESULT[@]}" "PASS" )
                break
            fi
        fi
    done
    echo "****************************************************************************"
}

function check_cp4ba_deployment_status(){
    local project_name=$1
    local current_cr_kind=$2
    local current_cr_name=$3
    local current_cr_details_location=$4
    UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK=${CUR_DIR}/cp4ba-upgrade/project/$project_name/custom_resource/backup/icp4acluster_cr_backup.yaml
    UPGRADE_DEPLOYMENT_CONTENT_CR_BAK=${CUR_DIR}/cp4ba-upgrade/project/$project_name/custom_resource/backup/content_cr_backup.yaml

    # Get the current status of the top level CR before we process what the status of each deployed component is
    ${CLI_CMD} get $current_cr_kind $current_cr_name -n $project_name -o yaml > ${current_cr_details_location}

    # Instead of checking if a crd type content is present and then checking if it is a top level CR and then taking the CR details,
    # we can just use the variables loaded by the retrieve_custom_resource_details function which does all this at the start of each mode
    if [[ "$current_cr_kind" == "content" ]]; then
        source ${CUR_DIR}/helper/upgrade/deployment_check/fncm_status.sh
        # Add FNCM component status variables to overall status array
        CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_CPE_DEPLOYMENT_STATUS" "$CP4BA_GRAPHQL_DEPLOYMENT_STATUS" "$CP4BA_CSS_DEPLOYMENT_STATUS" "$CP4BA_CMIS_DEPLOYMENT_STATUS" "$CP4BA_IER_DEPLOYMENT_STATUS" "$CP4BA_ICC_DEPLOYMENT_STATUS" "$CP4BA_TM_DEPLOYMENT_STATUS" "$CP4BA_BAN_DEPLOYMENT_STATUS" "$CP4BA_ES_DEPLOYMENT_STATUS")
        bai_flag=`${YQ_CMD} r "$current_cr_details_location" spec.content_optional_components.bai`
        if [[ ! -z "$bai_flag" ]]; then
            bai_flag=$(echo "$bai_flag" | tr '[:upper:]' '[:lower:]')
            if [[ "${bai_flag}" == "true" ]]; then
                source ${CUR_DIR}/helper/upgrade/deployment_check/bai_status.sh
                CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BAI_DEPLOYMENT_STATUS")
            fi
        fi
        css_flag=`${YQ_CMD} r "$current_cr_details_location" spec.content_optional_components.css`
        css_flag=$(echo "$css_flag" | tr '[:upper:]' '[:lower:]')
    elif [[ "$current_cr_kind" == "icp4acluster" ]]; then

        convert_olm_cr "${current_cr_details_location}"
        if [[ $olm_cr_flag == "No" ]]; then
            #this variable is being used to check what the version of CP4BA was used before upgrade and is used later in a check if some alert message is to be printed
            existing_pattern_list=""
            existing_opt_component_list=""
            EXISTING_PATTERN_ARR=()
            EXISTING_OPT_COMPONENT_ARR=()
            existing_pattern_list=`${YQ_CMD} r "$current_cr_details_location" spec.shared_configuration.sc_deployment_patterns`
            existing_opt_component_list=`${YQ_CMD} r "$current_cr_details_location" spec.shared_configuration.sc_optional_components`

            OIFS=$IFS
            IFS=',' read -r -a EXISTING_PATTERN_ARR <<< "$existing_pattern_list"
            IFS=',' read -r -a EXISTING_OPT_COMPONENT_ARR <<< "$existing_opt_component_list"
            IFS=$OIFS
        fi
        #################### FNCM #######################
        if [[ " ${EXISTING_PATTERN_ARR[@]}" =~ "workflow-runtime" || " ${EXISTING_PATTERN_ARR[@]}" =~ "workflow-authoring" || " ${EXISTING_PATTERN_ARR[@]}" =~ "content" || " ${EXISTING_PATTERN_ARR[@]}" =~ "document_processing" || "${EXISTING_OPT_COMPONENT_ARR[@]}" =~ "ae_data_persistence" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/fncm_status.sh
            # Add FNCM component status variables to array
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_CPE_DEPLOYMENT_STATUS" "$CP4BA_GRAPHQL_DEPLOYMENT_STATUS" "$CP4BA_CSS_DEPLOYMENT_STATUS" "$CP4BA_CMIS_DEPLOYMENT_STATUS" "$CP4BA_IER_DEPLOYMENT_STATUS" "$CP4BA_ICC_DEPLOYMENT_STATUS" "$CP4BA_TM_DEPLOYMENT_STATUS" "$CP4BA_BAN_DEPLOYMENT_STATUS" "$CP4BA_ES_DEPLOYMENT_STATUS")
        fi

        #################### ADP #######################
        if [[ " ${EXISTING_PATTERN_ARR[@]}" =~ "document_processing" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/adp_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_ADP_ACA_DEPLOYMENT_STATUS" "$CP4BA_ADP_VIEWONE_DEPLOYMENT_STATUS" "$CP4BA_ADP_CDRA_DEPLOYMENT_STATUS" "$CP4BA_ADP_CDS_DEPLOYMENT_STATUS" "$CP4BA_ADP_CPDS_DEPLOYMENT_STATUS" "$CP4BA_ADP_GITSVC_DEPLOYMENT_STATUS")
        fi

        #################### DICMS #######################
        if [[ " ${EXISTING_PATTERN_ARR[@]}" =~ "decisions_ads" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/dicms_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_ADS_CREDENTIALS_SERVICE_DEPLOYMENT_STATUS" "$CP4BA_ADS_GIT_SERVICE_DEPLOYMENT_STATUS" "$CP4BA_ADS_LTPA_CREATION_DEPLOYMENT_STATUS" "$CP4BA_ADS_PARSING_SERVICE_DEPLOYMENT_STATUS" "$CP4BA_ADS_RESTAPI_DEPLOYMENT_STATUS" "$CP4BA_ADS_RRREGISTRATION_DEPLOYMENT_STATUS" "$CP4BA_ADS_RUN_SERVICE_DEPLOYMENT_STATUS" "$CP4BA_ADS_RUNTIME_SERVICE_DEPLOYMENT_STATUS")
        fi

        #################### ODM #######################
        containsElement "decisions" "${EXISTING_PATTERN_ARR[@]}"
        odm_Val=$?
        if [[ $odm_Val -eq 0 ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/odm_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_ODM_DECISION_CENTER_DEPLOYMENT_STATUS" "$CP4BA_ODM_DECISION_RUNNER_DEPLOYMENT_STATUS" "$CP4BA_ODM_DECISIONSERVER_CONSOLE_DEPLOYMENT_STATUS" "$CP4BA_ODM_DECISIONSERVER_RUNTIME_DEPLOYMENT_STATUS")
        fi

        #################### RR #######################
        source ${CUR_DIR}/helper/upgrade/deployment_check/rr_status.sh
        CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_RR_DEPLOYMENT_STATUS")

        #################### BAA AE Multiple instance #######################
        AE_ENGINE_DEPLOYMENT=`${YQ_CMD} r "$current_cr_details_location" spec.application_engine_configuration`
        if [[ ! -z "$AE_ENGINE_DEPLOYMENT" ]]; then
            item=0
            while true; do
                ae_config_name=`${YQ_CMD} r "$current_cr_details_location" spec.application_engine_configuration.[${item}].name`
                if [[ -z "$ae_config_name" ]]; then
                    break
                else
                    source ${CUR_DIR}/helper/upgrade/deployment_check/baa_status.sh
                    CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BAA_WORKSPACE_AAE_DEPLOYMENT_STATUS")
                    ((item++))
                fi
            done
        fi
        #################### BAStudio #######################
        BASTUDIO_DEPLOYMENT=`${YQ_CMD} r "$current_cr_details_location" spec.bastudio_configuration.admin_user`
        if [[ ! -z "$BASTUDIO_DEPLOYMENT" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/bastudio_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BASTUDIO_DEPLOYMENT_STATUS")
        fi
        #################### BAI #######################
        if [[ " ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/bai_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BAI_DEPLOYMENT_STATUS")
        fi

        #################### BAML #######################
        BAML_DEPLOYMENT=`${YQ_CMD} r "$current_cr_details_location" spec.baml_configuration`
        if [[ ! -z "$BAML_DEPLOYMENT" ]]; then
            source ${CUR_DIR}/helper/upgrade/deployment_check/baml_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BAML_DEPLOYMENT_STATUS")
        fi

        #################### BAW runtime Multiple instance #######################
        BAW_DEPLOYMENT=`${YQ_CMD} r "$current_cr_details_location" spec.baw_configuration`
        if [[ ! -z "$BAW_DEPLOYMENT" ]]; then
            item=0
            while true; do
                baw_instance_name=`${YQ_CMD} r "$current_cr_details_location" spec.baw_configuration.[${item}].name`
                if [[ -z "$baw_instance_name" ]]; then
                    break
                else
                    source ${CUR_DIR}/helper/upgrade/deployment_check/baw_runtime_status.sh
                    CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_BAW_DEPLOYMENT_STATUS")
                    ((item++))
                fi
            done
        fi
    else
        fail "No top level CP4BA custom resource found on this cluster in the project \"$project_name\"."
        exit 1
    fi

    exist_wfps_cr_array=($(${CLI_CMD} get WfPSRuntime -n $project_name --no-headers --ignore-not-found | awk '{print $1}'))
    if [ ! -z $exist_wfps_cr_array ]; then
        for item in "${exist_wfps_cr_array[@]}"
        do
            cr_type="WfPSRuntime"
            wfps_cr_metaname=$(${CLI_CMD} get $cr_type ${item} -n $project_name --no-headers --ignore-not-found -o yaml | ${YQ_CMD} r - metadata.name)
            ${CLI_CMD} get $cr_type ${item} -n $project_name --no-headers --ignore-not-found -o yaml > ${UPGRADE_DEPLOYMENT_WFPSRUNTIME_CR_TMP}
            #################### WfPS #######################
            source ${CUR_DIR}/helper/upgrade/deployment_check/wfps_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_WFPS_DEPLOYMENT_STATUS")
        done
    fi

    exist_pfs_cr_array=($(${CLI_CMD} get ProcessFederationServer -n $project_name --no-headers --ignore-not-found | awk '{print $1}'))
    if [ ! -z $exist_pfs_cr_array ]; then
        for item in "${exist_pfs_cr_array[@]}"
        do
            cr_type="ProcessFederationServer"
            pfs_cr_metaname=$(${CLI_CMD} get $cr_type ${item} -n $project_name --no-headers --ignore-not-found -o yaml | ${YQ_CMD} r - metadata.name)
            ${CLI_CMD} get $cr_type ${item} -n $project_name --no-headers --ignore-not-found -o yaml > ${UPGRADE_DEPLOYMENT_PFS_CR_TMP}
            #################### PFS #######################
            source ${CUR_DIR}/helper/upgrade/deployment_check/pfs_status.sh
            CP4BA_COMPONENT_STATUS_VALUES+=("$CP4BA_PFS_DEPLOYMENT_STATUS")
        done
    fi

}

function show_cp4ba_upgrade_status() {
    printf '%s %s\n' "$(date)"

    check_cp4ba_deployment_status "${CP4BA_SERVICES_NS}" "$top_level_cr_kind" "$top_level_cr_name" "$top_level_cr_details_location"

    _original_cr_version=${original_cr_version:-"PREVIOUS"}
    ## Change the upgrade version to CP4BA_RELEASE_BASE_MAJOR_VERSION, so we don't need to update the version here when we move to a later version.
    if [[ ! ("$cp4ba_original_csv_ver_for_upgrade_script" == "$CP4BA_RELEASE_BASE_MAJOR_VERSION"*) ]]; then
        printf "\n"
        step_num=1
        echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}:"
        echo "${YELLOW_TEXT}  * The status above will be refreshing every 30 seconds.  You can continue to monitor and when all the status for the CP4BA components is ${RESET_TEXT}${GREEN_TEXT}\"Done\"${RESET_TEXT}${YELLOW_TEXT},the script will gracefully exit.${RESET_TEXT}:"

        if [[ $css_flag == "true" || " ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "css" ]]; then
            echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT}: You have Content Search Services (CSS) installed. Make sure you start the IBM Content Search Services index dispatcher. Refer to the FileNet P8 Platform Documentation for more details."
            echo "    ${YELLOW_TEXT}* Starting the IBM Content Search Services index dispatcher.${RESET_TEXT}"
            echo "      1. Log in to the Administration Console for Content Platform Engine."
            echo "      2. In the navigation pane, select the domain icon."
            echo "      3. In the edit pane, click the Text Search Subsystem tab and select the Enable indexing check box."
            echo "      4. Click Save to save your changes."
            printf "\n"
            step_num=$((step_num + 1))
        fi

        if [[  " ${EXISTING_OPT_COMPONENT_ARR[@]} " =~ "bai" || "${bai_flag}" == "true" ]]; then
            printf "\n"
            echo "${RED_TEXT}(REQUIRED)${RESET_TEXT}:"
            printf '%b\n' "  ${YELLOW_TEXT}* AFTER UPGRADING IBM CLOUD PAK FOR BUSINESS AUTOMATION (CP4BA) DEPLOYMENT SUCCESSFULLY, YOU NEED TO REMOVE${RESET_TEXT} ${RED_TEXT}\"recovery_path\"${RESET_TEXT} ${YELLOW_TEXT}FROM CUSTOM RESOURCE UNDER${RESET_TEXT} ${RED_TEXT}\"bai_configuration\"${RESET_TEXT} ${YELLOW_TEXT}MANUALLY IF EXISTING.${RESET_TEXT}"
        fi

        printf "\n"
        echo "${YELLOW_TEXT}[ATTENTION]: ${RESET_TEXT}${YELLOW_TEXT}PLEASE DON'T SET ${RESET_TEXT}${RED_TEXT}\"shared_configuration.sc_egress_configuration.sc_restricted_internet_access\"${RESET_TEXT}${YELLOW_TEXT} TO ${RESET_TEXT}${RED_TEXT}\"true\"${RESET_TEXT}${YELLOW_TEXT} UNTIL AFTER YOU'VE COMPLETED THE CP4BA UPGRADE TO $CP4BA_RELEASE_BASE.${RESET_TEXT} ${GREEN_TEXT}(UNLESS YOU ALREADY HAD THIS SET TO \"true\" IN THE ${_original_cr_version} CP4BA VERSION)${RESET_TEXT}"
    else
        printf "\n"
        step_num=1
        echo "${YELLOW_TEXT}[NEXT ACTION]${RESET_TEXT}:"
        echo "${YELLOW_TEXT}  * The status above will be refreshing every 30 seconds.  You can continue to monitor and when all the status for the CP4BA components is ${RESET_TEXT}${GREEN_TEXT}\"Done\"${RESET_TEXT}${YELLOW_TEXT}, the script will gracefully exit.${RESET_TEXT}"
        printf "\n"
    fi
}
function check_cp4ba_separate_operand(){
    local project=$1
    # Check whether the CP4BA is separation of operators and operands.
    # also need to consider upgrade to 24.0.0 eGA
    # operators_namespace: openshift-operators
    # services_namespace: ibm-common-services

    # operators_namespace: ibm-common-services
    # services_namespace: ibm-common-services

    # operators_namespace: cp4a-ns
    # services_namespace: cp4a-ns

    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $project >/dev/null 2>&1; then
        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$project\"."
    else
        warning "\"ibm-cp4ba-common-config\" configMap was not found in the project \"$project\"."
        while [[ $CP4BA_SERVICES_NS == "" ]];
        do
            printf "\n"
            if [[ ($SCRIPT_MODE == "" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "review" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "baw-dev" && $RUNTIME_MODE == "") ]]; then
                echo -e "\x1B[1mWhere (namespace) do you want to deploy CP4BA operands (i.e., runtime pods)? \x1B[0m"
            else
                echo -e "\x1B[1mWhere (namespace) did you deploy CP4BA operands (i.e., runtime pods)? \x1B[0m"
            fi
            read -p "Enter the name for an existing namespace: " CP4BA_SERVICES_NS
            if [ -z "$CP4BA_SERVICES_NS" ]; then
                echo -e "\x1B[1;31mEnter a valid namespace name, namespace name can not be blank\x1B[0m"
            elif [[ "$CP4BA_SERVICES_NS" == openshift* ]]; then
                echo -e "\x1B[1;31mEnter a valid namespace name, namespace name should not be 'openshift' or start with 'openshift' \x1B[0m"
                CP4BA_SERVICES_NS=""
            elif [[ "$CP4BA_SERVICES_NS" == kube* ]]; then
                echo -e "\x1B[1;31mEnter a valid namespace name, namespace name should not be 'kube' or start with 'kube' \x1B[0m"
                CP4BA_SERVICES_NS=""
            else
                isProjExists=`${CLI_CMD} get namespace $CP4BA_SERVICES_NS --ignore-not-found | wc -l`  >/dev/null 2>&1

                if [ "$isProjExists" -ne 2 ] ; then
                    echo -e "\x1B[1;31mInvalid namespace name, please enter a existing namespace name ...\x1B[0m"
                    CP4BA_SERVICES_NS=""
                else
                    echo -e "\x1B[1mUsing project ${CP4BA_SERVICES_NS}...\x1B[0m"
                    if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $CP4BA_SERVICES_NS >/dev/null 2>&1; then
                        success "Found \"ibm-cp4ba-common-config\" configMap in the project \"$CP4BA_SERVICES_NS\"."
                    else
                        warning "\"ibm-cp4ba-common-config\" configMap not found in the project \"$CP4BA_SERVICES_NS\"."
                        CP4BA_SERVICES_NS=""
                        if [[ ($SCRIPT_MODE == "" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "review" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "baw-dev" && $RUNTIME_MODE == "") || ($SCRIPT_MODE == "" && $RUNTIME_MODE == "upgradeOperator")|| ($SCRIPT_MODE == "" && $RUNTIME_MODE == "upgradeDeployment") || ($SCRIPT_MODE == "" && $RUNTIME_MODE == "upgradeDeploymentStatus") ]]; then
                            # For https://jsw.ibm.com/browse/DBACLD-160661 where we have added remediation steps on how to recreate the configmap
                            fail "You NEED to first create the \"ibm-cp4ba-common-config\" configMap in the project (namespace) where you want to deploy or upgrade CP4BA operands (i.e., runtime pods)."
                            info "${YELLOW_TEXT}- [NEXT-STEPS]${RESET_TEXT}"
                            echo "  - STEP 1 ${RED_TEXT}(Required)${RESET_TEXT}:${GREEN_TEXT} # Execute the cp4a-clusteradmin-setup.sh script with the \"-fix_configmap\" option to re-create the missing \"ibm-cp4ba-common-config\" configMap in the target namespace.For additional information refer to the Troubleshooting page in the Upgrade Section of the Knowledge Center.${RESET_TEXT}"
                            exit 1
                        fi
                    fi
                fi
            fi
        done
    fi
    tmp_namespace_val=""
    if [[ $CP4BA_SERVICES_NS != "" ]]; then
        tmp_namespace_val=$CP4BA_SERVICES_NS
    else
        tmp_namespace_val=$project
    fi
    cp4ba_services_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.services_namespace}')
    cp4ba_operators_namespace=$(${CLI_CMD} get configMap ibm-cp4ba-common-config -n $tmp_namespace_val --no-headers --ignore-not-found -o jsonpath='{.data.operators_namespace}')
    if [[ (! -z $CP4BA_SERVICES_NS) ]]; then
        if [[ $cp4ba_services_namespace != $CP4BA_SERVICES_NS ]]; then
            fail "Your input value for CP4BA operands (i.e., runtime pods) is NOT equal to the value of \"services_namespace\" in \"ibm-cp4ba-common-config\" configMap under the project \"$CP4BA_SERVICES_NS\"."
            exit 1
        fi
    fi

    if [[ (! -z $cp4ba_services_namespace) && (! -z $cp4ba_operators_namespace) ]]; then
        # The IF condition below checks for separation of duties scenario (note: all-ns and shared CPfs are not considered separation of duties):
        #  - ($cp4ba_services_namespace != $cp4ba_operators_namespace) -> confirms that operator and services ns are different
        #  - ($cp4ba_operators_namespace != "openshift-operators") -> confirms that scenario is NOT all-ns
        #  - ($cp4ba_operators_namespace != "ibm-common-services") -> confirms that scenario is NOT shared/cluster-scoped CPfs scenario
        if [[ ($cp4ba_services_namespace != $cp4ba_operators_namespace) && ($cp4ba_operators_namespace != "openshift-operators" && $cp4ba_operators_namespace != "ibm-common-services") ]]; then
            info "This CP4BA deployment has been deployed with operators and operands in separate namespaces."
            SEPARATE_OPERAND_FLAG="Yes"
            CP4BA_SERVICES_NS=$cp4ba_services_namespace
            CP4BA_OPERATOR_NS=$cp4ba_operators_namespace #DBACLD-185209: Update logic to return Operator ns for separation of duty deployment.
        else
            SEPARATE_OPERAND_FLAG="No"
            CP4BA_SERVICES_NS=$cp4ba_services_namespace
            CP4BA_OPERATOR_NS=$cp4ba_operators_namespace
        fi
    else
        warning "\"operator_namespace\\services_namespace\" was not found in \"ibm-cp4ba-common-config\" configMap under the project \"$tmp_namespace_val\""
        fail "You need to set correct value(s) in \"ibm-cp4ba-common-config\" configMap for CP4BA seperate of operand under the project \"$tmp_namespace_val\""
        exit 1
    fi
}
