#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2022. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
CUR_DIR="${PARENT_DIR}"

REQUIRED_JAVA_MAJOR_VERSION=17

source ${PARENT_DIR}/helper/common.sh
source "${PARENT_DIR}/baw-storage-validation.sh"

# Override FNCM secret folder and file paths for migration to use content-cortex naming
FNCM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/content-cortex
FNCM_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-secret.yaml
FNCM_ICC_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-icc-secret.yaml
FNCM_ICCSAP_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-iccsap-secret.yaml
FNCM_IER_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-ier-secret.yaml
FNCM_DB_SSL_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-db-ssl-cert-secret.sh

# Override FNCM DB script folder for migration to use content-cortex naming
FNCM_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/content-cortex

function show_help() {
    echo -e "\nUsage: baw-case-prerequisites-migration.sh -m [modetype] -n [bawNamespace]\n"
    echo "Options:"
    echo "  -h  Display help"
    echo "  -m  The valid mode types are: [property], [generate], or [validate]"
    echo "  -n  The target namespace of the IBM Business Automation Workflow deployment."
    echo "      STEP1: Run the script in [property] mode. It creates property files (DB/LDAP property file) with default values (database name/user)."
    echo "      STEP2: Modify the DB/LDAP/user property files with your values."
    echo "      STEP3: Run the script in [generate] mode. Generates the DB SQL statement files and YAML templates for the secrets based on the values in the property files."
    echo "      STEP4: Create the databases and secrets by using the modified DB SQL statement files and YAML templates for the secrets."
    echo "      STEP5: Run the script in [validate] mode. Checks whether the databases and the secrets are created before you install BAW."
    echo "  --update-components"
    echo "      Updates optional components in an existing installation, then regenerates property files with the new configuration."
    echo "      Prerequisites:"
    echo "        - Active deployment in the namespace specified with \"-n\"."
    echo "        - Original property files must be available."
    echo "        - Must be used exclusively with \"-m property\" mode."
}

function parse_arguments() {
    while [[ "$@" != "" ]]; do
        case "$1" in
        -m)
            shift
            if [ -z "$1" ]; then
                echo "Invalid option: -m requires an argument"
                exit 1
            fi
            RUNTIME_MODE=$1
            if [[ $RUNTIME_MODE != "property" && $RUNTIME_MODE != "generate" && $RUNTIME_MODE != "validate" ]]; then
                msg "Use a valid value: -m [property] or [generate] or [validate]"
                exit 1
            fi
            ;;
        -n)
            shift
            if [ -z "$1" ]; then
                echo "Invalid option: -n requires an argument"
                exit 1
            fi
            TARGET_PROJECT_NAME=$1
            check_cluster_login
            isProjExists=`kubectl get namespace $TARGET_PROJECT_NAME --ignore-not-found | wc -l`  >/dev/null 2>&1
            if [ $isProjExists -ne 2 ] ; then
                echo -e "\x1B[1;31mInvalid namespace \"$TARGET_PROJECT_NAME\", please set a existing project name.\x1B[0m"
                exit 1
            fi
            ;;
        -h | --help | \?)
            show_help
            exit 0
            ;;
        --update-components)
            UPDATE_COMPONENTS="true"
            ;;
        *)
            echo "Invalid option"
            show_help
            exit 1
            ;;
        esac
        shift
    done
}

parse_arguments "$@"
if [[ -z "$RUNTIME_MODE" || -z "$TARGET_PROJECT_NAME" ]]; then
    show_help
    exit 1
fi

save_log "baw-script-logs/project/$TARGET_PROJECT_NAME" "baw-prerequisites-log"
trap cleanup_log EXIT
IBM_LICENS="Accept"
INSTALL_BAW_ONLY="No"

source ${PARENT_DIR}/helper/common.sh $TARGET_PROJECT_NAME
source ${PARENT_DIR}/helper/cp4a-verification.sh
source ${PARENT_DIR}/helper/cp4ba-property.sh
source ${PARENT_DIR}/helper/cp4ba-secret.sh
source ${PARENT_DIR}/helper/upgrade/upgrade_check_status.sh
source ${PARENT_DIR}/helper/update-selected-components/update-selected-components.sh

JDBC_DRIVER_DIR=${PARENT_DIR}/jdbc
MIG_ANS="No"
TOS_NUM=1
CASE_MIGRATION_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_case_migration.property
CP4A_PATTERN_FILE_BAK_TEMP=$FINAL_CR_FOLDER/.ibm_cp4a_cr_final_temp.yaml
CP4A_PATTERN_FILE_BAK_TEMP_JSON=$FINAL_CR_FOLDER/.ibm_cp4a_cr_final_temp.json

function cleanup_on_error() {
    if [[ -f "$CP4A_PATTERN_FILE_BAK_TEMP" ]]; then rm -f "$CP4A_PATTERN_FILE_BAK_TEMP"; fi
    if [[ -f "$CP4A_PATTERN_FILE_BAK_TEMP_JSON" ]]; then rm -f "$CP4A_PATTERN_FILE_BAK_TEMP_JSON"; fi
}
trap cleanup_on_error EXIT ERR

