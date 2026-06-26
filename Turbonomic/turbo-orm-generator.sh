#!/bin/bash
# set -x
###############################################################################
#
# Licensed Materials - Property of IBM
#
# (C) Copyright IBM Corp. 2025. All Rights Reserved.
#
# US Government Users Restricted Rights - Use, duplication or
# disclosure restricted by GSA ADP Schedule Contract with IBM Corp.
#
###############################################################################

# ============================================================
#  Workload Identification and Script Processing Logic
# ============================================================
# This template identifies and maps Kubernetes workloads
# (Deployments/StatefulSets) to their owning Custom Resource (CR)
# using label based matching and template driven logic.
#
# ------------------------------------------------------------
# HOW WORKLOADS ARE IDENTIFIED
# ------------------------------------------------------------
# A workload is uniquely identified using:
#
#   1. matchLabels (patterns[].owned.matchLabels)
#       Used by the generation script to FILTER workloads
#        from the cluster (e.g: app.kubernetes.io/name=workflow-server)
#
#   2. selectors[].matchLabels
#       Used by Turbonomic at runtime to MATCH workloads
#        (must align exactly with Kubernetes labels)
#
#   3. selector name (patterns[].owned.selector)
#       Must EXACTLY match the key under "selectors"
#
#   4. app.kubernetes.io/instance label
#       Differentiates multiple instances of the same component
#        (e.g: icp4adeploy-bawins1, icp4adeploy-bawins2)
#
# ------------------------------------------------------------
# HOW SCRIPT USES TEMPLATE VALUES
# ------------------------------------------------------------
#
#   owner.kind:
#       Determines which CR type to query from the cluster
#        Example:
#          kind: ICP4ACluster
#        Script executes:
#          oc get ICP4ACluster -n <namespace>
#
#   owner.name:
#       Identifies the specific CR instance (e.g: icp4adeploy)
#
#   patterns[].owned.kind:
#       Determines which Kubernetes workload type to scan
#        Example:
#          kind: StatefulSet
#        Script executes:
#          oc get StatefulSet -n <namespace>
#
#   patterns[].owned.matchLabels:
#       Filters workloads of the above kind to only relevant ones
#
# ------------------------------------------------------------
# HOW MAPPING IS ESTABLISHED
# ------------------------------------------------------------
#
#   Step 1: Script fetches CRs using owner.kind
#   Step 2: Script fetches workloads using owned.kind
#   Step 3: Script filters workloads using matchLabels
#   Step 4: Script extracts instance label
#   Step 5: Script generates selector + index-based ownerPath
#
# ------------------------------------------------------------
# IMPORTANT RULES
# ------------------------------------------------------------
#
#  selector (patterns) MUST match selectors key EXACTLY
#  matchLabels must uniquely identify the intended workload
#  index ({{ index }}) must map to correct CR configuration entry
#   (e.g., baw_configuration array index)
#
# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------
#
#   owner.kind         Which CRs to process
#   owned.kind         Which workloads to scan
#   matchLabels        Which workloads to select
#   instance label     Distinguish multiple instances
#   selector           Link patterns ‚Üî selectors
#   ownerPath          Map workload ‚Üí CR resource definition
#
# ============================================================

############################################
# CONFIG
############################################
TEMPLATE_DIR="./ORMs"
OUTPUT_DIR="./generated-orms"
mkdir -p "${OUTPUT_DIR}"

############################################
# DETECT CLI (kubectl or oc)
############################################
if command -v oc >/dev/null 2>&1; then
  CLI="oc"
elif command -v kubectl >/dev/null 2>&1; then
  CLI="kubectl"
else
  echo "ERROR: Neither oc nor kubectl found"
  exit 1
fi

echo " Using CLI: $CLI"

############################################
# INPUTS
############################################
if [ -z "$1" ]; then
  read -p " Enter namespace: " NAMESPACE
else
  NAMESPACE="$1"
fi

MODE="${2:-}"

if [ -z "$MODE" ]; then
  echo "1) Generate"
  echo "2) Generate + Apply"
  read -p "Choice: " c
  [[ "$c" == "2" ]] && MODE="-apply" || MODE="-generate"
