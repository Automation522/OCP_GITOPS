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

## Chaîne CI Tekton

1. Générer le secret cosign : `bash scripts/gen-cosign-secret.sh`
2. Appliquer `tekton/serviceaccount.yaml`, `tekton/task-*.yaml`, `tekton/pipeline.yaml`
3. Configurer Tekton Chains : `oc apply -f tekton/chains-config.yaml -n openshift-pipelines`
4. Créer `tekton/secret-argocd-token.yaml` avec un token valide (`argocd account generate-token`)
5. Déclencher `tekton/pipelinerun.yaml` (ou via trigger custom)

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