function preserve_existing_case_migration_property_file() {
    local existing_case_property_file=$1
    if [[ ! -f "$existing_case_property_file" ]]; then return 0; fi
    info "Preserving existing values from migration property file: $existing_case_property_file"
    if ! ${YQ_CMD} validate "$existing_case_property_file" >/dev/null 2>&1; then return 1; fi
    if ! grep -q "case:" "$existing_case_property_file" >/dev/null 2>&1; then return 1; fi
    cp "$existing_case_property_file" "${CASE_MIGRATION_PROPERTY_FILE}.bak" >/dev/null 2>&1
    local existing_tos_num
    existing_tos_num=$(${YQ_CMD} r "$existing_case_property_file" "case.tos_list" 2>/dev/null | grep -c "object_store_name" || echo "0")
    if [[ -n "$existing_tos_num" && "$existing_tos_num" -ge 1 ]]; then
        TOS_NUM="$existing_tos_num"
        ${SED_COMMAND} '/^TOS_NUM=/d' ${TEMPORARY_PROPERTY_FILE}
        echo "TOS_NUM=$TOS_NUM" >> ${TEMPORARY_PROPERTY_FILE}
    fi
    cp "$existing_case_property_file" "$CASE_MIGRATION_PROPERTY_FILE"
    return 0
}

if [[ "$UPDATE_COMPONENTS" == "true" && "$RUNTIME_MODE" != "property" ]]; then
    error "The --update-components flag can only be used with -m property mode"
    exit 1
fi

function read_tos_num() {
    printf "\x1B[1mProvide Number of Target Object Stores \x1B[0m \x1B[33m[Minimum 1] \x1B[0m :"
    read -rp "" TOS_NUM
    if ! [[ "$TOS_NUM" =~ ^[1-9][0-9]*$ ]]; then
        error "Invalid value \"$TOS_NUM\" for Number of Target Object Stores. Must be a positive integer (minimum 1)."
        exit 1
    fi
}

function create_case_migration_property_file() {
    echo "TOS_NUM=$TOS_NUM" >> ${TEMPORARY_PROPERTY_FILE}
    local MIG_PROP_TEMP="<Required>"
    touch ${CASE_MIGRATION_PROPERTY_FILE}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_type" --style=double $DB_TYPE
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_common_icn_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_servername" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_name" --style=double "ICNDB"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_port" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_username" --style=double "ICNDB"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_icn_datasource.dc_icn_database_password" --style=double ${MIG_PROP_TEMP}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_type" --style=double $DB_TYPE
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_common_gcd_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_common_gcd_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_servername" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_name" --style=double "GCDDB"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_port" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_username" --style=double "GCDDB"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_password" --style=double ${MIG_PROP_TEMP}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_type" --style=double $DB_TYPE
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_os_label" --style=double "BAWDOCS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_common_os_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_common_os_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_servername" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_name" --style=double "BAWDOCS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_port" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_username" --style=double "BAWDOCS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[0].dc_bawdocs_database_password" --style=double ${MIG_PROP_TEMP}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_type" --style=double $DB_TYPE
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_os_label" --style=double "BAWDOS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_common_os_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_common_os_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_servername" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_name" --style=double "BAWDOS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_port" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_username" --style=double "BAWDOS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[1].dc_bawdos_database_password" --style=double ${MIG_PROP_TEMP}

    for ((i=2;i<$TOS_NUM+2;i++)); do
        if [[ $TOS_NUM -gt 1 ]]; then
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_type" --style=double $DB_TYPE
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_os_label" --style=double "BAWTOS$((i-1))"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_common_os_datasource_name" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_common_os_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_servername" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_name" --style=double "BAWTOS$((i-1))"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_port" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_username" --style=double "BAWTOS$((i-1))"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_password" --style=double ${MIG_PROP_TEMP}
        else
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_type" --style=double $DB_TYPE
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_os_label" --style=double "BAWTOS"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_common_os_datasource_name" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_common_os_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_servername" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_name" --style=double "BAWTOS"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_port" --style=double ${MIG_PROP_TEMP}
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_username" --style=double "BAWTOS"
            ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_password" --style=double ${MIG_PROP_TEMP}
        fi
    done

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_type" --style=double $DB_TYPE
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_os_label" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_xa_datasource_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_servername" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_port" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_username" --style=double "CHOS"
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_database_password" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_cpe_datasources[0].dc_common_conn_name" --style=double ${MIG_PROP_TEMP}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "navigator_configuration.icn_production_setting.icn_jndids_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "navigator_configuration.icn_production_setting.icn_schema" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "navigator_configuration.icn_production_setting.icn_table_space" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "navigator_configuration.icn_production_setting.icn_admin" --style=double ${MIG_PROP_TEMP}

    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "content_integration.domain_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "content_integration.object_store_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.domain_name" --style=double ${MIG_PROP_TEMP}
    ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.object_store_name_dos" --style=double ${MIG_PROP_TEMP}
    for ((i=0;i<$TOS_NUM;i++)); do
        ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list[$i].object_store_name" --style=double ${MIG_PROP_TEMP}
        ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list[$i].connection_point_name" --style=double ${MIG_PROP_TEMP}
        ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list[$i].desktop_id" --style=double ${MIG_PROP_TEMP}
        ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list[$i].target_environment_name" --style=double ${MIG_PROP_TEMP}
        ${YQ_CMD} w -i ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list[$i].is_default" ${MIG_PROP_TEMP}
    done
    info "Migration property file created: $CASE_MIGRATION_PROPERTY_FILE"
}

function resolve_case_migration_property_file() {
    local resolved_case_file
    resolved_case_file="$(prop_tmp_property_file CASE_MIGRATION_PROPERTY_FILE)"
    if [[ -z "$resolved_case_file" ]]; then
        resolved_case_file="${PROPERTY_FILE_FOLDER}/baw_case_migration.property"
    fi
    CASE_MIGRATION_PROPERTY_FILE="$resolved_case_file"
}

