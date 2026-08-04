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

# This script contains shared utility functions and environment variables.
# CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

TEMP_FOLDER=${CUR_DIR}/.tmp
mkdir -p $TEMP_FOLDER
REQUIRED_JAVA_MAJOR_VERSION=17  # Semeru 17 is required for CP4BA 25.x

# Directory for common service script
COMMON_SERVICES_SCRIPT_FOLDER=${CUR_DIR}/cpfs/installer_scripts/cp3pt0-deployment
COMMON_SERVICES_SCRIPT_PARENT_FOLDER=${CUR_DIR}/cpfs/installer_scripts
OPENSEARCH_MIGRATION_SCRIPT=${CUR_DIR}/cpfs/migration/es-os-migration-script.sh

COMMON_SERVICES_SCRIPT_YQ_FOLDER=${CUR_DIR}/cpfs/yq
ALL_NAMESPACE_NAME="openshift-operators"
# Start of Section for BAW Rancher specific variables

# BAW CNCF folder
BAW_CNCF_FOLDER=${PARENT_DIR}/cncf/scripts

#OLM VARIABLES while installing olm on Rancher
OLM_MINIMAL_VERSION=v0.23.1
OLM_VERSION=v0.32.0

#Licensing service related variables that required during the creation of subscription and the checks.
# NEED TO BE UPDATED WHEN WE UPDATE THE VERSIONS
LICENSING_SERVICE_CHANNEL=v4.2
LICENSING_SERVICE_TARGET_VERSION="4.2.24"

#Cert Manager related variables that required during the creation of subscription and the checks.
# NEED TO BE UPDATED WHEN WE UPDATE THE VERSIONS
CERT_MANAGER_CHANNEL=v4.2
CERT_MANAGER_TARGET_VERSION="4.2.23"

# CATALOG SOURCE file name
CATALOG_SOURCE_FILENAME=${PARENT_DIR}/descriptors/op-olm/catalog_source.yaml
# OPERATOR GROUP file name
OPERATOR_GROUP_FILENAME=${PARENT_DIR}/descriptors/op-olm/operator_group.yaml
# SUBSCRIPTION file name
SUBSCRIPTION_FILENAME=${PARENT_DIR}/descriptors/op-olm/subscription.yaml

#The below are upgrade script variables needed for Rancher but these are currently not required for this release
licensing_service_minimal_version_for_upgrade="4.2.0"
cert_manager_minimal_version_for_upgrade="4.2.0"
cs_minimal_version_for_upgrade="4.6.2" # Minimal supported Common Service version before upgrading from 26.0.0 (version from 24.0.0)
cs_maximal_version_for_upgrade="5.0.0" # Maximal supported Common Service version before upgrading from 26.0.0
cs_minimal_version_for_ifix="4.10.0" # Minimal supported Common Service version before upgrading for ifix
cs_maximal_version_for_ifix="5.0.0" # Maximal supported Common Service version before upgrading for ifix

# Need this for the BAW S on CNCF dev mode so that we can get the image repository
BAW_S_FC_CR=${PARENT_DIR}/descriptors/patterns/ibm_cp4a_cr_production_FC_baw.yaml

#Change required each sprint for using dev mode
CURRENT_SPRINT_TAG="2500.SP06"
CP4BA_SERVICES_NS=""
CP4BA_OPERATORS_NS=""


# End of Section for BAW Rancher specific variables


PREREQUISITES_FOLDER=${CUR_DIR}/baw-prerequisites/project/$1
PREREQUISITES_FOLDER_BAK=${CUR_DIR}/baw-prerequisites-backup/project/$1
PROPERTY_FILE_FOLDER=${PREREQUISITES_FOLDER}/propertyfile
GENERATED_INGRESS_FILE_FOLDER=${PREREQUISITES_FOLDER}/ingress_template
GENERATED_GATEWAY_API_FILE_FOLDER=${PREREQUISITES_FOLDER}/gateway_api_template
PROPERTY_FILE_FOLDER_BAK=${PREREQUISITES_FOLDER_BAK}/propertyfile
CREATE_SECRET_SCRIPT_FILE=$PREREQUISITES_FOLDER/create_secret.sh

LDAP_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/ldap
EXT_LDAP_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/external_ldap
DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/db
ZEN_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/zen_external_db
IM_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/im_external_db
BTS_DB_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/bts_external_db
CP4BA_TLS_ISSUER_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/cp4ba_tls_issuer
AE_REDIS_SSL_CERT_FOLDER=${DB_SSL_CERT_FOLDER}/redis-ae
PLAYBACK_REDIS_SSL_CERT_FOLDER=${DB_SSL_CERT_FOLDER}/redis-playback
ADP_GIT_SSL_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/adp_git
ADP_CDRA_CERT_FOLDER=${PROPERTY_FILE_FOLDER}/cert/adp_cdra

TEMPORARY_PROPERTY_FILE=${TEMP_FOLDER}/.TEMPORARY.property
LDAP_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_LDAP.property
EXTERNAL_LDAP_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/cp4ba_External_LDAP.property

DB_NAME_USER_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_db_name_user.property
DB_SERVER_INFO_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_db_server.property
USER_PROFILE_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_user_profile.property

BAW_AUTH_OS_ARR=("BAWDOCS" "BAWDOS" "BAWTOS")
AEOS=("AEOS")
# Directory and script file for DB Script
DB_SCRIPT_FOLDER=${PREREQUISITES_FOLDER}/dbscript
FNCM_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/fncm
BAN_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/ban
ODM_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/odm
BAS_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/bas
ADP_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/adp
ADS_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/ads
BAA_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/baa
AE_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/ae
BAW_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/baw-authoring
BAW_AWS_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/baw-aws
UMS_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/ums

# Directory and template file for secret YAML template
SECRET_FILE_FOLDER=${PREREQUISITES_FOLDER}/secret_template

DB_SSL_SECRET_FOLDER=${SECRET_FILE_FOLDER}/cp4ba_db_ssl_secret
LDAP_SSL_SECRET_FOLDER=${SECRET_FILE_FOLDER}/baw_ldap_ssl_secret
REDIS_SSL_SECRET_FOLDER=${SECRET_FILE_FOLDER}/cp4ba_redis_ssl_secret

CP4A_DB_SSL_SECRET_FILE=${DB_SSL_SECRET_FOLDER}/ibm-cp4ba-db-ssl-cert-secret.sh
CP4A_AE_REDIS_SSL_SECRET_FILE=${REDIS_SSL_SECRET_FOLDER}/ibm-cp4ba-ae-redis-ssl-cert-secret.sh
CP4A_PLAYBACK_REDIS_SSL_SECRET_FILE=${REDIS_SSL_SECRET_FOLDER}/ibm-cp4ba-playback-redis-ssl-cert-secret.sh
CP4A_LDAP_SSL_SECRET_FILE=${LDAP_SSL_SECRET_FOLDER}/ibm-cp4ba-ldap-ssl-cert-secret.sh
CP4A_EXT_LDAP_SSL_SECRET_FILE=${LDAP_SSL_SECRET_FOLDER}/ibm-cp4ba-external-ldap-ssl-cert-secret.sh


LDAP_SECRET_FILE=${SECRET_FILE_FOLDER}/ldap-bind-secret.yaml
EXT_LDAP_SECRET_FILE=${SECRET_FILE_FOLDER}/ext-ldap-bind-secret.yaml

FNCM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/fncm
FNCM_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-fncm-secret.yaml

FNCM_ICC_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-fncm-icc-secret.yaml
FNCM_ICCSAP_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-fncm-iccsap-secret.yaml
FNCM_IER_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-fncm-ier-secret.yaml
FNCM_DB_SSL_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-fncm-db-ssl-cert-secret.sh

BAN_SECRET_FOLDER=${SECRET_FILE_FOLDER}/ban
BAN_SECRET_FILE=${BAN_SECRET_FOLDER}/ibm-ban-secret.yaml
BAN_DB_SSL_SECRET_FILE=${BAN_SECRET_FOLDER}/ibm-ban-db-ssl-cert-secret.sh

UMS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/ums
UMS_SECRET_FILE=${UMS_SECRET_FOLDER}/ibm-ums-db-secret.yaml
UMS_DB_SSL_SECRET_FILE=${UMS_SECRET_FOLDER}/ibm-ums-db-ssl-cert-secret.sh

ODM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/odm
ODM_SECRET_FILE=${ODM_SECRET_FOLDER}/ibm-odm-db-secret.yaml
ODM_DB_SSL_SECRET_FILE=${ODM_SECRET_FOLDER}/ibm-odm-db-ssl-cert-secret.sh

ADP_SECRET_FOLDER=${SECRET_FILE_FOLDER}/adp
ADP_BASE_DB_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-aca-db-secret.sh
ADP_BASE_DB_SECRET_YAML_FILE=${ADP_SECRET_FOLDER}/ibm-aca-db-secret.yaml
ADP_GIT_SSL_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-adp-git-connection-secret.sh
ADP_CDRA_SSL_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-adp-cdra-route-secret.sh
ADP_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-adp-secret.yaml
ADP_ACA_DESIGN_API_KEY_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-adp-aca-design-api-key-secret.sh

ADP_DB_SSL_SECRET_FILE=${ADP_SECRET_FOLDER}/ibm-apd-db-ssl-cert-secret.sh

BAW_SECRET_FOLDER=${SECRET_FILE_FOLDER}/baw
BAW_SECRET_FILE=${BAW_SECRET_FOLDER}/ibm-baw-db-secret.yaml
BAW_DB_SSL_SECRET_FILE=${BAW_SECRET_FOLDER}/ibm-baw-authoring-db-ssl-cert-secret.sh

BAW_AWS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/baw-aws
BAW_AWS_SECRET_FILE=${BAW_AWS_SECRET_FOLDER}/ibm-aws-db-secret.yaml
BAW_RUNTIME_SECRET_FILE=${BAW_AWS_SECRET_FOLDER}/ibm-baw-db-secret.yaml
ICP4A_ENCRYPTION_KEY_SECRET_FILE=${BAW_AWS_SECRET_FOLDER}/icp4a-shared-encryption-key-secret.yaml

APP_ENGINE_SECRET_FOLDER=${SECRET_FILE_FOLDER}/ae
APP_ENGINE_SECRET_FILE=${APP_ENGINE_SECRET_FOLDER}/ibm-aae-app-engine-secret.yaml
APP_ENGINE_PLAYBACK_SECRET_FILE=${APP_ENGINE_SECRET_FOLDER}/ibm-playback-server-admin-secret.yaml
APP_ENGINE_DB_SSL_SECRET_FILE=${APP_ENGINE_SECRET_FOLDER}/ibm-aae-app-engine-db-ssl-cert-secret.sh
APP_ORACLE_SSO_SSL_SECRET_FILE=${DB_SSL_SECRET_FOLDER}/ibm-ae-oracle-sso-cert-secret.sh

BAS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/bas
BAS_SECRET_FILE=${BAS_SECRET_FOLDER}/ibm-bas-admin-secret.yaml
BAS_DB_SSL_SECRET_FILE=${BAS_SECRET_FOLDER}/ibm-bas-admin-db-ssl-cert-secret.sh

#add ads varibles
ADS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/ads
ADS_SECRET_FILE=${ADS_SECRET_FOLDER}/ibm-dba-ads-mongo-secret.yaml
ADS_DB_SSL_SECRET_FILE=${ADS_SECRET_FOLDER}/ibm-dba-ads-mongo-db-ssl-cert-secret.sh
ADS_DESIGNER_FILE=${ADS_SECRET_FOLDER}/ibm-ads-designer-database.yaml
ADS_RUNTIME_FILE=${ADS_SECRET_FOLDER}/ibm-ads-runtime-database.yaml

ZEN_SECRET_FOLDER=${SECRET_FILE_FOLDER}/zen_external_db
ZEN_SECRET_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-edb-secret.sh
ZEN_CONFIGMAP_FILE=${ZEN_SECRET_FOLDER}/ibm-zen-metastore-edb-cm.yaml

IM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/im_external_db
IM_SECRET_FILE=${IM_SECRET_FOLDER}/ibm-im-metastore-edb-secret.sh
IM_CONFIGMAP_FILE=${IM_SECRET_FOLDER}/ibm-im-metastore-edb-cm.yaml

BTS_SECRET_FOLDER=${SECRET_FILE_FOLDER}/bts_external_db
BTS_SSL_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-ssl-secret.sh
BTS_SECRET_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-user-secret.yaml
BTS_CONFIGMAP_FILE=${BTS_SECRET_FOLDER}/ibm-bts-metastore-edb-cm.yaml

CP4BA_TLS_ISSUER_FOLDER=${SECRET_FILE_FOLDER}/cp4ba_tls_issuer
CP4BA_TLS_ISSUER_SECRET_FILE=${CP4BA_TLS_ISSUER_FOLDER}/ibm-cp4ba-tls-issuer-secret.sh
CP4BA_TLS_ISSUER_FILE=${CP4BA_TLS_ISSUER_FOLDER}/ibm-cp4ba-tls-issuer.yaml
CP4A_LDAP_SSL_SECRET_FILE=${LDAP_SSL_SECRET_FOLDER}/ibm-baw-ldap-ssl-cert-secret.sh


LDAP_SECRET_FILE=${SECRET_FILE_FOLDER}/ldap-bind-secret.yaml

# Release/Patch version for CP4BA
# CP4BA_RELEASE_BASE is for fetch content/foundation operator pod, only need to change for major release.
CP4BA_RELEASE_BASE="26.0.0"
BAW_PATCH_VERSION="IF001"
BAW_PATCH_VERSION="IF001"
#DBACLD-222678: This variable is used to specify the version that will skip EDB and Starter deployment option. It should be in the format of ${CP4BA_RELEASE_BASE}_${BAW_PATCH_VERSION}
# For 26.0.0_GA we will remove the Starter option and EDB option.
# From 26.0.0_IF001 onwards CNPG is supported, so skip_edb() returns 1 (false) and upgrade is allowed.
VERSION_TO_SKIP_EDB="26.0.0_GA"
# CP4BA_RELEASE_BASE_MAJOR_VERSION is used in certain checks where we used to hardcode to see if a upgrade is not ifix to ifix,change this only for major release
CP4BA_RELEASE_BASE_MAJOR_VERSION="26.0"
CP4BA_PATCH_VERSION="IF001"
# CP4BA_CSV_VERSION is for checking CP4BA operator upgrade status, need to update for each IFIX
CP4BA_CSV_VERSION="v26.0.1"
# CP4BA_CHANNEL_VERSION is for switch CP4BA operator upgrade status, need to update for major release
CP4BA_CHANNEL_VERSION="v26.0"
# CS_OPERATOR_VERSION is for checking CPFS operator upgrade status, need to update for each IFIX
CS_OPERATOR_VERSION="v4.19.2"
# CS_CHANNEL_VERSION is for for CPFS script -c option, need to update for each IFIX
CS_CHANNEL_VERSION="v4.19"
# CS CHANNEL VERSION that is used in the KC
# UMS (User Metering Service) Related Variables
# UMS_CHANNEL_VERSION is for UMS, need to update for each IFIX
UMS_CHANNEL_VERSION="v1.0"
# UMS_CSV_VERSION is for UMS, need to update for each IFIX
UMS_CSV_VERSION="v1.0.7"
# UMS_CATALOG_VERSION is the current UMS catalog name.
UMS_CATALOG_VERSION="ibm-usage-metering-catalog"
# UMS connection point secret name
UMS_CONNECTION_POINT_SECRET_NAME="baw-ums-secret"

#VPC metrics Related Variables

# Connection connection point secret name
ILS_CONNECTION_POINT_SECRET_NAME="baw-ils-secret"

# UMS OPERATOR subscription template location
UMS_OLM_SUBSCRIPTION=${PARENT_DIR}/descriptors/op-olm/baw-metrics/subscription.yaml
# UMS static CR location
UMS_STATIC_CR_LOCATION="${PARENT_DIR}/descriptors/patterns/baw-metrics"
# UMS Connection Point Static CR location
UMS_CONNECTION_POINT_STATIC_CR_LOCATION="${PARENT_DIR}/descriptors/patterns/baw-metrics/software-central-connection"

CS_CHANNEL_KC="4.x_cd"
# CERT_LICENSE_OPERATOR_VERSION is for checking IBM cert-manager/licensing operator upgrade status, need to update for each IFIX
CERT_LICENSE_OPERATOR_VERSION="v4.2.23"
# CERT_LICENSE_CHANNEL_VERSION is for for IBM cert-manager/licensing script -c option, need to update for each IFIX
CERT_LICENSE_CHANNEL_VERSION="v4.2"
# CS_CATALOG_VERSION is for CPFS script -s option, need to update for each IFIX
CS_CATALOG_VERSION="ibm-cs-install-catalog-v4-19-0"
# ZEN_OPERATOR_VERSION is for checking ZenService operator upgrade status, need to update for each IFIX
ZEN_OPERATOR_VERSION="v6.10.3"
# BTS_CHANNEL_VERSION is for for BTS, need to update for each IFIX
BTS_CHANNEL_VERSION="v3.35"
# BTS_CATALOG_VERSION is for BTS 3.35.13.
BTS_CATALOG_VERSION="ibm-bts-operator-catalog-v3-35"
# REQUIREDVER_BTS is for checking bts operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_BTS="3.35.13"
# REQUIREDVER_POSTGRESQL is for checking postgresql operator upgrade status before run removal_iaf.sh, need to update for each IFIX
REQUIREDVER_POSTGRESQL="1.28.4"
# EVENTS_OPERATOR_VERSION is for checking IBM Events operator upgrade status, need to update for each IFIX
EVENTS_OPERATOR_VERSION="v5.2.1"
# List of BAW versions that are supported for upgrade to $CP4BA_CSV_VERSION
MINIMUM_SUPPORTED_UPGRADE_VERSIONS=(25.0.1 25.0.0)

# Zen metastore EDB configmap name
ZEN_EDB_CFG="ibm-zen-metastore-edb-cm"
CERT_MANAGER_PROJECT="ibm-cert-manager"
LICENSE_MANAGER_PROJECT="ibm-licensing"
DEDICATED_CS_PROJECT="cs-control"
# Directory for upgrade operator and prerequisites
UPGRADE_TEMP_FOLDER=${TEMP_FOLDER}/upgrade
UPGRADE_PREREQUISITE_FOLDER=${UPGRADE_TEMP_FOLDER}/prerequisites
UPGRADE_CERT_MANAGER_FILE=${UPGRADE_PREREQUISITE_FOLDER}/cert_manager_operator.yaml
UPGRADE_IBM_LICENSE_FILE=${UPGRADE_PREREQUISITE_FOLDER}/license_operator.yaml
UPGRADE_OPERATOR_GROUP=${UPGRADE_PREREQUISITE_FOLDER}/operator_group.yaml

# Check CS is dedicated or shared
COMMON_SERVICES_CM_NAMESPACE="kube-public"
COMMON_SERVICES_CM_DEDICATED_NAME="common-service-maps"
COMMON_SERVICES_CM_SHARED_NAME="ibm-common-services-status"
COMMON_SERVICES_NAME="IBM Cloud Pak foundational services"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE="common-service-maps-update.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE_NAME="common-service-maps.yaml"
COMMON_SERVICES_CM_DEDICATE_FILE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME}"
COMMON_SERVICES_CM_DEDICATE_FILE_UPDATE="${PARENT_DIR}/descriptors/${COMMON_SERVICES_CM_DEDICATE_FILE_NAME_UPDATE}"

