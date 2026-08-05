#!/bin/bash

###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2024, 2026. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################

################################################################################
# CP4BA EDB PostgreSQL to IBM CloudNativePG Migration Script
#
# This script automates the complete migration from EDB PostgreSQL 14 to
# IBM CloudNativePG PostgreSQL 16 for CP4BA deployments.
#
# IMPORTANT: This script is designed to be integrated with upgradeOperator mode.
# It should NOT be executed standalone. It is automatically invoked during:
#   ./cp4a-deployment.sh -m upgradeOperator -n <namespace>
#
# INTEGRATION APPROACH:
# - This script is sourced by cp4a-deployment.sh during upgradeOperator mode
# - Three wrapper functions are called sequentially for each migration phase:
#   1. execute_backup_phase(namespace, backup_dir, cr_kind)
#   2. execute_create_cluster_phase(namespace)
#   3. execute_restore_phase(namespace, backup_dir)
#
# - ConfigMap-based state tracking enables automatic resumption on failure
# - Each phase validates completion before proceeding to the next
# - Application scaling is handled automatically based on CR kind
#
# Prerequisites (handled by upgradeOperator mode):
# - kubectl/oc configured and connected to cluster
# - IBM CNPG operator catalog installed (v28.x)
# - Sufficient disk space for backups
# - CP4BA operators shut down
# - Applications scaled down based on CR kind (ICP4ACluster or Content)
#
# For detailed integration documentation, see: EDB_CNPG_MIGRATION_INTEGRATION.md
################################################################################


# Note: common.sh is already sourced by the calling script (cp4a-deployment.sh)
# This script uses common.sh messaging functions: info, warning, error, success, fail

# Default Configuration
OLD_CLUSTER="postgres-cp4ba"
NEW_CLUSTER="postgres-cp4ba"
BACKUP_DIR=""
CNPG_MANIFEST="${TEMP_FOLDER}/cnpg-cluster-postgres-cp4ba.yaml"
RESTORE_DIR="/var/lib/postgresql/data/restore"
CR_KIND=""  # Top-level CR kind (icp4acluster or content)

# EDB Cluster Configuration (extracted before deletion)
EDB_STORAGE_CLASS=""
EDB_STORAGE_SIZE="100Gi"
EDB_INSTANCES="1"
EDB_CPU_REQUESTS="1"
EDB_MEMORY_REQUESTS="2Gi"
EDB_CPU_LIMITS="2"
EDB_MEMORY_LIMITS="4Gi"

# Operation modes
BACKUP_ONLY=false
RESTORE_ONLY=false
CREATE_CLUSTER_ONLY=false
SKIP_CNPG_CREATION=false

# Database list will be dynamically discovered
DATABASES=()

# Timeout Configuration (in seconds)
# These can be overridden via environment variables for different environments
EDB_CLUSTER_DELETE_TIMEOUT="${EDB_CLUSTER_DELETE_TIMEOUT:-120}"
PVC_DELETE_TIMEOUT="${PVC_DELETE_TIMEOUT:-120}"
SERVICE_DELETE_TIMEOUT="${SERVICE_DELETE_TIMEOUT:-60}"

# CR Kind to Component Mapping
# Maps top-level CR kinds to their associated component CR kinds for deployment scaling
ICP4ACLUSTER_CR_KIND_MAPPING_LIST=("ICP4ACluster" "Content" "InsightsEngine" "ICP4AAutomationDecisionService" "WFPSRuntime" "WorkflowRuntime" "ICP4ADocumentProcessingEngine")
CONTENT_CR_KIND_MAPPING_LIST=("Content" "Foundation" "InsightsEngine")

################################################################################
# Helper Functions
# These functions use common.sh messaging functions for consistency

################################################################################
# EDB to CNPG Migration ConfigMap Management Functions
# These functions manage the migration state using a ConfigMap to track progress
# across the three phases: backup, create-cluster, and restore
#
# CALLED FROM: cp4a-deployment.sh (upgradeOperator mode only)
# NOTE: This script is ONLY sourced by cp4a-deployment.sh
################################################################################

################################################################################
# Function: create_edb_cnpg_migration_configmap
# Purpose: Creates the ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap with initial state (all phases set to false)
#          and stores the CP4BA CSV version for validation during upgradeDeployment
# Parameters:
#   $1 - namespace: The namespace where the ConfigMap should be created
# Returns: 0 on success, 1 on failure
# Called from: cp4a-deployment.sh (upgradeOperator mode)
################################################################################
function create_edb_cnpg_migration_configmap() {
    local namespace=$1
    
    if [[ -z "$namespace" ]]; then
        fail "Namespace parameter is required for create_edb_cnpg_migration_configmap"
        return 1
    fi
    
    info "Creating ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap in namespace: $namespace"
    
    # Create ConfigMap with all migration phases set to false and store CP4BA CSV version
    cat <<EOF | ${CLI_CMD} apply -f - >&3 2>&3
apiVersion: v1
kind: ConfigMap
metadata:
  name: ${EDB_CNPG_MIGRATION_CM_NAME}
  namespace: $namespace
  labels:
    app: cp4ba
    migration: edb-to-cnpg
data:
  backup-completed: "false"
  create-cluster-completed: "false"
  restore-completed: "false"
  backup-directory: ""
  cp4ba-csv-version: "$CP4BA_CSV_VERSION"
  upgradeOperator-completed: "true"
  cm-valid: "true"
EOF
    
    if [[ $? -eq 0 ]]; then
        success "Created ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap successfully"
        return 0
    else
        fail "Failed to create ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap"
        return 1
    fi
}

################################################################################
# Function: get_migration_phase_status
# Purpose: Retrieves the status of a specific migration phase from the ConfigMap
# Parameters:
#   $1 - namespace: The namespace where the ConfigMap exists
#   $2 - phase: The phase to check (backup-completed, create-cluster-completed, restore-completed)
# Returns: Echoes "true" or "false", returns 0 on success, 1 on failure
# Called from: cp4a-deployment.sh (upgradeOperator, upgradeOperatorStatus, upgradeDeployment modes)
################################################################################
function get_migration_phase_status() {
    local namespace=$1
    local phase=$2
    
    if [[ -z "$namespace" ]] || [[ -z "$phase" ]]; then
        fail "Both namespace and phase parameters are required for get_migration_phase_status"
        return 1
    fi
    
    # Check if ConfigMap exists
    if ! ${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace >&3 2>&3; then
        echo "false"
        return 0
    fi
    
    # Get the phase status
    local status=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace -o jsonpath="{.data.$phase}" 2>/dev/null || echo "false")
    echo "$status"
    return 0
}

################################################################################
# Function: update_migration_phase_status
# Purpose: Updates the status of a specific migration phase in the ConfigMap
# Parameters:
#   $1 - namespace: The namespace where the ConfigMap exists
#   $2 - phase: The phase to update (backup-completed, create-cluster-completed, restore-completed)
#   $3 - status: The status to set (true or false)
# Returns: 0 on success, 1 on failure
# Called from: cp4a-deployment.sh (upgradeOperator mode)
################################################################################
function update_migration_phase_status() {
    local namespace=$1
    local phase=$2
    local status=$3
    
    if [[ -z "$namespace" ]] || [[ -z "$phase" ]] || [[ -z "$status" ]]; then
        fail "All parameters (namespace, phase, status) are required for update_migration_phase_status"
        return 1
    fi
    
    # Validate status value
    if [[ "$status" != "true" ]] && [[ "$status" != "false" ]]; then
        fail "Status must be 'true' or 'false', got: $status"
        return 1
    fi
    
    info "Updating migration phase '$phase' to '$status' in namespace: $namespace"
    
    # Update the ConfigMap
    ${CLI_CMD} patch configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace \
        --type merge \
        -p "{\"data\":{\"$phase\":\"$status\",\"$phase-timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}}" >&3 2>&3
    
    if [[ $? -eq 0 ]]; then
        success "Updated migration phase '$phase' to '$status'"
        return 0
    else
        fail "Failed to update migration phase '$phase'"
        return 1
    fi
}

################################################################################
# Function: check_migration_configmap_exists
# Purpose: Checks if the ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap exists
# Parameters:
#   $1 - namespace: The namespace to check
# Returns: 0 if exists, 1 if not exists
# Called from: cp4a-deployment.sh (upgradeOperator, upgradeOperatorStatus, upgradeDeployment modes)
################################################################################
function check_migration_configmap_exists() {
    local namespace=$1
    
    if [[ -z "$namespace" ]]; then
        fail "Namespace parameter is required for check_migration_configmap_exists"
        return 1
    fi
    
    ${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace >&3 2>&3
    return $?
}

################################################################################
# Function: get_next_migration_phase
# Purpose: Determines the next migration phase that needs to be executed
# Parameters:
#   $1 - namespace: The namespace where the ConfigMap exists
#   $2 - variable name to store result (using nameref)
# Returns: 0 on success, 1 on failure
# Called from: cp4a-deployment.sh (upgradeOperator mode)
################################################################################
function get_next_migration_phase() {
    local namespace=$1
    local -n result_var=$2
    
    if [[ -z "$namespace" ]]; then
        fail "Namespace parameter is required for get_next_migration_phase"
        return 1
    fi
    
    # Check if ConfigMap exists, if not, start from backup
    if ! check_migration_configmap_exists "$namespace"; then
        result_var="backup"
        return 0
    fi
    
    # Check each phase in order
    local backup_status=$(get_migration_phase_status "$namespace" "backup-completed")
    local create_status=$(get_migration_phase_status "$namespace" "create-cluster-completed")
    local restore_status=$(get_migration_phase_status "$namespace" "restore-completed")
    
    if [[ "$backup_status" != "true" ]]; then
        result_var="backup"
    elif [[ "$create_status" != "true" ]]; then
        result_var="create-cluster"
    elif [[ "$restore_status" != "true" ]]; then
        result_var="restore"
    else
        result_var="completed"
    fi
    
    return 0
}

################################################################################
# Function: display_migration_status
# Purpose: Displays the current status of all migration phases
# Parameters:
#   $1 - namespace: The namespace where the ConfigMap exists
# Returns: 0 on success
# Called from: cp4a-deployment.sh (upgradeOperator, upgradeOperatorStatus, upgradeDeployment modes)
################################################################################
function display_migration_status() {
    local namespace=$1
    
    if [[ -z "$namespace" ]]; then
        fail "Namespace parameter is required for display_migration_status"
        return 1
    fi
    
    info "=== EDB to IBM CloudNativePG Migration Status ==="
    
    if ! check_migration_configmap_exists "$namespace"; then
        warning "Migration ConfigMap does not exist - migration not started"
        return 0
    fi
    
    local backup_status=$(get_migration_phase_status "$namespace" "backup-completed")
    local create_status=$(get_migration_phase_status "$namespace" "create-cluster-completed")
    local restore_status=$(get_migration_phase_status "$namespace" "restore-completed")
    local backup_dir=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace -o jsonpath="{.data.backup-directory}" 2>/dev/null || echo "")
    
    echo ""
    echo "  Phase Status:"
    
    if [[ "$backup_status" == "true" ]]; then
        echo "    ✓ Backup Phase: COMPLETED"
        if [[ -n "$backup_dir" ]]; then
            echo "      Backup Location: $backup_dir"
        fi
    else
        echo "    ○ Backup Phase: PENDING"
    fi
    
    if [[ "$create_status" == "true" ]]; then
        echo "    ✓ Create Cluster Phase: COMPLETED"
    elif [[ "$backup_status" == "true" ]]; then
        echo "    ○ Create Cluster Phase: READY TO START"
    else
        echo "    ○ Create Cluster Phase: WAITING (backup must complete first)"
    fi
    
    if [[ "$restore_status" == "true" ]]; then
        echo "    ✓ Restore Phase: COMPLETED"
    elif [[ "$create_status" == "true" ]]; then
        echo "    ○ Restore Phase: READY TO START"
    else
        echo "    ○ Restore Phase: WAITING (create-cluster must complete first)"
    fi
    
    echo ""
    
    return 0
}

