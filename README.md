# OCP GitOps Demo (Air-Gapped)

Ce dépôt héberge la démonstration GitOps d'une application Node.js/Express + PostgreSQL
exécutée sur OpenShift 4.18 en environnement déconnecté. L'objectif est de versionner
l'intégralité des manifestes (application, GitOps, CI Tekton, scripts) afin de pouvoir :

- bâtir les images applicatives dans un registre miroir interne ;
- déployer et mettre à l'échelle l'application via Argo CD ;
- assurer la traçabilité des artefacts grâce à Tekton Chains + signatures cosign.

Structure actuelle :

```text
app/            Code Node.js/Express et scripts SQL
manifests/      Manifestes Kubernetes/OpenShift (base + overlays airgap)
argocd/         Définitions Argo CD (Application, AppProject, bootstrap)
tekton/         Pipelines, Tasks et PipelineRuns Tekton
scripts/        Outils auxiliaires (ex: génération secret cosign)
docs/           Documentation détaillée (airgap, CI/CD, opérations)
```

## Aperçu rapide

| Composant | Détails |
| --- | --- |
| Application | Node.js/Express (3 pods) + PostgreSQL 15 (StatefulSet 1 réplique, PVC RWX ceph-fs) |
| Déploiement | Kustomize (`manifests/base` + overlay `manifests/overlays/airgap`) suivi par Argo CD |
| CI/CD | Pipeline Tekton (tests → build/push → signature cosign → sync Argo) + Tekton Chains |
| Air-gap | Images mirroirées dans `registry.airgap.local`, secrets registry + cosign en namespace `gitops-demo` |

## Prérequis

- Cluster OpenShift 4.18 avec OpenShift GitOps (Argo CD) et OpenShift Pipelines (Tekton)
- Accès au registre miroir `registry.airgap.local` (secret `registry-credentials`)
- CLI `oc`, `cosign`, `kustomize` ou `kubectl kustomize`
- Droits pour créer les namespaces `gitops-demo` et `openshift-gitops`

## Workflow général

1. Builder/pusher les images dans le registre airgap (pipeline Tekton ou build manuel)
2. Générer la paire de clés cosign + secret OpenShift (`scripts/gen-cosign-secret.sh`)
3. Déployer les manifestes Kustomize via Argo CD (`argocd/application.yaml`)
4. Lancer la Pipeline Tekton pour tester, builder, signer, pousser, synchroniser Argo
5. Vérifier la Route exposée pour la page "Derniers clients"

## Démarrage rapide

### 1. Préparer l'environnement GitOps

```powershell
oc new-project gitops-demo
oc apply -f argocd/appproject.yaml
oc apply -f argocd/application.yaml
```

### 2. Secrets registry + cosign

```bash
oc apply -f tekton/secret-registry.yaml -n gitops-demo
bash scripts/gen-cosign-secret.sh
```

### 3. Configurer Tekton Chains

```bash
oc apply -f tekton/chains-config.yaml -n openshift-pipelines
```

### 4. Installer les ressources Tekton

```bash
oc apply -f tekton/serviceaccount.yaml -n gitops-demo
oc apply -f tekton/task-tests.yaml -n gitops-demo
oc apply -f tekton/task-build.yaml -n gitops-demo
oc apply -f tekton/task-argocd-sync.yaml -n gitops-demo
oc apply -f tekton/pipeline.yaml -n gitops-demo
oc apply -f tekton/secret-argocd-token.yaml -n gitops-demo # renseigner token réel
```

### 5. Lancer un PipelineRun

```bash
oc create -f tekton/pipelinerun.yaml -n gitops-demo
```

Pipeline :

1. clone du dépôt
2. `npm test`
3. build/push image web
4. build/push image init
5. signature cosign (Tekton Chains)
6. sync Argo CD

### 6. Vérifier la Route

```bash
oc get route customer-web -n gitops-demo -o jsonpath='{.spec.host}'
```

## Tests locaux

```bash
cd app
npm install
npm test
```

## Notes air-gap

- Ajuster `registry.airgap.local` et les tags dans `manifests/overlays/airgap/kustomization.yaml`
- S'assurer que les images Red Hat référencées sont mirroirées localement (UBI, nodejs, buildah, postgresql)
- Mettre à jour `tekton/secret-argocd-token.yaml` avec un token réel (`argocd account generate-token`)
