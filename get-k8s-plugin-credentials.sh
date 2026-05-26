#!/bin/bash
# get-k8s-plugin-credentials.sh
#
# Run this after:
#   kubectl apply -f manifests/k8s-plugin-rbac.yaml
#
# Prints the three values you need to paste into app-config.yaml
# under kubernetes.clusterLocatorMethods.clusters

set -e

NAMESPACE="backstage"
SECRET_NAME="backstage-k8s-reader-token"

echo ""
echo "── K8s plugin credentials ───────────────────────────────────────"
echo ""

# K8S_API_URL
API_URL=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "K8S_API_URL:"
echo "  $API_URL"
echo ""

# K8S_CA_DATA
CA_DATA=$(kubectl get secret $SECRET_NAME -n $NAMESPACE \
  -o jsonpath='{.data.ca\.crt}')
echo "K8S_CA_DATA (base64):"
echo "  $CA_DATA"
echo ""

# K8S_SA_TOKEN
TOKEN=$(kubectl get secret $SECRET_NAME -n $NAMESPACE \
  -o jsonpath='{.data.token}' | base64 -d)
echo "K8S_SA_TOKEN:"
echo "  $TOKEN"
echo ""

echo "── Paste these into your deployment.yaml env vars ───────────────"
echo ""
echo "Or add them to a K8s Secret and reference via secretKeyRef,"
echo "same pattern as the Postgres credentials."
echo ""