fi

IS_GENERATE=false
IS_APPLY=false

case "$MODE" in
  -generate)
    IS_GENERATE=true
    ;;
  -apply)
    IS_GENERATE=true
    IS_APPLY=true
    ;;
  *)
    echo " Invalid MODE: $MODE"
    exit 1
    ;;
esac

############################################
# Check Dependencies
############################################
command -v yq >/dev/null || { echo "yq not found"; exit 1; }
command -v jq >/dev/null || { echo "jq not found"; exit 1; }

############################################
# Check cluster access
############################################
$CLI cluster-info >/dev/null 2>&1 || {
  echo "ERROR: Not connected to Kubernetes cluster"
  exit 1
}

############################################
# Check namespace
############################################
$CLI get ns "$NAMESPACE" >/dev/null 2>&1 || {
  echo "Namespace '$NAMESPACE' not found"
  exit 1
}

############################################
# Check Turbonomic CRD
############################################
if [ "$IS_APPLY" = true ]; then
  $CLI get crd operatorresourcemappings.devops.turbonomic.io >/dev/null 2>&1 || {
    echo "Turbonomic CRD not found"
    echo "Install Turbonomic before running this script"
    exit 1
  }
fi

#echo "Environment validated"

############################################
# Build label selector
############################################
build_selector() {
  yq e -o=json '.spec.mappings.patterns[0].owned.matchLabels' "$1" | \
    jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")'
}