################################################################################
# Function: validate_edb_migration_completed
# Purpose: Validates that EDB to CNPG migration has been completed successfully
#          Always displays migration status, shows retry steps only if incomplete
# Parameters:
#   $1 - namespace: The namespace to check
#   $2 - current_csv_version: Current CP4BA CSV version for comparison
#   $3 - upgraded_csv_version: Target CP4BA CSV version for upgrade
# Returns: 0 if migration is complete and valid, 1 if not complete or invalid
# Called from: cp4a-deployment.sh (upgradeOperatorStatus, upgradeDeployment modes)
# NOTE: Requires messages.sh to be sourced by caller for displayEdbMigrationRetryMessage()
################################################################################
function validate_edb_migration_completed() {
    local namespace=$1
    local current_csv_version=$2
    local upgraded_csv_version=$3
    
    # EDB is detected, check if migration ConfigMap exists
    if ! check_migration_configmap_exists "$namespace"; then
        warning "EDB PostgreSQL detected but migration has not been started"
        echo ""
        
        # Display retry message for not-started case (messages.sh sourced at mode level)
        displayEdbMigrationRetryMessage "not-started" "$namespace" "$current_csv_version"
        
        return 1
    fi
    
    # Check CSV version and cm-valid flag - both must be correct for ConfigMap to be valid
    local cm_csv_version=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace -o jsonpath="{.data.cp4ba-csv-version}" 2>/dev/null || echo "")
    local cm_valid_flag=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $namespace -o jsonpath="{.data.cm-valid}" 2>/dev/null || echo "")
    
    # Check if CSV version is missing or doesn't match
    if [[ -z "$cm_csv_version" ]]; then
        info "Migration ConfigMap does not contain cp4ba-csv-version field - may be from older version"
        info "ConfigMap is redundant, proceeding with upgrade..."
        return 0
    elif [[ "$cm_csv_version" != "$upgraded_csv_version" ]]; then
        info "Migration ConfigMap CSV version ($cm_csv_version) does not match current version ($upgraded_csv_version)"
        info "ConfigMap is from a previous version and is redundant, proceeding with upgrade..."
        return 0
    fi
    
    # Check if cm-valid flag is not "true" - ConfigMap is invalid
    if [[ "$cm_valid_flag" != "true" ]]; then
        info "Migration ConfigMap cm-valid flag is not 'true' (current value: '$cm_valid_flag')"
        info "ConfigMap is invalid or from a completed previous migration, proceeding with upgrade..."
        return 0
    fi
    
    # Check all phases are completed
    local backup_status=$(get_migration_phase_status "$namespace" "backup-completed")
    local create_status=$(get_migration_phase_status "$namespace" "create-cluster-completed")
    local restore_status=$(get_migration_phase_status "$namespace" "restore-completed")
    
    # ALWAYS display migration status table
    echo ""
    display_migration_status "$namespace"
    echo ""
    
    # Determine which phase is incomplete
    local incomplete_phase=""
    if [[ "$backup_status" != "true" ]]; then
        incomplete_phase="backup"
    elif [[ "$create_status" != "true" ]]; then
        incomplete_phase="create-cluster"
    elif [[ "$restore_status" != "true" ]]; then
        incomplete_phase="restore"
    fi
    
    # If migration is incomplete, display retry steps
    if [[ -n "$incomplete_phase" ]]; then
        warning "EDB to IBM CloudNativePG migration is incomplete"
        
        # Display retry message (messages.sh sourced at mode level)
        displayEdbMigrationRetryMessage "$incomplete_phase" "$namespace" "$current_csv_version"
        
        return 1
    fi
    
    # All validations passed - migration is complete
    success "EDB to IBM CloudNativePG migration validation passed - all phases completed"
    
    return 0
}

################################################################################
# Function: handle_edb_migration_process
# Purpose: Orchestrates the complete EDB to CNPG migration process
#          Loops through all phases until completion or failure
# Parameters:
#   $1 - namespace: The namespace where migration should occur
#   $2 - cr_kind: The CR kind (ICP4ACluster or Content) for deployment scaling
# Returns: 0 on success (all phases complete), 1 on failure
# Called from: cp4a-deployment.sh (upgradeOperator mode)
################################################################################
function handle_edb_migration_process() {
    local services_namespace=$1
    local operator_namespace=$2
    local cr_kind=$3
    local next_phase=""
    
    info "EDB PostgreSQL detected in namespace: $services_namespace"
    info "Starting phased EDB to IBM CloudNativePG migration process..."
    printf "\n"
    
    # Display current migration status
    display_migration_status "$services_namespace"
    printf "\n"
    
    # Loop through all phases until completion
    while true; do
        # Determine the next phase to execute
        get_next_migration_phase "$services_namespace" next_phase
        
        if [[ "$next_phase" == "completed" ]]; then
            success "All EDB to IBM CloudNativePG migration phases have been completed!"
            info "Migration ConfigMap shows all phases are done."
            printf "\n"
            return 0
        fi
        
        info "Executing migration phase: $next_phase"
        printf "\n"
        
        # Execute phased migration with CR kind
        execute_phased_edb_migration "$services_namespace" "$operator_namespace" "$next_phase" "$cr_kind"
        
        # Display updated status after phase completion
        printf "\n"
        display_migration_status "$services_namespace"
        printf "\n"
    done
}

################################################################################
# Function: execute_phased_edb_migration
# Purpose: Executes a specific phase of the EDB to CNPG migration
#          This function orchestrates the phase execution and ConfigMap updates
# Parameters:
#   $1 - services_namespace: Namespace where EDB/CNPG clusters and databases exist
#   $2 - operator_namespace: Namespace where operator subscription/CSV are installed
#   $3 - phase: The phase to execute (backup, create-cluster, or restore)
#   $4 - cr_kind: The CR kind (ICP4ACluster or Content) for deployment scaling
# Returns: Exits with 0 on success, exits with 1 on failure
# Called from: handle_edb_migration_process() in upgradeOperator mode
# Note: services_namespace is used for all database operations, ConfigMaps, and clusters
#       operator_namespace is used only for operator subscription and CSV
################################################################################
function execute_phased_edb_migration() {
    local services_namespace=$1
    local operator_namespace=$2
    local phase=$3
    local cr_kind=$4
    
    if [[ -z "$services_namespace" ]] || [[ -z "$phase" ]]; then
        fail "Both namespace and phase parameters are required for execute_phased_edb_migration"
        exit 1
    fi
    
    if [[ -z "$cr_kind" ]]; then
        fail "CR kind parameter is required for execute_phased_edb_migration"
        exit 1
    fi
    
    # Validate phase parameter
    if [[ "$phase" != "backup" ]] && [[ "$phase" != "create-cluster" ]] && [[ "$phase" != "restore" ]]; then
        fail "Invalid phase: $phase. Must be one of: backup, create-cluster, restore"
        exit 1
    fi
    
    # Create ConfigMap if it doesn't exist
    if ! check_migration_configmap_exists "$services_namespace"; then
        info "Migration ConfigMap does not exist. Creating it now..."
        if ! create_edb_cnpg_migration_configmap "$services_namespace"; then
            fail "Failed to create migration ConfigMap"
            exit 1
        fi
    fi
    
    # Execute the appropriate phase by calling wrapper functions
    case "$phase" in
        backup)
            info "=========================================================================="
            info "EXECUTING MIGRATION PHASE 1: BACKUP"
            info "=========================================================================="
            
            # Create backup directory structure
            local migration_dir="${EDB_TO_CNPG_MIGRATION_FOLDER}/edb-to-cnpg-migration"
            local backups_dir="${migration_dir}/backups"
            local timestamp=$(date +%Y%m%d-%H%M%S)
            local backup_dir="${backups_dir}/backup-${timestamp}"
            
            info "Creating backup directory structure..."
            mkdir -p "$backup_dir" >&3 2>&3
            
            if [[ $? -ne 0 ]]; then
                fail "Failed to create backup directory: $backup_dir"
                exit 1
            fi
            
            success "Backup directory created: $backup_dir"
            
            info "This phase will:"
            info "  - Discover all databases in the EDB cluster"
            info "  - Backup all databases using pg_dump"
            info "  - Save backup metadata and validation data"
            info "  - Store backups in: $backup_dir"
            printf "\n"
            
            # Execute backup phase by calling wrapper function
            info "Executing backup phase function..."
            if execute_backup_phase "$services_namespace" "$operator_namespace" "$backup_dir" "$cr_kind"; then
                success "Backup phase completed successfully!"
                
                # Store backup directory path in ConfigMap
                info "Storing backup directory path in ConfigMap..."
                ${CLI_CMD} patch configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $services_namespace \
                    --type merge \
                    -p "{\"data\":{\"backup-directory\":\"$backup_dir\"}}" >&3 2>&3
                
                if [[ $? -eq 0 ]]; then
                    success "Backup directory path stored in ConfigMap"
                else
                    warning "Failed to store backup directory path, but backup was successful"
                    displayEdbMigrationRetryMessage "backup" "$services_namespace" "$cp4a_operator_csv_version"
                    exit 1
                fi
                
                # Update ConfigMap to mark backup as completed
                if update_migration_phase_status "$services_namespace" "backup-completed" "true"; then
                    success "Migration state updated: backup-completed = true"
                else
                    warning "Failed to update migration state, but backup was successful"
                fi
                
                printf "\n"
                info "=========================================================================="
                info "BACKUP PHASE COMPLETED"
                info "=========================================================================="
                info "Backup Location: $backup_dir"
                info "Next phase: create-cluster"
                info "The upgradeOperator will automatically continue to the next phase."
                printf "\n"
                
                return 0
            else
                fail "Backup phase failed"
                printf "\n"
                displayEdbMigrationRetryMessage "backup" "$services_namespace" "$cp4a_operator_csv_version"
                exit 1
            fi
            ;;
            
        create-cluster)
            info "=========================================================================="
            info "EXECUTING MIGRATION PHASE 2: CREATE IBM CloudNativePG CLUSTER"
            info "=========================================================================="
            info "This phase will:"
            info "  - Validate that backup phase is completed"
            info "  - Generate IBM CloudNativePG cluster manifest"
            info "  - Delete the old EDB cluster"
            info "  - Deploy the new IBM CloudNativePG cluster"
            info "  - Wait for the cluster to be ready"
            printf "\n"
            
            # Verify backup is completed
            local backup_status=$(get_migration_phase_status "$services_namespace" "backup-completed")
            if [[ "$backup_status" != "true" ]]; then
                fail "Cannot create cluster: backup phase not completed"
                error "Please complete the backup phase first by re-running upgradeOperator"
                exit 1
            fi
            
            # Execute create-cluster phase by calling wrapper function
            info "Executing create-cluster phase function..."
            if execute_create_cluster_phase "$services_namespace" "$operator_namespace"; then
                success "Create cluster phase completed successfully!"
                
                # Update ConfigMap to mark create-cluster as completed
                if update_migration_phase_status "$services_namespace" "create-cluster-completed" "true"; then
                    success "Migration state updated: create-cluster-completed = true"
                else
                    warning "Failed to update migration state, but cluster creation was successful"
                fi
                
                printf "\n"
                info "=========================================================================="
                info "CREATE CLUSTER PHASE COMPLETED"
                info "=========================================================================="
                info "Next phase: restore"
                info "The upgradeOperator will automatically continue to the next phase."
                printf "\n"
                
                return 0
            else
                fail "Create cluster phase failed in upgradeOperator mode"
                error "Phase: create-cluster"
                error "Services Namespace: $services_namespace"
                error "Operator Namespace: $operator_namespace"
                printf "\n"
                displayEdbMigrationRetryMessage "create-cluster" "$services_namespace" "$cp4a_operator_csv_version"
                exit 1
            fi
            ;;
            
        restore)
            info "=========================================================================="
            info "EXECUTING MIGRATION PHASE 3: RESTORE DATABASES"
            info "=========================================================================="
            info "This phase will:"
            info "  - Validate that create-cluster phase is completed"
            info "  - Restore all databases from backup to IBM CloudNativePG cluster"
            info "  - Validate data integrity"
            info "  - Compare pre/post migration statistics"
            printf "\n"
            
            # Verify create-cluster is completed
            local create_status=$(get_migration_phase_status "$services_namespace" "create-cluster-completed")
            if [[ "$create_status" != "true" ]]; then
                fail "Cannot restore: create-cluster phase not completed"
                error "Please complete the create-cluster phase first by re-running upgradeOperator"
                exit 1
            fi
            
            # Retrieve backup directory from ConfigMap
            local backup_dir=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n $services_namespace -o jsonpath="{.data.backup-directory}" 2>/dev/null || echo "")
            
            if [[ -z "$backup_dir" ]]; then
                fail "Cannot find backup directory path in ConfigMap"
                error "The backup-directory field is empty in the ${EDB_CNPG_MIGRATION_CM_NAME} ConfigMap"
                error "Please ensure the backup phase completed successfully"
                exit 1
            fi
            
            if [[ ! -d "$backup_dir" ]]; then
                fail "Backup directory does not exist: $backup_dir"
                error "The directory path stored in ConfigMap is invalid or has been deleted"
                error "Please verify the backup directory exists or re-run the backup phase"
                exit 1
            fi
            
            info "Using backup directory from ConfigMap: $backup_dir"
            printf "\n"
            
            # Execute restore phase by calling wrapper function
            info "Executing restore phase function..."
            if execute_restore_phase "$services_namespace" "$operator_namespace" "$backup_dir"; then
                success "Restore phase completed successfully!"
                
                # Update ConfigMap to mark restore as completed
                if update_migration_phase_status "$services_namespace" "restore-completed" "true"; then
                    success "Migration state updated: restore-completed = true"
                else
                    warning "Failed to update migration state, but restore was successful"
                fi
                
                printf "\n"
                success "=========================================================================="
                success "ALL MIGRATION PHASES COMPLETED SUCCESSFULLY!"
                success "=========================================================================="
                info "The EDB to IBM CloudNativePG migration is now complete."
                info "All databases have been migrated to IBM CloudNativePG."
                printf "\n"
                info "Migration Summary:"
                info "  ✓ Phase 1: Backup - COMPLETED"
                info "  ✓ Phase 2: Create Cluster - COMPLETED"
                info "  ✓ Phase 3: Restore - COMPLETED"
                info "  Backup Location: $backup_dir"
                printf "\n"
                info "You can now proceed with the CP4BA deployment upgrade."
                printf "\n"
                
                return 0
            else
                fail "Restore phase failed in upgradeOperator mode"
                error "Phase: restore"
                error "Services Namespace: $services_namespace"
                error "Operator Namespace: $operator_namespace"
                printf "\n"
                displayEdbMigrationRetryMessage "restore" "$services_namespace" "$cp4a_operator_csv_version"
                exit 1
            fi
            ;;
    esac
}

