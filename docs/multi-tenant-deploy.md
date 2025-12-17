# Déploiement Multi-Tenant ArgoCD pour `testappli`

Ce document décrit la procédure de déploiement de l'architecture Multi-Tenant avec 3 instances ArgoCD distinctes : `argocd-rbac`, `argocd-dev`, et `argocd-gov`.

## Architecture

L'objectif est de séparer les responsabilités sur le namespace cible `testappli` :

1.  **argocd-rbac** :
    *   Gère le **Namespace** lui-même (metadata, labels).
    *   Gère les objets **RBAC** (Role, RoleBinding) dans le namespace.
    *   *Raison* : C'est l'instance "admin" du tenant.
2.  **argocd-dev** :
    *   Gère les **Applications** (Deployment, StatefulSet, Service, Route, Secret, PVC...).
    *   *Restriction* : Ne peut PAS toucher aux Quotas, Limits ou RBAC.
3.  **argocd-gov** :
    *   Gère la **Gouvernance** (ResourceQuota, LimitRange).
    *   *Restriction* : Ne peut PAS toucher aux Apps ou RBAC.

## Prérequis

*   Accès administrateur au cluster OpenShift (`oc`).
*   Accès au dépôt Git contenant les manifestes.
*   Opérateur OpenShift GitOps installé.

## Étape 1 : Déploiement des 3 Instances ArgoCD

Nous allons créer les namespaces et les instances ArgoCD.

```bash
# 1. Création des namespaces (argocd-rbac, argocd-dev, argocd-gov)
oc apply -f manifests/instances/namespaces.yaml

# 2. Déploiement des CR ArgoCD
oc apply -f manifests/instances/argocd-instances.yaml
```

> **Note** : Attendez que les pods soient Running dans les 3 namespaces avant de passer à la suite.

## Étape 2 : Configuration des Projets et Applications

Cette étape configure les instances pour qu'elles gèrent `testappli` selon les règles définies.

```bash
# 1. Création des AppProjects (règles de whitelisting strictes)
oc apply -f manifests/testappli/argocd-config/projects.yaml

# 2. Création des Applications (pont entre Git et le Cluster)
oc apply -f manifests/testappli/argocd-config/applications.yaml
```

### Détail des configurations appliquées

*   **Project RBAC** : Autorise uniquement `Kind: Namespace` et `rbac.authorization.k8s.io/*`.
*   **Project Dev** : Autorise les ressources applicatives standards (Apps, Service, Route, etc.).
*   **Project Gov** : Autorise uniquement `ResourceQuota` et `LimitRange`.

## Étape 3 : Vérification

Une fois les applications synchronisées (ce qui devrait être automatique via `syncPolicy: automated`), vérifiez l'état de `testappli` :

1.  **Namespace** :
    ```bash
    oc get ns testappli --show-labels
    # Doit avoir le label : argocd.argoproj.io/managed-by=argocd-rbac
    ```

2.  **Ressources** :
    ```bash
    # MySQL (géré par argocd-dev)
    oc -n testappli get sts,svc,secret

    # Quotas (géré par argocd-gov)
    oc -n testappli get quota,limitrange

    # RBAC (géré par argocd-rbac)
    oc -n testappli get role,rolebinding
    ```

3.  **Permissions Croix** (Test manuel) :
    Les ServiceAccounts des contrôleurs ArgoCD ont des droits limités via les RoleBindings dans `manifests/testappli/rbac/rbac.yaml`.
    *   `argocd-dev` ne pourra pas supprimer un Quota.
    *   `argocd-gov` ne pourra pas modifier le StatefulSet.

## Structure du Dépôt

*   `manifests/instances/` : Définition des 3 ArgoCD.
*   `manifests/testappli/argocd-config/` : Configuration `AppProject` et `Application`.
*   `manifests/testappli/apps/` : Workloads (MySQL).
*   `manifests/testappli/gov/` : Quotas/Limits.
*   `manifests/testappli/rbac/` : Droits d'accès.
