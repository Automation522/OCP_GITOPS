# Guide de Déploiement Multi-Tenant ArgoCD

Ce document présente deux stratégies pour implémenter une architecture Multi-Tenant avec 3 instances ArgoCD distinctes (`argocd-rbac`, `argocd-dev`, `argocd-gov`) gérant un namespace cible commun `testappli`.

## Objectif

Séparer les responsabilités :
1.  **argocd-rbac** : Gestion du Namespace (metadata) et des accès RBAC.
2.  **argocd-dev** : Gestion des applications (Workloads, Services, etc.).
3.  **argocd-gov** : Gestion de la gouvernance (ResourceQuota, LimitRange).

---

## Stratégie 1 : Isolation par AppProjects (Recommandée)

Cette méthode utilise les `AppProjects` ArgoCD pour restreindre les types de ressources autorisés (`clusterResourceWhitelist` / `namespaceResourceWhitelist`).

### Localisation
Les fichiers se trouvent dans le dossier : `manifests-app-proj/`

### Configuration
1.  **Projets** : 3 AppProjects (`project-rbac`, `project-dev`, `project-gov`) définis dans `manifests-app-proj/testappli/argocd-config/projects.yaml`.
2.  **Restrictions** : Chaque projet whitelist uniquement les GVK (Group/Version/Kind) nécessaires.

### Déploiement
```bash
# 1. Déploiement des instances et namespaces
oc apply -f manifests-app-proj/instances/namespaces.yaml
oc apply -f manifests-app-proj/instances/argocd-instances.yaml

# 2. Configuration (Projets + Applications)
oc apply -f manifests-app-proj/testappli/argocd-config/projects.yaml
oc apply -f manifests-app-proj/testappli/argocd-config/applications.yaml
```

---

## Stratégie 2 : Isolation par Exclusions (Variante ConfigMap)

Cette méthode utilise la configuration `resource.inclusions` et `resource.exclusions` directement dans la ConfigMap (`argocd-cm`) de chaque instance ArgoCD. Elle permet d'utiliser le projet `default` tout en sécurisant les périmètres.

### Localisation
Les fichiers se trouvent dans le dossier : `manifests-exclusion/`

### Configuration
1.  **Instances** : Les CR `ArgoCD` (`manifests-exclusion/instances/argocd-instances.yaml`) contiennent une `extraConfig` définissant :
    *   `installationID` : Pour éviter les collisions.
    *   `resource.exclusions/inclusions` : Pour filtrer les ressources.
2.  **Projets** : Utilisation du projet `default`.

### Détail des filtres
*   **argocd-dev** : Exclut explicitement `ResourceQuota`, `LimitRange`, et `RBAC`. Inclus `apps`, `Service`, etc.
*   **argocd-gov** : Inclus uniquement `ResourceQuota` et `LimitRange`.
*   **argocd-rbac** : Inclus uniquement `Role`, `RoleBinding`.

### Déploiement
```bash
# 1. Déploiement des instances (avec configuration Exclusions)
oc apply -f manifests-exclusion/instances/namespaces.yaml
oc apply -f manifests-exclusion/instances/argocd-instances.yaml

# 2. Déploiement des Applications
oc apply -f manifests-exclusion/testappli/argocd-config/applications.yaml
```

---

## Vérification Commune

Quel que soit le mode choisi, le résultat attendu est :

1.  Le namespace `testappli` existe et porte le label `argocd.argoproj.io/managed-by: argocd-rbac`.
2.  Les pods MySQL (`argocd-dev`) sont en cours d'exécution.
3.  Les Quotas (`argocd-gov`) sont appliqués.
4.  Les accès croisés sont interdits (par RBAC Kubernetes et par la configuration ArgoCD).

### Commandes de vérification
```bash
# Vérifier le propriétaire du namespace
oc get ns testappli --show-labels

# Vérifier les workloads (Dev)
oc -n testappli get sts,svc

# Vérifier la gouvernance (Gov)
oc -n testappli get quota
```
