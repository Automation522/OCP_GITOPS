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
| Déploiement | Kustomize (`manifests/base` + overlay `manifests/overlays/airgap`) suivi par Argo CD |
| CI/CD | Pipeline Tekton (tests → build/push → signature cosign → sync Argo) + Tekton Chains |
| Air-gap | Images mirroirées dans `harbor.skyr.dca.scc`, secrets registry + cosign en namespace `gitops-demo` |

## Prérequis

- Cluster OpenShift 4.18 avec OpenShift GitOps (Argo CD) et OpenShift Pipelines (Tekton)
- Accès au registre miroir `harbor.skyr.dca.scc` (secret `registry-credentials`)
- CLI `oc`, `cosign`, `kustomize` ou `kubectl kustomize`
- Droits pour créer les namespaces `gitops-demo` et `openshift-gitops`

## Workflow général

1. Builder/pusher les images dans le registre airgap (pipeline Tekton ou build manuel)
2. Générer la paire de clés cosign + secret OpenShift (`scripts/gen-cosign-secret.sh`)
3. Déployer les manifestes Kustomize via Argo CD (`argocd/application.yaml`)
4. Lancer la Pipeline Tekton pour tester, builder, signer, pousser, synchroniser Argo
5. Vérifier la Route exposée pour la page "Derniers clients"

## Guide étape par étape

### Étape 0 — Préparer le cluster

1. Installer les opérateurs **OpenShift GitOps** et **OpenShift Pipelines** via OperatorHub.
2. Vérifier l'existence des namespaces `openshift-gitops` et `openshift-pipelines`.
3. Créer (ou réutiliser) le namespace applicatif :

```powershell
oc new-project gitops-demo
```

### Étape 1 — Déployer le squelette GitOps

```powershell
oc apply -f argocd/appproject.yaml
oc apply -f argocd/application.yaml
```

> Ajuster `spec.source.repoURL` et `targetRevision` si vous utilisez un fork ou une branche non `main`.

### Étape 2 — Secrets registry et cosign

1. Modifier `tekton/secret-registry.yaml` avec vos identifiants réels puis appliquer :

```bash
oc apply -f tekton/secret-registry.yaml -n gitops-demo
```

1. Générer la paire cosign et créer/mettre à jour le secret `cosign-key` dans `openshift-gitops` :

```bash
bash scripts/gen-cosign-secret.sh
```

### Étape 3 — Chaîne CI Tekton

1. Appliquer la configuration Tekton Chains :

```bash
oc apply -f tekton/chains-config.yaml -n openshift-pipelines
```

1. Déployer la ServiceAccount et les Tasks :

```bash
oc apply -f tekton/serviceaccount.yaml -n gitops-demo
oc apply -f tekton/task-tests.yaml -n gitops-demo
oc apply -f tekton/task-build.yaml -n gitops-demo
oc apply -f tekton/task-argocd-sync.yaml -n gitops-demo
oc apply -f tekton/pipeline.yaml -n gitops-demo
```

1. Créer le secret `argocd-token` avec un token valide :

```bash
oc create secret generic argocd-token -n gitops-demo \
  --from-literal=token=$(argocd account generate-token --account demo)
```

### Étape 4 — Lancer et suivre le PipelineRun

```bash
oc create -f tekton/pipelinerun.yaml -n gitops-demo
tkn pipelinerun logs -f -n gitops-demo $(tkn pipelinerun ls -n gitops-demo -o name | head -n1)
```

### Étape 5 — Valider la livraison

```powershell
oc get pods -n gitops-demo
oc get application customer-stack -n openshift-gitops -o jsonpath='{.status.sync.status}'
ROUTE=$(oc get route customer-web -n gitops-demo -o jsonpath='{.spec.host}')
curl -k https://$ROUTE | head
```

### Étape 6 — Nettoyer (optionnel)

```bash
oc delete -f tekton/pipelinerun.yaml -n gitops-demo --ignore-not-found
oc delete project gitops-demo
oc delete application customer-stack -n openshift-gitops --ignore-not-found
oc delete appproject gitops-demo -n openshift-gitops --ignore-not-found
```

## Dépannage rapide