#List of operators to be scale up or down
CP4BA_OPERATOR_LIST="ibm-cp4a-operator ibm-content-operator icp4a-foundation-operator  ibm-ads-operator  ibm-ccx-ai-services-operator ibm-cp4a-wfps-operator ibm-dpe-operator ibm-insights-engine-operator ibm-odm-operator ibm-pfs-operator ibm-workflow-operator"

# CP4BA EDB default instance name
EDB_INSTANCE_CP4BA_NAME="postgres-cp4ba"

# EDB to CNPG Migration ConfigMap name
EDB_CNPG_MIGRATION_CM_NAME="edb-cnpg-migration"
EDB_TO_CNPG_MIGRATION_FOLDER="${CUR_DIR}/cp4ba-upgrade/project/$1"

# EDB to CNPG Migration CNPG Cluster template path
CNPG_CLUSTER_TEMPLATE="${PARENT_DIR}/descriptors/cnpg/cnpg-cluster-postgres-cp4ba-template.yaml"

# CNPG operator subscription template and version
CNPG_OPERATOR_SUBSCRIPTION_TEMPLATE="${PARENT_DIR}/descriptors/cnpg/cnpg-operator-subscription-template.yaml"
CNPG_OPERATOR_CHANNEL="v28"
CNPG_OPERATOR_CSV_VERSION="ibm-pg-operator.v28.4.0"

# set CLI_CMD var
# Prioritize kubectl for CNCF platforms (Tanzu/Rancher/GKE)
# Check if we're actually connected to an OpenShift cluster
if kubectl version --client 2>/dev/null | grep -q "Client Version" && ! oc version 2>/dev/null | grep -q "Server Version.*openshift"; then
    # kubectl is available and we're NOT on an OpenShift cluster
    CLI_CMD=kubectl
elif which oc >/dev/null 2>&1; then
    CLI_CMD=oc
elif which kubectl >/dev/null 2>&1; then
    CLI_CMD=kubectl
else
    echo -e  "\x1B[1;31mUnable to locate Kubernetes CLI or OpenShift CLI. You must install it to run this script.\x1B[0m" && \
    exit 1
fi

