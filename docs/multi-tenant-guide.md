# Architecture Multi-Tenant ArgoCD : Guide Technique Avancé

Ce document détaille deux méthodologies distinctes pour implémenter une **ségrégation stricte des responsabilités (SoD)** via ArgoCD.

## 1. Fondamentaux Techniques

L'architecture repose sur l'instanciation de **3 contrôleurs ArgoCD indépendants**, chacun opérant dans un périmètre fonctionnel restreint sur un namespace cible commun (`testappli`).

### Matrice des Responsabilités
| Instance | Domaine Fonctionnel | Groupes d'API Kubernetes Autorisés (GVK) | Rôle Technique |
| :--- | :--- | :--- | :--- |
| **argocd-rbac** | **Identity & Access** | `rbac.authorization.k8s.io/*`, `v1/Namespace`, `v1/ServiceAccount` | Administrateur du Tenant. Propriétaire du label `managed-by`. |
| **argocd-gov** | **Gouvernance & Quotas** | `v1/ResourceQuota`, `v1/LimitRange` | Garant de la conformité et de l'allocation des ressources. |
| **argocd-dev** | **Workloads Applicatifs** | `apps/*` (Deployments, StatefulSets), `v1/Service`, `route.openshift.io/*` | Déploiement logiciel standard. |

---

## 2. Implémentation A : Ségrégation par `AppProject` (RBAC ArgoCD)

### Principe Technique
Cette méthode utilise le **Plan de Contrôle ArgoCD**. La restriction est appliquée au niveau de l'API ArgoCD avant même que la requête n'atteigne le contrôleur.
*   **Mécanisme** : `spec.namespaceResourceWhitelist` dans la CRD `AppProject`.
*   **Localisation** : `manifests-app-proj/`

### A.1 Architecture Logique
Chaque Application est liée à un `AppProject` spécifique qui agit comme un pare-feu applicatif (L7). Si une ressource non whitelistée est détectée dans le Git, ArgoCD lève une erreur de validation `PermissonDenied`.

### A.2 Exemples de Configuration

#### 1. Configuration de l'AppProject (Ex: Gouvernance)
Ce projet interdit tout sauf les Quotas et Limits.
```yaml
# manifests-app-proj/testappli/argocd-config/projects.yaml (Extrait)
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: project-gov
  namespace: argocd-gov
spec:
  # WHITELIST STRICTE : Seuls ces GVK sont autorisés
  namespaceResourceWhitelist:
  - group: ''
    kind: ResourceQuota
  - group: ''
    kind: LimitRange
  sourceRepos:
  - '*'
  destinations:
  - namespace: testappli
    server: https://kubernetes.default.svc
```

#### 2. Configuration de l'Application
L'Application doit référencer le projet contraint.
```yaml
# manifests-app-proj/testappli/argocd-config/applications.yaml (Extrait)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-testappli-gov
  namespace: argocd-gov
spec:
  project: project-gov  # <--- Lien vers la politique de sécurité
  source:
    path: manifests-app-proj/testappli/gov
    repoURL: ...
  destination:
    namespace: testappli
```

### A.3 Analyse
*   **Sécurité** : Déclarative et centralisée via les CRD ArgoCD.
*   **Visibilité** : Les violations de politiques apparaissent clairement dans l'UI ArgoCD (Sync Failed).

---

## 3. Implémentation B : Ségrégation par Exclusions (Filtrage Contrôleur)

### Principe Technique
Cette méthode utilise le **Filtrage Natif du Contrôleur**. La restriction est appliquée au niveau du binaire `argocd-application-controller` via des arguments de démarrage injectés par ConfigMap.
*   **Mécanisme** : `resource.exclusions` et `resource.inclusions` dans `argocd-cm`.
*   **Localisation** : `manifests-exclusion/`

### B.1 Architecture Logique
Ici, les `AppProjects` ne portent aucune restriction (utilisation du projet `default`). C'est l'instance ArgoCD elle-même qui est "aveugle" aux ressources interdites.
On définit également un `installationID` unique pour garantir l'isolation des caches Redis et éviter les conflits de propriété entre contrôleurs (Split Brain).

### B.2 Exemples de Configuration

#### 1. Configuration de l'Instance (Ex: Dev)
On modifie la ConfigMap via `extraConfig` dans l'opérateur. Notez l'exclusion explicite du RBAC et des Quotas.
```yaml
# manifests-exclusion/instances/argocd-instances.yaml (Extrait)
apiVersion: argoproj.io/v1alpha1
kind: ArgoCD
metadata:
  name: argocd-dev
  namespace: argocd-dev
spec:
  extraConfig:
    argocd-cm: |
      installationID: "argocd-dev"            # Isolation du cluster cache
      application.resourceTrackingMethod: annotation # Tracking sans label collision
      
      # INCLUSIONS : Ce contrôleur ne voit QUE les apps
      resource.inclusions: |
        - apiGroups: ["apps"]
          kinds: ["Deployment","StatefulSet"]
        - apiGroups: [""]
          kinds: ["Service","ConfigMap"]
      
      # EXCLUSIONS : Ceinture de sécurité supplémentaire
      resource.exclusions: |
        - apiGroups: [""]
          kinds: ["ResourceQuota"]
        - apiGroups: ["rbac.authorization.k8s.io"]
          kinds: ["Role","RoleBinding"]
```

#### 2. Configuration de l'Application
L'Application est standard et utilise le projet par défaut.
```yaml
# manifests-exclusion/testappli/argocd-config/applications.yaml (Extrait)
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-testappli-dev
  namespace: argocd-dev
spec:
  project: default  # <--- Pas de restriction ici, c'est le contrôleur qui filtre
  source:
    path: manifests-exclusion/testappli/apps/mysql
    repoURL: ...
```

### B.3 Analyse
*   **Sécurité** : Intrinsèque au processus. Un admin ArgoCD ne peut pas contourner la restriction sans redémarrer l'instance.
*   **Comportement** : Les ressources exclues sont totalement ignorées (comme si elles n'existaient pas dans le Git). Pas d'erreur de Sync, mais une "invisibilité".

---

## 4. Comparatif Technique

| Caractéristique | Implémentation A (AppProject) | Implémentation B (Exclusions) |
| :--- | :--- | :--- |
| **Niveau d'application** | API ArgoCD (Validating Webhook logique) | Contrôleur Kubernetes (Filtrage In-Memory) |
| **Flexibilité** | Haute (Chaque App peut avoir un Projet différent) | Basse (S'applique à toute l'instance ArgoCD) |
| **Sécurité** | RBAC logique (Soft) | Hardening binaire (Hard) |
| **Gestion des Conflits** | Via AppProject isolation | Via `installationID` et Tracking Annotation |
| **Expérience Utilisateur** | Erreur explicite "Permission Denied" | La ressource est ignorée silencieusement |

## 5. Recommandation

Pour un environnement de production multi-tenant sur OpenShift :
*   Utilisez l'**Implémentation B (Exclusions)** si vous souhaitez une isolation forte où chaque instance ArgoCD est dédiée à une fonction (Usine à Apps vs Usine à Infra).
*   Utilisez l'**Implémentation A (AppProject)** si vous souhaitez une instance partagée mais avec des permissions granulaires par équipe.

Dans le scénario actuel (3 instances distinctes demandées), l'**Implémentation B** offre le niveau de garantie le plus élevé contre les erreurs de configuration humaine.
