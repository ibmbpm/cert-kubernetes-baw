
#!/bin/bash
# set -x
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
CUR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PARENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

# FIXED: Corrected path references to use PARENT_DIR
# Import common utilities and environment variables
source ${PARENT_DIR}/helper/common.sh

# Import variables for property file
source ${PARENT_DIR}/helper/cp4ba-property.sh

# FIXED: Corrected path to baw-deployment.sh
source ${PARENT_DIR}/baw-deployment.sh

# Migration
pattern_name_list=""
MIG_ANS="No"
TOS_NUM=1
CASE_MIGRATION_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_case_migration.property
CP4A_PATTERN_FILE_BAK_TEMP=$FINAL_CR_FOLDER/.ibm_cp4a_cr_final_temp.yaml
CP4A_PATTERN_FILE_BAK_TEMP_JSON=$FINAL_CR_FOLDER/.ibm_cp4a_cr_final_temp.json

################################################################
# ADDED: Cleanup function for error handling
################################################################
function cleanup_on_error() {
    if [[ -f "$CP4A_PATTERN_FILE_BAK_TEMP" ]]; then
        rm -f "$CP4A_PATTERN_FILE_BAK_TEMP"
    fi
    if [[ -f "$CP4A_PATTERN_FILE_BAK_TEMP_JSON" ]]; then
        rm -f "$CP4A_PATTERN_FILE_BAK_TEMP_JSON"
    fi
}

# Set trap for cleanup on error
trap cleanup_on_error EXIT ERR

################################################################
# Migration 
# To replace parameters in cr file
################################################################
function case_migration_replace(){
    local param_in1=$1
    local param_out1=$2
    local param_q1=$3

    local MIG_PROP_TEMP=$(${YQ_CMD} r ${CASE_MIGRATION_PROPERTY_FILE} $param_in1)
    
    if [ "$param_q1" = "q" ] ;
    then 
        ${YQ_CMD} w -i ${CP4A_PATTERN_FILE_BAK_TEMP} $param_out1 --style=double "${MIG_PROP_TEMP}"
    else 
        ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} $param_out1 "${MIG_PROP_TEMP}" 
    fi
}