function prop_upgrade_property_file() {
    grep "^${1}=" ${UPGRADE_DEPLOYMENT_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_tmp_property_file() {
    grep "^${1}=" ${TEMPORARY_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_ldap_property_file() {
    grep "^${1}=" ${LDAP_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_ext_ldap_property_file() {
    grep "^${1}=" ${EXTERNAL_LDAP_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_user_profile_property_file() {
    grep "^${1}=" ${USER_PROFILE_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_db_name_user_property_file() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'"' -f2
}

function prop_db_name_user_property_file_for_server_name() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'.' -f1
}

function prop_osdb_property_file() {
    grep "^.*${1}=" ${DB_NAME_USER_PROPERTY_FILE}|cut -d'=' -f2
}

function prop_db_server_property_file() {
    local value=$(grep "^${1}=" ${DB_SERVER_INFO_PROPERTY_FILE}|cut -d'"' -f2)
    # Convert azuresqlmi to sqlserver for CR generation (operator only understands sqlserver)
    if [[ "${1}" == *"DATABASE_TYPE" && "$value" == "azuresqlmi" ]]; then
        value="sqlserver"
    fi
    echo "$value"
}

function prop_db_oracle_server_property_file() {
    grep "^${1}=" ${DB_SERVER_INFO_PROPERTY_FILE}|cut -d'"' -f2
}
# set CLI_CMD var
# Prioritize kubectl for CNCF platforms (Tanzu/Rancher/GKE)
# Check if we're actually connected to an OpenShift cluster
if kubectl version --client 2>/dev/null | grep -q "Client Version" && ! oc version 2>/dev/null | grep -q "Server Version.*openshift"; then
    # kubectl is available and we're NOT on an OpenShift cluster
    CLI_CMD=kubectl
elif which oc >/dev/null 2>&1; then
    CLI_CMD=oc
elif which kubectl >/dev/null 2>&1; then
    CLI_CMD=kubectl
else
    echo -e  "\x1B[1;31mUnable to locate Kubernetes CLI or OpenShift CLI. You must install it to run this script.\x1B[0m" && \
    exit 1
fi


function set_global_env_vars() {
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)      machine="Linux";;
        Darwin*)     machine="Mac";;
        *)           machine="UNKNOWN:${unameOut}"
    esac

    if [[ "$machine" == "Mac" ]]; then
        SED_COMMAND='sed -i ""'
        SED_COMMAND_FORMAT='sed -i "" s/^M//g'
        YQ_CMD=${CUR_DIR}/helper/yq/yq_darwin_amd64
        CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/macos/yq
        COPY_CMD=/bin/cp
        BASE64_DECODE='base64 --decode'
    else
        SED_COMMAND='sed -i'
        SED_COMMAND_FORMAT='sed -i s/\r//g'
        BASE64_DECODE='base64 -w 0 --decode'
        if [[ $(uname -m) == 'x86_64' ]]; then
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_amd64
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/amd64/yq
        elif [[ $(uname -m) == 'ppc64le' ]]; then
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_ppc64le
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/ppc64le/yq
        else
            YQ_CMD=${CUR_DIR}/helper/yq/yq_linux_s390x
            CPFS_YQ_PATH=$COMMON_SERVICES_SCRIPT_YQ_FOLDER/s390x/yq
        fi
        COPY_CMD=/usr/bin/cp
    fi
}

############################
# CLI installation utilities
############################

function validate_cli(){
    which ${YQ_CMD} &>/dev/null
    [[ $? -ne 0 ]] && \
        while true; do
            echo_bold "\"yq\" Command Not Found\n"
            echo_bold "Please download \"yq\" binary file from cert-kubernetes repo\n"
            exit 0
        done
    which timeout &>/dev/null
    [[ $? -ne 0 ]] && \
        while true; do
            echo_bold "\"timeout\" Command Not Found\n"
            echo_bold "The \"timeout\" will be installed automatically\n"
            echo_bold "Do you accept (Yes/No, default: No):"
            read -rp "" ans
            case "$ans" in
            "y"|"Y"|"yes"|"Yes"|"YES")
                install_timeout_cli
                break
                ;;
            "n"|"N"|"no"|"No"|"NO")
                echo -e "You do not accept, exiting...\n"
                exit 0
                ;;
            *)
                echo_red "You do not accept, exiting...\n"
                exit 0
                ;;
            esac
        done
}

function install_timeout_cli(){
    if [[ ${machine} = "Mac" ]]; then
        echo -n "Installing timeout..."; brew install coreutils >/dev/null 2>&1; sudo ln -s /usr/local/bin/gtimeout /usr/local/bin/timeout >/dev/null 2>&1; echo "done.";
    fi
    printf "\n"
}

function install_yq_cli(){
    if [[ ${machine} = "Linux" ]]; then
        echo -n "Downloading..."; curl -LO https://github.com/mikefarah/yq/releases/download/3.2.1/yq_linux_amd64  >/dev/null 2>&1; echo "done.";
        echo -n "Installing yq..."; sudo chmod +x yq_linux_amd64 >/dev/null; sudo mv yq_linux_amd64 /usr/local/bin/yq >/dev/null; echo "done.";
    else
        echo -n "Installing yq..."; brew install yq >/dev/null; echo "done.";
    fi
    printf "\n"
}

function validate_java_runtime() {
    local CUSTOM_JAVA_PATH=$1
    
    # Step 1: Set JAVA_CMD and KEYTOOL_CMD based on CUSTOM_JAVA_PATH
    if [[ -n "$CUSTOM_JAVA_PATH" ]]; then
        # Normalize path - ensure it points to bin directory
        if [[ "$CUSTOM_JAVA_PATH" != */bin ]]; then
            CUSTOM_JAVA_PATH="${CUSTOM_JAVA_PATH}/bin"
        fi
        
        JAVA_CMD="${CUSTOM_JAVA_PATH}/java"
        KEYTOOL_CMD="${CUSTOM_JAVA_PATH}/keytool"
        
        # Verify the custom Java path exists and is executable
        if [[ ! -x "$JAVA_CMD" ]]; then
            printf '%b\n' "\x1B[1;31mError: Java executable not found at specified path: $JAVA_CMD\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease provide a valid path to Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation.\x1B[0m"
            exit 1
        fi
        
        # Verify keytool exists and is executable
        if [[ ! -x "$KEYTOOL_CMD" ]]; then
            printf '%b\n' "\x1B[1;31mError: keytool executable not found at specified path: $KEYTOOL_CMD\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease provide a valid path to Java (JRE) installation.\x1B[0m"
            exit 1
        fi
    else
        JAVA_CMD="java"
        KEYTOOL_CMD="keytool"
        
        # Verify that default Java is available
        if ! command -v java &> /dev/null; then
            printf '%b\n' "\x1B[1;31mUnable to locate a Java Runtime. Java (JRE)$REQUIRED_JAVA_MAJOR_VERSION or higher must be installed to run this script.\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease install Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
            printf '%b\n' "\x1B[1;33mInstallation instructions:\x1B[0m"
            printf '%b\n' "  - Install any compatible Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher distribution (e.g., IBM Semeru, Oracle JDK, or OpenJDK)"
            printf '%b\n' "  - Ensure the new Java version is added to your PATH environment variable"
            printf '%b\n' "  - Re-run this script"
            printf '%b\n' "\x1B[1;33mAlternatively, you can specify the path to an existing Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation:\x1B[0m"
            printf '%b\n' " - Re-run this script with the Java (JRE)path parameter, using --java-path <path_to_java>; e.g., $0 -m validate -n $TARGET_PROJECT_NAME --java-path=/custom/java/path"
            exit 1
        fi
        
        # Verify that default keytool is available
        if ! command -v keytool &> /dev/null; then
            printf '%b\n' "\x1B[1;31mUnable to locate keytool. Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher must be installed to run this script.\x1B[0m"
            printf '%b\n' "\x1B[1;31mPlease install Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
            exit 1
        fi
    fi
    
    # Step 2: Validate Java version
    "$JAVA_CMD" -version &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n' "\x1B[1;31mUnable to execute Java. Please check your Java (JRE) installation.\x1B[0m"
        exit 1
    fi
    
    # Extract the full version string
    local CURRENT_JAVA_VERSION=$("$JAVA_CMD" -version 2>&1 | grep -i version | head -n 1 | awk -F '"' '{print $2}')
    
    # Extract just the major version for comparison
    local CURRENT_MAJOR_VERSION=$(echo "$CURRENT_JAVA_VERSION" | awk -F '.' '{print $1}')
    
    # If version starts with "1.", use the second number (e.g., 1.8 -> 8)
    if [[ "$CURRENT_JAVA_VERSION" == 1.* ]]; then
        CURRENT_MAJOR_VERSION=$(echo "$CURRENT_JAVA_VERSION" | awk -F '.' '{print $2}')
    fi
    
    # Check if current version is less than the required version
    if [[ -n "$CURRENT_MAJOR_VERSION" && "$CURRENT_MAJOR_VERSION" -lt "$REQUIRED_JAVA_MAJOR_VERSION" ]]; then
        printf '%b\n' "\x1B[1;31mJava version $CURRENT_JAVA_VERSION is installed but does not meet the minimum requirement (version $REQUIRED_JAVA_MAJOR_VERSION).\x1B[0m"
        printf '%b\n' "\x1B[1;31mPlease upgrade to Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher manually before continuing.\x1B[0m"
        printf '%b\n' "\x1B[1;33mJava (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher upgrade instructions:\x1B[0m"
        printf '%b\n' "  - Install any compatible Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher distribution (e.g., IBM Semeru, Oracle JDK, or OpenJDK)"
        printf '%b\n' "  - Ensure the new Java version is added to your PATH environment variable"
        printf '%b\n' "  - Re-run this script"
        printf '%b\n' "\x1B[1;33mAlternatively, you can specify the path to an existing Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation:\x1B[0m"
        printf '%b\n' " - Re-run this script with the Java (JRE) path parameter, using --java-path <path_to_java>; e.g., $0 -m validate -n $TARGET_PROJECT_NAME --java-path=/custom/java/path"
        exit 1
    fi
    
    info "Using Java version: $CURRENT_JAVA_VERSION located at: $(command -v "$JAVA_CMD")"
    
    # Step 3: Validate keytool
    "$KEYTOOL_CMD" -help &>/dev/null
    if [[ $? -ne 0 ]]; then
        printf '%b\n' "\x1B[1;31mUnable to execute keytool. Keytool is required and should be part of your Java (JRE) installation.\x1B[0m"
        printf '%b\n' "\x1B[1;31mPlease ensure you have a complete Java (JRE) $REQUIRED_JAVA_MAJOR_VERSION or higher installation that includes keytool.\x1B[0m"
        exit 1
    fi
    
    # Step 4: Export the commands so they're available to child scripts
    export JAVA_CMD
    export KEYTOOL_CMD
}

function install_kubectl_cli(){
    if [[ ${machine} = "Linux" ]]; then
        echo -n "Downloading..."
        if [[ $(uname -m) == 'x86_64' ]]; then
            PLATFORM_ARCH='amd64'
        elif [[ $(uname -m) == 'ppc64le' ]]; then
            PLATFORM_ARCH='ppc64le'
        elif [[ $(uname -m) == 's390x' ]]; then
            PLATFORM_ARCH='s390x'
        fi
        curl -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${PLATFORM_ARCH}/kubectl" >/dev/null 2>&1; echo "done."
        echo -n "Installing Kubectl CLI..."; sudo install -o root -g root -m 0755 /tmp/kubectl /usr/local/bin/kubectl >/dev/null; echo "done.";
    elif [[ ${machine} = "Mac" ]]; then
        echo -n "Downloading..."; curl -o /tmp/kubectl "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl" >/dev/null 2>&1; echo "done.";
        echo -n "Installing Kubectl CLI..."; chmod +x /tmp/kubectl >/dev/null; sudo mv /tmp/kubectl /usr/local/bin/kubectl >/dev/null; sudo chown root: /usr/local/bin/kubectl; echo "done.";
    fi
    printf "\n"
}

function install_openssl(){
    if [[ ${machine} = "Linux" ]]; then
        echo -n "Installing OpenSSL..."; sudo yum install openssl-3.2.2 -y >/dev/null; echo "done.";
    elif [[ ${machine} = "Mac" ]]; then
        echo -n "Installing OpenSSL..."; sudo brew install openssl@3.0 >/dev/null; echo 'export PATH="/usr/local/opt/openssl/bin:$PATH"' >> ~/.bash_profile; source ~/.bash_profile; echo "done.";
    fi
    printf "\n"
}

###################
# Echoing utilities
###################
RED_TEXT=`tput setaf 1`
GREEN_TEXT=`tput setaf 2`
YELLOW_TEXT=`tput setaf 3`
CYAN_TEXT=`tput setaf 6`
BLUE_TEXT=`tput setaf 6`
WHITE_TEXT=`tput setaf 7`
RESET_TEXT=`tput sgr0`

printHeaderMessage()
{
 echo ""
  if [  "${#2}" -ge 1 ] ;then
      echo "${2}${1}"
  else
      echo "${WHITE_TEXT}##########################################################${RESET_TEXT}"
      echo "             ${WHITE_TEXT}${1}"
  fi
  echo "##########################################################${RESET_TEXT}"
}

printFooterMessage()
{
  echo "${WHITE_TEXT}##########################################################${RESET_TEXT}"
}

function msg() {

  printf '\n%b\n' "$1"

}



function wait_msg() {

  printf '%s\r' "${1}"

}

function success() {

  msg "\33[32m[✔] ${1}\33[0m"

}

function info() {

  msg "\x1B[33;5m[INFO] \x1B[0m${1}"

}

function INFO() {

  msg "============== ${1} =============="

}


function tips() {

  echo -en "\x1B[1;31m[NEXT ACTIONS]\x1B[0m${1}\n"

}

function warning() {

  msg "\33[33m[✗] ${1}\33[0m"

}



function error() {

  msg "\33[31m[✘] ${1}\33[0m"

}


function msgRed() {

  echo -en "\x1B[1;31m[*] ${1}\x1B[0m\n"

}

function fail() {

  msg "\33[31m[FAILED] ${1}\33[0m"

}



function title() {

  msg "\33[1m ($step) ${1}\33[0m"
  step=$((step + 1))

}



function msgB() {

  echo -e "\x1B[1m${1}\x1B[0m\n"

}

function echo_bold() {
    # Echoes a message in bold characters
    echo_impl "${1}" "m"
}

function echo_red() {
    # Echoes a message in red bold characters
    echo_impl "${1}" ";31m"
}

function echo_impl() {
    # Echoes a message prefixed and suffixed by formatting characters
    local MSG=${1:?Missing message to echo}
    local PREFIX=${2:?Missing message prefix}
    #local SUFFIX=${3:?Missing message suffix}
    echo -e "\x1B[1${PREFIX}${MSG}\x1B[0m"
}

## <https://jsw.ibm.com/browse/DBACLD-159357> - Introduced new function to deal with pressing control keys to continune, need to clear buffer before and after reading user input.
## - - https://jsw.ibm.com/browse/DBACLD-165921 - <Press any key to continue...does not continue when "shift key" is pressed>
function prompt_press_any_key_to_continue() {
    while read -r -t 1; do :; done  # Clear the buffer
    read -rsn1 -p "Press Enter/Return to continue ${1}..."; echo # wait for user input
    read -r -t 1 # Clear any remaining escape seqence
}

############################
# check OCP version
############################
function check_platform_version(){
    currentver=$(oc get nodes | awk 'NR==2{print $5}')
    requiredver="v1.17.1"
    if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
        PLATFORM_VERSION="4.4OrLater"
    else
        # PLATFORM_VERSION="3.11"
        PLATFORM_VERSION="4.4OrLater"
        echo -e "\x1B[1;31mIMPORTANT: Only support OCp4.4 or Later, exit...\n\x1B[0m"
        exit 1
    fi
}

## <https://jsw.ibm.com/browse/DBACLD-161428> - Create a common function to check cluster login for all related scripts.
#############################
# Check Cluster Login
#############################
function check_cluster_login() {
    local oc_login=true
    local kubectl_login=true
    if which oc >/dev/null 2>&1; then
        oc whoami >/dev/null 2>&1
        if [ $? -gt 0 ]; then
            oc_login=false
        fi
    fi
    if which kubectl >/dev/null 2>&1; then
        kubectl auth whoami >/dev/null 2>&1
        if [ $? -gt 0 ]; then
            kubectl_login=false
        fi
    fi
    # if both oc and kubectl are not logged in, exit the script
    if [[ "$oc_login" == "false" && "$kubectl_login" == "false" ]]; then
        error "Cannot find a login context for the cluster. Please login to a cluster before running this script."
        exit 1
    fi
}

set_global_env_vars


function allocate_operator_pvc(){
    # For dynamic storage classname
    printf "\n"
    echo -e "\x1B[1mApplying the persistent volumes for the Cloud Pak operator by using the storage classname: ${STORAGE_CLASS_NAME}...\x1B[0m"

    printf "\n"
    if [[ $DEPLOYMENT_TYPE == "starter" && ($PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "other") ]] ;
    then
        sed "s/<StorageClassName>/$STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_BAK} > ${OPERATOR_PVC_FILE_TMP1}
        sed "s/<Fast_StorageClassName>/$STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_TMP1}  > ${OPERATOR_PVC_FILE_TMP} # &> /dev/null

    elif [[ ($DEPLOYMENT_TYPE == "production" && ($PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "other")) || $PLATFORM_SELECTED == "ROKS" ]];
    then
        sed "s/<StorageClassName>/$SLOW_STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_BAK} > ${OPERATOR_PVC_FILE_TMP1} # &> /dev/null
        sed "s/<Fast_StorageClassName>/$FAST_STORAGE_CLASS_NAME/g" ${OPERATOR_PVC_FILE_TMP1} > ${OPERATOR_PVC_FILE_TMP} # &> /dev/null
    fi

    ${COPY_CMD} -rf ${OPERATOR_PVC_FILE_TMP} ${OPERATOR_PVC_FILE_BAK}
    # Create Operator Persistent Volume.
    CREATE_PVC_CMD="${CLI_CMD} apply -f ${OPERATOR_PVC_FILE_TMP}"
    if $CREATE_PVC_CMD ; then
        echo -e "\x1B[1mDone\x1B[0m"
    else
        echo -e "\x1B[1;31mFailed\x1B[0m"
    fi
   # Check Operator Persistent Volume status every 5 seconds (max 10 minutes) until allocate.
    ATTEMPTS=0
    TIMEOUT=60
    printf "\n"
    echo -e "\x1B[1mWaiting for the persistent volumes to be ready...\x1B[0m"
    until ${CLI_CMD} get pvc | grep cp4a-shared-log-pvc | grep -q -m 1 "Bound" || [ $ATTEMPTS -eq $TIMEOUT ]; do
        ATTEMPTS=$((ATTEMPTS + 1))
        echo -e "......"
        sleep 10
        if [ $ATTEMPTS -eq $TIMEOUT ] ; then
            echo -e "\x1B[1;31mFailed to allocate the persistent volumes!\x1B[0m"
            echo -e "\x1B[1;31mRun the following command to check the claim '${CLI_CMD} describe pvc operator-shared-pvc'\x1B[0m"
            exit 1
        fi
    done
    if [ $ATTEMPTS -lt $TIMEOUT ] ; then
            echo -e "\x1B[1mDone\x1B[0m"
    fi
}

function save_log(){
    local LOG_DIR="$CUR_DIR/$1"
    LOG_FILE="$LOG_DIR/$2_$(date +'%Y%m%d%H%M%S').log"

    if [[ ! -d $LOG_DIR ]]; then
        mkdir -p "$LOG_DIR"
    fi

    # Create a named pipe
    PIPE=$(mktemp -u)
    mkfifo "$PIPE"

    # Tee the output to both the log file and the terminal
    tee "$LOG_FILE" < "$PIPE" &

    # Redirect stdout and stderr to the named pipe
    exec > "$PIPE" 2>&1

    # Remove the named pipe
    rm "$PIPE"

}
#function save_log1() {
#    local LOG_DIR="$CUR_DIR/$1"
#    LOG_FILE="$LOG_DIR/$2_$(date +'%Y%m%d%H%M%S').log"
#
#    if [[ ! -d $LOG_DIR ]]; then
#        mkdir -p "$LOG_DIR"
#    fi
#
#    # Redirect stdout and stderr directly to the log file
#    exec > >(tee -a "$LOG_FILE") 2>&1
#}

function cleanup_log() {
    # Check if the log file already exists
    if [[ -e $LOG_FILE ]]; then
        # Remove ANSI escape sequences from log file
        sed -E 's/\x1B\[[0-9;]+[A-Za-z]//g' "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

function decode_xor_password() {

  local encoded=$1
  local operator_project_name=$2
  local operator_pod_name=$3
  local was_home="/opt/ibm/securityUtility"
  local class_path="${was_home}/plugins/com.ibm.ws.runtime.jar:${was_home}/lib/bootstrap.jar:${was_home}/plugins/com.ibm.ws.emf.jar:${was_home}/lib/ffdc.jar:${was_home}/plugins/org.eclipse.emf.ecore.jar:${was_home}/plugins/org.eclipse.emf.common.jar:${was_home}/glassfish-corba-omgapi-4.2.4.jar"
  if [[ $encoded != "" ]] && [[ "$encoded" == *"{xor}"* ]]; then
    local decoded=$( ${CLI_CMD} exec -i -n $operator_project_name $operator_pod_name -- bash -c "java -cp \"${class_path}\" com.ibm.ws.security.util.PasswordDecoder \"$encoded\"")
    echo "$decoded" | grep -i 'decoded password == ' | awk '{print $8}' | sed -e 's/^"//' -e 's/"$//'
  else
    echo $encoded
  fi
}

# Function to encode the certificate contents to a base64 string
encode_crt_file_to_base64() {
    local crt_file="$1"
    if [[ ! -f "$crt_file" ]]; then
        echo "File not found: $crt_file"
        return 1
    fi

    # Read and base64 encode the .crt file
    local machine_lower=$(echo "${machine}" | tr '[:upper:]' '[:lower:]')
    if [[ "$machine_lower" == "linux" ]]; then
        base64_encoded_content=$(cat "$crt_file" | base64 -w 0)
    else
        base64_encoded_content=$(cat "$crt_file" | base64 )
    fi

    echo "$base64_encoded_content"
}

function check_single_quotes_password() {
    local temp_pwd=$1
    local variable_name=$2
    temp_pwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$temp_pwd")
    variable_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$variable_name")
    if [[ $temp_pwd == *"'"* ]]; then
        fail "Found single quotes (') in \"$variable_name\". Exiting..."
        warning "DO NOT use special character single quotes (') in the password."
        exit 1
    fi
}


function check_single_quotes_password() {
    local temp_pwd=$1
    local variable_name=$2
    temp_pwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$temp_pwd")
    variable_name=$(sed -e 's/^"//' -e 's/"$//' <<<"$variable_name")
    if [[ $temp_pwd == *"'"* ]]; then
        fail "Found single quotes (') in \"$variable_name\". Exiting..."
        warning "DO NOT use special character single quotes (') in the password."
        exit 1
    fi
}

# For https://jsw.ibm.com/browse/DBACLD-157020
# Function that base64 encodes the password in the generated secret template and moves it to the data section of the template
# We cant directy use the base64 value in the stringData field as when the secret template is applied the cluster automatically base64 encodes it again and this will result in a wrong password being used by the operator code
# This was code that was repeating in numerous places so it was made a common function
# password_value is the value to base64 and update in the secret template
# secret template field is the property field in the secret template who's value will be the value in password_value
# secret_file is the name of the secret template file. (this file is already created prior to this function call)
# new_secret_template_field is the name of a new secret field to be added. This is only passed for the fncm secret where we add password fields to the existing template
# for new_secret_template_field to be used, secret template field must be osDBpassword as the current logic will append the new field after osDBpassword .
# Other than for fncm secret the new_secret_template_field field is empty and not needed
function update_secret_template_passwords(){
    local password_value=$1
    local secret_template_field=$2
    local secret_file=$3
    local new_secret_template_field=$4
    # Checking if the password in the property file is base64 encoded and if so we just remove the prefix.
    # IF the password is plaintext we base64 encode it

    if [[ "${password_value:0:8}" == "{Base64}"  ]]; then
        temp_val=$(echo "$password_value" | sed -e "s/^{Base64}//" )
    else
        local machine_lower=$(echo "${machine}" | tr '[:upper:]' '[:lower:]')
        if [[ "$machine_lower" == "linux" ]]; then
            temp_val=$(echo -n "$password_value" | base64 -w 0 )
        else
            temp_val=$(echo "$password_value" | base64 )
        fi
    fi
    if ${YQ_CMD} r "$secret_file" "stringData.$secret_template_field" >/dev/null 2>&1; then
        # Remove the field from stringData and add it to data with the new encoded value
        # Use yq to delete and add the field in a more compatible way without eval
        if [[ "$secret_template_field" != "osDBPassword" ]]; then
            ${YQ_CMD} w -i "$secret_file" "data.$secret_template_field" "$temp_val"
            ${YQ_CMD} d -i "$secret_file" "stringData.$secret_template_field"
        else
            ${YQ_CMD} w -i "$secret_file" "data.$new_secret_template_field" "$temp_val"
        fi
    else
        echo "Field $secret_template_field not found in stringData."
    fi
}



# function to create a userpassword dictionary string to pass to the ldap validation jar
# Sample format - username:testuser,password:testpassword;username:testuser2,password:;
# All values are base64 encoded so that all special characters are parsed correctly
function create_user_password_dictionary_string(){
    usernames=("${!1}")
    passwords=("${!2}")
    output=""
    # Loop through the arrays
    for i in "${!usernames[@]}"; do
        # Username is already encoded in the add_to_list function
        username="${usernames[$i]}"
        password="${passwords[$i]}"


        # Check if the password is empty or not
        if [ -n "$password" ]; then
            # For https://jsw.ibm.com/browse/DBACLD-157019 where we want to make sure we consider if passwords are encoded
            # If the value provided is base64 already we take the base64 value else we convert it to base64
            # Check if the password starts with {Base64}
            if [[ $password == "{Base64}"* ]]; then
                encoded_password="${password#'{Base64}'}"
            else
                encoded_password=$(printf "$password" | base64)
            fi
        else
            encoded_password=""
        fi

        # Append to the output string
        output="${output}username:${username},password:${encoded_password};"
    done

    # Print the final output
    echo "$output"
}

# certain fields have the full bind dn , and i am extracting it to just get the username
function extract_user_from_ldap_bind() {
  local ldap_bind_dn="$1"
  local display_name_attr="$2"  # LDAP_USER_DISPLAY_NAME_ATTR (e.g., cn or CN)

  # Use sed to dynamically extract the value based on the attribute name (case-insensitive)
  user=$(echo "$ldap_bind_dn" | sed -n "s/^${display_name_attr}=\([^,]*\).*/\1/ip")

  echo "$user"
}

# function that processes all properties from the property files that are associated with an LDAP value
# The function returns values that are passed in the appropriate format to the LDAPTest.jar for additional validation
function ldap_validation_parameter_generator(){
    ldap_group_basedn="$(prop_ldap_property_file LDAP_GROUP_BASE_DN)"
    ldap_user_filter="$(prop_ldap_property_file LC_USER_FILTER)"
    ldap_user_attribute="$(prop_ldap_property_file LDAP_USER_DISPLAY_NAME_ATTR)"
    ldap_group_filter="$(prop_ldap_property_file LC_GROUP_FILTER)"
    if [ -f "${USER_PROFILE_PROPERTY_FILE}" ]; then
        ldap_admins_group_name="$(prop_user_profile_property_file CONTENT_INITIALIZATION.LDAP_ADMINS_GROUPS_NAME)"
        cpe_obj_store_group_name="$(prop_user_profile_property_file CONTENT_INITIALIZATION.CPE_OBJ_STORE_ADMIN_USER_GROUPS)"
        adp_service_user_name="$(extract_user_from_ldap_bind "$(prop_user_profile_property_file ADP.SERVICE_USER_NAME)" "$ldap_user_attribute")"
        adp_service_user_name_base="$(extract_user_from_ldap_bind "$(prop_user_profile_property_file ADP.SERVICE_USER_NAME_BASE)" "$ldap_user_attribute")"
        adp_service_user_name_ca="$(extract_user_from_ldap_bind "$(prop_user_profile_property_file ADP.SERVICE_USER_NAME_CA)" "$ldap_user_attribute")"
        adp_env_owner_user_name="$(extract_user_from_ldap_bind "$(prop_user_profile_property_file ADP.ENV_OWNER_USER_NAME)" "$ldap_user_attribute")"
    else
        ldap_admins_group_name=""
        cpe_obj_store_group_name=""
        adp_service_user_name=""
        adp_service_user_name_ca=""
        adp_service_user_name_base=""
        adp_env_owner_user_name=""
    fi
    ldap_user_list=()
    ldap_password_list=()
    ldap_group_list=()
    ldap_user_password_list=()
    # Function to add a string if it's not in the list
    # if the value is null that means that the property is not in the property file and the functions skips that value
    add_to_list() {
        local value="$1"
        local found=0
        if [ "$value" ]; then
            # Check if the user starts with {Base64}
            # For https://jsw.ibm.com/browse/DBACLD-157019 where we want to make sure we consider if passwords are encoded
            # If the value provided is base64 already we take the base64 value else we convert it to base64
            if [[ $value == "{Base64}"* ]]; then
                encoded_value="${value#'{Base64}'}"
            else
                encoded_value=$(printf "$value" | base64)
            fi
            # Loop through the array to check if the value already exists
            for user in "${ldap_user_list[@]}"; do
                if [[ "$user" == "$encoded_value" ]]; then
                found=1
                break
                fi
            done

            # If the value was not found, add it to the list
            if [[ $found -eq 0 ]]; then
                ldap_user_list+=("$encoded_value")
                return 0  # Indicates the value was added
            fi
        fi
        return 1
    }
    # If a user processed is not a duplicate found, then for values that we have a password field we append it, else we append an empty string
    if [ -f "${USER_PROFILE_PROPERTY_FILE}" ]; then
        if add_to_list "$(prop_user_profile_property_file CONTENT.APPLOGIN_USER)"; then
            ldap_password_list+=("$(prop_user_profile_property_file CONTENT.APPLOGIN_PASSWORD)")
        fi
        if add_to_list "$(prop_user_profile_property_file BAN.APPLOGIN_USER)"; then
            ldap_password_list+=("$(prop_user_profile_property_file BAN.APPLOGIN_PASSWORD)")
        fi
        if add_to_list "$(prop_user_profile_property_file CONTENT_INITIALIZATION.LDAP_ADMIN_USER_NAME)"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$(prop_user_profile_property_file APP_ENGINE.ADMIN_USER)"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$(prop_user_profile_property_file APP_PLAYBACK.ADMIN_USER)"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$(prop_user_profile_property_file BASTUDIO.ADMIN_USER)"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$(prop_user_profile_property_file BAW_RUNTIME.ADMIN_USER)"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$adp_service_user_name"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$adp_service_user_name_ca"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$adp_service_user_name_base"; then
            ldap_password_list+=("")
        fi
        if add_to_list "$adp_env_owner_user_name"; then
            ldap_password_list+=("")
        fi
    fi
    # collecting groups for the ldap group list
    if [[ -n "$ldap_admins_group_name" ]]; then
        # Convert the comma-separated values to an array
        IFS=',' read -r -a values_array <<< "$ldap_admins_group_name"
        for value in "${values_array[@]}"; do
            ldap_group_list+=("$value")
        done
    fi
    if [[ -n "$cpe_obj_store_group_name" ]]; then
        # Convert the comma-separated values to an array
        IFS=',' read -r -a values_array <<< "$cpe_obj_store_group_name"
        for value in "${values_array[@]}"; do
            ldap_group_list+=("$value")
        done
    fi

    # Convert the space-separated list to a comma-separated string with unique values
    final_ldap_group_list=$(echo "${ldap_group_list[@]}" | tr ' ' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')

    # creating the user password dictionary string
    ldap_user_password_list=$(create_user_password_dictionary_string ldap_user_list[@] ldap_password_list[@])

    ldap_details=("$ldap_group_basedn" "$ldap_user_filter" "$ldap_group_filter" "$ldap_user_password_list" "$final_ldap_group_list")
}

# This function is used to display a latency warning based on the time taken for a DB/LDAP connection
# Takes in 2 parameters
# 1. time_taken which is used to display the latency and make comparisons using bc -l which allows for float point based comparisons
# connection_type which is used to display if the connection is for a DB or LDAP
# DBACLD-159742
function display_latency_warning() {
    local time_taken=$1
    local connection_type=$2
    echo "Latency: $time_taken ms"
    # Check if elapsed time is greater than 10 ms using awk. [[ ]] not used since it doesnt do float point comparisons correctly
    # If tt is between 10 and 30, it exits with 0 (success)
    if awk -v tt="$time_taken" 'BEGIN { exit !(tt < 10) }'; then
        echo "The latency is less than 10ms, which is acceptable performance for a simple $connection_type operation."
    elif awk -v tt="$time_taken" 'BEGIN { exit !(tt >= 10 && tt <= 30) }'; then
        echo "The latency is between 10ms and 30ms, which exceeds acceptable performance of 10 ms for a simple $connection_type operation, but the service is still accessible."
    else
        echo "The latency exceeds 30ms for a simple $connection_type operation, which indicates potential for failures."
    fi
}
# This function checks if its a valid version during the course of upgrade
# It looks at the current csv version and compares it to the minimum support upgraded versions stored in MINIMUM_SUPPORTED_UPGRADE_VERSIONS.
# The version the operator should be in that channel and not equal to the CSV version of BAW Operator that the scripts are for.
function check_valid_baw_operator_version() {
    local current_operator_version=$1
    valid_baw_operator_version=false
    for version in "${MINIMUM_SUPPORTED_UPGRADE_VERSIONS[@]}"; do
        if [[ "$current_operator_version" == "$version"* && "$current_operator_version" != "${CP4BA_CSV_VERSION#v}" ]]; then
            valid_baw_operator_version=true
            break
        fi
    done
}


# Function used to check if a specific value is present in a list of values
function containsElement(){
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}


# Function to clean up old files that are not required
# Used in cp4a-prerequisites.sh script
function clean_up_temp_file(){
    local files=()
    files=($(find $PREREQUISITES_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done

    # deletes all temporary files i.e files ending with ""
    files=($(find $TEMP_FOLDER -name '*.*""'))
    for item in ${files[*]}
    do
        rm -rf $item >/dev/null 2>&1
    done
}

# Function that loads certain properties from the temp property file
# Used in baw-prerequisites.sh script (generate and validate mode) and baw-deployment.sh for fresh install

function load_properties_from_temp_file(){
    if [[ ! -f $TEMPORARY_PROPERTY_FILE || ! -f $USER_PROFILE_PROPERTY_FILE ]]; then
        fail "Not Found existing property file under \"$PROPERTY_FILE_FOLDER\" .Run \"baw-prerequisites.sh\" in property mode to complete the generation of property files"
        exit 1
    fi

    # load the flag that stores whether ldap was selected or not
    selected_ldap_flag="$(prop_tmp_property_file SELECTED_LDAP_FLAG)"

    # load ldap type
    LDAP_TYPE="$(prop_tmp_property_file LDAP_TYPE)"

    # load external postgres DB for IM Flag
    EXTERNAL_POSTGRESDB_FOR_IM_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_IM_FLAG=$(echo $EXTERNAL_POSTGRESDB_FOR_IM_FLAG | tr '[:upper:]' '[:lower:]')

    # Load external postgres DB for Zen Flag
    EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG=$(echo $EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG | tr '[:upper:]' '[:lower:]')

    # Load external postgres DB for BTS Flag
    EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
    EXTERNAL_POSTGRESDB_FOR_BTS_FLAG=$(echo $EXTERNAL_POSTGRESDB_FOR_BTS_FLAG | tr '[:upper:]' '[:lower:]')


    # load pattern into pattern_cr_arr
    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
    pattern_name_list="$(prop_tmp_property_file PATTERN_NAME_LIST)"
    optional_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
    optional_component_name_list="$(prop_tmp_property_file OPTION_COMPONENT_NAME_LIST)"
    foundation_list="$(prop_tmp_property_file FOUNDATION_LIST)"

    OIFS=$IFS
    IFS=',' read -ra pattern_cr_arr <<< "$pattern_list"
    IFS=',' read -ra PATTERNS_CR_SELECTED <<< "$pattern_list"

    IFS=',' read -ra pattern_arr <<< "$pattern_name_list"
    IFS=',' read -ra optional_component_cr_arr <<< "$optional_component_list"
    IFS=',' read -ra optional_component_arr <<< "$optional_component_name_list"
    IFS=',' read -ra foundation_component_arr <<< "$foundation_list"
    IFS=$OIFS

    # load fips enabled flag
    # FIPS_ENABLED="false"
    # DBACLD-202948: remove -Dsemeru.fips option from all java commands for connection verification
    local java_opts=""

    # load profile size  flag
    PROFILE_TYPE=$(prop_tmp_property_file PROFILE_SIZE_FLAG)


}

# This function is to generate a truststore password for DB and LDAP verification
# DBACLD-167057
function generate_truststore_password() {
    local pwd_length="${1:-8}"
    local pwd_charset="${2:-A-Za-z0-9}"
    local machine_lower=$(echo "${machine}" | tr '[:upper:]' '[:lower:]')
    if [[ "$machine_lower" == "linux" ]]; then
        < /dev/urandom tr -dc "$pwd_charset" | head -c "$pwd_length"
    else
        < /dev/urandom tr -dc "$pwd_charset" | cut -c1-"$pwd_length"
    fi
    echo
}

# Function to update repository and tag sections in the CR with the staging repository and current sprint tag
# This function is used by the baw-deployment.sh only in
# 1.For OTHER type of platform
# 2.DEV mode
function update_repository_and_tags(){
    component_path=$1
    if [[ "$component_path" == *"keytool_init_container"* ]]; then
        repository_path="$component_path.repository"
        tag_path="$component_path.tag"
    else
        repository_path="$component_path.image.repository"
        tag_path="$component_path.image.tag"
    fi
    repo_value=$(${YQ_CMD} r ${BAW_S_FC_CR} $repository_path || echo "")
    updated_value=$(echo "$repo_value" | sed 's|cp.icr.io/cp|cp.stg.icr.io/cp|')
    ${YQ_CMD} w -i "$BAW_PATTERN_FILE_TMP" "$repository_path" "\"$updated_value\""
    ${YQ_CMD} w -i ${BAW_PATTERN_FILE_TMP} "$tag_path" "\"$CURRENT_SPRINT_TAG\""


}


# Function to get the domain name
# Used only for OTHER type of platform
# 1.To cupdate the property file as part of the property mode of baw-prerequisites.sh
function get_domain_name() {
    local namespace=$1
    local configmap_name=$2
    domain_name=""
    # Check if the ConfigMap exists
    if ${CLI_CMD} get configmap "$configmap_name" -n "$namespace" &>/dev/null; then
        # Retrieve the parameter from the data section
        domain_name=$(kubectl get configmap "$configmap_name" -n "$namespace" -o jsonpath="{.data.domain_name}" 2>/dev/null)

        if [ -n "$domain_name" ]; then
            success "\033[1;32mConfigMap '$configmap_name' found and Domain Name was retrieved sucessfully\033[0m"
        else
            error "\033[1;31mConfigMap '$configmap_name' found, but key 'domain_name' is missing.\033[0m"
            info  "\033[1;33m The ConfigMap '$configmap_name' is created during the execution of ${CUR_DIR}/baw-clusteradmin-setup.sh script\033[0m"

        fi
    else
        # Prompt the user to create the ConfigMap
        error  "\033[1;31mError: ConfigMap '$configmap_name' not found in namespace '$namespace'.\033[0m"
        info  "\033[1;33m The ConfigMap '$configmap_name' is created during the execution of ${CUR_DIR}/baw-clusteradmin-setup.sh script\033[0m"
    fi
}

#This function is used to validate the docker and podman CLI
# Used by both baw-clusteradmin-setup script and baw-deployment.sh so its being moved here
function validate_docker_podman_cli() {
    if [[ "$machine" == "Mac" ]]; then
        which podman &>/dev/null
        [[ $? -ne 0 ]] && PODMAN_FOUND="No"
        which docker &>/dev/null
        [[ $? -ne 0 ]] && DOCKER_FOUND="No"
        if [[ $DOCKER_FOUND == "No" && $PODMAN_FOUND == "No" ]]; then
            echo -e "\033[1;31mUnable to locate docker or podman. Install either of them first.\033[0m"
            exit 1
        fi
    elif [[ $OCP_VERSION =~ ^4\. || $OCP_VERSION == "4.4OrLater" ]]; then
        which podman &>/dev/null
        [[ $? -ne 0 ]] && {
            echo -e "\033[1;31mUnable to locate podman. Install it first.\033[0m"
            exit 1
        }
    else
        which podman &>/dev/null
        [[ $? -ne 0 ]] && PODMAN_FOUND="No"
        which docker &>/dev/null
        [[ $? -ne 0 ]] && DOCKER_FOUND="No"
        if [[ $DOCKER_FOUND == "No" && $PODMAN_FOUND == "No" ]]; then
            echo -e "\033[1;31mUnable to locate docker or podman. Install either of them first.\033[0m"
            exit 1
        fi
    fi
}


# Function that validates if a specific CLI is present based on the platform type
function validate_kube_oc_cli(){
    if  [[ $PLATFORM_SELECTED == "OCP" || $PLATFORM_SELECTED == "ROKS" ]]; then
        which oc &>/dev/null
        [[ $? -ne 0 ]] && \
        echo -e  "\x1B[1;31mUnable to locate the OpenShift CLI. You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
    if  [[ $PLATFORM_SELECTED == "other" ]]; then
        which kubectl &>/dev/null
        [[ $? -ne 0 ]] && \
        echo -e  "\x1B[1;31mUnable to locate the Kubernetes CLI, You must install it to run this script.\x1B[0m" && \
        exit 1
    fi
}

# Function that takes in namespace value passed in the -n parameter and checks if it is a valid namespace
# Function used in baw-deployment.sh
function validate_namespace() {

    printf "\n"
    echo -e "\x1B[1mValidating the Namespace used to deploy IBM Business Automation Insights standalone...\x1B[0m"
    printf "\n"
    #read -p "Enter the name for an existing project (namespace): " TARGET_PROJECT_NAME
    if [[ "$TARGET_PROJECT_NAME" == openshift* ]]; then
        error  "\x1B[1;31mEnter a valid namespace name, namespace name should not be 'openshift' or start with 'openshift' \x1B[0m"
        exit
    elif [[ "$TARGET_PROJECT_NAME" == kube* ]]; then
        error "\x1B[1;31mEnter a valid namespace name, namespace name should not be 'kube' or start with 'kube' \x1B[0m"
        exit
    else
        check_cluster_login
        isProjExists=`${CLI_CMD} get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1

        if [ "$isProjExists" -ne 2 ] ; then
            error "\x1B[1;31mInvalid project name "$TARGET_PROJECT_NAME" , enter an existing project name ...\x1B[0m"
            exit
        else
            success "\x1B[1mUsing project ${TARGET_PROJECT_NAME}...\x1B[0m"
        fi
    fi

}

# Function to check for OCP version
function check_ocp_version(){
    if [[ ${PLATFORM_SELECTED} == "OCP" || ${PLATFORM_SELECTED} == "ROKS" ]];then
        temp_ver=`${CLI_CMD} version | grep v[1-9]\.[1-9][0-9] | tail -n1`
        if [[ $temp_ver == *"Kubernetes Version"* ]]; then
            currentver="${temp_ver:20:7}"
        else
            currentver="${temp_ver:11:7}"
        fi
        requiredver="v1.17.1"
        if [ "$(printf '%s\n' "$requiredver" "$currentver" | sort -V | head -n1)" = "$requiredver" ]; then
            OCP_VERSION="4.4OrLater"
        else
            # OCP_VERSION="3.11"
            OCP_VERSION="4.4OrLater"
            echo -e "\x1B[1;31mIMPORTANT: The apiextensions.k8s.io/v1beta API has been deprecated from k8s 1.16+, OCP 4.3 is using k8s 1.16.x. recommend you to upgrade your OCP to version 4.4 or later\n\x1B[0m"
            prompt_press_any_key_to_continue
            # exit 0
        fi
    fi
}

function prompt_to_continue() {
    while true; do
        printf "\x1B[1mPlease confirm that you are ready to continue.  Enter Yes to continue or No to exit (Yes/No, default: No): \x1B[0m"
        read -rp "" ans
        case "$ans" in
        "y"|"Y"|"yes"|"Yes"|"YES"|"")
            break
            ;;
        "n"|"N"|"no"|"No"|"NO")
            exit
            ;;
        *)
            echo -e "Answer must be \"Yes\" or \"No\"\n"
            ;;
        esac
    done
}

# Function that retrieves the networktype and network cidr range
# This function is used in the cp4a-clusteradmin-setup.sh for fresh install ( mode is "fresh_install")
# This function is used in the cp4a-deployment script in upgradeDeployment mode for upgrade ( mode is "upgrade")
# https://jsw.ibm.com/browse/DBACLD-173602
function retrieve_network_details(){
    local mode=$1
    local namespace=$2
    network_type=""
    network_cidr=""
    if ! network_configuration_output=$(${CLI_CMD} get network cluster -o yaml 2>/dev/null) ; then
        printf "${YELLOW_TEXT}[IMPORTANT]${RESET_TEXT}"
        printf "\n"
        printf "The user does not have sufficient permissions to retrieve cluster network details. As a result, the \"ibm-cp4a-common-configmap\" ConfigMap must be manually updated with the correct network CIDR and network type. This step is required before applying the custom resource file."
        printf "\n"
        printf "${YELLOW_TEXT}[NOTE]:${RESET_TEXT} In OCP or ROKS, this information can be obtained by querying the Network resource \"oc get network cluster -o yaml\" or by retrieving the details from the OCP Console."
        printf "Then update the 'ibm-cp4ba-common-config' configMap in the namespace where BAW Standalone is deployed with the following command: \" oc patch configmap ibm-cp4ba-common-config -n <BAW-namespace> --type merge -p \"{ \"data\": { \"network_cidr\": \"<cidr range from command>\", \"network_type\": \"<networkType from command>\" } } \" where the values being patched are the CIDR range and networkType that you obtained from the command above respectively."
        printf "\n"
    else
        network_cidr=$(${YQ_CMD} r - <<< "$network_configuration_output" 'spec.clusterNetwork[0].cidr')
        network_type=$(${YQ_CMD} r - <<< "$network_configuration_output" 'spec.networkType')
    fi

    if [[ "$mode" == "upgrade" && ( ! -z $network_cidr ) && ( ! -z $network_type )  ]]; then
        printf "\n"
        info " Patching the ibm-cp4ba-common-config configMap with the Cluster Network details... "
        printf "\n"
        if ${CLI_CMD} get configMap ibm-cp4ba-common-config -n $namespace >/dev/null 2>&1; then
            ${CLI_CMD} patch configmap ibm-cp4ba-common-config -n $namespace --type merge -p "{ \"data\": { \"network_cidr\": \"${network_cidr}\", \"network_type\": \"${network_type}\" } }"
        fi
    fi


}

#DBACLD-194974: Version to remove EDB and skip Starter deployment option for CP4BA by checking the version $BAW_PATCH_VERSION and $CP4BA_RELEASE_BASE
#Update the version and patch here to skip EDB and Starter deployment option.  
function skip_edb() {
    local _existing_cp4ba_version=${CP4BA_RELEASE_BASE}_${BAW_PATCH_VERSION}
    local _version_to_skip="$VERSION_TO_SKIP_EDB"

    if [[ "$_existing_cp4ba_version" == "$_version_to_skip" ]]; then
        return 0  # Skip EDB
    else
        return 1  # Do not skip EDB
    fi
}

#DBACLD-222678: Function to check whether EDB is detected
function is_edb_detected(){
    local ns=$1
    is_edb=$($CLI_CMD get cluster.postgresql.k8s.enterprisedb.io -n $ns --no-headers --ignore-not-found 2>/dev/null | awk {'print $1'} || echo "")
    
    # Initialize the detection variable to false
    CP4BA_EDB_INSTANCE_DETECTED="false"
    
    if [[ ! -z $is_edb ]]; then
        info "The following EDB instances are found: \n$is_edb"
        
        # Check if the specific postgres-cp4ba instance is in the returned list
        if echo "$is_edb" | grep -q -w "${EDB_INSTANCE_CP4BA_NAME}"; then
            CP4BA_EDB_INSTANCE_DETECTED="true"
        fi
        
        return 0
    else
        return 1
    fi
}



#############################################################
##### Functions to install IBM Usage Metering Operator ######
#############################################################


# Function to apply Subscription for the UMS Operator
# https://jsw.ibm.com/browse/DBACLD-216413
# https://jsw.ibm.com/browse/DBACLD-225399
function apply_subscription() {
    local namespace="$1"
    local channel="$2"
    local catalog_name="$3"
    local catalog_namespace="$4"
    UMS_OLM_SUBSCRIPTION_TMP=${TEMP_FOLDER}/.ums_subscription.yaml

    info "Creating IBM Usage Metering Subscription in namespace: $namespace"

    if [ ! -f "$UMS_OLM_SUBSCRIPTION" ]; then
        error "Template file $UMS_OLM_SUBSCRIPTION not found"
        return 1
    fi
    
    # Copy template to temp file
    cp "$UMS_OLM_SUBSCRIPTION" "$UMS_OLM_SUBSCRIPTION_TMP"
    
    # Replace REPLACE_NAMESPACE with actual namespace using sed
    sed -i "s/REPLACE_NAMESPACE/$namespace/g" "$UMS_OLM_SUBSCRIPTION_TMP"
    
    # Replace REPLACE_CHANNEL with actual channel using sed
    sed -i "s/REPLACE_CHANNEL/$channel/g" "$UMS_OLM_SUBSCRIPTION_TMP"
    
    # Set sourceNamespace using yq v3
    "${YQ_CMD}" write -i "$UMS_OLM_SUBSCRIPTION_TMP" "spec.sourceNamespace" "$catalog_namespace"
    
    # Set source (catalog name) using yq v3
    "${YQ_CMD}" write -i "$UMS_OLM_SUBSCRIPTION_TMP" "spec.source" "$catalog_name"

    ${CLI_CMD} apply -f ${UMS_OLM_SUBSCRIPTION_TMP}
    if [ $? -eq 0 ]
        then
        success "UMS Operator Subscription Created!"
    else
        error "UMS Operator Subscription creation failed"
        exit 1
    fi
}


# Function to create the ibm usage metering connection point secret
# It uses the Entitlement key to generate a secret named baw-ums-secret
# In the future the entitlement key secret already created would be used
# https://jsw.ibm.com/browse/DBACLD-216413
# https://jsw.ibm.com/browse/DBACLD-225399
function create_connection_point_secret(){
    local secret_name=$1
    local services_namespace=$2
    local entitlement_key=$3
    # Use a variable to detect if the connection point creation passed
    connection_point_secret_creation="false"

    if ${CLI_CMD} get secret "$secret_name" -n "${services_namespace}" >/dev/null 2>&1; then
        success "Secret $secret_name already exists in namespace $services_namespace, skipping recreation."
        connection_point_secret_creation="true"
        return 0
    fi
    
    info "Creating the IBM usage metering secret using the Entitlement key which will be used for configuring the connection point in the project $services_namespace..."
    echo
    
    if ${CLI_CMD} create secret generic "$secret_name" \
        --from-literal="token=$entitlement_key" \
        -n "$services_namespace"; then
        success "Secret $secret_name has been successfully created"
        connection_point_secret_creation="true"
    else
        fail "Failed to create secret $secret_name."
    fi
        
}
# Function to patch UMS subscription with new channel
function patch_ums_subscription() {
    local operator_namespace=$1
    local channel=$2
    local catalog_namespace=$3
    
    # Find subscription with "ibm-usage-metering" in the name
    local subscription_name=$(${CLI_CMD} get subscription -n "$operator_namespace" --no-headers 2>/dev/null | grep "ibm-usage-metering" | awk '{print $1}' | head -n 1)
    
    if [ -z "$subscription_name" ]; then
        error "No subscription containing 'ibm-usage-metering' found in namespace '$operator_namespace'"
        return 1
    fi
    
    info "Found subscription: '$subscription_name'"
    info "Patching subscription with channel '$channel'..."
    ${CLI_CMD} patch subscription "$subscription_name" -n "$operator_namespace" \
        --type='json' \
        -p="[{'op': 'replace', 'path': '/spec/channel', 'value': '$channel'}]"
    
    if [ $? -eq 0 ]; then
        success "Subscription '$subscription_name' patched successfully with channel '$channel'"
    else
        error "Failed to patch subscription '$subscription_name'"
        return 1
    fi
    
    info "Patching subscription with sourcenamespace '$catalog_namespace'..."
    ${CLI_CMD} patch subscription "$subscription_name" -n "$operator_namespace" \
        --type='json' \
        -p="[{'op': 'replace', 'path': '/spec/sourceNamespace', 'value': '$catalog_namespace'}]"
    
    if [ $? -eq 0 ]; then
        success "Subscription '$subscription_name' patched successfully with sourcenamespace '$catalog_namespace'"
        return 0
    else
        error "Failed to patch subscription '$subscription_name'"
        return 1
    fi
}

# Function to extract entitlement key password from a dockerconfigjson secret.
#
# Lookup order:
#   1. Secret passed in as $1 in the namespace passed in as $2
#   2. pull-secret in openshift-config namespace
#
# Registry lookup order inside the dockerconfigjson:
#   1. cp.icr.io
#   2. cp.stg.icr.io
#
# The function reads the registry "auth" field, decodes it from base64,
# and extracts the password/token portion from the "username:password" value.
#
# Arguments:
#   $1 - secret name to check first, typically ibm-entitlement-key
#   $2 - namespace where the secret should exist
#
# Output:
#   Sets global variable: entitlement_key
#
# Return:
#   0 on success
#   1 if the entitlement key could not be extracted
function get_entitlement_key_from_secret() {
    local secret_name="$1"
    local namespace="$2"
    local dockerconfigjson=""
    local auth_value=""
    local decoded_auth=""
    local source_secret_name=""
    local source_namespace=""

    info "Extracting entitlement key from secret '$secret_name' in namespace '$namespace'..."

    # Step 1: Check whether the requested secret exists in the provided namespace.
    # If it exists, use it as the primary source.
    if ${CLI_CMD} get secret "$secret_name" -n "$namespace" &>/dev/null; then
        source_secret_name="$secret_name"
        source_namespace="$namespace"
        info "Found secret '$source_secret_name' in namespace '$source_namespace'"
    else
        warning "Secret '$secret_name' not found in namespace '$namespace'. Checking 'pull-secret' in namespace 'openshift-config'..."

        # Step 2: If the original secret is not present, fall back to the cluster pull-secret.
        if ${CLI_CMD} get secret pull-secret -n openshift-config &>/dev/null; then
            source_secret_name="pull-secret"
            source_namespace="openshift-config"
            info "Found fallback secret '$source_secret_name' in namespace '$source_namespace'"
        else
            error "Neither secret '$secret_name' in namespace '$namespace' nor secret 'pull-secret' in namespace 'openshift-config' was found. Failed to extract the entitlement-key from the cluster."
            return 1
        fi
    fi

    # Step 3: Extract and decode the dockerconfigjson payload from the selected secret.
    dockerconfigjson=$(${CLI_CMD} get secret "$source_secret_name" -n "$source_namespace" -o yaml | \
        "${YQ_CMD}" read - 'data[.dockerconfigjson]' | \
        ${BASE64_DECODE})

    if [[ -z "$dockerconfigjson" ]] || [[ "$dockerconfigjson" == "null" ]]; then
        error "Failed to extract the entitlement-key from secret '$source_secret_name' in namespace '$source_namespace'."
        return 1
    fi

    # Step 4: Try cp.icr.io first by reading the auth field.
    auth_value=$(printf '%s' "$dockerconfigjson" | "${YQ_CMD}" read - 'auths."cp.icr.io".auth')

    # Step 5: If cp.icr.io is not present, try cp.stg.icr.io.
    if [[ -z "$auth_value" ]] || [[ "$auth_value" == "null" ]]; then
        auth_value=$(printf '%s' "$dockerconfigjson" | "${YQ_CMD}" read - 'auths."cp.stg.icr.io".auth')
    fi

    # Step 6: If both registry auth entries are missing, handle it the same as empty password.
    if [[ -z "$auth_value" ]] || [[ "$auth_value" == "null" ]]; then
        error "Failed to extract password from dockerconfigjson (tried cp.icr.io and cp.stg.icr.io)"
        return 1
    fi

    # Step 7: Decode the auth entry. It should be in the form username:password
    decoded_auth=$(printf '%s' "$auth_value" | ${BASE64_DECODE})

    if [[ -z "$decoded_auth" ]] || [[ "$decoded_auth" == "null" ]]; then
        error "Failed to decode auth field from dockerconfigjson"
        return 1
    fi

    # Step 8: Extract the password/token portion after the first colon.
    entitlement_key=$(printf '%s' "$decoded_auth" | sed 's/^[^:]*://')

    # Step 9: If the extracted password is empty, handle it as failure.
    if [[ -z "$entitlement_key" ]] || [[ "$entitlement_key" == "$decoded_auth" ]]; then
        error "Failed to extract password from decoded auth field"
        return 1
    fi

    return 0
}

# Function to fix BAW database client TLS secrets (operator-generated)
function fix_baw_db_client_tls_secrets() {
    local namespace="$1"
    
    info "Checking for BAW database client TLS secrets that need to be fixed in namespace: $namespace"
    echo
    
    # Find all secrets that match the pattern for BAW DB client TLS
    # Pattern: *-baw-db-client-tls or similar operator-generated secrets
    local baw_db_secrets=$(${CLI_CMD} get secrets -n "$namespace" -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | test("baw.*db.*client.*tls|bawins.*db.*tls")) | .metadata.name' 2>/dev/null)
    
    if [[ -z "$baw_db_secrets" ]]; then
        info "No BAW database client TLS secrets found in namespace '$namespace'"
        info "Searching for any secrets with 'tls.p8' key..."
        
        # Broader search for any secret with tls.p8
        baw_db_secrets=$(${CLI_CMD} get secrets -n "$namespace" -o json 2>/dev/null | \
            jq -r '.items[] | select(.data."tls.p8" != null and .data."tls.key" == null) | .metadata.name' 2>/dev/null)
        
        if [[ -z "$baw_db_secrets" ]]; then
            success "No secrets found with 'tls.p8' that are missing 'tls.key'. No fixes needed."
            return 0
        else
            warning "Found secrets with 'tls.p8' but missing 'tls.key':"
            echo "$baw_db_secrets"
            echo
        fi
    fi
    
    local secrets_fixed=0
    local secrets_skipped=0
    
    while IFS= read -r secret_name; do
        if [[ -z "$secret_name" ]]; then
            continue
        fi
        
        info "Processing secret: $secret_name"
        
        # Check if secret has tls.p8
        local has_tls_p8=$(${CLI_CMD} get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.p8}' 2>/dev/null)
        
        # Check if secret already has tls.key
        local has_tls_key=$(${CLI_CMD} get secret "$secret_name" -n "$namespace" -o jsonpath='{.data.tls\.key}' 2>/dev/null)
        
        if [[ -n "$has_tls_p8" && -z "$has_tls_key" ]]; then
            warning "Secret '$secret_name' has 'tls.p8' but missing 'tls.key'"
            info "Adding 'tls.key' with the same content as 'tls.p8'..."
            
            # Patch the secret to add tls.key with the same value as tls.p8
            ${CLI_CMD} patch secret "$secret_name" -n "$namespace" --type=json -p="[
                {\"op\": \"add\", \"path\": \"/data/tls.key\", \"value\": \"$has_tls_p8\"}
            ]" 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                success "Successfully added 'tls.key' to secret '$secret_name'"
                secrets_fixed=$((secrets_fixed + 1))
            else
                error "Failed to patch secret '$secret_name'"
            fi
        elif [[ -n "$has_tls_key" && -n "$has_tls_p8" ]]; then
            info "Secret '$secret_name' already has both 'tls.key' and 'tls.p8'. No changes needed."
            secrets_skipped=$((secrets_skipped + 1))
        elif [[ -z "$has_tls_p8" ]]; then
            info "Secret '$secret_name' does not have 'tls.p8'. Skipping."
            secrets_skipped=$((secrets_skipped + 1))
        fi
        echo
    done <<< "$baw_db_secrets"
    
    echo
    if [[ $secrets_fixed -gt 0 ]]; then
        success "Fixed $secrets_fixed BAW database client TLS secret(s)"
    elif [[ $secrets_skipped -gt 0 ]]; then
        success "All $secrets_skipped secret(s) already have the correct format. No fixes needed."
    else
        info "No secrets were processed."
    fi
    
    return 0
}


# Function to process and apply IBMServiceMeterDefinition YAMLs
# Parameters:
#   $1 - namespace
#   $2 - file location (directory containing YAML files)
# https://jsw.ibm.com/browse/DBACLD-216413
function apply_service_meter_definitions() {
    local namespace="$1"
    local file_location="$2"
    
    
    if [[ -z "$file_location" ]]; then
        error "File location parameter is required"
        return 1
    fi
    
    if [[ ! -d "$file_location" ]]; then
        error "Directory '$file_location' does not exist"
        return 1
    fi
    
    info "Processing IBMServiceMeterDefinition YAMLs in: $file_location"
    info "Target namespace for the YAMLs to be applied in: $namespace"
    
    # Process each YAML file in the directory
    for yaml_file in "$file_location"/*.yaml "$file_location"/*.yml; do
        # Skip if no files match
        [[ -e "$yaml_file" ]] || continue
        
        local filename=$(basename "$yaml_file")
        
        # Check if the file is of kind IBMServiceMeterDefinition
        local kind=$("${YQ_CMD}" read "$yaml_file" 'kind' 2>/dev/null)
        
        if [[ "$kind" != "IBMServiceMeterDefinition" ]]; then
            #echo "Skipping $filename - not an IBMServiceMeterDefinition (kind: $kind)"
            continue
        fi
        
        # Create a temporary file for modifications
        local temp_file="${TEMP_FOLDER}/${filename}"
        cp "$yaml_file" "$temp_file"
        
        # Update namespace
        "${YQ_CMD}" write -i "$temp_file" "metadata.namespace" "$namespace"
        
        # If flag is set, rename componentId to productId and componentName to productName
        # This is a temporary block that will be removed once UMS pushes a fix in their next release
        #if [[ "$RENAME_COMPONENT_FIELDS" == "true" ]]; then
        #
        #    # Check if componentId exists directly under data and rename to productId
        #    local component_id=$("${YQ_CMD}" read "$temp_file" 'spec.data.componentId' 2>/dev/null)
        #    if [[ "$component_id" != "null" && -n "$component_id" ]]; then
        #        "${YQ_CMD}" write -i "$temp_file" "spec.data.productId" "$component_id"
        #        "${YQ_CMD}" delete -i "$temp_file" "spec.data.componentId"
        #    fi

            # Check if componentName exists directly under data and rename to productName
        #    local component_name=$("${YQ_CMD}" read "$temp_file" 'spec.data.componentName' 2>/dev/null)
        #    if [[ "$component_name" != "null" && -n "$component_name" ]]; then
        #        "${YQ_CMD}" write -i "$temp_file" "spec.data.productName" "$component_name"
        #        "${YQ_CMD}" delete -i "$temp_file" "spec.data.componentName"
        #    fi
            
            # Process sources array - rename componentId and componentName in each source
        #    local sources_count=$("${YQ_CMD}" read "$temp_file" 'spec.sources' 2>/dev/null | grep -c "^-" 2>/dev/null || echo "0")
        #    sources_count=$(echo "$sources_count" | tr -d '[:space:]')
        #    if [[ "$sources_count" != "0" && "$sources_count" =~ ^[0-9]+$ ]]; then
        #        # Rename componentId to productId and componentName to productName in sources array
        #        for ((i=0; i<sources_count; i++)); do
        #            local comp_id=$("${YQ_CMD}" read "$temp_file" "spec.sources[$i].componentId" 2>/dev/null)
        #            if [[ "$comp_id" != "null" && -n "$comp_id" ]]; then
        #                "${YQ_CMD}" write -i "$temp_file" "spec.sources[$i].productId" "$comp_id"
        #                "${YQ_CMD}" delete -i "$temp_file" "spec.sources[$i].componentId"
        #            fi
        #
        #            local comp_name=$("${YQ_CMD}" read "$temp_file" "spec.sources[$i].componentName" 2>/dev/null)
        #            if [[ "$comp_name" != "null" && -n "$comp_name" ]]; then
        #                "${YQ_CMD}" write -i "$temp_file" "spec.sources[$i].productName" "$comp_name"
        #                "${YQ_CMD}" delete -i "$temp_file" "spec.sources[$i].componentName"
        #            fi
        #        done
        #
        #    fi
        #
        #fi
        
        # Apply the modified YAML
        info "  - Applying $filename to namespace $namespace"
        if ${CLI_CMD} apply -f "$temp_file" -n "$namespace"; then
            success "Successfully applied $filename"
        else
            error "Failed to apply $filename"
        fi
        
        # Clean up temp file
        rm -f "$temp_file"
        echo ""
    done
    
    success "All IBMServiceMeterDefinition Static CRs for the Usage Metering Service have been applied."
    echo
}


# Function to process and apply IBMUsageMetering YAMLs. As of right now there is only 1 yaml to be applied but function can handle multiple
# Parameters:
#   $1 - namespace (replaces REPLACE_NAMESPACE)
#   $2 - secret name (replaces REPLACE_SECRET_NAME)
#   $3 - file location (directory containing YAML files)
#   $4 - mode parameter which will tell us if the user is deploying with the dev mode. If the user did not use the dev flag, this parameter will be empty and if not the sanbox:true will be patched into the UsageMetering CR.
# https://jsw.ibm.com/browse/DBACLD-216413
# https://jsw.ibm.com/browse/DBACLD-225399
function apply_usage_metering_definition () {
    local namespace="$1"
    local secret_name="$2"
    local file_location="$3"
    local mode="$4"
    local airgap_mode="$5"
    
    
    if [[ -z "$file_location" ]]; then
        error "File location parameter is required"
        return 1
    fi
    
    if [[ ! -d "$file_location" ]]; then
        error "Directory '$file_location' does not exist"
        return 1
    fi

    if [[ "$mode" == "dev" ]]; then
        info "Usage Metering mode is dev, setting sandbox=true"
    fi
    
    # Create temp folder if it doesn't exist
    mkdir -p "$TEMP_FOLDER"
    
    info "Processing IBMUsageMetering YAMLs in: $file_location"
    info "Target namespace: $namespace"
    
    # Process each YAML file in the directory
    for yaml_file in "$file_location"/*.yaml "$file_location"/*.yml; do
        # Skip if no files match
        [[ -e "$yaml_file" ]] || continue
        
        local filename=$(basename "$yaml_file")
        
        # Check if the file is of kind IBMUsageMetering
        local kind=$("${YQ_CMD}" read "$yaml_file" 'kind' 2>/dev/null)
        
        if [[ "$kind" != "IBMUsageMetering" ]]; then
            echo "Skipping $filename - not an IBMUsageMetering (kind: $kind)"
            continue
        fi
        
        
        # Create a temporary file for modifications
        local temp_file="${TEMP_FOLDER}/${filename}"
        cp "$yaml_file" "$temp_file"
        
        # Check and replace namespace if it contains REPLACE_NAMESPACE
        local current_namespace=$("${YQ_CMD}" read "$temp_file" 'metadata.namespace' 2>/dev/null)
        if [[ "$current_namespace" == "REPLACE_NAMESPACE" ]]; then
            "${YQ_CMD}" write -i "$temp_file" "metadata.namespace" "$namespace"
        fi
        
        if [[ "$airgap_mode" == "true" || "$airgap_mode" == "yes" || "$airgap_mode" == "Yes" ]]; then
            #info "Airgap mode detected, removing .spec.sender.softwareCentral from $filename"
            "${YQ_CMD}" delete -i "$temp_file" 'spec.sender.softwareCentral'
        else
            # Check and replace secret name if it contains REPLACE_SECRET_NAME
            local current_secret=$("${YQ_CMD}" read "$temp_file" 'spec.sender.softwareCentral.entitlementKeySecret' 2>/dev/null)
            if [[ "$current_secret" == "REPLACE_SECRET_NAME" ]]; then
                "${YQ_CMD}" write -i "$temp_file" "spec.sender.softwareCentral.entitlementKeySecret" "$secret_name"
            fi

            # If mode is dev, set sandbox to true
            # https://jsw.ibm.com/browse/DBACLD-225399
            if [[ "$mode" == "dev" ]]; then
                "${YQ_CMD}" write -i "$temp_file" 'spec.sender.softwareCentral.sandbox' "true"
            fi
        fi
        
        # Apply the modified YAML
        info "  - Applying $filename to namespace $namespace"
        if ${CLI_CMD} apply -f "$temp_file" -n "$namespace"; then
            success "Successfully applied $filename"
        else
            error "Failed to apply $filename"
        fi
        
        # Clean up temp file
        rm -f "$temp_file"
        echo ""
    done
    
    success "All IBM Usage Metering Static CRs for the Usage Metering Service have been applied."
    echo
}


# Main installation function for UMS for either fresh install or upgrade
# based on argument 3 the function is able to perform the required steps for either of those scenarios
# $1 Operator namespace
# $2 Services namespace
# $3 scenario i.e fresh_install or upgrade
# $4 entitlement_key which is the key used to generate the connection point secret
# $5 runtime mode that tells the script if it is being used in dev mode and if so the sandbox setting is enabled
# $6 catalog_namespace which is the namespace where the catalog source is located
# $7 airgap_mode which indicates if this is an airgap/offline installation
# https://jsw.ibm.com/browse/DBACLD-216413
function install_ibm_usage_metering() {
    local operator_namespace=$1
    local services_namespace=$2
    local scenario=$3
    local entitlement_key=$4
    local runtime_mode=$5
    local catalog_namespace=$6
    local airgap_mode=$7
    local create_secret="true"
    local create_secret_and_resources="true"
    local connection_point_secret_creation="false"
    echo ""
    echo "=========================================="
    echo "IBM Usage Metering Operator Installation"
    echo "=========================================="
    echo ""

    # Step 1: Check if CatalogSource exists
    if ! ${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" &>/dev/null; then
        error "CatalogSource '$UMS_CATALOG_VERSION' not found in namespace '$catalog_namespace'"
        echo ""
        return 1
    fi

    # Wait for CatalogSource to be ready
    echo "Waiting for IBM Usage Metering Catalog Source to be ready..."
    local timeout=300
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local state=$(${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null)
        if [ "$state" = "READY" ]; then
            info "IBM Usage Metering Catalog Source is ready."
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        error "IBM Usage Metering CatalogSource did not become ready in time."
        exit 1
    fi
    echo ""


    # Step 2: Handle Subscription based on scenario
    if [[ "$scenario" == "fresh_install" ]]; then
        
        info "Creating the IBM Usage Metering Subscription..."
        apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        echo ""
    # For upgrade scenario we might have to apply a new subscription or patch it based on the version the user is already on.
    elif [[ "$scenario" == "upgrade" ]]; then
        info "Checking for existing IBM Usage Metering Subscription..."
        
        # Check if any subscription with "ibm-usage-metering" exists
        local subscription_exists=$(${CLI_CMD} get subscription -n "$operator_namespace" --no-headers 2>/dev/null | grep "ibm-usage-metering" | wc -l)
        
        if [ "$subscription_exists" -gt 0 ]; then
            patch_ums_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$catalog_namespace"
            if [ $? -ne 0 ]; then
                exit 1
            fi
        else
            info "No IBM Usage Metering subscription found. Creating new subscription..."
            
            apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        fi
        echo ""
    fi

    # Step 3: Wait for UMS operator to be ready
    echo "Waiting for the UMS operator to be ready and in running state"
    timeout=600
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get csv -n "$operator_namespace" 2>/dev/null | grep -q "ibm-usage-metering.*Succeeded"; then
            echo "✓ Operator is ready"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... (${elapsed}s/${timeout}s)"
    done

    if [ $elapsed -ge $timeout ]; then
        echo "✗ ERROR: Operator did not become ready in time"
        return 1
    fi
    echo ""

    # This block makes sure the UMS operator pod is running
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get pods -n "$operator_namespace" -l app.kubernetes.io/name=ibm-usage-metering-operator --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
            echo "✓ Operator pod is running"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "✗ WARNING: Operator pod not running yet, but continuing..."
    fi
    echo ""

    # This is the flag that helps modify the static CRs to apply. Right now this flag is needed but once UMS pushes a fix it can be removed
    #RENAME_COMPONENT_FIELDS="true"
    
    # Step 4: Applying the service metering definition static CRs from the descriptors folder
    apply_service_meter_definitions "$services_namespace" "$UMS_STATIC_CR_LOCATION"
    
    # Step 5 which is to create the the connection point secret and connection point CR
    # Step 5(a) For airgap deployments, do not create the UMS secret and apply the UsageMetering CR without the softwareCentral section.
    # Step 5(b) For non-airgap deployments, create the secret only when needed and only apply the CR if the secret exists or was created successfully.
    if [[ "$airgap_mode" == "true" || "$airgap_mode" == "yes" || "$airgap_mode" == "Yes" ]]; then
        info "Airgap mode detected. Skipping creation of secret '$UMS_CONNECTION_POINT_SECRET_NAME' and applying UsageMetering CR."
        apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
    else
        if ${CLI_CMD} get secret "$UMS_CONNECTION_POINT_SECRET_NAME" -n "$services_namespace" >/dev/null 2>&1; then
            success "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' already exists in namespace '$services_namespace', skipping the creation of the secret."
            create_secret_and_resources="true"
            connection_point_secret_creation="true"
        else
            info "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' not found in namespace '$services_namespace', the script will now proceed to creating it using the entitlement key."

            # For upgrade non-airgap, if the entitlement key was not passed in, retrieve it from an existing secret.
            if [[ -z "$entitlement_key" && "$scenario" == "upgrade" ]]; then
                get_entitlement_key_from_secret "ibm-entitlement-key" "$services_namespace"
                if [ $? -ne 0 ]; then
                    warning "Failed to extract entitlement key from secret.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point custom resource file."
                    create_secret_and_resources="false"
                fi
            fi

            # For fresh install non-airgap, entitlement key is expected to be passed in. If not present, do not create the secret or CR.
            if [[ -z "$entitlement_key" ]]; then
                warning "[IMPORTANT]The IBM Entitlement key is not available, so the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
                create_secret_and_resources="false"
            fi
        fi

        # Step 6: Creating the connection point secret and UsageMetering CR only if we were able to retrieve or were passed the entitlement key
        if [[ "$create_secret_and_resources" == "true" ]]; then
            create_connection_point_secret "$UMS_CONNECTION_POINT_SECRET_NAME" "$services_namespace" "$entitlement_key"
            if [[ "$connection_point_secret_creation" == "true" ]]; then
                apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
            else
                warning "[IMPORTANT]Since the $UMS_CONNECTION_POINT_SECRET_NAME could not be created, the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
            fi
        fi
    fi


    echo "================================================="
    echo "Usage Metering Operator Installation Complete!"
    echo "================================================="
    echo ""
    
}


# Complete the IBM Usage Metering installation after the subscription has already been created/patched.
# This function covers the second phase of the UMS setup: waiting for the operator to become ready,
# applying service meter definition CRs, and configuring the connection point secret and CR.
# The subscription setup phase is handled separately by setup_ibm_usage_metering_subscription().
#
# Arguments:
# $1 Operator namespace
# $2 Services namespace
# $3 scenario i.e fresh_install or upgrade
# $4 entitlement_key (empty for upgrade, will be retrieved if needed)
# $5 runtime mode that tells the script if it is being used in dev mode
# $6 airgap mode which makes sure that the connection point CR is created without the softwareCentral section
function complete_ibm_usage_metering_installation() {
    local operator_namespace=$1
    local services_namespace=$2
    local scenario=$3
    local entitlement_key=$4
    local runtime_mode=$5
    local airgap_mode=$6
    local create_secret_and_resources="true"
    local connection_point_secret_creation="false"

    echo ""
    echo "=========================================="
    echo "IBM Usage Metering Installation (Phase 2)"
    echo "=========================================="
    echo ""

    # Step 1: Wait for UMS operator CSV to be ready
    echo "Waiting for the UMS operator to be ready and in running state"
    local timeout=600
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get csv -n "$operator_namespace" 2>/dev/null | grep -q "ibm-usage-metering.*Succeeded"; then
            echo "✓ Operator is ready"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        echo "  Waiting... (${elapsed}s/${timeout}s)"
    done

    if [ $elapsed -ge $timeout ]; then
        echo "✗ ERROR: Operator did not become ready in time"
        return 1
    fi
    echo ""

    # Step 2: Wait for UMS operator pod to be running
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if ${CLI_CMD} get pods -n "$operator_namespace" -l app.kubernetes.io/name=ibm-usage-metering-operator --field-selector=status.phase=Running 2>/dev/null | grep -q Running; then
            echo "✓ Operator pod is running"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        echo "✗ WARNING: Operator pod not running yet, but continuing..."
    fi
    echo ""

    # Step 3: Apply the service metering definition static CRs from the descriptors folder
    apply_service_meter_definitions "$services_namespace" "$UMS_STATIC_CR_LOCATION"

    # Step 4: Create the connection point secret and apply connection point CR
    if [[ "$airgap_mode" == "true" || "$airgap_mode" == "yes" || "$airgap_mode" == "Yes" ]]; then
        info "Airgap mode detected. Skipping creation of secret '$UMS_CONNECTION_POINT_SECRET_NAME' and applying UsageMetering CR."
        apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
    else
        if ${CLI_CMD} get secret "$UMS_CONNECTION_POINT_SECRET_NAME" -n "$services_namespace" >/dev/null 2>&1; then
            success "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' already exists in namespace '$services_namespace', skipping the creation of the secret."
            create_secret_and_resources="true"
            connection_point_secret_creation="true"
        else
            info "UMS connection point secret '$UMS_CONNECTION_POINT_SECRET_NAME' not found in namespace '$services_namespace', the script will now proceed to creating it using the entitlement key."

            # For upgrade non-airgap, if the entitlement key was not passed in, retrieve it from an existing secret.
            if [[ -z "$entitlement_key" && "$scenario" == "upgrade" ]]; then
                get_entitlement_key_from_secret "ibm-entitlement-key" "$services_namespace"
                if [ $? -ne 0 ]; then
                    warning "Failed to extract entitlement key from secret.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point custom resource file."
                    create_secret_and_resources="false"
                fi
            fi

            # If entitlement key is still empty, do not create the secret or CR.
            if [[ -z "$entitlement_key" ]]; then
                warning "[IMPORTANT]The IBM Entitlement key is not available, so the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
                create_secret_and_resources="false"
            fi
        fi

        if [[ "$create_secret_and_resources" == "true" ]]; then
            create_connection_point_secret "$UMS_CONNECTION_POINT_SECRET_NAME" "$services_namespace" "$entitlement_key"
            if [[ "$connection_point_secret_creation" == "true" ]]; then
                apply_usage_metering_definition "$services_namespace" "$UMS_CONNECTION_POINT_SECRET_NAME" "$UMS_CONNECTION_POINT_STATIC_CR_LOCATION" "$runtime_mode" "$airgap_mode"
            else
                warning "[IMPORTANT]Since the $UMS_CONNECTION_POINT_SECRET_NAME could not be created, the UsageMetering connection point Custom Resource file will not be created.Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $UMS_CONNECTION_POINT_SECRET_NAME secret and the UsageMetering connection point Custom Resource file."
            fi
        fi
    fi

    echo "================================================="
    echo "Usage Metering Installation Complete!"
    echo "================================================="
    echo ""
}


# Patch an existing IBMLicensing resource to configure Software Central uploads.
# Arguments:
#   $1 - secret name to set in spec.sender.softwareCentral.entitlementKeySecret
#   $2 - IBMLicensing resource name
#   $3 - runtime mode; if "dev", sandbox=true is added
function patch_ils_instance() {
    local secret_name="$1"
    local licensing_name="$2"
    local mode="$3"
    local patch_payload=""

    # Build the default merge patch payload
    patch_payload=$(cat <<EOF
{
  "spec": {
    "softwareCentral": {
      "enable": true,
      "frequency": "5 0 * * *",
      "entitlementKeySecret": "$secret_name"
    }
  }
}
EOF
)

    # Add sandbox only in dev mode
    if [[ "$mode" == "dev" ]]; then
        info "Runtime mode is dev, setting spec.softwareCentral.sandbox=true"
        patch_payload=$(cat <<EOF
{
  "spec": {
    "softwareCentral": {
      "enable": true,
      "frequency": "5 0 * * *",
      "entitlementKeySecret": "$secret_name",
      "sandbox": true
    }
  }
}
EOF
)
    fi

    # Patch the IBMLicensing custom resource
    info "Patching IBMLicensing resource \"$licensing_name\""
    if ${CLI_CMD} patch IBMLicensing "$licensing_name" --type=merge -p "$patch_payload"; then
        success "Successfully patched IBMLicensing resource \"$licensing_name\""
        return 0
    else
        error "Failed to patch IBMLicensing resource \"$licensing_name\""
        return 1
    fi
}


# Configure Software Central integration for an existing IBMLicensing resource.
#
# Flow:
#   1. Check whether an IBMLicensing resource exists.
#   2. If no IBMLicensing resource exists, skip the configuration.
#   3. Check whether the ILS connection point secret already exists.
#   4. If the secret does not exist:
#      - use the provided entitlement key if available
#      - otherwise, for upgrade scenario only, try to retrieve it from ibm-entitlement-key
#      - if no entitlement key can be obtained, skip secret creation and CR patching
#      - if entitlement key is available, create the secret
#   5. Patch the IBMLicensing resource to enable Software Central uploads.
#   6. In dev mode, also set sandbox=true.
#
# Arguments:
#   $1 - namespace where the ILS connection point secret should exist
#   $2 - services namespace where ibm-entitlement-key may exist
#   $3 - entitlement key value; may be empty during upgrade
#   $4 - scenario value such as "upgrade" or "fresh_install"
#   $5 - runtime mode such as "dev" or "prod"
function setup_ils_configuration_for_vpc_metrics() {
    local licensing_namespace="$1"
    local services_namespace="$2"
    local entitlement_key="$3"
    local scenario="$4"
    local mode="$5"
    local licensing_name=""
    local mode_lower=""
    local create_secret="true"

    # Normalize runtime mode to lowercase for comparison
    mode_lower=$(echo "$mode" | tr '[:upper:]' '[:lower:]')

    # Step 1: Check whether an IBMLicensing resource exists
    info "Checking for IBMLicensing resource..."
    licensing_name=$(${CLI_CMD} get IBMLicensing --no-headers --ignore-not-found 2>/dev/null | awk 'NR==1{print $1}')

    if [[ -z "$licensing_name" ]]; then
        warning "No IBMLicensing resource found. Skipping ILS Software Central configuration."
        return 0
    fi

    success "Found IBMLicensing resource: $licensing_name"

    # Step 2: Check whether the ILS connection point secret already exists
    if ${CLI_CMD} get secret "$ILS_CONNECTION_POINT_SECRET_NAME" -n "$licensing_namespace" >/dev/null 2>&1; then
        success "ILS connection point secret '$ILS_CONNECTION_POINT_SECRET_NAME' already exists in namespace '$licensing_namespace'."

        # Step 3: Patch the IBMLicensing resource even if the secret already exists
        patch_ils_instance "$ILS_CONNECTION_POINT_SECRET_NAME" "$licensing_name" "$mode_lower"
        return $?
    fi

    info "ILS connection point secret '$ILS_CONNECTION_POINT_SECRET_NAME' not found in namespace '$licensing_namespace'. The script will attempt to create it."

    # Step 4: If no entitlement key was passed and this is an upgrade, try retrieving it
    if [[ -z "$entitlement_key" && "$scenario" == "upgrade" ]]; then
        info "Entitlement key was not passed in upgrade scenario. Attempting to retrieve it from secret \"ibm-entitlement-key\" in namespace \"$services_namespace\"."

        get_entitlement_key_from_secret "ibm-entitlement-key" "$services_namespace"
        if [ $? -ne 0 ]; then
            error "Failed to extract entitlement key from secret. Refer to https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/$CP4BA_RELEASE_BASE for more information on how to create the $ILS_CONNECTION_POINT_SECRET_NAME secret and update the IBMLicensing custom resource."
            create_secret="false"
        else
            entitlement_key="$ENTITLEMENT_KEY"
        fi
    fi

    # Step 5: If entitlement key is still empty, do not create the secret or patch the CR
    if [[ -z "$entitlement_key" ]]; then
        warning "Entitlement key is empty. Skipping creation of secret '$ILS_CONNECTION_POINT_SECRET_NAME' and skipping IBMLicensing patch."
        return 0
    fi

    # Step 6: Create the secret only if allowed
    if [[ "$create_secret" == "true" ]]; then
        info "Creating ILS connection point secret '$ILS_CONNECTION_POINT_SECRET_NAME' in namespace '$licensing_namespace'"
        create_connection_point_secret "$ILS_CONNECTION_POINT_SECRET_NAME" "$licensing_namespace" "$entitlement_key"

        # Step 7: Patch the IBMLicensing resource after secret creation
        patch_ils_instance "$ILS_CONNECTION_POINT_SECRET_NAME" "$licensing_name" "$mode_lower"
        return $?
    fi

    return 0
}




# Function to get the total reconcile count for a CP4BA operator pod.
# Sets the global variable OPERATOR_RECONCILE_COUNT to a numeric value.
# Returns:
#   0 when reconcile artifact count was found and parsed
#   1 when the artifact count could not be found
function get_cp4ba_operator_reconcile_count() {
    local operator_namespace="$1"
    local operator_pod_name="$2"
    local top_level_cr_kind="$3"
    local top_level_cr_name="$4"
    local cr_kind_path=""
    local reconcile_count=""

    OPERATOR_RECONCILE_COUNT=0

    if [[ -z "$operator_namespace" || -z "$operator_pod_name" || -z "$top_level_cr_kind" || -z "$top_level_cr_name" || -z "$CP4BA_SERVICES_NS" ]]; then
        return 1
    fi

    if [[ "$top_level_cr_kind" == "content" ]]; then
        cr_kind_path="Content"
    else
        cr_kind_path="ICP4ACluster"
    fi

    reconcile_count=$(${CLI_CMD} -n "$operator_namespace" exec "$operator_pod_name" -- sh -c "
        ls /tmp/ansible-operator/runner/icp4a.ibm.com/v1/${cr_kind_path}/${CP4BA_SERVICES_NS}/${top_level_cr_name}/artifacts/ 2>/dev/null | grep -c '^[0-9]'
    " 2>/dev/null)

    if [[ $? -eq 0 && "$reconcile_count" =~ ^[0-9]+$ ]]; then
        OPERATOR_RECONCILE_COUNT="$reconcile_count"
        return 0
    fi

    return 1
}


# Function to update BTS datastore configuration for tls.key to tls.pk8 migration
# This function checks for the ConfigMap 'ibm-bts-config-extension' and Secret 'bts-datastore-edb-secret'
# and updates tls.key references to tls.pk8 where needed.
function update_bts_datastore_resources() {
    local namespace="$1"
    local bts_configmap_name="ibm-bts-config-extension"
    local bts_secret_name="bts-datastore-edb-secret"

    fix_baw_db_client_tls_secrets $namespace

    info "Checking if the current deployment has the Secret '$bts_secret_name' and ConfigMap '$bts_configmap_name' created in the namespace: $namespace"
    echo
    # Check if ConfigMap exists
    local cm_exists=false
    if ${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" &> /dev/null; then
        cm_exists=true
        info "ConfigMap '$bts_configmap_name' found in namespace '$namespace'"
    else
        info "ConfigMap '$bts_configmap_name' not found in namespace '$namespace'"
    fi

    # Check if Secret exists
    local secret_exists=false
    if ${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" &> /dev/null; then
        secret_exists=true
        info "Secret '$bts_secret_name' found in namespace '$namespace'"
    else
        info "Secret '$bts_secret_name' not found in namespace '$namespace'"
    fi

    # Exit if neither resource exists
    if [[ "$cm_exists" == "false" && "$secret_exists" == "false" ]]; then
        info "Neither ConfigMap '$bts_configmap_name' nor Secret '$bts_secret_name' exist in this deployment. Skipping the resource updates as they are not required."
        return 0
    fi
    echo
    # Process Secret if it exists
    if [[ "$secret_exists" == "true" ]]; then
        info "Processing Secret '$bts_secret_name' to check for 'tls.key' field..."

        # Check if secret has tls.key using jsonpath
        local has_tls_key=$(${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" -o jsonpath='{.data.tls\.key}' 2>/dev/null)

        if [[ -n "$has_tls_key" ]]; then
            warning "Found 'tls.key' field in Secret '$bts_secret_name'. This field needs to be renamed to 'tls.pk8' for compatibility with the latest BTS version."
            info "Applying patch to rename 'tls.key' to 'tls.pk8' in Secret '$bts_secret_name'..."

            # Create a patch to rename tls.key to tls.pk8
            ${CLI_CMD} patch secret "$bts_secret_name" -n "$namespace" --type=json -p="[
                {\"op\": \"add\", \"path\": \"/data/tls.pk8\", \"value\": \"$has_tls_key\"},
                {\"op\": \"remove\", \"path\": \"/data/tls.key\"}
            ]"

            if [[ $? -eq 0 ]]; then
                success "Successfully renamed 'tls.key' to 'tls.pk8' in Secret '$bts_secret_name'"
            else
                error "Failed to update Secret '$bts_secret_name'. Please check the secret permissions and try again."
                return 1
            fi
        else
            # Check if tls.pk8 already exists
            local has_tls_pk8=$(${CLI_CMD} get secret "$bts_secret_name" -n "$namespace" -o jsonpath='{.data.tls\.pk8}' 2>/dev/null)
            if [[ -n "$has_tls_pk8" ]]; then
                info "Secret '$bts_secret_name' already has 'tls.pk8' field. No changes needed."
            fi
        fi
    fi

    # Process ConfigMap if it exists
    if [[ "$cm_exists" == "true" ]]; then
        info "Processing ConfigMap '$bts_configmap_name' to check for 'tls.key' file path references..."

        # Get all keys from ConfigMap data section
        local all_keys=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath='{.data}' 2>/dev/null)

        if [[ -z "$all_keys" || "$all_keys" == "{}" ]]; then
            warning "No data found in ConfigMap '$bts_configmap_name'. ConfigMap appears to be empty."
        else
            # Find all customPropertyName keys and check for sslKey value
            local ssl_key_num=""
            local custom_prop_names=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o json | grep -o '"customPropertyName[0-9]*"' | tr -d '"')

            if [[ -z "$custom_prop_names" ]]; then
                info "No 'customPropertyName' keys found in ConfigMap '$bts_configmap_name'. No SSL key configuration to update."
            else
                # Check each customPropertyName to find sslKey
                while IFS= read -r key; do
                    if [[ -n "$key" ]]; then
                        local value=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath="{.data.$key}" 2>/dev/null)

                        if [[ "$value" == "sslKey" ]]; then
                            # Extract the number from customPropertyNameX
                            ssl_key_num=$(echo "$key" | grep -o '[0-9]*$')
                            info "Found 'sslKey' property at '$key'"
                            break
                        fi
                    fi
                done <<< "$custom_prop_names"

                if [[ -n "$ssl_key_num" ]]; then
                    # Check the corresponding customPropertyValue
                    local custom_prop_value_key="customPropertyValue$ssl_key_num"
                    local current_value=$(${CLI_CMD} get configmap "$bts_configmap_name" -n "$namespace" -o jsonpath="{.data.$custom_prop_value_key}" 2>/dev/null)

                    if [[ -n "$current_value" ]]; then

                        # Check if the path ends with tls.key
                        if [[ "$current_value" == *"tls.key" ]]; then
                            local new_value="${current_value%tls.key}tls.pk8"
                            warning "File path ends with 'tls.key' which needs to be updated to 'tls.pk8' for compatibility with the latest BTS version."
                            info "Applying patch to update '$custom_prop_value_key' from '$current_value' to '$new_value'..."

                            # Patch the ConfigMap
                            ${CLI_CMD} patch configmap "$bts_configmap_name" -n "$namespace" --type=json -p="[
                                {\"op\": \"replace\", \"path\": \"/data/$custom_prop_value_key\", \"value\": \"$new_value\"}
                            ]"

                            if [[ $? -eq 0 ]]; then
                                success "Successfully updated the '$custom_prop_value_key' key in ConfigMap '$bts_configmap_name'"
                            else
                                error "Failed to update ConfigMap '$bts_configmap_name'. Please check the configmap '$bts_configmap_name' permissions and try again."
                                return 1
                            fi
                        elif [[ "$current_value" == *"tls.pk8" ]]; then
                            info "File path already ends with 'tls.pk8'. No changes needed."
                        else
                            echo
                        fi
                    else
                        warning "Property '$custom_prop_value_key' not found or is empty in ConfigMap '$bts_configmap_name'."
                        warning "Expected to find the SSL key file path at this property."
                    fi
                else
                    info "No 'sslKey' property found in ConfigMap '$bts_configmap_name'."
                    info "Please verify the '$bts_configmap_name' configmap before proceeding with next steps."
                fi
            fi
        fi
    fi

    success "BTS Datasource resources are compatible with the latest BTS version."

    return 0
}

###############################################################################
# Functions added from cert-kubernetes to cert-kubernetes-baw for upgrade support
###############################################################################
function create_odm_keystore_secret_for_upgrade() {
    local namespace=$1
    local cr_file=$2
    local secret_name="ibm-odm-keystore-secret"
    
    # Check if passwordSecretRef is already defined in the CR
    local password_secret_ref=$(${YQ_CMD} r "$cr_file" spec.odm_configuration.dba.passwordSecretRef 2>/dev/null)
    
    if [[ -n "$password_secret_ref" && "$password_secret_ref" != "null" ]]; then
        info "ODM keystore password secret reference already exists in CR: $password_secret_ref. Skipping secret creation."
        return 0
    fi
    
    # Check if the secret already exists in the namespace
    local secret_exists=$(${CLI_CMD} get secret "$secret_name" -n "$namespace" --ignore-not-found 2>/dev/null)
    
    if [[ -n "$secret_exists" ]]; then
        info "ODM keystore password secret '$secret_name' already exists in namespace '$namespace'. Skipping secret creation."
        return 0
    fi
    
    # Generate a random 16-character password
    local password=$(openssl rand -hex 8)
    
    # Create the secret using kubectl create secret generic with --from-literal
    ${CLI_CMD} create secret generic "${secret_name}" \
        --from-literal=keystorePassword="${password}" \
        -n "${namespace}" >/dev/null 2>&1
    
    if [[ $? -eq 0 ]]; then
        # Add the label to the secret
        ${CLI_CMD} label secret "${secret_name}" \
            cp4ba.ibm.com/backup-type=mandatory \
            -n "${namespace}" >/dev/null 2>&1
        
        success "Successfully created ODM keystore password secret '${secret_name}' in namespace '${namespace}'"
    else
        step_num=1
        warning "Failed to automatically create ODM keystore password secret '${secret_name}'. Please create it manually."
        echo
        echo "  - STEP ${step_num} ${RED_TEXT}(Required)${RESET_TEXT} Starting with CP4BA release 26.0.0, deployments that include the Operational Decision Manager (ODM) pattern require a secret named \"ibm-odm-keystore-secret\" to be created before applying the upgraded Custom Resource file."
        echo
        echo "    This secret must contain a 'keystorePassword' field. If this secret already exists in your namespace, no action is required."
        echo
        echo "    To create the secret, follow these sub-steps:"
        echo
        echo "      ${step_num}.a Check if the secret already exists:"
        echo "      ${GREEN_TEXT} # ${CLI_CMD} get secret ibm-odm-keystore-secret -n ${namespace}${RESET_TEXT}"
        echo
        echo "      ${step_num}.b Create the secret with the required label using the following command:"
        echo "      ${GREEN_TEXT} # ${CLI_CMD} create secret generic ibm-odm-keystore-secret --from-literal=keystorePassword=\"\${KEYSTORE_PASSWORD}\" -n ${namespace} ${RESET_TEXT}"
        echo
        echo "      ${step_num}.c Add the required label to the secret:"
        echo "      ${GREEN_TEXT} # ${CLI_CMD} label secret ibm-odm-keystore-secret \"cp4ba.ibm.com/backup-type=mandatory\" -n ${namespace} ${RESET_TEXT}"
        echo
        echo "      ${step_num}.d Verify the secret was created successfully with the correct label:"
        echo "      ${GREEN_TEXT} # ${CLI_CMD} get secret ibm-odm-keystore-secret -n ${namespace} --show-labels ${RESET_TEXT}"
        echo
        echo "    ${YELLOW_TEXT}Note:${RESET_TEXT} For more information, refer to: https://www.ibm.com/docs/en/cloud-paks/cp-biz-automation/${CP4BA_RELEASE_BASE}?topic=automation-upgrading"
        echo
    fi
}

function get_existing_csvs() {
    # Usage: get_existing_csvs <namespace> <output_dir> <sub_name>
    # Reads the installedCSV from the given subscription and saves its YAML to <output_dir>/<csv_name>.yaml
    local namespace="$1"
    local output_dir="$2"
    local sub_name="$3"

    if [[ -z "$namespace" || -z "$output_dir" || -z "$sub_name" ]]; then
        warning "Namespace, output directory, and subscription name must be provided."
        return 1
    fi

    mkdir -p "$output_dir" >/dev/null 2>&1

    # Extract the installedCSV name from the subscription status, e.g. ibm-ads-operator.v25.1.1
    local csv_name
    csv_name=$(${CLI_CMD} get subscription.operators.coreos.com "$sub_name" -n "$namespace" \
        --no-headers --ignore-not-found -o 'jsonpath={.status.installedCSV}') >/dev/null 2>&1
    if [[ -z "$csv_name" ]]; then
        warning "No installedCSV found for subscription \"$sub_name\" in namespace \"$namespace\", skipping."
        return 0
    fi

    local output_file="${output_dir}/${csv_name}.yaml"
    # If the file already exists, rename it with a timestamp suffix before writing a new one
    if [[ -e "$output_file" ]]; then
        local ts
        ts=$(date +'%Y%m%d%H%M%S')
        mv "$output_file" "${output_file%.yaml}_${ts}.yaml_bak"
        info "Existing backup renamed to \"${output_file%.yaml}_${ts}.yaml_bak\""
    fi
    ${CLI_CMD} get csv "$csv_name" -n "$namespace" --ignore-not-found -o yaml > "$output_file" 2>/dev/null
    if [[ $? -eq 0 && -s "$output_file" ]]; then
        info "Backed up CSV \"$csv_name\" to \"$output_file\""
    else
        warning "Failed to back up CSV \"$csv_name\" from namespace \"$namespace\"."
    fi
    return 0
}

function setup_ibm_usage_metering_subscription() {
    local operator_namespace=$1
    local scenario=$2
    local catalog_namespace=$3
    local services_namespace=$4
    
    echo ""
    echo "=========================================="
    echo "IBM Usage Metering Subscription Setup"
    echo "=========================================="
    echo ""

    # Step 1: Check if CatalogSource exists
    if ! ${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" &>/dev/null; then
        error "CatalogSource '$UMS_CATALOG_VERSION' not found in namespace '$catalog_namespace'"
        echo ""
        exit 1
    fi

    # Wait for CatalogSource to be ready
    echo "Waiting for IBM Usage Metering Catalog Source to be ready..."
    local timeout=300
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local state=$(${CLI_CMD} get catalogsource "$UMS_CATALOG_VERSION" -n "$catalog_namespace" -o jsonpath='{.status.connectionState.lastObservedState}' 2>/dev/null)
        if [ "$state" = "READY" ]; then
            info "IBM Usage Metering Catalog Source is ready."
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [ $elapsed -ge $timeout ]; then
        TMP_MESSAGE="IBM Usage Metering Installation failed due to Catalog source not being ready"
        if [[ "$scenario" == "upgrade" ]]; then
            displayUpgradeOperatorMessage "$TMP_MESSAGE" $services_namespace $cp4a_operator_csv_version
        else
            displayClusterAdminMessage "$TMP_MESSAGE" "$CP4BA_RELEASE_BASE-$CP4BA_PATCH_VERSION"
        fi
        exit 1
    fi
    echo ""

    # Step 2: Handle Subscription based on scenario
    if [[ "$scenario" == "fresh_install" ]]; then
        info "Creating the IBM Usage Metering Subscription..."
        apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        echo ""
    elif [[ "$scenario" == "upgrade" ]]; then
        info "Checking for existing IBM Usage Metering Subscription..."
        
        local subscription_exists=$(${CLI_CMD} get subscription -n "$operator_namespace" --no-headers 2>/dev/null | grep "ibm-usage-metering" | wc -l)
        
        if [ "$subscription_exists" -gt 0 ]; then
            patch_ums_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$catalog_namespace"
            if [ $? -ne 0 ]; then
                TMP_MESSAGE="IBM Usage Metering Installation failed as patching the IBM Usage Metering Installation Operator Subscription failed."
                displayUpgradeOperatorMessage "$TMP_MESSAGE" $services_namespace $cp4a_operator_csv_version
                exit 1
            fi
        else
            info "No IBM Usage Metering subscription found. Creating new subscription..."
            apply_subscription "$operator_namespace" "$UMS_CHANNEL_VERSION" "$UMS_CATALOG_VERSION" "$catalog_namespace"
        fi
        echo ""
    fi
    
    success "IBM Usage Metering Subscription setup completed successfully"
    return 0
}

function retrieve_custom_resource_details(){
    local cr_namespace=$1
    local icp4acluster_cr_details_location=$2
    local content_cr_details_location=$3
    top_level_cr_kind=""
    top_level_cr_name=""
    top_level_cr_details_location=""
    top_level_cr_details_backup_location=""
    content_cr_name=""
    icp4acluster_cr_name=""
    content_cr_present="false"
    icp4acluster_cr_present="false"

    #Logic that detects what the top level CR is in the deployment
    # If the content CR does not have an owner reference , it is the top level CR otherwise the top level CR is the ICP4ACLuster CR
    ${CLI_CMD} get crd |grep contents.icp4a.ibm.com >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        content_cr_name=$(${CLI_CMD} get content -n $cr_namespace --no-headers --ignore-not-found | awk '{print $1}')
        if [[ ! -z $content_cr_name ]]; then
            owner_ref=$(${CLI_CMD} get content $content_cr_name -n $cr_namespace -o yaml | ${YQ_CMD} r - metadata.ownerReferences.[0].kind)
            # Store the Content CR contents in a certain file location
            ${CLI_CMD} get content $content_cr_name -n $cr_namespace -o yaml > ${content_cr_details_location}
            if [[ ${owner_ref} != "ICP4ACluster" ]]; then
                top_level_cr_kind="content"
                top_level_cr_name="$content_cr_name"
                top_level_cr_details_location="${content_cr_details_location}" 
                top_level_cr_details_backup_location="${UPGRADE_DEPLOYMENT_CONTENT_CR_BAK}"              
            fi
        fi
    fi

    if [[ -z "$top_level_cr_kind" ]]; then
        icp4acluster_cr_name=$(${CLI_CMD} get icp4acluster -n $cr_namespace --no-headers --ignore-not-found | awk '{print $1}')
        if [[ ! -z $icp4acluster_cr_name ]]; then
            # Store the Content CR contents in a certain file location
            ${CLI_CMD} get icp4acluster $icp4acluster_cr_name -n $cr_namespace -o yaml > ${icp4acluster_cr_details_location}
            top_level_cr_kind="icp4acluster"
            top_level_cr_name="$icp4acluster_cr_name"
            top_level_cr_details_location="${icp4acluster_cr_details_location}" 
            top_level_cr_details_backup_location="${UPGRADE_DEPLOYMENT_ICP4ACLUSTER_CR_BAK}" 
        fi
    fi

    if [[ -z "$top_level_cr_kind" || -z "$top_level_cr_name" ]]; then
        error "Could not find a IC4ACluster Kind Custom Resource file or a Content Kind Custom Resource file in the $cr_namespace namespace. The script will now exit."
        exit
    fi

    # Retrieve the CR info and store it in a certain file location defined

    # Display Custom Resource Details
    echo ""
    echo "================================================================================"
    echo "${YELLOW_TEXT}Custom Resource Details - Namespace: ${cr_namespace}${RESET_TEXT}"
    echo "================================================================================"
    
    # Display ICP4ACluster CR
    if [[ ! -z "$icp4acluster_cr_name" ]]; then
        echo "ICP4ACluster CR : ${GREEN_TEXT}${icp4acluster_cr_name}${RESET_TEXT}"
    else
        echo "ICP4ACluster CR : Not found"
    fi
    
    # Display Content CR
    if [[ ! -z "$content_cr_name" ]]; then
        echo "Content CR      : ${GREEN_TEXT}${content_cr_name}${RESET_TEXT}"
    else
        echo "Content CR      : Not found"
    fi

    echo ""
    echo "========================================================================================================================"
    echo "Top Level CR Kind   : ${YELLOW_TEXT}${top_level_cr_kind}${RESET_TEXT}"
    echo "Top Level CR Name   : ${GREEN_TEXT}${top_level_cr_name}${RESET_TEXT}"
    echo "Top Level CR Stored at : ${GREEN_TEXT}${top_level_cr_details_location}${RESET_TEXT}"
    echo "========================================================================================================================"
    echo ""
}

#create a YAML file for the ibm-cp4ba-shared-info ConfigMap
#used to store shared information related to the CP4BA deployment, such as operator versions and last reconciliation details
# Function is called in populate_shared_info_configmap based on the top level CR kind
function create_ibm_cp4ba_shared_info_cm_yaml(){
    mkdir -p ${UPGRADE_DEPLOYMENT_CR}
cat << EOF > ${UPGRADE_ICP4A_SHARED_INFO_CM_FILE}
kind: ConfigMap
apiVersion: v1
metadata:
  name: ibm-cp4ba-shared-info
  namespace: <cp4a_namespace>
  labels:
    app.kubernetes.io/managed-by: Operator
    app.kubernetes.io/name: ibm-cp4ba-shared-info
    app.kubernetes.io/version: <cr_version>
    release: <cr_version>
  ownerReferences:
    - apiVersion: icp4a.ibm.com/v1
      kind: ICP4ACluster
      name: <cr_metaname>
      uid: <cr_uid>
data:
  ads_operator_of_last_reconcile: <csv_version>
  cp4ba_operator_of_last_reconcile: <csv_version>
  odm_operator_of_last_reconcile: <csv_version>
  baw_operator_of_last_reconcile: <csv_version>
EOF
}

#create a YAML file for the ibm-cp4ba-shared-info ConfigMap
#used to store shared information related to the CP4BA deployment, such as operator versions and last reconciliation details
# Function is called in populate_shared_info_configmap based on the top level CR kind
function create_ibm_cp4ba_content_shared_info_cm_yaml(){
    mkdir -p ${UPGRADE_DEPLOYMENT_CR}
cat << EOF > ${UPGRADE_ICP4A_CONTENT_SHARED_INFO_CM_FILE}
kind: ConfigMap
apiVersion: v1
metadata:
  name: ibm-cp4ba-content-shared-info
  namespace: <content_namespace>
  labels:
    app.kubernetes.io/managed-by: Operator
    app.kubernetes.io/name: ibm-cp4ba-shared-info
    app.kubernetes.io/version: <cr_version>
    release: <cr_version>
  ownerReferences:
    - apiVersion: icp4a.ibm.com/v1
      kind: Content
      name: <cr_metaname>
      uid: <cr_uid>
data:
  content_operator_of_last_reconcile: <csv_version>
EOF
}

# This is a common function that can create the shared info configmap or patch it with required values.
# The function replaces code that was essentially repeating with the only differences being the name of the configmap based on the top level CR
# The function takes in 4 parameters
# 1. The name of the configmap
# 2. The current details of that configmap
# 3. The namespace to check for the configmap
# 4. The temporary file location that is used to as a template yaml to create the configmap if it is not present
# 5. The top level CR kind
# Variables like $cr_metaname, $cr_uid , $cp4a_operator_csv_version , $cr_version are already set at this point in time
function populate_shared_info_configmap(){
    local configmap_name=$1
    local current_shared_info_configmap_details=$2
    local namespace=$3
    local temp_configmap_details_location=$4
    local cr_kind=$5
    if [[ -z $current_shared_info_configmap_details ]]; then
        info "$configmap_name configMap could not be found,the script will now create it."
        if [[ "$cr_kind" == "icp4acluster" ]]; then
            create_ibm_cp4ba_shared_info_cm_yaml
        elif [[ "$cr_kind" == "content" ]]; then
            create_ibm_cp4ba_content_shared_info_cm_yaml
        else
            fail "No top level CP4BA custom resource found on this cluster in the project \"$namespace\"."
            exit 1
        fi
        ${SED_COMMAND} "s|<cp4a_namespace>|$namespace|g" ${temp_configmap_details_location}
        ${SED_COMMAND} "s|<cr_metaname>|$cr_metaname|g" ${temp_configmap_details_location}
        ${SED_COMMAND} "s|<cr_uid>|$cr_uid|g" ${temp_configmap_details_location}
        ${SED_COMMAND} "s|<csv_version>|$cp4a_operator_csv_version|g" ${temp_configmap_details_location}
        ${SED_COMMAND} "s|<cr_version>|$cr_version|g" ${temp_configmap_details_location}

        ${CLI_CMD} apply -f $temp_configmap_details_location  >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            success "$configmap_name configMap has been created in the project \"$namespace\"!"
            ${CLI_CMD} patch configmap $configmap_name -n $namespace --type=json -p="[{'op': 'add', 'path': '/data/cp4ba_original_csv_ver_for_upgrade_script', 'value': '$(echo "$cp4a_operator_csv_version")'}]" >/dev/null 2>&1
            ${CLI_CMD} patch configmap $configmap_name -n $namespace --type=json -p="[{'op': 'add', 'path': '/data/cpfs_original_csv_ver_for_upgrade_script', 'value': '$(echo "$cpfs_operator_csv_version")'}]" >/dev/null 2>&1
            cp4ba_original_csv_ver_for_upgrade_script=$cp4a_operator_csv_version
        else
            fail "Failed to create $configmap_name configMap in the project \"$namespace\"!"
        fi
    else
        success "$configmap_name configMap was found in namespace \"$namespace\"!"
        ${CLI_CMD} patch configmap $configmap_name -n $namespace --type=json -p="[{'op': 'add', 'path': '/data/cp4ba_original_csv_ver_for_upgrade_script', 'value': '$(echo "$cp4a_operator_csv_version")'}]" >/dev/null 2>&1
        ${CLI_CMD} patch configmap $configmap_name -n $namespace --type=json -p="[{'op': 'add', 'path': '/data/cpfs_original_csv_ver_for_upgrade_script', 'value': '$(echo "$cpfs_operator_csv_version")'}]" >/dev/null 2>&1
        cp4ba_original_csv_ver_for_upgrade_script=$cp4a_operator_csv_version
    fi
}

function set_bai_recovery_path() {
    local component_name="$1"
    local search_pattern="bai-${component_name}"
    local tmp_recovery_path=""
    
    # Extract recovery path based on platform
    if [[ "$machine" == "Mac" ]]; then
        tmp_recovery_path=$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json | jq '.[].location' | grep "$search_pattern")
    else
        tmp_recovery_path=$(grep -Po '"location":.*?[^\\]"' ${UPGRADE_DEPLOYMENT_CR}/bai.json | grep "$search_pattern" | cut -d':' -f2)
    fi
    
    # Clean up quotes
    tmp_recovery_path=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_recovery_path")
    
    # Set recovery path if found
    if [ ! -z "$tmp_recovery_path" ]; then
        ${YQ_CMD} w -i ${UPGRADE_DEPLOYMENT_BAI_TMP} spec.bai_configuration.${component_name}.recovery_path "${tmp_recovery_path}"
        success "Merged Flink savepoint for ${component_name^^}: \"$tmp_recovery_path\""
        info "When running \"cp4a-deployment -m upgradeDeployment\", this savepoint will be auto-filled into spec.bai_configuration.${component_name}.recovery_path."
    fi
}

function get_bai_management_url_from_zenextension() {
    local namespace="$1"
    local zen_extension_name=""

    # Find ZenExtension ending with insights-engine-zen-extension-cr
    zen_extension_name=$(${CLI_CMD} get zenextension -n "${namespace}" --no-headers -o custom-columns=NAME:.metadata.name 2>/dev/null | grep 'insights-engine-zen-extension-cr$' | head -n 1)

    if [[ -z "$zen_extension_name" ]]; then
        error "No ZenExtension ending with 'insights-engine-zen-extension-cr' found in namespace ${namespace}"
        return 1
    fi

    # Get the ZenExtension as YAML and extract proxy_pass URL from nginx.conf
    local zen_yaml=$(${CLI_CMD} get zenextension "${zen_extension_name}" -n "${namespace}" -o yaml 2>/dev/null)

    if [[ -z "$zen_yaml" ]]; then
        error "Failed to retrieve ZenExtension ${zen_extension_name}"
        return 1
    fi

    # Extract nginx.conf and find proxy_pass URL for /bai-management/
    MANAGEMENT_URL=$(echo "$zen_yaml" | ${YQ_CMD} r - 'spec."nginx.conf"' | awk '/location \/bai-management\// {found=1} found && /proxy_pass/ {print; exit}' | sed -n 's/.*proxy_pass \(https:\/\/[^;]*\).*/\1/p')

    if [[ -z "$MANAGEMENT_URL" ]]; then
        error "Failed to extract proxy_pass URL from location /bai-management/ in ZenExtension ${zen_extension_name}"
        return 1
    fi

    # Remove trailing slash if present
    MANAGEMENT_URL="${MANAGEMENT_URL%/}"

    return 0
}

function create_bai_savepoints(){
    local namespace=$1
    local cr_contents_location=$2
    local cr_contents_backup_location=$3
    
    # Backup existing top level CR
    mkdir -p ${cr_contents_backup_location} >/dev/null 2>&1
    ${COPY_CMD} -rf ${cr_contents_location} ${cr_contents_backup_location}
    
    mkdir -p ${TEMP_FOLDER} >/dev/null 2>&1
    # Check the jq install on MacOS
    if [[ "$machine" == "Mac" ]]; then
        which jq &>/dev/null
        [[ $? -ne 0 ]] && \
        printf '%b\n'  "\x1B[1;31mUnable to locate the jq CLI. You must install it to run this script on macOS.\x1B[0m" && \
        exit 1
    fi

    info "Create the BAI savepoints for recovery path which will be referenced when the new custom resource file is generated as a part of the upgradeDeployment mode."
    ${CLI_CMD} get crd |grep insightsengines.icp4a.ibm.com >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        INSIGHTS_ENGINE_CR=$(${CLI_CMD} get insightsengines.icp4a.ibm.com --no-headers --ignore-not-found -n ${namespace} -o name)
    fi
    if [[ -z $INSIGHTS_ENGINE_CR ]]; then
        INSIGHTS_ENGINE_CR=$(${CLI_CMD} get insightsengines.insightsengine.automation.ibm.com --no-headers --ignore-not-found -n ${namespace} -o name)
        if [[ -z $INSIGHTS_ENGINE_CR ]]; then
            error "An InsightsEngine kind custom resource was not found in the project \"${namespace}\"."
            return 1
        fi
    fi
    if [[ ! -z $INSIGHTS_ENGINE_CR ]]; then
        if [[ "$SKIP_FOR_API" == "true" ]]; then
            info "Upgrade is being executed via API endpoints, retrieving Management URL from ZenExtension..."
            get_bai_management_url_from_zenextension "${namespace}"
            if [[ $? -ne 0 || -z "$MANAGEMENT_URL" ]]; then
                error "Failed to retrieve Management URL from ZenExtension"
                return 1
            fi
            info "Retrieved Management URL from ZenExtension: ${MANAGEMENT_URL}"
        else
            MANAGEMENT_URL=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${namespace} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].uri}')
            info "Retrieved Management URL from InsightsEngine CR: ${MANAGEMENT_URL}"
        fi
        MANAGEMENT_AUTH_SECRET=$(${CLI_CMD} get ${INSIGHTS_ENGINE_CR} --no-headers --ignore-not-found -n ${namespace} -o jsonpath='{.status.components.management.endpoints[?(@.scope=="External")].authentication.secret.secretName}')
        MANAGEMENT_USERNAME=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${namespace} -o jsonpath='{.data.username}' | base64 -d)
        MANAGEMENT_PASSWORD=$(${CLI_CMD} get secret ${MANAGEMENT_AUTH_SECRET} --no-headers --ignore-not-found -n ${namespace} -o jsonpath='{.data.password}' | base64 -d)
        if [[ -z "$MANAGEMENT_URL" || -z "$MANAGEMENT_AUTH_SECRET" || -z "$MANAGEMENT_USERNAME" || -z "$MANAGEMENT_PASSWORD" ]]; then
            error "Can not create the BAI savepoints for recovery path."
            return 1
        else
            # rm -rf ${UPGRADE_DEPLOYMENT_CR}/bai.json 
            # Ensure output directory exists
            mkdir -p ${UPGRADE_DEPLOYMENT_CR} >/dev/null 2>&1
            touch ${UPGRADE_DEPLOYMENT_BAI_TMP} >/dev/null 2>&1
            if [[ -e ${UPGRADE_DEPLOYMENT_CR}/bai.json ]]; then
                [ "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" != "[]" ] && mkdir -p ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup && cp ${UPGRADE_DEPLOYMENT_CR}/bai.json ${UPGRADE_DEPLOYMENT_CR}/bai-json-backup/bai_$(date +'%Y%m%d%H%M%S').json
            fi
            curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} "${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints" -o ${UPGRADE_DEPLOYMENT_CR}/bai.json >/dev/null 2>&1

            json_file_content="[]"
            if [ "$json_file_content" == "$(cat ${UPGRADE_DEPLOYMENT_CR}/bai.json)" ] ;then
                fail "None return in \"${UPGRADE_DEPLOYMENT_CR}/bai.json\" when request BAI savepoint through REST API: curl -X POST -k -u ${MANAGEMENT_USERNAME}:${MANAGEMENT_PASSWORD} \"${MANAGEMENT_URL}/api/v1/processing/jobs/savepoints\" "
                warning "Fetch Flink job savepoints for the recovery path using above REST API manually, then place the JSON file (bai.json) under the directory \"${TEMP_FOLDER}/\""
                if [[ "$SKIP_FOR_API" != "true" ]]; then
                    prompt_press_any_key_to_continue
                fi
            fi
            ##########################################################################################################################
            ## In 24.0.1 and later, we'll only support n-1 upgrade therefore we're back to the old way of saving content event-forwarder savepoint and bai-content savepoint UNLESS the ALLOW_DIRECT_UPGRADE == 1 .
            ##########################################################################################################################
            # Process savepoints for different components
            # For n-1 upgrade (not direct upgrade), process event-forwarder and content
            if [[ "$ALLOW_DIRECT_UPGRADE" != 1 ]]; then
                set_bai_recovery_path "event-forwarder"
                set_bai_recovery_path "content"
            fi
            
            # Process other components (always)
            set_bai_recovery_path "icm"
            set_bai_recovery_path "odm"
            set_bai_recovery_path "bawadv"
            set_bai_recovery_path "bpmn"
            set_bai_recovery_path "navigator"
            set_bai_recovery_path "ads"
        fi
    fi
}


# Helper function to scale operators for upgradeDeploymentStatus
function scale_operator() {
    local operator_name=$1
    local operator_label=$2
    
    info "Scaling up \"$operator_label\" operator"
    ${CLI_CMD} scale --replicas=1 deployment $operator_name -n $CP4BA_OPERATOR_NS >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        sleep 1
    else
        fail "Failed to scale up \"$operator_label\" operator"
    fi
}

function delete_cpfs_operand_requests(){
    local project_name=$1
    to_delete_operand_requests=("iaf-system" "operandrequest-kafkauser-iaf-system")
    current_operand_requests=($(${CLI_CMD} get operandrequests -n $project_name -o custom-columns=NAME:.metadata.name --no-headers))
    # Loop through each operand request
    for req in "${current_operand_requests[@]}"; do
        delete=false

        for to_delete_operand_request in "${to_delete_operand_requests[@]}"; do
            if [[ "$req" == "$to_delete_operand_request" ]]; then
            delete=true
            break
            fi
        done

        if [[ $delete == "true" ]]; then
            echo
            info "The operand request $req is no longer required in the CP4BA $CP4BA_RELEASE_BASE stream.To prevent any disruption in the upgrade, the script will delete the $req operand request."
            info "Deleting operand request $req .. "
            ${CLI_CMD} delete operandrequest "$req" -n $project_name --ignore-not-found
            echo
        fi
    done
}

function patch_strimzi_podset(){
    local operator_namespace=$1
    local services_namespace=$2

    echo "Checking the ibm-events-operator subscription and channel..."
    # Check if the events operator subscription exists and get its actual name. we found sometimes the subscription gets created with the channel appended to the name.
    events_operator_subscription_name=$(${CLI_CMD} get subscription.operators.coreos.com -n $operator_namespace --no-headers -o custom-columns=":metadata.name" 2>/dev/null | grep "ibm-events-operator" | head -n 1 || echo "")

    if [[ -z "$events_operator_subscription_name" ]]; then
        echo "Subscription matching 'ibm-events-operator' not found, skipping"
        strimzi_patched=true
        return
    fi

    echo "Found subscription: $events_operator_subscription_name"

    # Get the subscription channel using the actual subscription name
    events_operator_channel=$(${CLI_CMD} get subscription.operators.coreos.com "$events_operator_subscription_name" -n $operator_namespace -o yaml 2>/dev/null | ${YQ_CMD} r - 'spec.channel')

    if [[ -z "$events_operator_channel" || "$events_operator_channel" == "null" ]]; then
        echo "Could not retrieve channel for subscription '$events_operator_subscription_name'"
        return
    fi

    echo "Current channel: $events_operator_channel"

    # Check if channel is v5.2
    if [[ "$events_operator_channel" == "v5.2" ]]; then
        echo "Events Operator Channel is v5.2, proceeding to check if the events operator is running..."

        # Find the operator pod that starts with ibm-events-operator-v5.2
        events_operator_pod=$(${CLI_CMD} get pods --no-headers -n $operator_namespace -o custom-columns=":metadata.name" | grep "^ibm-events-operator-v5.2" || echo "")

        if [[ -z "$events_operator_pod" ]]; then
            echo "'ibm-events-operator-v5.2' pod is not found"
            return
        fi

        echo "Found operator pod: $events_operator_pod"

        # Check if the pod is in Ready state
        events_operator_pod_ready=$(${CLI_CMD} get pod "$events_operator_pod" -n $operator_namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

        if [[ "$events_operator_pod_ready" != "True" ]]; then
            echo "Operator pod '$events_operator_pod' is not in Ready state"
            return
        fi

        # Get the StrimziPodSet resource
        kafka_podset_exists=$(${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace -o name --no-headers 2>/dev/null || echo "")

        if [[ -z "$kafka_podset_exists" ]]; then
            echo "StrimziPodSet 'iaf-system-kafka' not found"
            return
        fi

        echo "Found StrimziPodSet 'iaf-system-kafka'"

        # Get the current kafka version from the annotation
        kafka_annotation_value=$(${CLI_CMD} get strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace -o yaml | ${YQ_CMD} r - 'metadata.annotations[strimzi.io/kafka-version]')

        if [[ -z "$kafka_annotation_value" || "$kafka_annotation_value" == "null" ]]; then
            strimzi_patched=true
            return
        fi

        echo "Current kafka version: $kafka_annotation_value"

        # Apply the patch directly
        echo "Applying patch to update annotations..."
        ${CLI_CMD} patch strimzipodsets.core.ibmevents.ibm.com iaf-system-kafka -n $services_namespace --type=merge -p "{\"metadata\":{\"annotations\":{\"strimzi.io/kafka-version\":null,\"ibmevents.ibm.com/kafka-version\":\"$kafka_annotation_value\"}}}"

        echo "Successfully updated annotations:"
        echo "- Removed: strimzi.io/kafka-version"
        echo "- Added: ibmevents.ibm.com/kafka-version: $kafka_annotation_value"
        strimzi_patched=true
    else
        echo "Events operator is not at channel v5.2"
    fi
}


# Function to check if the deployment is SaaS
# We detect if sc_deploy_zen_with_iaf is explicitly set to false in the CR
# Returns: "true" if sc_deploy_zen_with_iaf is false, "false" otherwise
# Parameters:
#   $1 - CR kind (e.g., ICP4ACluster, Content, etc.)
#   $2 - CR name
#   $3 - namespace
function check_saas_deployment() {
    local cr_kind="$1"
    local cr_name="$2"
    local namespace="$3"

    # Get the CR and extract sc_deploy_zen_with_iaf value (defaults to true if not set)
    local zen_iaf_value
    zen_iaf_value=$(${CLI_CMD} get "$cr_kind" "$cr_name" -n "$namespace" -o yaml 2>/dev/null | \
        ${YQ_CMD} r - 'spec.shared_configuration.sc_deploy_zen_with_iaf')

    # Check if kubectl/yq command failed
    if [[ $? -ne 0 ]]; then
        return 1
    fi

    # Return true only if value is false, otherwise return false
    # If the value is false that means the deployment is SaaS
    if [[ "$zen_iaf_value" == "false" ]]; then
        return 0
    else
        return 1
    fi
}

function validate_zen_upgrade_status(){
    zen_service_name=$(${CLI_CMD} get zenService --no-headers --ignore-not-found -n $CP4BA_SERVICES_NS |awk '{print $1}')
    if [[ ! -z "$zen_service_name" ]]; then
        clear
        maxRetry=360
        for ((retry=0;retry<=${maxRetry};retry++)); do
            # As workaround for https://github.ibm.com/IBMPrivateCloud/roadmap/issues/64207
            # update secret postgresql-operator-controller-manager-config in <cp4ba> namespace and/or ibm-common-services namespace and add this annotation ibm-bts/skip-updates: "true"
            if ${CLI_CMD} get secret -n $CP4BA_SERVICES_NS --no-headers --ignore-not-found | grep postgresql-operator-controller-manager-config >/dev/null 2>&1; then
                ${CLI_CMD} patch secret postgresql-operator-controller-manager-config -n $CP4BA_SERVICES_NS -p '{"metadata": {"annotations": {"ibm-bts/skip-updates": "true"}}}' >/dev/null 2>&1
            fi

            zenservice_version=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $CP4BA_SERVICES_NS -o jsonpath='{.status.currentVersion}')
            isCompleted=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $CP4BA_SERVICES_NS -o jsonpath='{.status.zenStatus}')
            isProgressDone=$(${CLI_CMD} get zenService $zen_service_name --no-headers --ignore-not-found -n $CP4BA_SERVICES_NS -o jsonpath='{.status.progress}')

            if [[ "$isCompleted" != "Completed" || "$isProgressDone" != "100%" || "$zenservice_version" != "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                clear
                CP4BA_DEPLOYMENT_STATUS="Waiting for the zenService to be ready (could take up to 120 minutes) before upgrade the CP4BA capabilities..."
                printf '%s %s\n' "$(date)" "[refresh interval: 60s]"
                printf '%b' "[Press Ctrl+C to exit] \t\t"
                printf "\n"
                echo "${YELLOW_TEXT}$CP4BA_DEPLOYMENT_STATUS${RESET_TEXT}"
                printHeaderMessage "CP4BA Upgrade Status"
                if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
                else
                    echo "zenService Version (Expected - ${ZEN_OPERATOR_VERSION//v/})       : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
                fi
                if [[ "$isCompleted" == "Completed" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Status (Expected - Completed)    : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
                else
                    echo "zenService Status (Expected - Completed)    : ${RED_TEXT}$isCompleted${RESET_TEXT}"
                fi

                if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                    echo "zenService Progress (Expected - 100%)       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
                else
                    echo "zenService Progress (Expected - 100%)       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
                fi
                sleep 60
            elif [[ "$isCompleted" == "Completed" && "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
                break
            elif [[ $retry -eq ${maxRetry} ]]; then
                printf "\n"
                warning "Timeout waiting for the Zen Service to start"
                printf '%b\n' "\x1B[1mCheck the status of the Zen Service\x1B[0m"
                printf "\n"
                exit 1
            fi
        done
        clear
        CP4BA_DEPLOYMENT_STATUS="The Zen Service (${ZEN_OPERATOR_VERSION//v/}) is ready for CP4BA"
        printf '%s %s\n' "$(date)" "[refresh interval: 30s]"
        printf '%b' "[Press Ctrl+C to exit] \t\t"
        printf "\n"
        echo "${YELLOW_TEXT}$CP4BA_DEPLOYMENT_STATUS${RESET_TEXT}"
        info "Starting all CP4BA Operators to upgrade CP4BA capabilities"
        printHeaderMessage "CP4BA Upgrade Status"
        if [[ "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Version        : ${GREEN_TEXT}$zenservice_version${RESET_TEXT}"
        else
            echo "zenService Version        : ${RED_TEXT}$zenservice_version${RESET_TEXT}"
        fi
        if [[ "$isCompleted" == "Completed" ]]; then
            echo "zenService Status         : ${GREEN_TEXT}$isCompleted${RESET_TEXT}"
        else
            echo "zenService Status         : ${RED_TEXT}$isCompleted${RESET_TEXT}"
        fi

        if [[ "$isProgressDone" == "100%" && "$zenservice_version" == "${ZEN_OPERATOR_VERSION//v/}" ]]; then
            echo "zenService Progress       : ${GREEN_TEXT}$isProgressDone${RESET_TEXT}"
        else
            echo "zenService Progress       : ${RED_TEXT}$isProgressDone${RESET_TEXT}"
        fi
    else
        fail "ZenService not found in the project \"$CP4BA_SERVICES_NS\", exiting..."
        echo "****************************************************************************"
        exit 1
    fi
}

function check_if_all_components_are_ready() {
    # Check all component status values in the array
    for status_value in "${CP4BA_COMPONENT_STATUS_VALUES[@]}"; do

        # Skip if empty or whitespace only
        if [[ -z "$status_value" ]] || [[ "$status_value" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Skip if "Not Installed"
        if [[ "$status_value" =~ "Not Installed" ]]; then
            continue
        fi

        # Check for non-ready states
        if [[ "$status_value" =~ "In Progress" ]] || \
           [[ "$status_value" =~ "Not Ready" ]] || \
           [[ "$status_value" =~ "Failed" ]] || \
           [[ "$status_value" =~ "Pending" ]] || \
           [[ "$status_value" =~ "Upgrading" ]]; then
            return 1  # Not ready
        fi

        # Must contain "Done" or "Ready"
        if [[ ! "$status_value" =~ "Done" ]] && [[ ! "$status_value" =~ "Ready" ]]; then
            return 1  # Not ready
        fi
    done

    return 0  # All components ready
}
