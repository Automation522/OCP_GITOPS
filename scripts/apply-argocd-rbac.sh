#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARGOCD_NAMESPACE=${ARGOCD_NAMESPACE:-openshift-gitops}
ARGOCD_USER=${ARGOCD_USER:-demoscc}

role_file="${ROOT_DIR}/argocd/role-argo-admin.yaml"
rolebinding_file="${ROOT_DIR}/argocd/rolebinding-argo-admin.yaml"
ns_binding_file="${ROOT_DIR}/argocd/rolebinding-namespace-access.yaml"

if [[ ! -f "${role_file}" || ! -f "${rolebinding_file}" || ! -f "${ns_binding_file}" ]]; then
  echo "[ERROR] Missing role or rolebinding manifests under argocd/." >&2
  exit 1
fi

echo "Applying Argo CD RBAC manifests in namespace ${ARGOCD_NAMESPACE}..."
oc apply -f "${role_file}"
oc apply -f "${rolebinding_file}"
oc apply -f "${ns_binding_file}"

oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" --resource=applications.argoproj.io get
check_permission() {
  local verb=$1
  local resource=$2
  local api_group=$3
  if oc auth can-i --as="${ARGOCD_USER}" -n "${ARGOCD_NAMESPACE}" "${verb}" "${resource}".${api_group} >/dev/null 2>&1; then
    echo "✔ ${ARGOCD_USER} can ${verb} ${resource}.${api_group}"
  else
    echo "✖ ${ARGOCD_USER} cannot ${verb} ${resource}.${api_group}" >&2
  fi
}

echo "Verifying permissions for user ${ARGOCD_USER}..."
check_permission get applications argoproj.io
check_permission create applications argoproj.io
check_permission get appprojects argoproj.io
check_permission create appprojects argoproj.io

echo "Argo CD RBAC applied. User ${ARGOCD_USER} should now be able to manage Argo CD resources."