function create_secret_multi_tos() {
    local tmp_gcd_db_servername=""
    local tmp_dbname=""
    local tmp_appuser=""
    local tmp_apppwd=""
    local tmp_ltpapwd=""
    local tmp_kestorepwd=""
    local tmp_dbuser=""
    local tmp_dbuserpwd=""
    local tmp_os_db_servername=""
    local tmp_flag=""
    local tmp_postgresql_client_flag=""
    local tmp_val=""
    local pattern_list=""
    local option_component_list=""
    local content_os_number=0

    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
    option_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
    content_os_number="$(prop_tmp_property_file CONTENT_OS_NUMBER)"
    if [[ -z "$content_os_number" ]]; then
        content_os_number=0
    fi

    optional_component_cr_arr=()
    if [[ "$option_component_list" == *"ae_data_persistence"* ]]; then
        optional_component_cr_arr=("ae_data_persistence")
    fi

    pattern_cr_arr=()
    if [[ -n "$pattern_list" ]]; then
        IFS=',' read -r -a pattern_cr_arr <<< "$pattern_list"
    fi

    wait_msg "Creating ibm-fncm-secret secret YAML template for BAW migration (content-cortex)"

    tmp_gcd_db_servername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_servername")"
    tmp_gcd_db_servername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_gcd_db_servername")
    create_fncm_secret_template "$tmp_gcd_db_servername"

    tmp_appuser="$(prop_user_profile_property_file CONTENT.APPLOGIN_USER)"
    tmp_apppwd="$(prop_user_profile_property_file CONTENT.APPLOGIN_PASSWORD)"
    ${YQ_CMD} w -i "${FNCM_SECRET_FILE}" "stringData.appLoginUsername" "$tmp_appuser"
    update_secret_template_passwords "$tmp_apppwd" "appLoginPassword" "$FNCM_SECRET_FILE"

    tmp_ltpapwd="$(prop_user_profile_property_file CONTENT.LTPA_PASSWORD)"
    tmp_kestorepwd="$(prop_user_profile_property_file CONTENT.KEYSTORE_PASSWORD)"
    update_secret_template_passwords "$tmp_ltpapwd" "ltpaPassword" "$FNCM_SECRET_FILE"
    update_secret_template_passwords "$tmp_kestorepwd" "keystorePassword" "$FNCM_SECRET_FILE"

    tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_username")"
    ${YQ_CMD} w -i "${FNCM_SECRET_FILE}" "stringData.gcdDBUsername" "$tmp_dbuser"
    tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_password")"
    update_secret_template_passwords "$tmp_dbuserpwd" "gcdDBPassword" "$FNCM_SECRET_FILE"

    # Use the actual OS label value (e.g. DOCS, DOS, TOS1) as the secret key prefix
    local tmp_os_label=""
    for ((i=0;i<TOS_NUM+2;i++)); do
        if [[ $i -eq 0 ]]; then
            tmp_os_label="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdocs_os_label")"
            tmp_os_label=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_os_label")
            tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdocs_database_username")"
            tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdocs_database_password")"
        elif [[ $i -eq 1 ]]; then
            tmp_os_label="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdos_os_label")"
            tmp_os_label=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_os_label")
            tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdos_database_username")"
            tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawdos_database_password")"
        else
            if [[ $TOS_NUM -gt 1 ]]; then
                tmp_os_label="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_os_label")"
                tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_username")"
                tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos$((i-1))_database_password")"
            else
                tmp_os_label="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos_os_label")"
                tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_username")"
                tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$i].dc_bawtos_database_password")"
            fi
            tmp_os_label=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_os_label")
        fi
        tmp_val="${tmp_os_label}"
        ${YQ_CMD} w -i "${FNCM_SECRET_FILE}" "stringData.${tmp_val}DBUsername" "$tmp_dbuser"
        update_secret_template_passwords "$tmp_dbuserpwd" "osDBPassword" "$FNCM_SECRET_FILE" "${tmp_val}DBPassword"
    done

    if [[ "${optional_component_cr_arr[@]}" =~ "ae_data_persistence" ]]; then
        tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$((TOS_NUM+2))].dc_aeos_database_username")"
        tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$((TOS_NUM+2))].dc_aeos_database_password")"
        ${YQ_CMD} w -i "${FNCM_SECRET_FILE}" "stringData.aeosDBUsername" "$tmp_dbuser"
        update_secret_template_passwords "$tmp_dbuserpwd" "osDBPassword" "$FNCM_SECRET_FILE" "aeosDBPassword"
    fi

    tmp_dbuser="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_username")"
    tmp_dbuserpwd="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_password")"
    ${YQ_CMD} w -i "${FNCM_SECRET_FILE}" "stringData.chDBUsername" "$tmp_dbuser"
    update_secret_template_passwords "$tmp_dbuserpwd" "osDBPassword" "$FNCM_SECRET_FILE" "chDBPassword"

    ${SED_COMMAND} '/^  osDBUsername/d' ${FNCM_SECRET_FILE}
    ${SED_COMMAND} '/^  osDBPassword/d' ${FNCM_SECRET_FILE}

    success "ibm-fncm-secret secret YAML template for BAW migration has been created at: ${FNCM_SECRET_FILE}\n"
}

function load_case_migrate_property_before_generate() {
    resolve_case_migration_property_file
    if [[ ! -f "$CASE_MIGRATION_PROPERTY_FILE" ]]; then
        return
    fi
    TOS_NUM=$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "case.tos_list" 2>/dev/null | grep -c "object_store_name" || echo "0")
}

function validate_case_migrate_prerequisites() {
    if [[ ! -f "$CASE_MIGRATION_PROPERTY_FILE" ]]; then
        error "Migration property file not found: ${CASE_MIGRATION_PROPERTY_FILE}"
        exit 1
    fi
}

