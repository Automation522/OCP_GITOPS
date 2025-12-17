# Déploiement Multi-Tenant ArgoCD (Variante Exclusions)

Ce document décrit la variante "Exclusions" du déploiement multi-tenant.
Contrairement à la méthode AppProjects, ici chaque instance ArgoCD est configurée via son ConfigMap (`argocd-cm`) pour ignorer explicitement certains types de ressources.

## Architecture

*   **Projet ArgoCD** : Tous les déploiements utilisent le projet `default`.
*   **Isolation** : Configurée au niveau `Resource Inclusions/Exclusions` de chaque instance.
*   **Tracking** : Utilise l'annotation (`application.resourceTrackingMethod: annotation`) pour éviter les conflits d'`installationID`.

## Instances configurées

Les définitions se trouvent dans `manifests-exclusion/instances/argocd-instances.yaml`.

### 1. argocd-dev
*   **Rôle** : Déploie les applications.
*   **Inclusions** : `apps` (Deployment, StatefulSet), `Service`, `Route`, `Secret`, `ConfigMap`.
*   **Exclusions** : `ResourceQuota`, `LimitRange`, `RBAC`.

### 2. argocd-gov
*   **Rôle** : Déploie la gouvernance.
*   **Inclusions** : `ResourceQuota`, `LimitRange`.
*   **Exclusions** : `apps` (Deployment, StatefulSet...).

### 3. argocd-rbac
*   **Rôle** : Gère les accès et le Namespace.
*   **Inclusions** : `Role`, `RoleBinding`, `ServiceAccount`.

## Déploiement

```bash
# 1. Déploiement des instances et namespaces
oc apply -f manifests-exclusion/instances/namespaces.yaml
oc apply -f manifests-exclusion/instances/argocd-instances.yaml

# Attendre que les instances soient prêtes...

# 2. Déploiement des Applications
oc apply -f manifests-exclusion/testappli/argocd-config/applications.yaml
```

## Vérification

L'instance `argocd-rbac` va créer le namespace `testappli` et l'annoter.
Les autres instances déploieront leurs ressources respectives.
Si vous essayez d'ajouter un `ResourceQuota` dans le repo git de `argocd-dev`, il sera **ignoré** par ArgoCD car exclu dans la configuration de l'instance.
