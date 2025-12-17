# Guide Complet de Déploiement Multi-Tenant ArgoCD

Ce document détaille l'implémentation d'une architecture Multi-Tenant sécurisée utilisant 3 instances ArgoCD distinctes.

## 1. Concepts Clés et Architecture

### Pourquoi 3 instances ArgoCD ?
L'objectif est d'appliquer le principe de moindre privilège et de séparation des responsabilités (SoD - Separation of Duties) au niveau le plus fondamental : le contrôleur de déploiement lui-même.

| Instance | Rôle | Responsabilités (Périmètre) | Pourquoi ? |
| :--- | :--- | :--- | :--- |
| **argocd-rbac** | **Admin / Sécurité** | Gestion du Namespace cible (création, labels) et des objets RBAC (Roles, Bindings). | Empêche les développeurs de s'auto-attribuer des droits élevés. Seul cet ArgoCD peut toucher à la sécurité. |
| **argocd-gov** | **Gouvernance** | Gestion des Quotas (CPU/RAM/Storage) et LimitRanges. | Garantit que les équipes applicatives ne peuvent pas modifier ou supprimer leurs propres limites de ressources. |
| **argocd-dev** | **Applicatif** | Gestion des Workloads (Deployments, StatefulSets), Services, ConfigMaps, Secrets. | Permet aux développeurs de déployer leurs apps sans risque d'impacter la sécurité ou les quotas du namespace. |

### Le concept de "Managed-By"
Un Namespace Kubernetes ne peut avoir qu'un seul label `argocd.argoproj.io/managed-by`. Cela signifie qu'une seule instance ArgoCD est "propriétaire" du namespace au sens de l'opérateur.
*   **Notre choix** : `argocd-rbac` sera le propriétaire.
*   **Conséquence** : Les autres instances (`dev` et `gov`) n'ont PAS de droits automatiques sur ce namespace. Nous devons leur donner des droits explicites via des RoleBindings Kubernetes créés par `argocd-rbac`.

---

## 2. Déroulement du Déploiement (Pas à Pas)

### Étape 0 : Préparation de l'environnement
Nous commençons par déployer les 3 instances ArgoCD dans leurs propres namespaces d'administration.

*   **Action** : Création des namespaces `argocd-rbac`, `argocd-dev`, `argocd-gov`.
*   **Action** : Déploiement des CR `ArgoCD`.
*   **Fichier** : `manifests/instances/` (ou `manifests-exclusion/instances/`).

### Étape 1 : Le Socle de Sécurité (Role de argocd-rbac)
C'est la première brique à poser.
`argocd-rbac` va créer le namespace cible `testappli` et y installer les règles du jeu.

1.  **Création du Namespace** : `argocd-rbac` crée `testappli` et pose le label `managed-by: argocd-rbac`.
2.  **Création du RBAC interne** : Il déploie des `Role` et `RoleBinding` dans `testappli`.
    *   *Exemple* : Il crée un Role `argocd-dev-apps` qui dit "Autorisé à toucher aux Deployments et Services".
    *   *Binding* : Il lie ce Role au ServiceAccount de l'instance `argocd-dev`.
    *   *Résultat* : `argocd-dev` a maintenant le droit de déployer des apps, mais toujours pas de toucher aux quotas.

### Étape 2 : La Gouvernance (Role de argocd-gov)
Une fois le socle posé, `argocd-gov` entre en jeu.
Il déploie les objets `ResourceQuota` et `LimitRange`.
*   Comme `argocd-gov` n'est pas le propriétaire du namespace, il utilise les droits (RoleBinding) que `argocd-rbac` lui a préparés à l'étape 1.

### Étape 3 : L'Application (Role de argocd-dev)
Enfin, les développeurs peuvent déployer.
`argocd-dev` déploie le MySQL et le Service.
*   Si le déploiement demande 100 CPU, le `ResourceQuota` posé par `argocd-gov` bloquera la création du Pod. `argocd-dev` ne pourra rien y faire (car il n'a pas les droits pour modifier le Quota).

---

## 3. Deux Stratégies de Mise en Œuvre

Nous proposons deux variantes techniques pour implémenter cette architecture.

### Stratégie A : Isolation par AppProjects (Whitelist)
*C'est la méthode standard ArgoCD.*

*   **Mécanisme** : On définit un objet `AppProject` pour chaque instance.
*   **Configuration** : Dans l'`AppProject`, on remplit le champ `namespaceResourceWhitelist`.
    *   Projet Dev : Whitelist `Deployment`, `Service`, etc.
    *   Projet Gov : Whitelist `ResourceQuota`.
*   **Avantage** : Centralisé et visible dans l'UI ArgoCD. Si on essaie de sync un objet interdit, l'UI affiche une erreur de permission immédiate.
*   **Dossier** : `manifests-app-proj/`

### Stratégie B : Isolation par Exclusions (ConfigMap)
*C'est une méthode "Hardened" configurée au niveau de l'instance.*

*   **Mécanisme** : On configure le contrôleur ArgoCD lui-même (via sa ConfigMap `argocd-cm`) pour qu'il ignore totalement certains types de ressources.
*   **Configuration** :
    *   Instance Dev : `resource.exclusions: [ResourceQuota, LimitRange, Role, ...]`
*   **Avantage** : Sécurité absolue au niveau du binaire. Même si un admin ArgoCD essaie de créer un Quota, le contrôleur l'ignorera complètement.
*   **Détail technique** : On utilise aussi `installationID` pour que plusieurs ArgoCD puissent cohabiter sans se marcher sur les pieds (évite qu'ArgoCD A supprime les ressources de ArgoCD B).
*   **Dossier** : `manifests-exclusion/`

---

## 4. Instructions de Déploiement

Choisissez **une seule** des deux stratégies ci-dessous.

### Option A : Déploiement via AppProjects

```bash
# 1. Installer les instances
oc apply -f manifests-app-proj/instances/namespaces.yaml
oc apply -f manifests-app-proj/instances/argocd-instances.yaml

# 2. Configurer les autorisations (Projets et Apps)
oc apply -f manifests-app-proj/testappli/argocd-config/projects.yaml
oc apply -f manifests-app-proj/testappli/argocd-config/applications.yaml
```

### Option B : Déploiement via Exclusions

```bash
# 1. Installer les instances (Configurées avec exclusions)
oc apply -f manifests-exclusion/instances/namespaces.yaml
oc apply -f manifests-exclusion/instances/argocd-instances.yaml

# 2. Déployer les Applications
oc apply -f manifests-exclusion/testappli/argocd-config/applications.yaml
```

---

## 5. Vérification

Pour valider que la séparation fonctionne :

1.  **Vérifier le Namespace** :
    ```bash
    oc describe ns testappli
    # Doit montrer le label: argocd.argoproj.io/managed-by=argocd-rbac
    ```

2.  **Test d'intrusion (Simulation)** :
    Essayez d'ajouter un `ResourceQuota` dans le dépôt Git utilisé par `argocd-dev`.
    *   *Résultat attendu* : ArgoCD refusera de le synchroniser OU l'ignorera, car il n'a pas les droits/inclusions nécessaires.