############################################
# Generate ORM 
############################################
generate_orm() {

  TEMPLATE=$1

  OWNER_KIND=$(yq e '.spec.owner.kind' "$TEMPLATE")
  WORKLOAD_KIND=$(yq e '.spec.mappings.patterns[0].owned.kind' "$TEMPLATE")
  BASE_NAME=$(yq e '.metadata.name' "$TEMPLATE")

  PATH_TEMPLATE=$(yq e '.spec.mappings.patterns[0].owned.path' "$TEMPLATE")
  OWNER_PATH_TEMPLATE=$(yq e '.spec.mappings.patterns[0].ownerPath' "$TEMPLATE")

  LABEL_SELECTOR=$(build_selector "$TEMPLATE")

  printf  "\n\nTemplate: $TEMPLATE\n"
  echo "WorkloadKind: $WORKLOAD_KIND"

  CRS=$($CLI get "$OWNER_KIND" -n "$NAMESPACE" \
    -o jsonpath='{.items[*].metadata.name}')

  for CR_NAME in $CRS; do

    echo "Processing CR: $CR_NAME"

    WORKLOADS=$($CLI get "$WORKLOAD_KIND" -n "$NAMESPACE" \
      -l "$LABEL_SELECTOR" \
      -o jsonpath='{range .items[*]}{.metadata.name}{"|"}{.metadata.labels.app\.kubernetes\.io/instance}{"|"}{.metadata.labels.app}{"\n"}{end}')

    if [ -z "$WORKLOADS" ]; then
      echo "No workloads found for label: $LABEL_SELECTOR"
      continue
    fi

    MATCH_FOUND=false
    INDEX=0

    ####################################
    # FIX: NO SUBSHELL HERE
    ####################################
    while IFS="|" read -r RESOURCE INSTANCE APP_LABEL; do

      [ -z "$RESOURCE" ] && continue

      if [ -z "$INSTANCE" ]; then
        INSTANCE="$APP_LABEL"
      fi

      case "$INSTANCE" in
        *${CR_NAME}*|*ins*) ;;
        *) continue ;;
      esac

      if [ "$MATCH_FOUND" = false ]; then

        OUTPUT="${OUTPUT_DIR}/${CR_NAME}-${BASE_NAME}.yaml"

        yq -n "
          .apiVersion = \"devops.turbonomic.io/v1alpha1\" |
          .kind = \"OperatorResourceMapping\" |
          .metadata.name = \"${CR_NAME}-${BASE_NAME}\" |
          .metadata.namespace = \"${NAMESPACE}\" |
          .spec.mappings.patterns = [] |
          .spec.mappings.selectors = {} |
          .spec.owner.apiVersion = \"icp4a.ibm.com/v1\" |
          .spec.owner.kind = \"${OWNER_KIND}\" |
          .spec.owner.name = \"${CR_NAME}\"
        " > "$OUTPUT"

        MATCH_FOUND=true
      fi

      ####################################
      # GET LABELS
      ####################################
      LABEL_NAME=$($CLI get "$WORKLOAD_KIND" "$RESOURCE" -n "$NAMESPACE" \
        -o jsonpath='{.metadata.labels.app\.kubernetes\.io/name}')

      LABEL_APP=""
      if [ -z "$LABEL_NAME" ]; then
          LABEL_APP=$($CLI get "$WORKLOAD_KIND" "$RESOURCE" -n "$NAMESPACE" \
          -o jsonpath='{.metadata.labels.app}')
      fi


      CONTAINER=$($CLI get "$WORKLOAD_KIND" "$RESOURCE" -n "$NAMESPACE" \
        -o jsonpath='{.spec.template.spec.containers[0].name}')



      LABEL_MLS_CAPABILITY=$($CLI get "$WORKLOAD_KIND" "$RESOURCE" -n "$NAMESPACE" -o json | \
          jq -r '.metadata.labels["app.kubernetes.io/mls-capability"] // empty')

      LABEL_INSTANCE_NAME=$($CLI get "$WORKLOAD_KIND" "$RESOURCE" -n "$NAMESPACE" \
        -o jsonpath='{.metadata.labels.app\.kubernetes\.io/instance}')



      ####################################
      # BUILD VALUES
      ####################################
      SUFFIX=${RESOURCE#${CR_NAME}-}
      SELECTOR_NAME="selector-${SUFFIX}"

      PATH_VALUE=$(echo "$PATH_TEMPLATE" | \
        sed "s/{{[[:space:]]*container.name[[:space:]]*}}/$CONTAINER/g")

      OWNER_PATH=$(echo "$OWNER_PATH_TEMPLATE" | \
        sed "s/{{[[:space:]]*index[[:space:]]*}}/$INDEX/g")

      export WORKLOAD_KIND SELECTOR_NAME PATH_VALUE OWNER_PATH LABEL_INSTANCE_NAME INSTANCE LABEL_NAME LABEL_MLS_CAPABILITY LABEL_APP

     # echo " Mapping: $RESOURCE ‚index $INDEX"

      ####################################
      # ADD PATTERN
      ####################################
      yq -i '
        .spec.mappings.patterns += [{
          "owned": {
            "apiVersion": "apps/v1",
            "kind": strenv(WORKLOAD_KIND),
            "selector": strenv(SELECTOR_NAME),
            "path": strenv(PATH_VALUE)
          },
          "ownerPath": strenv(OWNER_PATH)
        }]
      ' "$OUTPUT"


	yq -i '
	  .spec.mappings.selectors[strenv(SELECTOR_NAME)] = {
	    "matchLabels": (
	      {}
	      + (strenv(LABEL_INSTANCE_NAME) | select(length > 0) | {"app.kubernetes.io/instance": .})
	      + (strenv(LABEL_NAME) | select(length > 0) | {"app.kubernetes.io/name": .})
	      + (strenv(LABEL_MLS_CAPABILITY) | select(length > 0) | {"app.kubernetes.io/mls-capability": .})
	      + (strenv(LABEL_APP) | select(length > 0) | {"app": .})
	    )
	  }
	' "$OUTPUT"



    INDEX=$((INDEX + 1))

    done <<< "$WORKLOADS"

    ####################################
    # FINAL CHECK
    ####################################
    if [ "$MATCH_FOUND" = false ]; then
      echo "No valid mappings for CR: $CR_NAME"
      continue
    fi

    echo "Generated Turbonomic ORM: $OUTPUT"

    if [ "$IS_APPLY" = true ]; then
      echo "Applying ORM"
      $CLI apply -f "$OUTPUT" -n "$NAMESPACE"
    fi

  done
}
############################################
# main
############################################
for TEMPLATE in ${TEMPLATE_DIR}/*.template; do
  generate_orm "$TEMPLATE"
done

./apply_orm.sh -n "$NAMESPACE"

echo " Done"
