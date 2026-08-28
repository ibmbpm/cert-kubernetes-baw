#!/bin/bash
set -e

NAMESPACE=""
INGRESS_HOST=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -h|--host)
      INGRESS_HOST="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$NAMESPACE" ]; then
  echo "Error: Namespace is required (-n <namespace>)"
  exit 1
fi

if [ -z "$INGRESS_HOST" ]; then
  echo "Error: Ingress host is required (-h <ingress_host>)"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_TEMPLATE="${SCRIPT_DIR}/gateway_api_template_rancher_traefik_base.yaml"
OUTPUT_DIR="${SCRIPT_DIR}/../../scripts/baw-prerequisites/project/${NAMESPACE}/gateway_api_template"
OUTPUT_FILE="${OUTPUT_DIR}/gateway-api-rancher-traefik.yaml"

mkdir -p "${OUTPUT_DIR}"

echo "Fetching TLS certificate secret ibm-baw-wc-secret from namespace ${NAMESPACE}..."
CA_CERT_SECRET=$(kubectl get secret ibm-baw-wc-secret -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")
CA_KEY_SECRET=$(kubectl get secret ibm-baw-wc-secret -n "${NAMESPACE}" -o jsonpath='{.data.tls\.key}' 2>/dev/null || echo "")

if [ -z "$CA_CERT_SECRET" ] || [ -z "$CA_KEY_SECRET" ]; then
  echo "Warning: ibm-baw-wc-secret not found in ${NAMESPACE}, checking iaf-system-automationui-aui-zen-ca-secret..."
  CA_CERT_SECRET=$(kubectl get secret iaf-system-automationui-aui-zen-ca-secret -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' 2>/dev/null || echo "")
  CA_KEY_SECRET=$(kubectl get secret iaf-system-automationui-aui-zen-ca-secret -n "${NAMESPACE}" -o jsonpath='{.data.tls\.key}' 2>/dev/null || echo "")
fi

sed -e "s/<NAMESPACE>/${NAMESPACE}/g" \
    -e "s/<INGRESS_HOST>/${INGRESS_HOST}/g" \
    -e "s|<CA_CERT_SECRET>|${CA_CERT_SECRET}|g" \
    -e "s|<CA_KEY_SECRET>|${CA_KEY_SECRET}|g" \
    "${BASE_TEMPLATE}" > "${OUTPUT_FILE}"

echo "Traefik Gateway API manifest generated successfully at: ${OUTPUT_FILE}"
