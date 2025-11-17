# Documentation de la démo

Ce dossier rassemble les guides opérationnels pour exécuter la démo GitOps
dans un environnement OpenShift 4.18 déconnecté.

## Sommaire

1. [Architecture](#architecture)
2. [Mirroring des images](#mirroring-des-images)
3. [Chaîne CI Tekton](#chaîne-ci-tekton)
4. [Déroulé de la démo](#déroulé-de-la-démo)
5. [Nettoyage](#nettoyage)

## Architecture

- Web : Node.js/Express (3 pods) utilisant `customer` table via PostgreSQL
- Base : PostgreSQL 15 StatefulSet (1 réplica) avec PVC RWX `ocs-storagecluster-cephfs`
- GitOps : Argo CD synchronise l'overlay `manifests/overlays/airgap`
- CI/CD : Pipeline Tekton `gitops-build-sign` + Tekton Chains (signatures cosign)

## Mirroring des images

1. Télécharger les images Red Hat nécessaires depuis le CDN (UBI9 nodejs, postgresql-15, buildah, argocd-rhel8)
2. Pousser les images applicatives et init dans `harbor.skyr.dca.scc/gitops/*`
3. Mettre à jour `tekton/secret-registry.yaml` avec les identifiants réels
4. Référencer les tags mirroirés dans `manifests/overlays/airgap/kustomization.yaml`
5. Cloner/pointer le dépôt Git `https://bastion.skyr.dca.scc:3000/OCP_GITOPS.git` pour Argo CD et Tekton

## Chaîne CI Tekton

1. Générer le secret cosign : `bash scripts/gen-cosign-secret.sh`
2. Appliquer `tekton/serviceaccount.yaml`, `tekton/task-*.yaml`, `tekton/pipeline.yaml`
3. Configurer Tekton Chains : `oc apply -f tekton/chains-config.yaml -n openshift-pipelines`
4. Créer `tekton/secret-argocd-token.yaml` avec un token valide (`argocd account generate-token`)
5. Déclencher `tekton/pipelinerun.yaml` (ou via trigger custom)

### Rôle des manifestes Tekton

| Fichier | Description |
| --- | --- |
| `tekton/serviceaccount.yaml` | Compte de service `pipeline-gitops` qui référence les secrets `registry-credentials` (pull/push) et `cosign-key` (signatures). |
| `tekton/secret-registry.yaml` | Secret type dockerconfigjson/annotation Tekton qui fournit l'accès à `harbor.skyr.dca.scc`. À adapter avec vos identifiants ou robot account. |
| `tekton/secret-argocd-token.yaml` | Secret opaque contenant le token API Argo CD utilisé par la Task `argocd-sync` pour lancer `argocd app sync`. |
| `tekton/task-tests.yaml` | Task `run-node-tests` qui exécute `npm ci && npm test` dans l'image UBI Node.js et s'assure que l'application est saine avant build. |
| `tekton/task-build.yaml` | Task `build-and-push` basée sur Buildah (mode privilégié) pour builder et pousser les images `customer-web` et `customer-db-init` avec vérification TLS paramétrable. |
| `tekton/task-argocd-sync.yaml` | Task qui embarque le CLI Argo CD pour se connecter (grpc-web), synchroniser l'application `customer-stack` et attendre qu'elle soit healthy. |
| `tekton/pipeline.yaml` | Pipeline `gitops-build-sign` orchestrant git clone → tests → build images → sync Argo. Les paramètres `APP_IMAGE`, `INIT_IMAGE`, `TLSVERIFY`, `ARGOCD_*` permettent l'adaptation à l'environnement airgap. |
| `tekton/pipelinerun.yaml` | Exemple de `PipelineRun` avec PVC éphémère, paramètres pointant sur Harbor et référence au secret `argocd-token`. Sert de canevas pour déclencher manuellement la chaîne. |
| `tekton/chains-config.yaml` | ConfigMap appliquée dans `openshift-pipelines` pour activer Tekton Chains avec stockage OCI (`harbor.skyr.dca.scc/gitops/signatures`) et signer via cosign. |

## Déroulé de la démo

1. Montrer la structure Git (`app/`, `manifests/`, `argocd/`, `tekton/`, `scripts/`)
2. Exécuter la Pipeline Tekton et suivre les étapes dans la console OpenShift
3. Vérifier les signatures Tekton Chains (TaskRun attested, image signée dans `harbor.skyr.dca.scc/gitops/signatures`)
4. Ouvrir la Route `customer-web` pour visualiser les derniers clients

## Nettoyage

```bash
oc delete project gitops-demo
oc delete appproject gitops-demo -n openshift-gitops
oc delete application customer-stack -n openshift-gitops
oc delete -f tekton/chains-config.yaml -n openshift-pipelines
```