################################################################################

################################################################################
# Function: info
# Purpose: Wrapper for info() from common.sh - displays informational messages
# Parameters: $1 - message to display
################################################################################

################################################################################
# Function: discover_databases
# Purpose: Discovers all databases in the EDB cluster or loads from backup list
# Parameters: None (uses global variables)
# Global Variables:
#   - RESTORE_ONLY: If true, loads database list from backup directory
#   - BACKUP_DIR: Directory containing database_list.txt for restore mode
#   - OLD_CLUSTER: Name of the EDB cluster to query
#   - SERVICES_NAMESPACE: Kubernetes namespace where EDB cluster exists
#   - DATABASES: Array populated with discovered database names
# Returns: 0 on success, exits on error
################################################################################
function discover_databases() {
    info "=== DISCOVERING DATABASES ==="
    
    
    if [[ "$RESTORE_ONLY" = true ]]; then
        # Load database list from backup directory
        if [[ -f "$BACKUP_DIR/database_list.txt" ]]; then
            info "Loading database list from backup..."
            mapfile -t DATABASES < "$BACKUP_DIR/database_list.txt"
        else
            error "Database list file not found in backup directory."
            exit 1
        fi
    else
        # Discover from EDB cluster - try multiple label selectors
        info "Looking for EDB PostgreSQL pod..."
        
        # Try method 1: EDB operator labels (k8s.enterprisedb.io)
        local EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE -l k8s.enterprisedb.io/cluster=$OLD_CLUSTER,role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        # Try method 2: Old CrunchyData labels
        if [[ -z "$EDB_POD" ]]; then
            EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE -l postgres-operator.crunchydata.com/cluster=$OLD_CLUSTER,postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        fi
        
        # Try method 3: Simple name-based search
        if [[ -z "$EDB_POD" ]]; then
            EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers | grep "^$OLD_CLUSTER-" | grep -v "pooler" | head -1 | awk '{print $1}')
        fi
        
        if [[ -z "$EDB_POD" ]]; then
            # For create-cluster phase, try fallback to backup directory
            if [[ "$CREATE_CLUSTER_ONLY" = true ]] && [[ -n "$BACKUP_DIR" ]] && [[ -f "$BACKUP_DIR/database_list.txt" ]]; then
                warning "Could not find EDB PostgreSQL pod (expected after backup phase)."
                info "Falling back to database list from backup directory..."
                mapfile -t DATABASES < "$BACKUP_DIR/database_list.txt"
                
                if [[ ${#DATABASES[@]} -eq 0 ]]; then
                    error "Database list file is empty."
                    return 1
                fi
                
                success "Loaded ${#DATABASES[@]} databases from backup:"
                for db in "${DATABASES[@]}"; do
                    info "  - $db"
                done
                return 0
            else
                # For backup phase or when no backup available, this is an error
                error "Could not find EDB PostgreSQL pod."
                error "Tried the following methods:"
                error "  1. Label: k8s.enterprisedb.io/cluster=$OLD_CLUSTER,role=primary"
                error "  2. Label: postgres-operator.crunchydata.com/cluster=$OLD_CLUSTER"
                error "  3. Pod name pattern: $OLD_CLUSTER-*"
                error ""
                error "Available pods in namespace $SERVICES_NAMESPACE:"
                ${CLI_CMD} get pods -n $SERVICES_NAMESPACE
                return 1
            fi
        fi
        
        info "Using EDB pod: $EDB_POD"
        
        # Get list of databases excluding system databases
        info "Querying databases from PostgreSQL instance..."
        local db_list=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $EDB_POD -- psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'rdsadmin') ORDER BY datname;" | xargs)
        
        if [[ -z "$db_list" ]]; then
            error "No databases found in the cluster."
            exit 1
        fi
        
        # Convert to array
        DATABASES=($db_list)
    fi
    
    success "Discovered ${#DATABASES[@]} databases:"
    for db in "${DATABASES[@]}"; do
        info "  - $db"
    done
    
    echo ""
    info "These databases will be processed."
}

################################################################################
# Function: scale_down_applications
# Purpose: Scales down CP4BA applications before database migration
# Parameters: None (uses global variables)
# Global Variables:
#   - CR_KIND: Type of CP4BA CR (ICP4ACluster, Content, etc.)
#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success, 1 on error
# Note: Scales deployments to 0 replicas to prevent database access during migration
################################################################################
function scale_down_applications() {
    info "=== PHASE: SCALING DOWN APPLICATIONS ==="
    
    # Validate CR_KIND is provided
    if [[ -z "$CR_KIND" ]]; then
        error "CR kind not provided. Cannot determine which deployments to scale down."
        error "This parameter should be passed automatically when called from upgradeOperator mode."
        exit 1
    fi
    
    # Convert CR_KIND to lowercase for comparison
    local cr_kind_lower=$(echo "$CR_KIND" | tr '[:upper:]' '[:lower:]')
    
    # Determine which CR kinds to check based on top-level CR kind
    local cr_kinds_to_check=()
    if [[ "$cr_kind_lower" == "icp4acluster" ]]; then
        cr_kinds_to_check=("${ICP4ACLUSTER_CR_KIND_MAPPING_LIST[@]}")
        info "Top-level CR kind: ICP4ACluster"
        info "Will scale down deployments owned by: ${ICP4ACLUSTER_CR_KIND_MAPPING_LIST[*]}"
    elif [[ "$cr_kind_lower" == "content" ]]; then
        cr_kinds_to_check=("${CONTENT_CR_KIND_MAPPING_LIST[@]}")
        info "Top-level CR kind: Content"
        info "Will scale down deployments owned by: ${CONTENT_CR_KIND_MAPPING_LIST[*]}"
    else
        error "Unknown CR kind: $CR_KIND"
        error "Expected 'ICP4ACluster' or 'Content'"
        exit 1
    fi
    
    echo ""
    info "Discovering deployments to scale down..."
    
    # Get all deployments in the namespace
    local all_deployments=$(${CLI_CMD} get deployments -n $SERVICES_NAMESPACE -o json 2>/dev/null)
    
    if [[ $? -ne 0 ]] || [[ -z "$all_deployments" ]]; then
        warning "No deployments found in namespace $SERVICES_NAMESPACE"
        return 0
    fi
    
    # Array to store deployments to scale down
    local deployments_to_scale=()
    
    # Iterate through each deployment and check owner references
    while IFS= read -r deployment_name; do
        # Skip empty lines
        [[ -z "$deployment_name" ]] && continue
        
        # Get owner references for this deployment
        local owner_refs=$(${CLI_CMD} get deployment "$deployment_name" -n $SERVICES_NAMESPACE -o jsonpath='{.metadata.ownerReferences[*].kind}' 2>/dev/null)
        
        if [[ -z "$owner_refs" ]]; then
            continue
        fi
        
        # Check if any owner reference matches our CR kinds
        local should_scale=false
        for cr_kind in "${cr_kinds_to_check[@]}"; do
            if echo "$owner_refs" | grep -q "$cr_kind"; then
                should_scale=true
                break
            fi
        done
        
        if [[ "$should_scale" = true ]]; then
            # Exclude operators and database pods
            if [[ ! "$deployment_name" =~ -operator$ ]] && \
               [[ ! "$deployment_name" =~ ^postgres ]] && \
               [[ ! "$deployment_name" =~ ^edb ]] && \
               [[ ! "$deployment_name" =~ ^ibm-pg-operator ]]; then
                deployments_to_scale+=("$deployment_name")
            fi
        fi
    done < <(echo "$all_deployments" | jq -r '.items[].metadata.name' 2>/dev/null)
    
    # Display deployments to be scaled down
    if [[ ${#deployments_to_scale[@]} -eq 0 ]]; then
        info "No deployments found to scale down"
        return 0
    fi
    
    echo ""
    info "Found ${#deployments_to_scale[@]} deployment(s) to scale down:"
    for dep in "${deployments_to_scale[@]}"; do
        local current_replicas=$(${CLI_CMD} get deployment "$dep" -n $SERVICES_NAMESPACE -o jsonpath='{.spec.replicas}' 2>/dev/null)
        info "  - $dep (current replicas: $current_replicas)"
    done
    
    echo ""
    warning "These deployments will be scaled down to 0 replicas."
    warning "This is necessary to ensure no active database connections during migration."
    echo ""
    
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    
    echo ""
    info "Scaling down deployments..."
    
    # Scale down each deployment
    local scaled_count=0
    local failed_count=0
    
    for dep in "${deployments_to_scale[@]}"; do
        info "Scaling down: $dep"
        if ${CLI_CMD} scale deployment "$dep" -n $SERVICES_NAMESPACE --replicas=0 >&3 2>&3; then
            scaled_count=$((scaled_count + 1))
            success "  ✓ Scaled down: $dep"
        else
            failed_count=$((failed_count + 1))
            error "  ✗ Failed to scale down: $dep"
        fi
    done
    
    echo ""
    if [[ $failed_count -eq 0 ]]; then
        success "Successfully scaled down $scaled_count deployment(s)"
    else
        warning "Scaled down $scaled_count deployment(s), $failed_count failed"
    fi
    
    # Wait for pods to terminate
    echo ""
    info "Waiting for pods to terminate..."
    sleep 5
    
    local max_wait=300  # 5 minutes
    local elapsed=0
    local check_interval=10
    
    while [[ $elapsed -lt $max_wait ]]; do
        running_pods=0
        for dep in "${deployments_to_scale[@]}"; do
            pod_count=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE -l app="$dep" --field-selector=status.phase=Running 2>/dev/null | grep -c "$dep" || echo "0")
            pod_count=$(echo "$pod_count" | tr -d '\n' | tr -d ' ')
            running_pods=$((running_pods + ${pod_count:-0}))
        done
        
        if [[ $running_pods -eq 0 ]]; then
            success "All pods have terminated"
            break
        fi
        
        info "Waiting for $running_pods pod(s) to terminate... (${elapsed}s/${max_wait}s)"
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    if [[ $elapsed -ge $max_wait ]]; then
        warning "Timeout waiting for all pods to terminate"
        warning "Some pods may still be running. Please verify manually."
    fi
    
    echo ""
    success "Scale down phase completed"
}

################################################################################
# Function: backup_databases
# Purpose: Backs up all discovered databases from EDB cluster using pg_dump
# Parameters: None (uses global variables)
# Global Variables:
#   - BACKUP_DIR: Directory to store backup files
#   - DATABASES: Array of database names to backup
#   - OLD_CLUSTER: Name of the EDB cluster
################################################################################
# Function: validate_database_pre_backup
# Purpose: Validates database before backup by collecting table counts and row estimates
# Parameters:
#   $1 - pod: EDB pod name
#   $2 - db: Database name to validate
# Global Variables:
#   - NAMESPACE: Kubernetes namespace
#   - BACKUP_DIR: Directory to store validation file
#   - CLI_CMD: kubectl or oc command
# Returns: 0 (always succeeds)
# Note: Saves validation data to pre_backup_validation.txt for later comparison
#       with post-restore data
################################################################################
function validate_database_pre_backup() {
    local pod=$1
    local db=$2
    
    info "Validating database before backup: $db"
    
    # Force fresh statistics so n_live_tup is accurate
    info "  Updating database statistics (ANALYZE)..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -c "ANALYZE;" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        info "  ✓ Statistics updated"
    else
        warning "  ⚠ Failed to update statistics, row estimates may be inaccurate"
    fi
    
    # Get table count
    local table_count=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema');" 2>/dev/null | xargs)
    
    # Get row count estimate (n_live_tup from pg_stat_user_tables - now fresh after ANALYZE)
    local row_estimate=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT SUM(n_live_tup) FROM pg_stat_user_tables;" 2>/dev/null | xargs)
    
    # Get database size
    local db_size=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT pg_size_pretty(pg_database_size('$db'));" 2>/dev/null | xargs)
    
    # Save validation data
    echo "$db|$table_count|$row_estimate|$db_size" >> "$BACKUP_DIR/pre_backup_validation.txt"
    
    info "  Tables: $table_count, Estimated Rows: $row_estimate (from fresh statistics), Size: $db_size"
}

#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success, exits on error
# Note: Creates individual .sql files for each database and a database_list.txt
################################################################################
function backup_databases() {
    info "=== PHASE: BACKING UP DATABASES ==="
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    info "Backup directory: $BACKUP_DIR"
    
    # Get EDB pod name - try multiple methods
    info "Looking for EDB PostgreSQL pod..."
    local EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE -l k8s.enterprisedb.io/cluster=$OLD_CLUSTER,role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$EDB_POD" ]]; then
        EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE -l postgres-operator.crunchydata.com/cluster=$OLD_CLUSTER,postgres-operator.crunchydata.com/role=master -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    fi
    
    if [[ -z "$EDB_POD" ]]; then
        EDB_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers | grep "^$OLD_CLUSTER-" | grep -v "pooler" | head -1 | awk '{print $1}')
    fi
    
    if [[ -z "$EDB_POD" ]]; then
        error "Could not find EDB PostgreSQL pod."
        return 1
    fi
    
    info "Using EDB pod: $EDB_POD"
    
    # Validate databases before backup
    info "Validating databases before backup..."
    for db in "${DATABASES[@]}"; do
        validate_database_pre_backup "$EDB_POD" "$db"
    done
    success "Pre-backup validation complete."
    echo ""
    
    # Backup globals
    info "Backing up global objects (roles, tablespaces)..."
    if ! ${CLI_CMD} exec -n $SERVICES_NAMESPACE $EDB_POD -- pg_dumpall -U postgres --globals-only > "$BACKUP_DIR/globals.sql"; then
        local exit_code=$?
        error "pg_dumpall failed for global objects with exit code $exit_code"
        error "Backup file may be incomplete or corrupted"
        return 1
    fi
    
    # Verify globals backup file was created and has content
    if [[ ! -f "$BACKUP_DIR/globals.sql" ]]; then
        error "Globals backup file not created: $BACKUP_DIR/globals.sql"
        return 1
    fi
    
    local globals_size=$(stat -f%z "$BACKUP_DIR/globals.sql" 2>/dev/null || stat -c%s "$BACKUP_DIR/globals.sql" 2>/dev/null)
    if [[ "$globals_size" -eq 0 ]]; then
        error "Globals backup file is empty: $BACKUP_DIR/globals.sql"
        return 1
    fi
    
    success "Globals backed up to $BACKUP_DIR/globals.sql (size: $(du -h "$BACKUP_DIR/globals.sql" | cut -f1))"
    
    # Backup database-level ownership and GRANT statements
    # pg_dumpall --globals-only captures roles but NOT database-level ACLs
    # (ALTER DATABASE ... OWNER TO / GRANT ... ON DATABASE).
    # We extract them explicitly here so they can be applied during restore.
    info "Backing up database-level ownership and grant statements..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $EDB_POD -- psql -U postgres -t -A -c \
        "SELECT 'ALTER DATABASE ' || quote_ident(d.datname) || ' OWNER TO ' || quote_ident(r.rolname) || ';'
         FROM pg_database d
         JOIN pg_roles r ON d.datdba = r.oid
         WHERE d.datistemplate = false
           AND d.datname NOT IN ('postgres', 'rdsadmin')
         ORDER BY d.datname;" > "$BACKUP_DIR/db_ownership_grants.sql"

    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $EDB_POD -- psql -U postgres -t -A -c \
        "SELECT 'GRANT ' || privilege_type || ' ON DATABASE ' || quote_ident(db) || ' TO ' || grantee || ';'
         FROM (
             SELECT d.datname AS db,
                    (aclexplode(d.datacl)).privilege_type AS privilege_type,
                    CASE WHEN (aclexplode(d.datacl)).grantee = 0 THEN 'PUBLIC' ELSE quote_ident((aclexplode(d.datacl)).grantee::regrole::text) END AS grantee
             FROM pg_database d
             WHERE d.datistemplate = false
               AND d.datname NOT IN ('postgres', 'rdsadmin')
               AND d.datacl IS NOT NULL
         ) acls
         WHERE grantee <> ''
         ORDER BY db, grantee, privilege_type;" >> "$BACKUP_DIR/db_ownership_grants.sql"

    if [[ -f "$BACKUP_DIR/db_ownership_grants.sql" ]] && [[ -s "$BACKUP_DIR/db_ownership_grants.sql" ]]; then
        success "Database ownership and grants backed up to $BACKUP_DIR/db_ownership_grants.sql"
    else
        warning "No database-level ownership/grants found or file is empty"
        # Create empty file to avoid errors during restore
        touch "$BACKUP_DIR/db_ownership_grants.sql"
    fi
    
    # Backup each database
    for db in "${DATABASES[@]}"; do
        info "Backing up database: $db"
        
        # Execute pg_dump and capture exit code
        if ! ${CLI_CMD} exec -n $SERVICES_NAMESPACE $EDB_POD -- pg_dump -U postgres -Fc -d $db > "$BACKUP_DIR/$db.dump"; then
            local exit_code=$?
            error "pg_dump failed for database $db with exit code $exit_code"
            error "Backup file may be incomplete or corrupted"
            return 1
        fi
        
        # Verify backup file was created and has content
        if [[ ! -f "$BACKUP_DIR/$db.dump" ]]; then
            error "Backup file not created: $BACKUP_DIR/$db.dump"
            return 1
        fi
        
        local file_size=$(stat -f%z "$BACKUP_DIR/$db.dump" 2>/dev/null || stat -c%s "$BACKUP_DIR/$db.dump" 2>/dev/null)
        if [[ "$file_size" -eq 0 ]]; then
            error "Backup file is empty: $BACKUP_DIR/$db.dump"
            return 1
        fi
        
        local size=$(du -h "$BACKUP_DIR/$db.dump" | cut -f1)
        success "Database $db backed up successfully (size: $size)"
    done
    
    # Save database list for restore phase
    printf "%s\n" "${DATABASES[@]}" > "$BACKUP_DIR/database_list.txt"
    info "Database list saved to $BACKUP_DIR/database_list.txt"
    
    success "All databases backed up to $BACKUP_DIR"
    info "Backup contents:"
    ls -lh "$BACKUP_DIR"
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    return 0
}

################################################################################
# Function: extract_edb_cluster_configuration
# Purpose: Extracts EDB cluster configuration before deletion for CNPG cluster creation
# Parameters: None (uses global variables)
# Global Variables (Set):
#   - EDB_STORAGE_CLASS: Storage class from EDB cluster
#   - EDB_STORAGE_SIZE: Storage size (default: 100Gi)
#   - EDB_INSTANCES: Number of instances (default: 1)
#   - EDB_CPU_REQUESTS: CPU requests (default: 1)
#   - EDB_MEMORY_REQUESTS: Memory requests (default: 2Gi)
#   - EDB_CPU_LIMITS: CPU limits (default: 2)
#   - EDB_MEMORY_LIMITS: Memory limits (default: 4Gi)
# Global Variables (Read):
#   - OLD_CLUSTER: Name of the EDB cluster
#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
# Returns: 0 (always succeeds, uses defaults if extraction fails)
# Note: Must be called BEFORE delete_edb_cluster() to preserve configuration
################################################################################
function extract_edb_cluster_configuration() {
    info "=== EXTRACTING EDB CLUSTER CONFIGURATION ==="
    
    # Check if EDB cluster exists
    if ${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE &> /dev/null; then
        info "Extracting configuration from existing EDB cluster..."
        
        EDB_STORAGE_CLASS=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.storage.storageClass}' 2>/dev/null || echo "")
        EDB_STORAGE_SIZE=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.storage.size}' 2>/dev/null || echo "100Gi")
        EDB_INSTANCES=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.instances}' 2>/dev/null || echo "1")
        EDB_CPU_REQUESTS=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.resources.requests.cpu}' 2>/dev/null || echo "1")
        EDB_MEMORY_REQUESTS=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.resources.requests.memory}' 2>/dev/null || echo "2Gi")
        EDB_CPU_LIMITS=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.resources.limits.cpu}' 2>/dev/null || echo "2")
        EDB_MEMORY_LIMITS=$(${CLI_CMD} get cluster.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.spec.resources.limits.memory}' 2>/dev/null || echo "4Gi")
        
        if [[ -z "$EDB_STORAGE_CLASS" ]]; then
            warning "Could not extract storage class from EDB cluster"
        else
            info "Extracted storage class: $EDB_STORAGE_CLASS"
        fi
        
        info "Configuration extracted:"
        info "  Storage: $EDB_STORAGE_SIZE on ${EDB_STORAGE_CLASS:-<not set>}"
        info "  Instances: $EDB_INSTANCES"
        info "  Resources: CPU($EDB_CPU_REQUESTS/$EDB_CPU_LIMITS) Memory($EDB_MEMORY_REQUESTS/$EDB_MEMORY_LIMITS)"
    else
        warning "EDB cluster does not exist, using default configuration"
    fi
    
    return 0
}