# Validation function: Check utility tools
function validate_migration_utility_tools() {
    which kubectl &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Unable to locate Kubernetes CLI. Kubernetes CLI must be installed to run this script."
        exit 1
    fi
    
    # Check Java
    JAVA_PATH="${CUSTOM_JAVA_PATH:-$JAVA_HOME}"
    validate_java_runtime "$JAVA_PATH"
    
    which openssl &>/dev/null
    if [[ $? -ne 0 ]]; then
        error "Unable to locate openssl. OpenSSL must be installed to run this script."
        exit 1
    fi
}

# Validation function: Check storage classes
function validate_migration_storage_classes() {
    INFO "Checking Slow/Medium/Fast/Block storage class required by BAW"
    
    local tmp_storage_classname=$(prop_user_profile_property_file CP4BA.SLOW_FILE_STORAGE_CLASSNAME)
    local sample_pvc_name="cp4ba-test-slow-pvc-$RANDOM"
    verify_storage_class_valid "$tmp_storage_classname" "ReadWriteMany" "$sample_pvc_name" "$TARGET_PROJECT_NAME"

    tmp_storage_classname=$(prop_user_profile_property_file CP4BA.MEDIUM_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="cp4ba-test-medium-pvc-$RANDOM"
    verify_storage_class_valid "$tmp_storage_classname" "ReadWriteMany" "$sample_pvc_name" "$TARGET_PROJECT_NAME"

    tmp_storage_classname=$(prop_user_profile_property_file CP4BA.FAST_FILE_STORAGE_CLASSNAME)
    sample_pvc_name="cp4ba-test-fast-pvc-$RANDOM"
    verify_storage_class_valid "$tmp_storage_classname" "ReadWriteMany" "$sample_pvc_name" "$TARGET_PROJECT_NAME"

    tmp_storage_classname=$(prop_user_profile_property_file CP4BA.BLOCK_STORAGE_CLASS_NAME)
    sample_pvc_name="cp4ba-test-block-pvc-$RANDOM"
    verify_storage_class_valid "$tmp_storage_classname" "ReadWriteOnce" "$sample_pvc_name" "$TARGET_PROJECT_NAME"

    if [[ $verification_sc_passed == "No" ]]; then
        kubectl delete pvc -l cp4ba=test-only >/dev/null 2>&1
        exit 0
    fi
}

# Validation function: Check secrets in cluster
function validate_migration_secrets() {
    INFO "Checking the Kubernetes secret required by Business Automation Workflow existing in cluster or not"
    
    local secret_name=""
    local secret_list=("ldap-bind-secret" "ibm-fncm-secret" "ibm-icc-secret" "ibm-ban-secret" "ibm-workflow-assistant-secrets" "ibm-baw-wfs-server-db-secret")
    
    for secret_name in "${secret_list[@]}"; do
        if kubectl get secret -n "$CP4BA_SERVICES_NS" -l name=$secret_name >/dev/null 2>&1; then
            success "Secret \"$secret_name\" found in Kubernetes cluster, PASSED!"
        else
            fail "Secret \"$secret_name\" not found in Kubernetes cluster. Please create it before proceeding."
        fi
    done
    
    # Check ConfigMaps and Secrets for external PostgreSQL databases (IM, ZEN, BTS)
    local tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        if kubectl get configmap -n "$CP4BA_SERVICES_NS" im-datastore-edb-cm >/dev/null 2>&1; then
            success "ConfigMap \"im-datastore-edb-cm\" found in Kubernetes cluster, PASSED!"
        else
            fail "ConfigMap \"im-datastore-edb-cm\" not found in Kubernetes cluster. Please create it before proceeding."
        fi
        if kubectl get secret -n "$CP4BA_SERVICES_NS" im-datastore-edb-secret >/dev/null 2>&1; then
            success "Secret \"im-datastore-edb-secret\" found in Kubernetes cluster, PASSED!"
        else
            fail "Secret \"im-datastore-edb-secret\" not found in Kubernetes cluster. Please create it before proceeding."
        fi
    fi
    
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        if kubectl get configmap -n "$CP4BA_SERVICES_NS" ibm-zen-metastore-edb-cm >/dev/null 2>&1; then
            success "ConfigMap \"ibm-zen-metastore-edb-cm\" found in Kubernetes cluster, PASSED!"
        else
            fail "ConfigMap \"ibm-zen-metastore-edb-cm\" not found in Kubernetes cluster. Please create it before proceeding."
        fi
        if kubectl get secret -n "$CP4BA_SERVICES_NS" ibm-zen-metastore-edb-secret >/dev/null 2>&1; then
            success "Secret \"ibm-zen-metastore-edb-secret\" found in Kubernetes cluster, PASSED!"
        else
            fail "Secret \"ibm-zen-metastore-edb-secret\" not found in Kubernetes cluster. Please create it before proceeding."
        fi
    fi
    
    # Check BTS external PostgreSQL database support
    local EXTERNAL_POSTGRESDB_FOR_BTS=$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS)
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS == "true" ]]; then
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
            if kubectl get configmap -n "$CP4BA_SERVICES_NS" ibm-bts-config-extension >/dev/null 2>&1; then
                success "ConfigMap \"ibm-bts-config-extension\" found in Kubernetes cluster, PASSED!"
            else
                fail "ConfigMap \"ibm-bts-config-extension\" not found in Kubernetes cluster. Please create it before proceeding."
            fi
            if kubectl get secret -n "$CP4BA_SERVICES_NS" bts-datastore-edb-secret >/dev/null 2>&1; then
                success "Secret \"bts-datastore-edb-secret\" found in Kubernetes cluster, PASSED!"
            else
                fail "Secret \"bts-datastore-edb-secret\" not found in Kubernetes cluster. Please create it before proceeding."
            fi
        fi
    fi
    
    success "All secrets created in Kubernetes cluster, PASSED!"
}