################################################################
# ENHANCED: Migration function with better error handling
# Begin - Modify the Generated CR for Migration
################################################################
function case_migration_apply_pattern_cr() {
    local os_num_cr=0
    local os_num_prop=0
    local initial_os_cr=0
    local content_os_number=0

    # ADDED: Validate prerequisites
    if [[ ! -f "$CP4A_PATTERN_FILE_BAK" ]]; then
        error "Generated CR file not found: $CP4A_PATTERN_FILE_BAK"
        error "Please run baw-deployment.sh first to generate the base CR"
        return 1
    fi
    
    if [[ ! -f "$CASE_MIGRATION_PROPERTY_FILE" ]]; then
        error "Migration property file not found: $CASE_MIGRATION_PROPERTY_FILE"
        error "Please run baw-case-prerequisites-migration.sh in property mode first"
        return 1
    fi

    if [ -e $CP4A_PATTERN_FILE_BAK ] ; 
    then  
        ${COPY_CMD} -rf "${CP4A_PATTERN_FILE_BAK}" "${CP4A_PATTERN_FILE_BAK_TEMP}"
    else 
        error "CR Generation Failed"
        exit 1
    fi

    #Retrieve TOS count, preferring migration property file to preserve existing values
    TOS_NUM=$(${YQ_CMD} r ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list" 2>/dev/null | grep -c "object_store_name" || echo "0")
    if [[ -z "$TOS_NUM" || "$TOS_NUM" -eq 0 ]]; then
        TOS_NUM="$(prop_tmp_property_file TOS_NUM)"
    fi

    ## Removing the initialize_configuration Section from CR 
    ## This section is not needed because you are reusing the existing FileNet domain, Object stores, and LDAP.
    ${YQ_CMD} d -i ${CP4A_PATTERN_FILE_BAK_TEMP} spec.initialize_configuration
    
    # Updating icn datasource value 
    ${SED_COMMAND_FORMAT} ${CASE_MIGRATION_PROPERTY_FILE}
    #sc_content_initialization
    ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.shared_configuration.sc_content_initialization" "false" 

    #icn datasource
    case_migration_replace "datasource_configuration.dc_icn_datasource.dc_icn_database_type" "spec.datasource_configuration.dc_icn_datasource.dc_database_type" "q"
    case_migration_replace "datasource_configuration.dc_icn_datasource.dc_common_icn_datasource_name" "spec.datasource_configuration.dc_icn_datasource.dc_common_icn_datasource_name" "q"
    case_migration_replace "datasource_configuration.dc_icn_datasource.dc_icn_database_servername" "spec.datasource_configuration.dc_icn_datasource.database_servername" "q"
    case_migration_replace "datasource_configuration.dc_icn_datasource.dc_icn_database_name" "spec.datasource_configuration.dc_icn_datasource.database_name" "q"
    case_migration_replace "datasource_configuration.dc_icn_datasource.dc_icn_database_port" "spec.datasource_configuration.dc_icn_datasource.database_port" "q"
    if [[ $DB_TYPE == *"oracle"* ]];
    then 
        case_migration_replace "datasource_configuration.dc_icn_datasource.dc_icn_oracle_os_jdbc_url" "spec.datasource_configuration.dc_icn_datasource.dc_oracle_icn_jdbc_url" "q"
    fi

    #GCD datasource
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_gcd_database_type" "spec.datasource_configuration.dc_gcd_datasource.dc_database_type" "q"
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_common_gcd_datasource_name" "spec.datasource_configuration.dc_gcd_datasource.dc_common_gcd_datasource_name" "q"
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_common_gcd_xa_datasource_name" "spec.datasource_configuration.dc_gcd_datasource.dc_common_gcd_xa_datasource_name" "q"
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_gcd_database_servername" "spec.datasource_configuration.dc_gcd_datasource.database_servername" "q"
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_gcd_database_name" "spec.datasource_configuration.dc_gcd_datasource.database_name" "q"
    case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_gcd_database_port" "spec.datasource_configuration.dc_gcd_datasource.database_port" "q"
    if [[ $DB_TYPE == *"oracle"* ]];
    then 
        case_migration_replace "datasource_configuration.dc_gcd_datasource.dc_gcd_oracle_os_jdbc_url" "spec.datasource_configuration.dc_gcd_datasource.dc_oracle_gcd_jdbc_url" "q"
    fi 

    #os data sources
    option_component_list="$(prop_tmp_property_file OPTION_COMPONENT_LIST)"
    pattern_list="$(prop_tmp_property_file PATTERN_LIST)"
    if [[ $pattern_list == *"workflow-authoring"* ]];
    then 
        
        if [[ $option_component_list == *"ae_data_persistence"* ]];
        then 
            os_num_cr=$((os_num_cr+1))
            initial_os_cr=$((initial_os_cr+1))
            i=$((TOS_NUM+2))

            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_type" "spec.datasource_configuration.dc_os_datasources[0].dc_database_type" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_os_label" "spec.datasource_configuration.dc_os_datasources[0].dc_os_label" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[0].dc_common_os_datasource_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[0].dc_common_os_xa_datasource_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_servername" "spec.datasource_configuration.dc_os_datasources[0].database_servername" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_name" "spec.datasource_configuration.dc_os_datasources[0].database_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_port" "spec.datasource_configuration.dc_os_datasources[0].database_port" "q"
            
            if [[ $DB_TYPE == *"oracle"* ]];
            then 
                case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[0].dc_oracle_os_jdbc_url" "q"
            fi 
        fi
    fi

    content_os_number="$(prop_tmp_property_file CONTENT_OS_NUMBER)"
    os_num_cr=$((os_num_cr + content_os_number + TOS_NUM + 2 ))
    initial_os_cr=$((initial_os_cr + content_os_number ))
    os_num_prop=$((os_num_prop + TOS_NUM +2 ))

    local prop_flag=false    
    local os_count=$initial_os_cr
    for ((j=0;j<${os_num_prop};j++))
        do
            if [[ $j -eq 0 ]];
            then 
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_database_type" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_os_label" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_os_label" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_datasource_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_xa_datasource_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_database_servername" "spec.datasource_configuration.dc_os_datasources[$os_count].database_servername" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_database_name" "spec.datasource_configuration.dc_os_datasources[$os_count].database_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_database_port" "spec.datasource_configuration.dc_os_datasources[$os_count].database_port" "q"
                if [[ $DB_TYPE == *"oracle"* ]];
                then 
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdocs_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_oracle_os_jdbc_url" "q"
                fi
                ((os_count++))
            elif [[ $j -eq 1 ]];
            then 
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_database_type" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_os_label" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_os_label" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_datasource_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_xa_datasource_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_database_servername" "spec.datasource_configuration.dc_os_datasources[$os_count].database_servername" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_database_name" "spec.datasource_configuration.dc_os_datasources[$os_count].database_name" "q"
                case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_database_port" "spec.datasource_configuration.dc_os_datasources[$os_count].database_port" "q"
                if [[ $DB_TYPE == *"oracle"* ]];
                then 
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawdos_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_oracle_os_jdbc_url" "q"
                fi

                ((os_count++))
            else 
                if [[ $TOS_NUM -eq 1 ]] && [[ $j -eq 2 ]];
                then 
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_database_type" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_os_label" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_os_label" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_datasource_name" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_xa_datasource_name" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_database_servername" "spec.datasource_configuration.dc_os_datasources[$os_count].database_servername" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_database_name" "spec.datasource_configuration.dc_os_datasources[$os_count].database_name" "q"
                    case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_database_port" "spec.datasource_configuration.dc_os_datasources[$os_count].database_port" "q"
                    if [[ $DB_TYPE == *"oracle"* ]];
                    then
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos1_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_oracle_os_jdbc_url" "q"
                    fi
                    ((os_count++))
                else 
                    if [[ "$prop_flag" = false ]] && [[ $TOS_NUM -gt 1 ]];
                    then
                        ${YQ_CMD} w -i ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" --style=double "BAWTOS_START"
                        
                        for ((i=1;i<$TOS_NUM;i++))
                        do
                            content_start="$(grep -n "BAWTOS_START" ${CP4A_PATTERN_FILE_BAK_TEMP} | head -n 1 | cut -d: -f1)"
                            content_tmp="$(tail -n +$content_start < ${CP4A_PATTERN_FILE_BAK_TEMP} | grep -n "dc_hadr_max_retries_for_client_reroute:" | head -n1 | cut -d: -f1)"
                            content_stop=$(( $content_start + $content_tmp - 1))
                            awk -v s="$content_start" -v e="$content_stop" \
                                'NR>=s && NR<=e { block[NR-s+1]=$0 } NR==e { for(k=1;k<=e-s+1;k++) print block[k] } { print }' \
                                "${CP4A_PATTERN_FILE_BAK_TEMP}" > "${CP4A_PATTERN_FILE_BAK_TEMP}.dup" \
                                && mv "${CP4A_PATTERN_FILE_BAK_TEMP}.dup" "${CP4A_PATTERN_FILE_BAK_TEMP}"
                        done
                        prop_flag=true
                    fi
                    if [[ "$prop_flag" = true ]];
                    then
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_database_type" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_os_label" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_os_label" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_datasource_name" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_xa_datasource_name" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_database_servername" "spec.datasource_configuration.dc_os_datasources[$os_count].database_servername" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_database_name" "spec.datasource_configuration.dc_os_datasources[$os_count].database_name" "q"
                        case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_database_port" "spec.datasource_configuration.dc_os_datasources[$os_count].database_port" "q"
                        if [[ $DB_TYPE == *"oracle"* ]];
                        then
                            case_migration_replace "datasource_configuration.dc_os_datasources[$j].dc_bawtos$((j-1))_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_oracle_os_jdbc_url" "q"
                        fi
                        ((os_count++))
                    fi
                fi

            fi
        done            

    #Cpe Database
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_database_type" "spec.datasource_configuration.dc_cpe_datasources[0].dc_database_type" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_os_label" "spec.datasource_configuration.dc_cpe_datasources[0].dc_os_label" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_datasource_name" "spec.datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_datasource_name" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_xa_datasource_name" "spec.datasource_configuration.dc_cpe_datasources[0].dc_common_cpe_xa_datasource_name" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_database_servername" "spec.datasource_configuration.dc_cpe_datasources[0].database_servername" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_database_name" "spec.datasource_configuration.dc_cpe_datasources[0].database_name" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_database_port" "spec.datasource_configuration.dc_cpe_datasources[0].database_port" "q"
    case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_common_conn_name" "spec.datasource_configuration.dc_cpe_datasources[0].dc_common_conn_name" "q"
    if [[ $DB_TYPE == *"oracle"* ]];
    then
        case_migration_replace "datasource_configuration.dc_cpe_datasources[0].dc_oracle_os_jdbc_url" "spec.datasource_configuration.dc_cpe_datasources[0].dc_oracle_os_jdbc_url" "q"
    fi

    #Navigator Configuration
    case_migration_replace "navigator_configuration.icn_production_setting.icn_jndids_name" "spec.navigator_configuration.icn_production_setting.icn_jndids_name" "q"
    case_migration_replace "navigator_configuration.icn_production_setting.icn_schema" "spec.navigator_configuration.icn_production_setting.icn_schema" "q"
    case_migration_replace "navigator_configuration.icn_production_setting.icn_table_space" "spec.navigator_configuration.icn_production_setting.icn_table_space" "q"
    case_migration_replace "navigator_configuration.icn_production_setting.icn_admin" "spec.navigator_configuration.icn_production_setting.icn_admin" "q"

    
    if [[ $pattern_list == *"workflow-authoring"* ]];
    then 
        prop_flag=false
        local temp_flag=false
        #content_integration
        case_migration_replace "content_integration.domain_name" "spec.workflow_authoring_configuration.content_integration.domain_name" "q"
        case_migration_replace "content_integration.object_store_name" "spec.workflow_authoring_configuration.content_integration.object_store_name" "q"

        #Case
        case_migration_replace "case.domain_name" "spec.workflow_authoring_configuration.case.domain_name" "q"
        case_migration_replace "case.object_store_name_dos" "spec.workflow_authoring_configuration.case.object_store_name_dos" "q"
        
        #tos_list
        for ((j=0;j<$TOS_NUM;j++))
        do
            case_migration_replace "case.tos_list[$j].object_store_name" "spec.workflow_authoring_configuration.case.tos_list[$j].object_store_name" "q"
            case_migration_replace "case.tos_list[$j].connection_point_name" "spec.workflow_authoring_configuration.case.tos_list[$j].connection_point_name" "q"
            case_migration_replace "case.tos_list[$j].desktop_id" "spec.workflow_authoring_configuration.case.tos_list[$j].desktop_id" "q"
            case_migration_replace "case.tos_list[$j].target_environment_name" "spec.workflow_authoring_configuration.case.tos_list[$j].target_environment_name" "q"
            case_migration_replace "case.tos_list[$j].is_default" "spec.workflow_authoring_configuration.case.tos_list[$j].is_default" 
            temp_flag=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.workflow_authoring_configuration.case.tos_list[$j].is_default")
            if [[ "$temp_flag" = true ]]; then
                prop_flag=true;
            fi
        done
        
        if [[ "$prop_flag" = false ]]; then
            ${YQ_CMD} w -i ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.workflow_authoring_configuration.case.tos_list[0].is_default" "true"
        fi

    elif [[ $pattern_list == *"workflow-runtime"* ]];
    then 
        case_migration_replace "content_integration.domain_name" "spec.baw_configuration[0].content_integration.domain_name" "q"
        case_migration_replace "content_integration.object_store_name" "spec.baw_configuration[0].content_integration.object_store_name" "q"
        if [[ $option_component_list == *"ae_data_persistence"* ]];
        then 
            i=$((TOS_NUM+2))

            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_type" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_database_type" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_os_label" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_os_label" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_common_os_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_datasource_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_common_os_xa_datasource_name" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_common_os_xa_datasource_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_servername" "spec.datasource_configuration.dc_os_datasources[$os_count].database_servername" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_name" "spec.datasource_configuration.dc_os_datasources[$os_count].database_name" "q"
            case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_database_port" "spec.datasource_configuration.dc_os_datasources[$os_count].database_port" "q"
            
            if [[ $DB_TYPE == *"oracle"* ]];
            then 
                case_migration_replace "datasource_configuration.dc_os_datasources[$i].dc_aeos_oracle_os_jdbc_url" "spec.datasource_configuration.dc_os_datasources[$os_count].dc_oracle_os_jdbc_url" "q"
            fi 
            ((os_count++))
        fi

        #Case
        case_migration_replace "case.domain_name" "spec.baw_configuration[0].case.domain_name" "q"
        case_migration_replace "case.object_store_name_dos" "spec.baw_configuration[0].case.object_store_name_dos" "q"
        
        #tos_list
        prop_flag=false
        local temp_flag=false

        for ((j=0;j<$TOS_NUM;j++))
        do
            case_migration_replace "case.tos_list[$j].object_store_name" "spec.baw_configuration[0].case.tos_list[$j].object_store_name" "q"
            case_migration_replace "case.tos_list[$j].connection_point_name" "spec.baw_configuration[0].case.tos_list[$j].connection_point_name" "q"
            case_migration_replace "case.tos_list[$j].desktop_id" "spec.baw_configuration[0].case.tos_list[$j].desktop_id" "q"
            case_migration_replace "case.tos_list[$j].target_environment_name" "spec.baw_configuration[0].case.tos_list[$j].target_environment_name" "q"
            case_migration_replace "case.tos_list[$j].is_default" "spec.baw_configuration[0].case.tos_list[$j].is_default"
            temp_flag=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.baw_configuration[0].case.tos_list[$j].is_default")
            if [[ "$temp_flag" = true ]]; then
                prop_flag=true;
            fi
        done

        if [[ "$prop_flag" = false ]]; then
            ${YQ_CMD} w -i ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.baw_configuration[0].case.tos_list[0].is_default" "true"
        fi

    fi

    #ecm_configuration
    local MIG_PROP_TEMP=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.cpe.replica_count")
    if [ -z "$MIG_PROP_TEMP" ];
    then 
        ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.cpe.replica_count" "1" 
    fi 

    local MIG_PROP_TEMP=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.cmis.replica_count")
    if [ -z "$MIG_PROP_TEMP" ];
    then 
        ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.cmis.replica_count" "1" 
    fi

    local MIG_PROP_TEMP=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.graphql.replica_count")
    if [ -z "$MIG_PROP_TEMP" ];
    then 
        ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.ecm_configuration.graphql.replica_count" "1" 
    fi

    local MIG_PROP_TEMP=$(${YQ_CMD} r ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.resource_registry_configuration.service_type")
    if [ -z "$MIG_PROP_TEMP" ];
    then 
        ${YQ_CMD} w -i  ${CP4A_PATTERN_FILE_BAK_TEMP} "spec.resource_registry_configuration.service_type" "Route" 
    fi

    ## Copying the Final CR after Modifications for Migration
    ${COPY_CMD} -rf "${CP4A_PATTERN_FILE_BAK_TEMP}" "${CP4A_PATTERN_FILE_BAK}"
    rm -rf "${CP4A_PATTERN_FILE_BAK_TEMP}"
    ${SED_COMMAND_FORMAT} ${CP4A_PATTERN_FILE_BAK}
}

################################################
#### Begin - Main step for install operator ####
################################################

pattern_name_list="$(prop_tmp_property_file PATTERN_NAME_LIST)"

if [[ $pattern_name_list == *"Business Automation Workflow"* ]];
then
    script_file="0"
    CASE_MIGRATION_PROPERTY_FILE="$(prop_tmp_property_file CASE_MIGRATION_PROPERTY_FILE)"
    if [[ -z "$CASE_MIGRATION_PROPERTY_FILE" ]]; then
        CASE_MIGRATION_PROPERTY_FILE=${PROPERTY_FILE_FOLDER}/baw_case_migration.property
    fi

    if [ -e $CASE_MIGRATION_PROPERTY_FILE ] ;
    then
        value_empty=0

        #Validate the property file for all Required Fields
        value_empty=`grep "<Required>" "${CASE_MIGRATION_PROPERTY_FILE}" | wc -l`  >/dev/null 2>&1
        if [ $value_empty -ne 0 ] ; 
        then
            error "Found invalid value(s) \"<Required>\" in property file \"${CASE_MIGRATION_PROPERTY_FILE}\", input the correct value and rerun the migration"
            exit 1
        fi
        
        #Validate the property file for Syntax errors
        if ! ${YQ_CMD} validate $CASE_MIGRATION_PROPERTY_FILE ;
        then 
            error "Invalid Property File Syntax (YAML): \"${CASE_MIGRATION_PROPERTY_FILE}\", correct the syntax and rerun the migration"
            exit 1
        fi
        
        # ADDED: Validate TOS_NUM is set
        TOS_NUM=$(${YQ_CMD} r ${CASE_MIGRATION_PROPERTY_FILE} "case.tos_list" | grep -c "object_store_name" || echo "0")
        if [[ -z "$TOS_NUM" || "$TOS_NUM" -eq 0 ]]; then
            error "No Target Object Stores (TOS) defined in migration property file"
            error "Please ensure case.tos_list contains at least one object store configuration"
            exit 1
        fi
        
        # ADDED: Validate database type consistency
        DB_TYPE=$(${YQ_CMD} r ${CASE_MIGRATION_PROPERTY_FILE} "datasource_configuration.dc_gcd_datasource.dc_gcd_database_type")
        if [[ -z "$DB_TYPE" ]]; then
            error "Database type not specified in migration property file"
            error "Please set datasource_configuration.dc_gcd_datasource.dc_gcd_database_type"
            exit 1
        fi
        
        info "Migration validation passed:"
        info "  - TOS Count: $TOS_NUM"
        info "  - Database Type: $DB_TYPE"
        
    else 
        error "Migration Property File not Found: \"${CASE_MIGRATION_PROPERTY_FILE}\""
        error "Please run baw-case-prerequisites-migration.sh in property mode to create the file"
        exit 1
    fi
            
    ##########################################
    # Migration Function to do changes on cr based on migration requirement
    # Import common utilities and environment variables
    source ${PARENT_DIR}/helper/common.sh $TARGET_PROJECT_NAME
    
    info "Starting migration CR generation..."
    case_migration_apply_pattern_cr
    
    if [ $? -eq 0 ]; then
        success "Migration CR generated successfully: $CP4A_PATTERN_FILE_BAK"
        info "Please review the generated CR before applying it to your cluster"
    else
        error "Migration CR generation failed"
        exit 1
    fi
    ##########################################

else 
    error "Migration script is only for Business Automation Workflow."
    error "Current pattern: $pattern_name_list"
    exit 1
fi

