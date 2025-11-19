#!/usr/bin/env bash
set -euo pipefail

if ! command -v cosign >/dev/null 2>&1; then
  echo "cosign n'est pas disponible dans le PATH" >&2
  exit 1
fi

if ! command -v oc >/dev/null 2>&1; then
  echo "oc CLI est requis pour créer le secret OpenShift" >&2
  exit 1
fi

SECRET_NAME="cosign-key"
NAMESPACE="openshift-gitops"
KEY_DIR="${TMPDIR:-/tmp}/cosign-keys-$(date +%s)"
mkdir -p "$KEY_DIR"

COSIGN_PASSWORD=${COSIGN_PASSWORD:-$(openssl rand -base64 32)}
export COSIGN_PASSWORD

echo "[*] Génération de la paire de clés cosign..."
cosign generate-key-pair --output-key-prefix "${KEY_DIR}/cosign"

echo "[*] Création/ajout du secret ${SECRET_NAME} dans ${NAMESPACE}"
oc delete secret "${SECRET_NAME}" -n "${NAMESPACE}" --ignore-not-found
oc create secret generic "${SECRET_NAME}" -n "${NAMESPACE}" \
  --from-file=cosign.key="${KEY_DIR}/cosign.key" \
  --from-file=cosign.pub="${KEY_DIR}/cosign.pub" \
  --from-literal=COSIGN_PASSWORD="${COSIGN_PASSWORD}"

echo "[*] Secret créé. SHA clé publique :"
sha256sum "${KEY_DIR}/cosign.pub"

echo "[*] Nettoyage local"
rm -rf "$KEY_DIR"