# Validation function: Check LDAP connection
function validate_migration_ldap_connection() {
    INFO "Checking LDAP connection required by BAW"
    
    local tmp_servername="$(prop_ldap_property_file LDAP_SERVER)"
    local tmp_serverport="$(prop_ldap_property_file LDAP_PORT)"
    local tmp_basdn="$(prop_ldap_property_file LDAP_BASE_DN)"
    local tmp_ldapssl="$(prop_ldap_property_file LDAP_SSL_ENABLED)"
    local tmp_user=$( $CLI_CMD get secret -n "$CP4BA_SERVICES_NS" -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].data.ldapUsername | base64 --decode )
    local cp4a_operator=$( $CLI_CMD get pods -l name=ibm-cp4a-operator --no-headers --ignore-not-found -n $TARGET_PROJECT_NAME | awk '{print $1}' )
    local tmp_userpwd=$( $CLI_CMD get secret -n "$CP4BA_SERVICES_NS" -l name=ldap-bind-secret -o yaml | ${YQ_CMD} r - items.[0].data.ldapPassword | base64 --decode )
    
    if [[ "$tmp_userpwd" =~ "{xor}" ]]; then
        tmp_userpwd=$(decode_xor_password $tmp_userpwd $cp4ba_operators_namespace $cp4a_operator)
    fi

    tmp_servername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_servername")
    tmp_serverport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_serverport")
    tmp_basdn=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_basdn")
    tmp_ldapssl=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_ldapssl")
    tmp_ldapssl=$(echo $tmp_ldapssl | tr '[:upper:]' '[:lower:]')
    tmp_user=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_user")
    tmp_userpwd=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_userpwd")

    # Process LDAP validation parameters
    ldap_validation_parameter_generator
    local tmp_ldap_group_basedn=${ldap_details[0]}
    local tmp_ldap_user_filter=${ldap_details[1]}
    local tmp_ldap_group_filter=${ldap_details[2]}
    local tmp_ldap_user_password_list=${ldap_details[3]}
    local tmp_ldap_group_list=${ldap_details[4]}

    verify_ldap_connection "$tmp_servername" "$tmp_serverport" "$tmp_basdn" "$tmp_user" "$tmp_userpwd" "$tmp_ldapssl" "$tmp_ldap_group_basedn" "$tmp_ldap_user_filter" "$tmp_ldap_group_filter" "$tmp_ldap_user_password_list" "$tmp_ldap_group_list"
}

function verify_migration_db_connection() {
    local dbserver=$1
    local dbport=$2
    local dbname=$3
    local dbuser=$4
    local dbuserpwd=$5
    local DB_JDBC_NAME=${JDBC_DRIVER_DIR}/$DB_TYPE
    local DB_CONNECTION_JAR_PATH=${CUR_DIR}/helper/verification/$DB_TYPE
    
    if [[ $DB_TYPE == "oracle" ]]; then
        printf "\n"
        info "Checking connection for $DB_TYPE database \"${dbuser}\" on server \"${dbserver}:${dbport}\"...."
        
        local oracle_url="jdbc:oracle:thin:@//${dbserver}:${dbport}/${dbname}"
        local output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar" OracleConnection -url "$oracle_url" -u $dbuser -pwd $dbuserpwd 2>&1)
        local retVal=$?
        
        [[ $retVal -ne 0 ]] && \
        warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/ojdbc8.jar:${DB_CONNECTION_JAR_PATH}/OracleJDBCConnection.jar\" OracleConnection -url \"$oracle_url\" -u $dbuser -pwd ******" && \
        fail "Unable to connect to database \"$dbuser\" using JDBC URL \"$oracle_url\", please check configuration again."
        [[ $retVal -eq 0 ]] && \
        success "Checked DB connection for \"$dbuser\" using JDBC URL \"$oracle_url\", PASSED!"
    else
        printf "\n"
        info "Checking connection for $DB_TYPE database \"${dbname}\" on server \"${dbserver}:${dbport}\"...."
        
        case $DB_TYPE in
            "db2")
                local output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd 2>&1)
                local retVal=$?
                [[ $retVal -ne 0 ]] && \
                warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/db2jcc4.jar:${DB_CONNECTION_JAR_PATH}/DB2JDBCConnection.jar\" DB2Connection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ******" && \
                fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
                [[ $retVal -eq 0 ]] && \
                success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
                ;;
            "sqlserver"|"azuresqlmi")
                local output=$(java -Duser.language=en -Duser.country=US -cp "${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd $dbuserpwd -ssl 'encrypt=false' 2>&1)
                local retVal=$?
                [[ $retVal -ne 0 ]] && \
                warning "Execute: java -Duser.language=en -Duser.country=US -cp \"${DB_JDBC_NAME}/mssql-jdbc.jre11.jar:${DB_CONNECTION_JAR_PATH}/SQLJDBCConnection.jar\" SQLConnection -h $dbserver -p $dbport -d $dbname -u $dbuser -pwd ****** -ssl 'encrypt=false'" && \
                fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
                [[ $retVal -eq 0 ]] && \
                success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
                ;;
            "postgresql")
                local output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode disable 2>&1)
                local retVal=$?
                [[ $retVal -ne 0 ]] && \
                warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode disable" && \
                fail "Unable to connect to database \"$dbname\" on database host server \"$dbserver\", please check configuration again."
                [[ $retVal -eq 0 ]] && \
                success "Checked DB connection for \"$dbname\" on database host server \"$dbserver\", PASSED!"
                ;;
        esac
    fi
}

