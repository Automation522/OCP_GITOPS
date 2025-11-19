#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-openshift-gitops}
ARGOCD_USER=${ARGOCD_USER:-demoscc}

role_file="${ROOT_DIR}/argocd/role-argo-admin.yaml"
rolebinding_file="${ROOT_DIR}/argocd/rolebinding-argo-admin.yaml"

if [[ ! -f "${role_file}" || ! -f "${rolebinding_file}" ]]; then
  echo "[ERROR] Missing role or rolebinding manifests under argocd/." >&2
  exit 1
fi

echo "Applying Argo CD RBAC manifests in namespace ${ARGOCD_NAMESPACE}..."
oc apply -f "${role_file}"
oc apply -f "${rolebinding_file}"

echo "Verifying permissions for user ${ARGOCD_USER}..."
oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" --resource=applications.argoproj.io get
oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" --resource=applications.argoproj.io create
oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" --resource=appprojects.argoproj.io get
oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" --resource=appprojects.argoproj.io create

echo "Argo CD RBAC applied. User ${ARGOCD_USER} should now be able to manage Argo CD resources."