################################################################################
# Function: delete_edb_cluster
# Purpose: Deletes the old EDB PostgreSQL cluster and associated resources
# Parameters: None (uses global variables)
# Global Variables:
#   - OLD_CLUSTER: Name of the EDB cluster to delete
#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success, 1 on error
# Note: Deletes cluster, services, and PVCs. Waits for cleanup completion.
################################################################################
function delete_edb_cluster() {
    info "=== PHASE: DELETING OLD EDB CLUSTER ==="
    
    # Check if EDB cluster exists
    if ${CLI_CMD} get clusters.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE &> /dev/null; then
        info "EDB cluster '$OLD_CLUSTER' found."
        warning "This will delete the EDB PostgreSQL cluster: $OLD_CLUSTER"
        warning "Ensure backups are complete and verified before proceeding!"
        if [[ "$SKIP_FOR_API" != "true" ]]; then
            prompt_press_any_key_to_continue
        fi
        
        # Delete cluster using correct EDB API
        info "Deleting EDB cluster..."
        ${CLI_CMD} delete clusters.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE --wait=false
        
        # Poll for actual cluster deletion
        info "Waiting for EDB cluster to be fully deleted..."
        local max_wait=$EDB_CLUSTER_DELETE_TIMEOUT
        local elapsed=0
        local check_interval=5
        
        while ${CLI_CMD} get clusters.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE &>/dev/null; do
            if [[ $elapsed -ge $max_wait ]]; then
                error "Timeout waiting for EDB cluster deletion after ${max_wait} seconds"
                error "Cluster may still be terminating. Check with:"
                error "  ${CLI_CMD} get clusters.postgresql.k8s.enterprisedb.io $OLD_CLUSTER -n $SERVICES_NAMESPACE"
                return 1
            fi
            
            if [[ $((elapsed % 15)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
                info "Still waiting for cluster deletion... (${elapsed}s elapsed)"
            fi
            
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done
        
        success "EDB cluster deleted successfully (took ${elapsed}s)"
        
        # Delete services
        info "Deleting old EDB services..."
        ${CLI_CMD} delete svc ${OLD_CLUSTER}-rw -n $SERVICES_NAMESPACE --ignore-not-found=true
        ${CLI_CMD} delete svc ${OLD_CLUSTER}-ro -n $SERVICES_NAMESPACE --ignore-not-found=true
        ${CLI_CMD} delete svc ${OLD_CLUSTER}-r -n $SERVICES_NAMESPACE --ignore-not-found=true
        
        # Wait for services to be deleted
        info "Waiting for services to be deleted..."
        max_wait=$SERVICE_DELETE_TIMEOUT
        elapsed=0
        
        while ${CLI_CMD} get svc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" &>/dev/null; do
            if [[ $elapsed -ge $max_wait ]]; then
                warning "Some services still exist after ${max_wait}s, continuing anyway"
                break
            fi
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
        done
        
        success "All EDB services deleted"
        
        # Delete PVCs with proper waiting and finalizer handling
        info "Deleting old EDB PVCs..."
        local pvcs=$(${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" | awk '{print $1}')
        
        if [[ -z "$pvcs" ]]; then
            info "No PVCs found for cluster $OLD_CLUSTER"
        else
            info "Found PVCs to delete:"
            echo "$pvcs" | while read pvc; do
                info "  - $pvc"
            done
            
            # Delete PVCs without waiting
            echo "$pvcs" | xargs ${CLI_CMD} delete pvc -n $SERVICES_NAMESPACE --wait=false 2>/dev/null || true
            
            # Wait for PVCs to be fully deleted
            info "Waiting for PVCs to be fully deleted..."
            max_wait=$PVC_DELETE_TIMEOUT
            elapsed=0
            local finalizer_check_done=false
            
            while ${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" &>/dev/null; do
                if [[ $elapsed -ge $max_wait ]]; then
                    warning "Some PVCs still terminating after ${max_wait}s"
                    warning "Remaining PVCs:"
                    ${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" || true
                    warning "These may need manual cleanup if they remain stuck"
                    break
                fi
                
                # After 30 seconds, check for stuck PVCs with finalizers
                if [[ $elapsed -ge 30 ]] && [[ "$finalizer_check_done" == "false" ]]; then
                    finalizer_check_done=true
                    info "Checking for PVCs stuck with finalizers..."
                    
                    local stuck_pvcs=$(${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" | awk '{print $1}')
                    if [[ -n "$stuck_pvcs" ]]; then
                        for pvc in $stuck_pvcs; do
                            # Check if PVC has finalizers
                            local finalizers=$(${CLI_CMD} get pvc $pvc -n $SERVICES_NAMESPACE -o jsonpath='{.metadata.finalizers}' 2>/dev/null)
                            if [[ -n "$finalizers" ]] && [[ "$finalizers" != "[]" ]]; then
                                warning "PVC $pvc has finalizers, attempting to remove them..."
                                info "Finalizers: $finalizers"
                                
                                # Remove finalizers by patching the PVC
                                if ${CLI_CMD} patch pvc $pvc -n $SERVICES_NAMESPACE -p '{"metadata":{"finalizers":null}}' --type=merge 2>/dev/null; then
                                    success "Removed finalizers from PVC $pvc"
                                else
                                    warning "Failed to remove finalizers from PVC $pvc"
                                fi
                            fi
                        done
                    fi
                fi
                
                if [[ $((elapsed % 15)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
                    local remaining=$(${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" | wc -l | tr -d ' ')
                    info "Still waiting for $remaining PVC(s) to be deleted... (${elapsed}s elapsed)"
                fi
                
                sleep $check_interval
                elapsed=$((elapsed + check_interval))
            done
            
            # Final verification
            if ! ${CLI_CMD} get pvc -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${OLD_CLUSTER}-" &>/dev/null; then
                success "All PVCs deleted successfully (took ${elapsed}s)"
            fi
        fi
    else
        info "EDB cluster '$OLD_CLUSTER' not found (may have been deleted already)."
        info "Skipping all EDB cluster cleanup (cluster, services, PVCs)..."
        success "No EDB resources to clean up."
    fi
    
    # Check if CNPG cluster exists and warn user
    if ${CLI_CMD} get cluster.pg.ibm.com $NEW_CLUSTER -n $SERVICES_NAMESPACE &> /dev/null; then
        warning "IBM CloudNativePG cluster '$NEW_CLUSTER' already exists!"
        warning "If you want to recreate it, delete it first with:"
        warning "  ${CLI_CMD} delete cluster.pg.ibm.com $NEW_CLUSTER -n $SERVICES_NAMESPACE"
        echo ""
        if [[ "$SKIP_FOR_API" != "true" ]]; then
            read -p "Do you want to continue and skip the IBM CloudNativePG cluster creation? (yes/no): " confirm
        else
            confirm="yes"
        fi
        confirm_lower=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
        if [[ "$confirm_lower" != "yes" ]] && [[ "$confirm_lower" != "y" ]]; then
            info "Operation aborted by user."
            echo ""
            displayEdbMigrationRetryMessage "create-cluster" "$SERVICES_NAMESPACE" "$cp4a_operator_csv_version"
            exit 1
        fi
        # Set a flag to skip cluster creation
        SKIP_CNPG_CREATION=true
    else
        success "All $OLD_CLUSTER PVCs removed"
    fi
    
    success "EDB cluster deleted and cleaned up."
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    return 0
}

################################################################################
# Function: install_cnpg_operator
# Purpose: Installs IBM CloudNativePG operator via subscription
# Parameters: None (uses global variables)
# Global Variables:
#   - NAMESPACE: Kubernetes namespace for operator
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success, 1 on error
# Note: Checks if operator already exists, waits for operator pod to be ready
################################################################################
function install_cnpg_operator() {
    info "=== PHASE: INSTALLING IBM CloudNativePG OPERATOR ==="
    
    # Check if subscription already exists
    if ${CLI_CMD} get subscription ibm-pg-operator -n $OPERATOR_NAMESPACE &> /dev/null; then
        info "IBM CloudNativePG operator subscription already exists, checking operator status..."
        
        # Check if CSV already exists and is ready
        local existing_csv=$(${CLI_CMD} get csv ${CNPG_OPERATOR_CSV_VERSION} -n $OPERATOR_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [[ "$existing_csv" == "Succeeded" ]]; then
            success "IBM CloudNativePG operator already installed and ready!"
            info "CSV: ${CNPG_OPERATOR_CSV_VERSION}"
            return 0
        else
            info "Operator subscription exists but CSV not ready yet (phase: $existing_csv)"
            info "Will wait for operator to become ready..."
            # Continue to wait logic below
        fi
    else
        info "Creating IBM CloudNativePG operator subscription..."
        
        # Check if template file exists
        if [[ ! -f "$CNPG_OPERATOR_SUBSCRIPTION_TEMPLATE" ]]; then
            error "IBM CloudNativePG operator subscription template not found: $CNPG_OPERATOR_SUBSCRIPTION_TEMPLATE"
            return 1
        fi
        
        # Generate subscription manifest from template
        local CNPG_SUBSCRIPTION_MANIFEST="${TEMP_FOLDER}/cnpg-operator-subscription.yaml"
        info "Generating IBM CloudNativePG operator subscription manifest from template..."
        
        # Copy template and replace placeholders using yq
        cp "$CNPG_OPERATOR_SUBSCRIPTION_TEMPLATE" "$CNPG_SUBSCRIPTION_MANIFEST"
        
        # Replace namespace placeholder
        ${YQ_CMD} eval ".metadata.namespace = \"$OPERATOR_NAMESPACE\"" -i "$CNPG_SUBSCRIPTION_MANIFEST"
        ${YQ_CMD} eval ".spec.sourceNamespace = \"$OPERATOR_NAMESPACE\"" -i "$CNPG_SUBSCRIPTION_MANIFEST"
        
        # Replace channel placeholder
        ${YQ_CMD} eval ".spec.channel = \"$CNPG_OPERATOR_CHANNEL\"" -i "$CNPG_SUBSCRIPTION_MANIFEST"
        
        info "Applying IBM CloudNativePG operator subscription..."
        info "  Channel: $CNPG_OPERATOR_CHANNEL"
        info "  Namespace: $OPERATOR_NAMESPACE"
        
        ${CLI_CMD} apply -f "$CNPG_SUBSCRIPTION_MANIFEST"
        
        if [[ $? -ne 0 ]]; then
            error "Failed to create IBM CloudNativePG operator subscription"
            return 1
        fi
        
        success "IBM CloudNativePG operator subscription created successfully"
    fi
    
    info "Waiting for IBM CloudNativePG operator to be ready (this may take 5-10 minutes)..."
    
    # Wait for operator to be ready
    local max_wait=600  # 10 minutes
    local elapsed=0
    local interval=10
    local csv=""
    local csv_name=""
    
    while [[ $elapsed -lt $max_wait ]]; do
        # Try to find CSV by exact name first (most reliable)
        csv=$(${CLI_CMD} get csv ${CNPG_OPERATOR_CSV_VERSION} -n $OPERATOR_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        
        # Debug: show what we got
        if [[ $elapsed -eq 0 ]]; then
            info "Debug: Checking namespace=$OPERATOR_NAMESPACE, csv='$csv', length=${#csv}"
        fi
        
        # If not found by exact name, try to find by name prefix using grep
        if [[ -z "$csv" ]]; then
            csv_name=$(${CLI_CMD} get csv -n $OPERATOR_NAMESPACE --no-headers 2>/dev/null | grep "^ibm-pg-operator" | head -1 | awk '{print $1}')
            if [[ -n "$csv_name" ]]; then
                csv=$(${CLI_CMD} get csv $csv_name -n $OPERATOR_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
                if [[ $elapsed -eq 0 ]]; then
                    info "Debug: Found CSV by grep: $csv_name, phase='$csv'"
                fi
            fi
        fi
        
        # If still not found, try by display name
        if [[ -z "$csv" ]]; then
            csv=$(${CLI_CMD} get csv -n $OPERATOR_NAMESPACE -o jsonpath='{.items[?(@.spec.displayName=="IBM Cloud Native PostgreSQL")].status.phase}' 2>/dev/null || echo "")
        fi
        
        # Last resort: check if any CSV exists
        if [[ -z "$csv" ]]; then
            csv="NotFound"
        fi
        
        if [[ "$csv" == "Succeeded" ]]; then
            success "IBM CloudNativePG operator is ready!"
            success "IBM CloudNativePG operator installation complete."
            
            # Show which CSV was found
            local csv_name=$(${CLI_CMD} get csv -n $OPERATOR_NAMESPACE --no-headers 2>/dev/null | grep "^ibm-pg-operator" | head -1 | awk '{print $1}')
            if [[ -z "$csv_name" ]]; then
                csv_name="${CNPG_OPERATOR_CSV_VERSION}"
            fi
            info "CSV: $csv_name"
            
            if [[ "$SKIP_FOR_API" != "true" ]]; then
                prompt_press_any_key_to_continue
            fi
            return 0
        fi
        
        # Show more detailed status every 30 seconds
        if [[ $((elapsed % 30)) -eq 0 ]] && [[ $elapsed -gt 0 ]]; then
            info "Detailed status check:"
            ${CLI_CMD} get csv -n $OPERATOR_NAMESPACE 2>/dev/null | head -5 || info "  No CSV found yet"
        fi
        
        info "Operator status: $csv (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    # If we get here, we timed out
    error "Timeout waiting for IBM CloudNativePG operator to be ready!"
    error "Operator did not reach 'Succeeded' state within $max_wait seconds."
    echo ""
    info "Checking operator status..."
    ${CLI_CMD} get csv -n $OPERATOR_NAMESPACE 2>/dev/null || warning "No CSV found"
    echo ""
    info "Checking subscription status..."
    ${CLI_CMD} get subscription ibm-pg-operator -n $OPERATOR_NAMESPACE -o yaml 2>/dev/null || warning "No subscription found"
    echo ""
    error "Please check the operator installation and try again."
    info "You can check operator logs with:"
    info "  ${CLI_CMD} get pods -n $OPERATOR_NAMESPACE | grep operator"
    info "  ${CLI_CMD} logs <operator-pod> -n $OPERATOR_NAMESPACE"
    return 1
}

################################################################################
# Function: generate_cnpg_manifest
# Purpose: Generates CNPG cluster manifest from template using extracted EDB configuration
# Parameters: None (uses global variables)
# Global Variables (Read):
#   - CNPG_CLUSTER_TEMPLATE: Path to template file (from common.sh)
#   - EDB_STORAGE_CLASS, EDB_STORAGE_SIZE, EDB_INSTANCES: Extracted EDB config
#   - EDB_CPU_REQUESTS, EDB_MEMORY_REQUESTS, EDB_CPU_LIMITS, EDB_MEMORY_LIMITS
#   - DATABASES: Array of database names for initdb
#   - NEW_CLUSTER: Name for the new CNPG cluster
#   - NAMESPACE: Kubernetes namespace
# Global Variables (Set):
#   - CNPG_MANIFEST: Path to generated manifest file
# Returns: 0 on success, 1 on error
# Note: Uses yq to modify template. Prompts for storage class if not extracted.
#       Template location: descriptors/cnpg/cnpg-cluster-postgres-cp4ba-template.yaml
################################################################################
function generate_cnpg_manifest() {
    # Define where the file for the CNPG cluster template to be applied will be stored
    CNPG_MANIFEST="${TEMP_FOLDER}/cnpg-cluster-postgres-cp4ba.yaml"
    info "=== GENERATING IBM CloudNativePG MANIFEST ==="
    
    if [[ ${#DATABASES[@]} -eq 0 ]]; then
        error "No databases discovered. Cannot generate manifest."
        return 1
    fi
    
    info "Generating manifest for ${#DATABASES[@]} databases..."
    
    # Check if template file exists
    if [[ ! -f "$CNPG_CLUSTER_TEMPLATE" ]]; then
        error "IBM CloudNativePG cluster template not found: $CNPG_CLUSTER_TEMPLATE"
        return 1
    fi
    
    # Use global EDB_* variables (extracted before EDB cluster deletion)
    local storage_class="$EDB_STORAGE_CLASS"
    local storage_size="$EDB_STORAGE_SIZE"
    local instances="$EDB_INSTANCES"
    local cpu_requests="$EDB_CPU_REQUESTS"
    local memory_requests="$EDB_MEMORY_REQUESTS"
    local cpu_limits="$EDB_CPU_LIMITS"
    local memory_limits="$EDB_MEMORY_LIMITS"
    
    info "Using extracted EDB configuration:"
    info "  Storage: $storage_size on ${storage_class:-<not set>}"
    info "  Instances: $instances"
    info "  Resources: CPU($cpu_requests/$cpu_limits) Memory($memory_requests/$memory_limits)"
    
    # If storage class wasn't extracted, ask user or list available options
    if [[ -z "$storage_class" ]]; then
        warning "Storage class not available from EDB cluster"
        info "Available storage classes in the cluster:"
        ${CLI_CMD} get storageclass --no-headers | awk '{print "  - " $1}' || warning "Could not list storage classes"
        echo ""
        read -p "Enter storage class name (or press Enter for default 'ocs-storagecluster-ceph-rbd'): " user_storage_class
        
        if [[ -n "$user_storage_class" ]]; then
            storage_class="$user_storage_class"
            info "Using user-provided storage class: $storage_class"
        else
            storage_class="ocs-storagecluster-ceph-rbd"
            info "Using default storage class: $storage_class"
        fi
    fi
    
    info "Configuration extracted:"
    info "  Storage Class: $storage_class"
    info "  Storage Size: $storage_size"
    info "  Instances: $instances"
    info "  CPU Requests: $cpu_requests, Limits: $cpu_limits"
    info "  Memory Requests: $memory_requests, Limits: $memory_limits"
    
    # Copy template and use yq to replace placeholders
    info "Generating manifest from template: $CNPG_CLUSTER_TEMPLATE"
    cp "$CNPG_CLUSTER_TEMPLATE" "$CNPG_MANIFEST"
    
    # Use yq to replace placeholders with actual values
    ${YQ_CMD} eval -i ".metadata.name = \"${NEW_CLUSTER}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".metadata.namespace = \"${SERVICES_NAMESPACE}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.instances = ${instances}" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.storage.size = \"${storage_size}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.storage.storageClass = \"${storage_class}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.resources.requests.memory = \"${memory_requests}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.resources.requests.cpu = \"${cpu_requests}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.resources.limits.memory = \"${memory_limits}\"" "$CNPG_MANIFEST"
    ${YQ_CMD} eval -i ".spec.resources.limits.cpu = \"${cpu_limits}\"" "$CNPG_MANIFEST"
    
    success "IBM CloudNativePG manifest generated: $CNPG_MANIFEST"
    info "Manifest includes the following databases:"
    for db in "${DATABASES[@]}"; do
        info "  - $db"
    done
    
    echo ""
    info "Manifest configuration (extracted from EDB cluster):"
    info "  - instances: $instances"
    info "  - storage.size: $storage_size"
    info "  - storage.storageClass: $storage_class"
    info "  - resources.requests: cpu=$cpu_requests, memory=$memory_requests"
    info "  - resources.limits: cpu=$cpu_limits, memory=$memory_limits"
    echo ""
    info "You can review and customize the manifest before deployment if needed."
    echo ""
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    return 0
}

################################################################################
# Function: deploy_cnpg_cluster
# Purpose: Deploys the IBM CNPG cluster and waits for it to be ready
# Parameters: None (uses global variables)
# Global Variables:
#   - SKIP_CNPG_CREATION: If true, skips cluster creation
#   - CNPG_MANIFEST: Path to generated manifest file
#   - NEW_CLUSTER: Name of the CNPG cluster
#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success, 1 on error
# Note: Calls generate_cnpg_manifest() if manifest doesn't exist.
#       Waits for cluster to reach "Cluster in healthy state" status.
################################################################################
function deploy_cnpg_cluster() {
    info "=== PHASE: DEPLOYING IBM IBM CloudNativePG CLUSTER ==="
    
    # Check if we should skip cluster creation
    if [[ "$SKIP_CNPG_CREATION" = true ]]; then
        info "IBM CloudNativePG cluster already exists, skipping creation."
        success "Using existing IBM CloudNativePG cluster: $NEW_CLUSTER"
        return 0
    fi
    
    # Generate manifest if it doesn't exist or if it contains invalid/outdated fields
    if [[ ! -f "$CNPG_MANIFEST" ]]; then
        info "Manifest not found, generating from discovered databases..."
        generate_cnpg_manifest
    else
        # Validate existing manifest for invalid fields or hardcoded values
        local needs_regeneration=false
        local reason=""
        
        # Check for wrong namespace
        local manifest_namespace=$(grep "namespace:" "$CNPG_MANIFEST" | head -1 | awk '{print $2}')
        if [[ -n "$manifest_namespace" ]] && [[ "$manifest_namespace" != "$SERVICES_NAMESPACE" ]]; then
            needs_regeneration=true
            reason="namespace mismatch (manifest: $manifest_namespace, current: $SERVICES_NAMESPACE)"
        elif grep -q "bootstrap.initdb.databases\|monitoring.enabled" "$CNPG_MANIFEST" 2>/dev/null; then
            needs_regeneration=true
            reason="invalid API fields detected"
        elif grep -q "storageClass: ocs-storagecluster-ceph-rbd" "$CNPG_MANIFEST" 2>/dev/null; then
            needs_regeneration=true
            reason="hardcoded storage class detected (should be extracted from EDB cluster)"
        elif grep -q "instances: 3" "$CNPG_MANIFEST" 2>/dev/null; then
            needs_regeneration=true
            reason="instance count is 3 (should be 1 based on current configuration)"
        fi
        
        if [[ "$needs_regeneration" = true ]]; then
            warning "Existing manifest needs regeneration: $reason"
            info "Backing up old manifest to ${CNPG_MANIFEST}.old"
            mv "$CNPG_MANIFEST" "${CNPG_MANIFEST}.old"
            info "Regenerating manifest with configuration from EDB cluster..."
            generate_cnpg_manifest
        else
            info "Using existing manifest: $CNPG_MANIFEST"
            info "Manifest validation: OK"
        fi
    fi
    
    info "Deploying IBM CloudNativePG cluster from $CNPG_MANIFEST..."
    ${CLI_CMD} apply -f $CNPG_MANIFEST
    
    info "Waiting for IBM CloudNativePG cluster to be ready (this may take 2-3 minutes)..."
    
    # Wait for cluster to be ready
    local max_wait=300  # 5 minutes
    local elapsed=0
    local interval=10
    
    while [[ $elapsed -lt $max_wait ]]; do
        local status=$(${CLI_CMD} get cluster.pg.ibm.com $NEW_CLUSTER -n $SERVICES_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
        
        if [[ "$status" == "Cluster in healthy state" ]]; then
            success "IBM CloudNativePG cluster is ready!"
            break
        fi
        
        info "Cluster status: $status (waiting...)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    
    if [[ $elapsed -ge $max_wait ]]; then
        error "Timeout waiting for IBM CloudNativePG cluster to be ready."
        exit 1
    fi
    
    # Show cluster status
    info "Cluster details:"
    ${CLI_CMD} get cluster.pg.ibm.com $NEW_CLUSTER -n $SERVICES_NAMESPACE
    
    info "Cluster pods:"
    ${CLI_CMD} get pods -n $SERVICES_NAMESPACE | grep "^${NEW_CLUSTER}-"
    
    success "IBM CloudNativePG cluster deployed successfully."
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    return 0
}

################################################################################
# Function: restore_databases
# Purpose: Restores all databases from backup files to CNPG cluster
# Parameters: None (uses global variables)
# Global Variables:
#   - BACKUP_DIR: Directory containing backup .sql files
#   - DATABASES: Array of database names to restore
#   - NEW_CLUSTER: Name of the CNPG cluster
#   - NAMESPACE: Kubernetes namespace
#   - CLI_CMD: kubectl or oc command
################################################################################
# Function: validate_database_post_restore
# Purpose: Validates a restored database by comparing table counts and row estimates
# Parameters:
#   $1 - pod: CNPG pod name
#   $2 - db: Database name to validate
# Global Variables:
#   - NAMESPACE: Kubernetes namespace
#   - BACKUP_DIR: Directory containing validation files
#   - CLI_CMD: kubectl or oc command
# Returns: 0 (always succeeds, logs warnings for mismatches)
# Note: Saves validation data to post_restore_validation.txt and compares with
#       pre_backup_validation.txt if available
################################################################################
function validate_database_post_restore() {
    local pod=$1
    local db=$2
    
    info "Validating restored database: $db"
    
    # Force fresh statistics so n_live_tup is accurate (critical after restore)
    info "  Updating database statistics (ANALYZE)..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -c "ANALYZE;" 2>/dev/null
    if [[ $? -eq 0 ]]; then
        info "  ✓ Statistics updated"
    else
        warning "  ⚠ Failed to update statistics, row estimates may be inaccurate"
    fi
    
    # Get table count
    local table_count=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema');" 2>/dev/null | xargs)
    
    # Get row count estimate (n_live_tup from pg_stat_user_tables - now fresh after ANALYZE)
    local row_estimate=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT SUM(n_live_tup) FROM pg_stat_user_tables;" 2>/dev/null | xargs)
    
    # Get database size
    local db_size=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $pod -- psql -U postgres -d $db -t -c "SELECT pg_size_pretty(pg_database_size('$db'));" 2>/dev/null | xargs)
    
    # Save validation data
    echo "$db|$table_count|$row_estimate|$db_size" >> "$BACKUP_DIR/post_restore_validation.txt"
    
    info "  Tables: $table_count, Estimated Rows: $row_estimate (from fresh statistics), Size: $db_size"
    
    # Compare with pre-backup data
    if [[ -f "$BACKUP_DIR/pre_backup_validation.txt" ]]; then
        local pre_data=$(grep "^$db|" "$BACKUP_DIR/pre_backup_validation.txt")
        local pre_tables=$(echo "$pre_data" | cut -d'|' -f2)
        local pre_rows=$(echo "$pre_data" | cut -d'|' -f3)
        
        if [[ "$table_count" == "$pre_tables" ]]; then
            success "  ✓ Table count matches: $table_count"
        else
            warning "  ⚠ Table count mismatch: Pre=$pre_tables, Post=$table_count"
        fi
        
        # Allow 5% variance in row count (due to ANALYZE estimates)
        # Note: With fresh ANALYZE on both sides, variance should be minimal (<1%)
        if [[ -n "$pre_rows" ]] && [[ -n "$row_estimate" ]] && [[ "$pre_rows" != "null" ]] && [[ "$row_estimate" != "null" ]]; then
            local diff=$((row_estimate - pre_rows))
            local abs_diff=${diff#-}
            local threshold=$((pre_rows * 5 / 100))
            
            if [[ $abs_diff -le $threshold ]]; then
                success "  ✓ Row count matches: $row_estimate (variance: $diff rows, ${abs_diff} from pre-backup)"
            else
                warning "  ⚠ Row count variance exceeds 5%: Pre=$pre_rows, Post=$row_estimate (diff: $diff)"
                warning "  Note: This compares statistical estimates. Verify with exact counts if concerned."
            fi
        fi
    fi
}

################################################################################
# Function: compare_validation_results
# Purpose: Compares pre-backup and post-restore validation data for all databases
# Parameters: None (uses global variables)
# Global Variables:
#   - BACKUP_DIR: Directory containing validation files
# Returns: 0 (always succeeds)
# Note: Displays formatted comparison table showing table counts and row estimates
#       before and after migration
################################################################################
function compare_validation_results() {
    info "=== VALIDATION COMPARISON ==="
    
    if [[ ! -f "$BACKUP_DIR/pre_backup_validation.txt" ]] || [[ ! -f "$BACKUP_DIR/post_restore_validation.txt" ]]; then
        warning "Validation files not found, skipping comparison."
        return 0
    fi
    
    info "Database validation summary:"
    echo ""
    printf "%-20s %-10s %-15s %-15s %-10s\n" "Database" "Tables" "Rows (Pre)" "Rows (Post)" "Status"
    printf "%-20s %-10s %-15s %-15s %-10s\n" "--------" "------" "-----------" "-----------" "------"
    
    while IFS='|' read -r db tables rows size; do
        local post_line=$(grep "^$db|" "$BACKUP_DIR/post_restore_validation.txt" 2>/dev/null)
        if [[ -n "$post_line" ]]; then
            local post_tables=$(echo "$post_line" | cut -d'|' -f2)
            local post_rows=$(echo "$post_line" | cut -d'|' -f3)
            
            local status="✓ OK"
            if [[ "$tables" != "$post_tables" ]]; then
                status="⚠ WARN"
            fi
            
            printf "%-20s %-10s %-15s %-15s %-10s\n" "$db" "$tables" "$rows" "$post_rows" "$status"
        fi
    done < "$BACKUP_DIR/pre_backup_validation.txt"
    
    echo ""
    success "Validation comparison complete. Check files for details:"
    info "  Pre-backup:  $BACKUP_DIR/pre_backup_validation.txt"
    info "  Post-restore: $BACKUP_DIR/post_restore_validation.txt"
}

# Returns: 0 on success, exits on error
# Note: Uses psql to restore each database from its backup file
################################################################################
function restore_databases() {
    info "=== PHASE: RESTORING DATABASES ==="
    
    # Get CNPG pod name (primary) - use name-based search
    info "Looking for IBM CloudNativePG PostgreSQL primary pod..."
    
    # CNPG pods are named: <cluster-name>-1, <cluster-name>-2, etc.
    # Primary is typically -1
    local CNPG_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${NEW_CLUSTER}-1 " | awk '{print $1}')
    
    # If -1 not found, try any pod from the cluster
    if [[ -z "$CNPG_POD" ]]; then
        CNPG_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${NEW_CLUSTER}-" | head -1 | awk '{print $1}')
    fi
    
    if [[ -z "$CNPG_POD" ]]; then
        error "Could not find IBM CloudNativePG PostgreSQL pod."
        error "Expected pod name pattern: ${NEW_CLUSTER}-1"
        error "Available pods in namespace $SERVICES_NAMESPACE:"
        ${CLI_CMD} get pods -n $SERVICES_NAMESPACE
        return 1
    fi
    
    info "Using IBM CloudNativePG pod: $CNPG_POD"
    
    # Check if databases have already been restored
    info "Checking if databases have already been restored..."
    local already_restored=0
    local databases_with_data=0
    
    for db in "${DATABASES[@]}"; do
        # Check if database exists and has tables
        local table_count=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -d $db -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema');" 2>/dev/null | xargs || echo "0")
        
        if [[ "$table_count" != "0" ]] && [[ -n "$table_count" ]]; then
            databases_with_data=$((databases_with_data + 1))
            info "  Database '$db' already has $table_count tables"
        fi
    done
    
    if [[ $databases_with_data -gt 0 ]]; then
        warning "Found $databases_with_data database(s) that already contain data!"
        warning "This suggests the restore has already been completed."
        echo ""
        if [[ "$SKIP_FOR_API" != "true" ]]; then
            read -p "Do you want to skip restore and proceed to validation? (yes/no): " skip_restore
        else
            skip_restore="yes"
        fi
        
        if [[ "$skip_restore" = "yes" ]]; then
            info "Skipping restore, proceeding to validation..."
            
            # Run post-restore validation
            info "=== POST-RESTORE VALIDATION ==="
            for db in "${DATABASES[@]}"; do
                validate_database_post_restore "$CNPG_POD" "$db"
            done
            success "Post-restore validation complete."
            
            # Compare results
            compare_validation_results
            return 0
        else
            warning "Continuing with restore - this will DROP and recreate databases!"
            echo ""
            if [[ "$SKIP_FOR_API" != "true" ]]; then
                read -p "Are you absolutely sure? (yes/no): " confirm_restore
                if [[ "$confirm_restore" != "yes" ]]; then
                    info "Restore aborted by user."
                    echo ""
                    displayEdbMigrationRetryMessage "restore" "$SERVICES_NAMESPACE" "$cp4a_operator_csv_version"
                    exit 1
                fi
            fi
        fi
    fi
    
    # Create restore directory
    info "Creating restore directory in pod..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- mkdir -p $RESTORE_DIR
    
    # Copy backup files to pod
    info "Copying backup files to pod..."
    ${CLI_CMD} cp "$BACKUP_DIR/globals.sql" $SERVICES_NAMESPACE/$CNPG_POD:$RESTORE_DIR/globals.sql
    
    # Copy database ownership and grants file if it exists
    if [[ -f "$BACKUP_DIR/db_ownership_grants.sql" ]]; then
        ${CLI_CMD} cp "$BACKUP_DIR/db_ownership_grants.sql" $SERVICES_NAMESPACE/$CNPG_POD:$RESTORE_DIR/db_ownership_grants.sql
    fi
    
    for db in "${DATABASES[@]}"; do
        info "Copying $db.dump..."
        ${CLI_CMD} cp "$BACKUP_DIR/$db.dump" $SERVICES_NAMESPACE/$CNPG_POD:$RESTORE_DIR/$db.dump
    done
    
    success "Backup files copied to pod."
    
    # STEP 1: Create all databases first (before restoring globals)
    # This ensures that database-level GRANTs in globals.sql will succeed
    info "Creating all databases..."
    for db in "${DATABASES[@]}"; do
        info "Creating database: $db"
        
        # Drop database if exists (for app database created by bootstrap)
        ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -c "DROP DATABASE IF EXISTS $db;" || true
        
        # Create database with UTF8 encoding
        ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -c "CREATE DATABASE $db ENCODING 'UTF8';"
        
        success "Database $db created."
    done
    echo ""
    
    # STEP 2: Restore globals (roles, tablespaces, and database-level permissions)
    # Now that databases exist, database-level GRANTs in globals.sql will work
    info "Restoring global objects (roles, tablespaces, database permissions)..."
    # Create tablespace directories referenced in globals.sql to avoid directory not exist errors
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- sh -c "for dir in \$(grep -o \"LOCATION '[^']*'\" $RESTORE_DIR/globals.sql 2>/dev/null | cut -d\"'\" -f2); do mkdir -p \"\$dir\"; done" || true
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -f $RESTORE_DIR/globals.sql || true
    success "Globals restored (some errors are expected for pre-existing roles)."
    echo ""
    
    # STEP 2.5: Apply database-level ownership and grants
    # This ensures all databases have correct ownership and permissions
    # even if pg_dumpall --globals-only didn't capture them
    if ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- test -f $RESTORE_DIR/db_ownership_grants.sql 2>/dev/null; then
        info "Applying database-level ownership and grants..."
        ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -f $RESTORE_DIR/db_ownership_grants.sql || true
        success "Database ownership and grants applied."
        echo ""
    else
        warning "Database ownership/grants file not found, skipping this step."
        echo ""
    fi
    
    # STEP 3: Restore data for each database
    info "Restoring data for all databases..."
    for db in "${DATABASES[@]}"; do
        info "Restoring data to database: $db"
        
        # Restore data using pg_restore
        ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- pg_restore -U postgres -d $db $RESTORE_DIR/$db.dump
        
        # Run ANALYZE to update statistics
        info "Running ANALYZE on $db..."
        ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -d $db -c "ANALYZE;"
        
        success "Database $db restored successfully."
    done
    
    # Cleanup restore directory
    info "Cleaning up restore directory..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- rm -rf $RESTORE_DIR
    
    success "All databases restored successfully."
    echo ""
    
    # Validate databases after restore
    info "Validating databases after restore..."
    for db in "${DATABASES[@]}"; do
        validate_database_post_restore "$CNPG_POD" "$db"
    done
    success "Post-restore validation complete."
    echo ""
    
    # Compare validation results
    compare_validation_results
    
    if [[ "$SKIP_FOR_API" != "true" ]]; then
        prompt_press_any_key_to_continue
    fi
    return 0
}

################################################################################
# Function: verify_migration
# Purpose: Verifies the migration by checking database connectivity and data
# Parameters: None (uses global variables)
# Global Variables:
#   - NEW_CLUSTER: Name of the CNPG cluster
#   - SERVICES_NAMESPACE: Kubernetes namespace where CNPG cluster exists
#   - OPERATOR_NAMESPACE: Kubernetes namespace where operator is installed
#   - DATABASES: Array of database names to verify
#   - CLI_CMD: kubectl or oc command
# Returns: 0 on success
# Note: Connects to CNPG cluster and lists databases to verify restoration
################################################################################
function verify_migration() {
    info "=== PHASE: VERIFICATION ==="
        
    # Get CNPG pod using name-based search
    local CNPG_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${NEW_CLUSTER}-1 " | awk '{print $1}')
    
    if [[ -z "$CNPG_POD" ]]; then
        CNPG_POD=$(${CLI_CMD} get pods -n $SERVICES_NAMESPACE --no-headers 2>/dev/null | grep "^${NEW_CLUSTER}-" | head -1 | awk '{print $1}')
    fi
    
    info "Verifying PostgreSQL version..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -c "SELECT version();"
    
    info "Verifying databases..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -c "\l"
    
    info "Verifying tablespaces..."
    ${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -c "\db+"
    
    info "Checking database sizes..."
    for db in "${DATABASES[@]}"; do
        local size=$(${CLI_CMD} exec -n $SERVICES_NAMESPACE $CNPG_POD -- psql -U postgres -d $db -t -c "SELECT pg_size_pretty(pg_database_size('$db'));" | xargs)
        info "Database $db size: $size"
    done
    
    info "Checking key application pods..."
    info "IBM CloudNativePG cluster pods:"
    ${CLI_CMD} get pods -n $SERVICES_NAMESPACE | grep "^${NEW_CLUSTER}-\|^NAME"
    
    success "Verification complete."
    return 0
}

################################################################################
# Function: execute_backup_phase
# Purpose: Executes the complete backup phase of migration
# Parameters:
#   $1 - SERVICES_NAMESPACE: Namespace where EDB cluster and databases exist
#   $2 - OPERATOR_NAMESPACE: Namespace where operator subscription/CSV are installed
#   $3 - BACKUP_DIR: Directory to store backups
#   $4 - CR_KIND: Type of CP4BA CR (ICP4ACluster or Content)
# Returns: 0 on success, 1 on error
# Note: Orchestrates: discover_databases → scale_down_applications → backup_databases
#       Uses SERVICES_NAMESPACE for all database operations
################################################################################
function execute_backup_phase() {
    SERVICES_NAMESPACE=$1
    OPERATOR_NAMESPACE=$2
    BACKUP_DIR=$3
    CR_KIND=$4
    
    if [[ -z "$SERVICES_NAMESPACE" ]] || [[ -z "$BACKUP_DIR" ]] || [[ -z "$CR_KIND" ]]; then
        error "Missing required parameters for backup phase"
        error "Usage: execute_backup_phase <namespace> <backup_dir> <cr_kind>"
        return 1
    fi
    
    info "=== EXECUTING BACKUP PHASE ==="
    info "Services Namespace: $SERVICES_NAMESPACE"
    info "Operator Namespace: $OPERATOR_NAMESPACE"
    info "Backup Directory: $BACKUP_DIR"
    info "CR Kind: $CR_KIND"
    printf "\n"
    
    # Execute backup workflow with error handling
    if ! discover_databases; then
        error "Failed to discover databases"
        return 1
    fi
    
    if ! scale_down_applications; then
        error "Failed to scale down applications"
        return 1
    fi
    
    if ! backup_databases; then
        error "Failed to backup databases"
        return 1
    fi
    
    success "Backup phase completed successfully!"
    return 0
}

################################################################################
# Function: execute_create_cluster_phase
# Purpose: Executes the cluster creation phase of migration
# Parameters:
#   $1 - SERVICES_NAMESPACE: Namespace where EDB/CNPG clusters exist
#   $2 - OPERATOR_NAMESPACE: Namespace where operator subscription/CSV are installed
# Returns: 0 on success, 1 on error
# Note: Orchestrates: extract_edb_cluster_configuration → delete_edb_cluster →
#       install_cnpg_operator → deploy_cnpg_cluster
#       Configuration is extracted BEFORE deletion to preserve settings
#       OPERATOR_NAMESPACE is used for operator installation
#       SERVICES_NAMESPACE is used for cluster operations
################################################################################
function execute_create_cluster_phase() {
    SERVICES_NAMESPACE=$1
    OPERATOR_NAMESPACE=$2

    
    if [[ -z "$SERVICES_NAMESPACE" ]]; then
        error "Missing required parameter: namespace"
        error "Usage: execute_create_cluster_phase <namespace>"
        return 1
    fi
    
    info "=== EXECUTING CREATE CLUSTER PHASE ==="
    info "Services Namespace: $SERVICES_NAMESPACE"
    info "Operator Namespace: $OPERATOR_NAMESPACE"
    printf "\n"
    
    # Set flag for create-cluster mode (enables fallback to backup directory)
    CREATE_CLUSTER_ONLY=true
    #info "CREATE_CLUSTER_ONLY flag set to: $CREATE_CLUSTER_ONLY"
    
    # Get backup directory from ConfigMap for database discovery fallback
    BACKUP_DIR=$(${CLI_CMD} get configmap ${EDB_CNPG_MIGRATION_CM_NAME} -n "$SERVICES_NAMESPACE" \
        -o jsonpath='{.data.backup-directory}' 2>/dev/null)
    
    if [[ -z "$BACKUP_DIR" ]]; then
        warning "Backup directory not found in ConfigMap"
        warning "Database discovery will attempt to query EDB cluster (will fail if EDB deleted)"
    else
        info "Backup directory from ConfigMap: $BACKUP_DIR"
        if [[ -f "$BACKUP_DIR/database_list.txt" ]]; then
            info "Database list file exists: $BACKUP_DIR/database_list.txt"
        else
            warning "Database list file NOT found: $BACKUP_DIR/database_list.txt"
        fi
    fi
    
    # Load database list from backup (stored in ConfigMap) with error handling
    if ! discover_databases; then
        error "Failed to discover databases"
        error "CREATE_CLUSTER_ONLY=$CREATE_CLUSTER_ONLY"
        error "BACKUP_DIR=$BACKUP_DIR"
        return 1
    fi
    
    # Extract EDB configuration before deletion
    if ! extract_edb_cluster_configuration; then
        error "Failed to extract EDB cluster configuration"
        return 1
    fi
    
    # Execute create-cluster workflow with error handling
    if ! delete_edb_cluster; then
        error "Failed to delete EDB cluster"
        return 1
    fi
    
    if ! install_cnpg_operator; then
        error "Failed to install IBM CloudNativePG operator"
        return 1
    fi
    
    # deploy_cnpg_cluster will call generate_cnpg_manifest if needed
    if ! deploy_cnpg_cluster; then
        error "Failed to deploy IBM CloudNativePG cluster"
        return 1
    fi
    
    success "Create cluster phase completed successfully!"
    return 0
}

################################################################################
# Function: execute_restore_phase
# Purpose: Executes the restore phase of migration
# Parameters:
#   $1 - SERVICES_NAMESPACE: Namespace where CNPG cluster and databases exist
#   $2 - OPERATOR_NAMESPACE: Namespace where operator subscription/CSV are installed
#   $3 - BACKUP_DIR: Directory containing backup files
# Returns: 0 on success, 1 on error
# Note: Orchestrates: discover_databases → restore_databases → verify_migration
#       Uses SERVICES_NAMESPACE for all database operations
################################################################################
function execute_restore_phase() {
    SERVICES_NAMESPACE=$1
    OPERATOR_NAMESPACE=$2
    BACKUP_DIR=$3
    
    if [[ -z "$SERVICES_NAMESPACE" ]] || [[ -z "$BACKUP_DIR" ]]; then
        error "Missing required parameters for restore phase"
        error "Usage: execute_restore_phase <namespace> <backup_dir>"
        return 1
    fi
    
    info "=== EXECUTING RESTORE PHASE ==="
    info "Services Namespace: $SERVICES_NAMESPACE"
    info "Operator Namespace: $OPERATOR_NAMESPACE"
    info "Backup Directory: $BACKUP_DIR"
    printf "\n"
    
    # Set flag for restore mode (uses backup directory)
    RESTORE_ONLY=true
    
    # Load database list from backup with error handling
    if ! discover_databases; then
        error "Failed to discover databases"
        return 1
    fi
    
    # Execute restore workflow with error handling
    if ! restore_databases; then
        error "Failed to restore databases"
        return 1
    fi
    
    if ! verify_migration; then
        error "Failed to verify migration"
        return 1
    fi
    
    success "Restore phase completed successfully!"
    return 0
}