function validate_case_migration_db_connections() {
    local tmp_dbserver=""
    local tmp_dbport=""
    local tmp_dbname=""
    local tmp_dbusername=""
    local tmp_dbuserpassword=""
    local tmp_secret_name=""
    local tmp_dbprop_prefix=""
    local tos_idx=0
    local tos_secret_suffix=""
    local os_yaml_idx=0
    local optional_component_cr_arr=()

    # Read DB_TYPE from migration property file
    DB_TYPE="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_type")"
    DB_TYPE=$(sed -e 's/^"//' -e 's/"$//' <<<"$DB_TYPE")
    
    if [[ $DB_TYPE == "postgresql-edb" ]]; then
        return
    fi

    INFO "Checking DB connection required by Business Automation Workflow migration"

    # Validate ICNDB connection
    tmp_dbserver="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_servername")"
    tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
    tmp_dbport="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_port")"
    tmp_dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbport")
    tmp_dbname="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_name")"
    tmp_dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbname")
    tmp_dbusername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_username")"
    tmp_dbusername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbusername")
    tmp_dbuserpassword="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_icn_datasource.dc_icn_database_password")"
    tmp_dbuserpassword=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbuserpassword")
    verify_migration_db_connection "${tmp_dbserver}" "${tmp_dbport}" "${tmp_dbname}" "${tmp_dbusername}" "${tmp_dbuserpassword}"

    # Validate GCDDB connection
    tmp_dbserver="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_servername")"
    tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
    tmp_dbport="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_port")"
    tmp_dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbport")
    tmp_dbname="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_name")"
    tmp_dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbname")
    tmp_dbusername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_username")"
    tmp_dbusername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbusername")
    tmp_dbuserpassword="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_gcd_datasource.dc_gcd_database_password")"
    tmp_dbuserpassword=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbuserpassword")
    verify_migration_db_connection "${tmp_dbserver}" "${tmp_dbport}" "${tmp_dbname}" "${tmp_dbusername}" "${tmp_dbuserpassword}"

    # Validate BAWDOCS and BAWDOS connections
    for os_yaml_idx in 0 1; do
        if [[ $os_yaml_idx -eq 0 ]]; then
            tmp_secret_name="bawdocs"
            tmp_dbprop_prefix="dc_bawdocs"
        else
            tmp_secret_name="bawdos"
            tmp_dbprop_prefix="dc_bawdos"
        fi

        tmp_dbserver="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_servername")"
        tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
        tmp_dbport="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_port")"
        tmp_dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbport")
        tmp_dbname="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_name")"
        tmp_dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbname")
        tmp_dbusername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_username")"
        tmp_dbusername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbusername")
        tmp_dbuserpassword="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_password")"
        tmp_dbuserpassword=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbuserpassword")
        verify_migration_db_connection "${tmp_dbserver}" "${tmp_dbport}" "${tmp_dbname}" "${tmp_dbusername}" "${tmp_dbuserpassword}"
    done

    # Validate TOS connections
    for ((tos_idx=0; tos_idx<TOS_NUM; tos_idx++)); do
        os_yaml_idx=$((tos_idx + 2))
        if [[ $TOS_NUM -gt 1 ]]; then
            tos_secret_suffix="bawtos$((tos_idx + 1))"
            tmp_dbprop_prefix="dc_bawtos$((tos_idx + 1))"
        else
            tos_secret_suffix="bawtos"
            tmp_dbprop_prefix="dc_bawtos"
        fi

        tmp_dbserver="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_servername")"
        tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
        tmp_dbport="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_port")"
        tmp_dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbport")
        tmp_dbname="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_name")"
        tmp_dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbname")
        tmp_dbusername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_username")"
        tmp_dbusername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbusername")
        tmp_dbuserpassword="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_os_datasources[$os_yaml_idx].${tmp_dbprop_prefix}_database_password")"
        tmp_dbuserpassword=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbuserpassword")
        verify_migration_db_connection "${tmp_dbserver}" "${tmp_dbport}" "${tmp_dbname}" "${tmp_dbusername}" "${tmp_dbuserpassword}"
    done

    # Validate CHOS connection
    tmp_dbserver="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_servername")"
    tmp_dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbserver")
    tmp_dbport="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_port")"
    tmp_dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbport")
    tmp_dbname="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_name")"
    tmp_dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbname")
    tmp_dbusername="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_username")"
    tmp_dbusername=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbusername")
    tmp_dbuserpassword="$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "datasource_configuration.dc_cpe_datasources[0].dc_database_password")"
    tmp_dbuserpassword=$(sed -e 's/^"//' -e 's/"$//' <<<"$tmp_dbuserpassword")
    verify_migration_db_connection "${tmp_dbserver}" "${tmp_dbport}" "${tmp_dbname}" "${tmp_dbusername}" "${tmp_dbuserpassword}"
}