- **Build Tekton en échec** : confirmer l'accès au registre airgap (`registry-credentials`) et si nécessaire passer `TLSVERIFY=false`.
- **Signatures absentes** : vérifier que le secret `cosign-key` est associé à la ServiceAccount `pipeline-gitops` et que `tekton/chains-config.yaml` pointe vers un dépôt OCI accessible.
- **Argo CD reste OutOfSync** : vérifier la connectivité au repo Git (`argocd app get customer-stack`) et relancer `argocd app sync customer-stack`.
- **Job `seed-customers` en erreur** : attendre que le StatefulSet PostgreSQL soit `Ready` et consulter les logs du job (`oc logs job/seed-customers`).

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

- Ajuster `harbor.skyr.dca.scc` et les tags dans `manifests/base/kustomization.yaml`
- S'assurer que les images Red Hat référencées sont mirroirées localement (UBI, nodejs, buildah, postgresql)
- Mettre à jour `tekton/secret-argocd-token.yaml` avec un token réel (`argocd account generate-token`)

### Sources d'images (source 1 / source 2)

| Composant | Source 1 (amont) | Source 2 (airgap) |
| --- | --- | --- |
| Application web | `build-local (podman build ./app)` | `harbor.skyr.dca.scc/gitops/customer-web:0.1.0` |
| Job init PostgreSQL | `build-local (podman build ./app/db)` | `harbor.skyr.dca.scc/gitops/customer-db-init:0.1.0` |
| Serveur PostgreSQL | `registry.redhat.io/rhel9/postgresql-15:latest` | `harbor.skyr.dca.scc/gitops/postgresql-15:latest` |
| Base Node.js (tests Tekton) | `registry.access.redhat.com/ubi9/nodejs-18:latest` | `harbor.skyr.dca.scc/gitops/nodejs-18:latest` |
| Buildah (Task build) | `registry.redhat.io/rhel8/buildah:latest` | `harbor.skyr.dca.scc/gitops/buildah:latest` |
| CLI Argo CD | `quay.io/argoproj/argocd:v2.13.3` | `harbor.skyr.dca.scc/gitops/argocd:v2.13.3` |

## Préparation du registre Harbor

### 1. Créer les projets

```bash
export HARBOR_URL="https://harbor.skyr.dca.scc"
export HARBOR_USER="admin"
export HARBOR_PASS="********"

for project in gitops rhel9 ubi9 rhel8 openshift4; do
  curl -k -u "${HARBOR_USER}:${HARBOR_PASS}" \
    -H "Content-Type: application/json" \
    -X POST "${HARBOR_URL}/api/v2.0/projects" \
    -d "{\"project_name\":\"${project}\",\"public\":false}" \
    || echo "Projet ${project} déjà créé";
done
```

### 2. (Optionnel) créer un compte robot pour Tekton

```bash
curl -k -u "${HARBOR_USER}:${HARBOR_PASS}" \
  -H "Content-Type: application/json" \
  -X POST "${HARBOR_URL}/api/v2.0/projects/gitops/robots" \
  -d '{"name":"tekton","access":[{"resource":"repository","action":"push","effect":"allow"},{"resource":"repository","action":"pull","effect":"allow"}]}'
```

Utiliser le mot de passe retourné pour `tekton/secret-registry.yaml`.

### 3. Mirrorer les images nécessaires

```bash
# Construire et pousser les images applicatives locales
podman build -t harbor.skyr.dca.scc/gitops/customer-web:0.1.0 app
podman push harbor.skyr.dca.scc/gitops/customer-web:0.1.0
podman build -t harbor.skyr.dca.scc/gitops/customer-db-init:0.1.0 app/db
podman push harbor.skyr.dca.scc/gitops/customer-db-init:0.1.0

# Mirrorer les images Red Hat
skopeo copy --all docker://registry.redhat.io/rhel9/postgresql-15:latest \
  docker://harbor.skyr.dca.scc/gitops/postgresql-15:latest
skopeo copy --all docker://registry.access.redhat.com/ubi9/nodejs-18:latest \
  docker://harbor.skyr.dca.scc/gitops/nodejs-18:latest
skopeo copy --all docker://registry.redhat.io/rhel8/buildah:latest \
  docker://harbor.skyr.dca.scc/gitops/buildah:latest
skopeo copy --all docker://quay.io/argoproj/argocd:v2.13.3 \
  docker://harbor.skyr.dca.scc/gitops/argocd:v2.13.3
```

Pré-créer aussi un dépôt vide `gitops/signatures` pour Tekton Chains (il sera alimenté par la pipeline).