function validate_external_postgres_databases() {
    local DB_JDBC_NAME=${JDBC_DRIVER_DIR}/postgresql
    local DB_CONNECTION_JAR_PATH=${CUR_DIR}/helper/verification/postgresql
    
    # Validate IM metastore external Postgres DB
    local tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_IM_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        printf "\n"
        INFO "Validating IM metastore external PostgreSQL database connection"
        local im_external_db_cert_folder="$(prop_user_profile_property_file CP4BA.IM_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        im_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$im_external_db_cert_folder")
        
        local dbserver="$(prop_user_profile_property_file CP4BA.IM_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
        local dbport="$(prop_user_profile_property_file CP4BA.IM_EXTERNAL_POSTGRES_DATABASE_PORT)"
        dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
        local dbname="$(prop_user_profile_property_file CP4BA.IM_EXTERNAL_POSTGRES_DATABASE_NAME)"
        dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
        local dbuser="$(prop_user_profile_property_file CP4BA.IM_EXTERNAL_POSTGRES_DATABASE_USER)"
        dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
        local dbuserpwd="changit"
        
        info "Checking connection for IM metastore external Postgres database \"${dbname}\" on database instance \"${dbserver}:${dbport}\"...."
        
        local postgres_cafile="${im_external_db_cert_folder}/root.crt"
        local postgres_clientkeyfile="${im_external_db_cert_folder}/client.key"
        local postgres_clientcertfile="${im_external_db_cert_folder}/client.crt"
        
        rm -rf ${im_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
        openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${im_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null
        
        local output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        local retVal=$?
        
        [[ $retVal -ne 0 ]] && \
        warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${im_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to IM metastore database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
        [[ $retVal -eq 0 ]] && \
        success "Checked IM metastore DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
    fi
    
    # Validate Zen metastore external Postgres DB
    tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_ZEN_FLAG)")
    tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
    if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
        printf "\n"
        INFO "Validating Zen metastore external PostgreSQL database connection"
        local zen_external_db_cert_folder="$(prop_user_profile_property_file CP4BA.ZEN_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
        zen_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$zen_external_db_cert_folder")
        
        local dbserver="$(prop_user_profile_property_file CP4BA.ZEN_EXTERNAL_POSTGRES_DATABASE_RW_ENDPOINT)"
        dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
        local dbport="$(prop_user_profile_property_file CP4BA.ZEN_EXTERNAL_POSTGRES_DATABASE_PORT)"
        dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
        local dbname="$(prop_user_profile_property_file CP4BA.ZEN_EXTERNAL_POSTGRES_DATABASE_NAME)"
        dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
        local dbuser="$(prop_user_profile_property_file CP4BA.ZEN_EXTERNAL_POSTGRES_DATABASE_USER)"
        dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
        local dbuserpwd="changit"
        
        info "Checking connection for Zen metastore external Postgres database \"${dbname}\" on database instance \"${dbserver}:${dbport}\"...."
        
        local postgres_cafile="${zen_external_db_cert_folder}/root.crt"
        local postgres_clientkeyfile="${zen_external_db_cert_folder}/client.key"
        local postgres_clientcertfile="${zen_external_db_cert_folder}/client.crt"
        
        rm -rf ${zen_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
        openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${zen_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null
        
        local output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
        local retVal=$?
        
        [[ $retVal -ne 0 ]] && \
        warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${zen_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
        fail "Unable to connect to Zen metastore database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
        [[ $retVal -eq 0 ]] && \
        success "Checked Zen metastore DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
    fi
    
    # Validate BTS metastore external Postgres DB
    local EXTERNAL_POSTGRESDB_FOR_BTS=$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS)
    if [[ $EXTERNAL_POSTGRESDB_FOR_BTS == "true" ]]; then
        tmp_flag=$(sed -e 's/^"//' -e 's/"$//' <<<"$(prop_tmp_property_file EXTERNAL_POSTGRESDB_FOR_BTS_FLAG)")
        tmp_flag=$(echo $tmp_flag | tr '[:upper:]' '[:lower:]')
        if [[ $tmp_flag == "true" || $tmp_flag == "yes" || $tmp_flag == "y" ]]; then
            printf "\n"
            INFO "Validating BTS metastore external PostgreSQL database connection"
            local bts_external_db_cert_folder="$(prop_user_profile_property_file CP4BA.BTS_EXTERNAL_POSTGRES_DATABASE_SSL_CERT_FILE_FOLDER)"
            bts_external_db_cert_folder=$(sed -e 's/^"//' -e 's/"$//' <<<"$bts_external_db_cert_folder")
            
            local dbserver="$(prop_user_profile_property_file CP4BA.BTS_EXTERNAL_POSTGRES_DATABASE_HOSTNAME)"
            dbserver=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbserver")
            local dbport="$(prop_user_profile_property_file CP4BA.BTS_EXTERNAL_POSTGRES_DATABASE_PORT)"
            dbport=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbport")
            local dbname="$(prop_user_profile_property_file CP4BA.BTS_EXTERNAL_POSTGRES_DATABASE_NAME)"
            dbname=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbname")
            local dbuser="$(prop_user_profile_property_file CP4BA.BTS_EXTERNAL_POSTGRES_DATABASE_USER_NAME)"
            dbuser=$(sed -e 's/^"//' -e 's/"$//' <<<"$dbuser")
            local dbuserpwd="changit"
            
            info "Checking connection for BTS metastore external Postgres database \"${dbname}\" on database instance \"${dbserver}:${dbport}\"...."
            
            local postgres_cafile="${bts_external_db_cert_folder}/root.crt"
            local postgres_clientkeyfile="${bts_external_db_cert_folder}/client.key"
            local postgres_clientcertfile="${bts_external_db_cert_folder}/client.crt"
            
            rm -rf ${bts_external_db_cert_folder}/clientkey.pk8 2>&1 </dev/null
            openssl pkcs8 -topk8 -outform DER -in $postgres_clientkeyfile -out ${bts_external_db_cert_folder}/clientkey.pk8 -nocrypt 2>&1 </dev/null
            
            local output=$(java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp "${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd $dbuserpwd -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile 2>&1)
            local retVal=$?
            
            [[ $retVal -ne 0 ]] && \
            warning "Execute: java -Duser.language=en -Duser.country=US -Dcom.ibm.jsse2.overrideDefaultTLS=true -Djavax.net.ssl.trustStoreType=PKCS12 -cp \"${DB_JDBC_NAME}/postgresql-42.7.2.jar:${DB_CONNECTION_JAR_PATH}/PostgresJDBCConnection.jar\" PostgresConnection -h $dbserver -p $dbport -db $dbname -u $dbuser -pwd ****** -sslmode verify-ca -ca $postgres_cafile -clientkey ${bts_external_db_cert_folder}/clientkey.pk8 -clientcert $postgres_clientcertfile" && \
            fail "Unable to connect to BTS metastore database \"$dbname\" on database server \"$dbserver\", please check the configuration again."
            [[ $retVal -eq 0 ]] && \
            success "Checked BTS metastore DB connection for \"$dbname\" on database server \"$dbserver\", PASSED!"
        fi
    fi
}

if [[ $RUNTIME_MODE == "property" ]]; then
    source ${PARENT_DIR}/baw-prerequisites.sh
    echo "TARGET_PROJECT_NAME=$TARGET_PROJECT_NAME" >> ${TEMPORARY_PROPERTY_FILE}
    CASE_MIGRATION_PROPERTY_FILE=$PROPERTY_FILE_FOLDER/baw_case_migration.property
    echo "CASE_MIGRATION_PROPERTY_FILE=$CASE_MIGRATION_PROPERTY_FILE" >> ${TEMPORARY_PROPERTY_FILE}

    if [[ "$UPDATE_COMPONENTS" == "true" ]]; then
        retrieve_existing_property_files
        retrieve_current_custom_resource_file "$TARGET_PROJECT_NAME" "prerequisites_script"
        print_current_summary_table "$TARGET_PROJECT_NAME"
        update_property_files
    fi

    existing_case_property_file=""
    if [ -e "$CASE_MIGRATION_PROPERTY_FILE" ] ; then
        existing_case_property_file="${CASE_MIGRATION_PROPERTY_FILE}.existing"
        cp "$CASE_MIGRATION_PROPERTY_FILE" "$existing_case_property_file" >/dev/null 2>&1
        rm -rf "$CASE_MIGRATION_PROPERTY_FILE"
    fi

    if [[ -n "$existing_case_property_file" && -f "$existing_case_property_file" ]]; then
        if preserve_existing_case_migration_property_file "$existing_case_property_file"; then
            ${SED_COMMAND_FORMAT} ${CASE_MIGRATION_PROPERTY_FILE}
        else
            rm -f "$existing_case_property_file"
            read_tos_num
            create_case_migration_property_file
            ${SED_COMMAND_FORMAT} ${CASE_MIGRATION_PROPERTY_FILE}
        fi
    else
        read_tos_num
        create_case_migration_property_file
        ${SED_COMMAND_FORMAT} ${CASE_MIGRATION_PROPERTY_FILE}
    fi
elif [[ $RUNTIME_MODE == "generate" ]]; then
    source ${PARENT_DIR}/baw-prerequisites.sh
    source ${PARENT_DIR}/helper/common.sh $TARGET_PROJECT_NAME
    # Re-apply content-cortex overrides after common.sh resets FNCM paths to fncm
    FNCM_SECRET_FOLDER=${SECRET_FILE_FOLDER}/content-cortex
    FNCM_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-secret.yaml
    FNCM_ICC_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-icc-secret.yaml
    FNCM_ICCSAP_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-iccsap-secret.yaml
    FNCM_IER_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-ier-secret.yaml
    FNCM_DB_SSL_SECRET_FILE=${FNCM_SECRET_FOLDER}/ibm-content-cortex-db-ssl-cert-secret.sh
    FNCM_DB_SCRIPT_FOLDER=${DB_SCRIPT_FOLDER}/content-cortex
    resolve_case_migration_property_file
    if [[ ! -e "$CASE_MIGRATION_PROPERTY_FILE" ]]; then
        error "Migration property file not found: \"${CASE_MIGRATION_PROPERTY_FILE}\""
        exit 1
    fi
    if ! ${YQ_CMD} validate "$CASE_MIGRATION_PROPERTY_FILE" ; then
        error "Invalid Property File Syntax (YAML): \"${CASE_MIGRATION_PROPERTY_FILE}\""
        exit 1
    fi
    TOS_NUM=$(${YQ_CMD} r "$CASE_MIGRATION_PROPERTY_FILE" "case.tos_list" 2>/dev/null | grep -c "object_store_name" || echo "0")
    if [[ -z "$TOS_NUM" || "$TOS_NUM" -eq 0 ]]; then
        error "No Target Object Stores (TOS) defined in migration property file"
        exit 1
    fi
    create_secret_multi_tos
    # Remove the stale fncm/ folder written by baw-prerequisites.sh's create_prerequisites
    # so that generate_create_secret_script scans only content-cortex/ files
    rm -rf "${SECRET_FILE_FOLDER}/fncm"
    generate_create_secret_script
elif [[ $RUNTIME_MODE == "validate" ]]; then
    echo "************************************************************"
    echo "Validating prerequisites for BAW Case Migration"
    echo "************************************************************"
    
    # TARGET_PROJECT_NAME is already set from command-line arguments (-n parameter)
    # Helper scripts (common.sh, cp4a-verification.sh) are already sourced at lines 98-100
    
    # Run migration-specific validation
    resolve_case_migration_property_file
    check_cp4ba_separate_operand $TARGET_PROJECT_NAME
    validate_migration_utility_tools
    load_case_migrate_property_before_generate
    validate_case_migrate_prerequisites
    validate_migration_storage_classes
    validate_migration_secrets
    validate_migration_ldap_connection
    validate_case_migration_db_connections
    validate_external_postgres_databases
    storage_and_performance_validation_tests $TARGET_PROJECT_NAME
fi


 





