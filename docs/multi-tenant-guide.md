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

## 1. Prérequis et Déploiement Initial

L'installation de l'architecture multi-tenant nécessite le déploiement de plusieurs ressources de base avant la configuration des instances ArgoCD.

### 1.1 Connexion Git et Authentification (Secrets)

Il est CRITIQUE d'appliquer les ressources de connexion Git et d'intégration FreeIPA dans tous les namespaces ArgoCD.

**Fichiers à configurer et déployer :**

1.  **Gestion des identifiants Git** : `manifests-exclusion/instances/git-creds.yaml`
    *   Ce fichier définit les secrets de type `repository` pour que les instances puissent fetcher le code.
    ```bash
    oc apply -f manifests-exclusion/instances/git-creds.yaml
    ```

2.  **Ressources FreeIPA (LDAP/TLS)** : `manifests-exclusion/instances/freeipa-resources.yaml`
    *   Contient le mot de passe de liaison LDAP (`freeipa-ldap-secret`) et le certificat CA de FreeIPA (`argocd-tls-certs-cm`).
    ```bash
    oc apply -f manifests-exclusion/instances/freeipa-resources.yaml
    ```

### 1.2 Création des Namespaces et Quotas

Avant de déployer les instances, assurez-vous que les namespaces de gestion existent.
```bash
oc apply -f manifests-exclusion/instances/namespaces.yaml
```

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

### A.3 Guide d'Installation (Variante AppProject)

**Prérequis** : Opérateur OpenShift GitOps installé.

1.  **Déploiement des Instances & Namespaces**
    On crée d'abords les 3 instances ArgoCD "vides".
    ```bash
    oc apply -f manifests-app-proj/instances/namespaces.yaml
    oc apply -f manifests-app-proj/instances/argocd-instances.yaml
    # Attendre que les pods argocd-server soient Running dans les 3 namespaces
    ```

2.  **Application de la Configuration (AppProjects + Applications)**
    On applique la logique métier : les projets restrictifs et les applications qui pointent vers eux.
    ```bash
    oc apply -f manifests-app-proj/testappli/argocd-config/projects.yaml
    oc apply -f manifests-app-proj/testappli/argocd-config/applications.yaml
    ```

3.  **Vérification**
    ```bash
    # Vérifier que le namespace cible a été créé par argocd-rbac
    oc get ns testappli --show-labels
    ```

---

## 3. Implémentation Réelle de la Démo (Exclusions côté contrôleur + 3 instances)

### Principe Technique
Cette méthode utilise le **Filtrage Natif du Contrôleur**. La restriction est appliquée au niveau du binaire `argocd-application-controller` via des arguments de démarrage injectés par ConfigMap.
*   **Mécanisme** : `resource.exclusions` et `resource.inclusions` dans `argocd-cm`.
*   **Localisation** : `manifests-exclusion/`

### B.1 Architecture Logique
Dans la démo, nous combinons deux leviers:
- 3 instances ArgoCD distinctes (argocd-rbac, argocd-gov, argocd-dev)
- Des AppProjects minimalistes pour expliciter les périmètres (inclusions/exclusions)

Répartition:
- `argocd-rbac` déploie le namespace et le RBAC (Role/RoleBinding) via l'application `app-testappli-rbac` (chemin `manifests-exclusion/testappli/rbac-access`).
- `argocd-gov` déploie uniquement `ResourceQuota` et `LimitRange` via `app-testappli-governance` (chemin `manifests-exclusion/testappli/gov`).
- `argocd-dev` déploie les workloads applicatifs via `app-testappli-apps` (chemin `manifests-exclusion/testappli/apps/mysql`).

Les AppProjects appliquent une whitelist stricte des GVK autorisés, assurant une ségrégation claire des responsabilités.

### B.2 Exemples de Configuration

#### 1. Configuration de l'Instance (Ex: Dev)
On modifie la ConfigMap via `extraConfig` dans l'opérateur. Notez l'exclusion explicite du RBAC et des Quotas.
```yaml
# manifests-exclusion/instances/argocd-instances.yaml (Extrait)
apiVersion: argoproj.io/v1beta1
kind: ArgoCD
metadata:
  name: argocd-dev
  namespace: argocd-dev
spec:
  sso:
    provider: dex
    dex:
      config: |
        logger:
          level: debug
        connectors:
        - type: ldap
          id: freeipa
          config:
            host: idm.skyr.dca.scc:636
            insecureSkipVerify: true # Bypasse le TLS pour la démo
            # ... bindDN, search parameters ...
  extraConfig:
    argocd-cm: |
      installationID: "argocd-dev"
      application.resourceTrackingMethod: annotation
      
      resource.inclusions: |
        - apiGroups: ["apps"]
          kinds: ["Deployment","StatefulSet"]
        - apiGroups: [""]
          kinds: ["Service","ConfigMap","Secret"]
```

### B.3 Guide d'Installation (Démo)

**Prérequis** : Opérateur OpenShift GitOps installé.

1.  **Déploiement des Instances Configurées**
    Cette étape est critique : elle déploie les ArgoCD déjà "durcis" avec les exclusions.
    ```bash
    oc apply -f manifests-exclusion/instances/namespaces.yaml
    oc apply -f manifests-exclusion/instances/argocd-instances.yaml
    # Attendre le redémarrage des statefulset argocd-application-controller pour prise en compte de la CM
    ```

2.  **Déploiement des Projets + Applications**
  On applique les AppProjects et les 3 Applications correspondantes (une par instance):
    ```bash
  oc apply -f manifests-exclusion/testappli/argocd-config/projects.yaml
  oc apply -f manifests-exclusion/testappli/argocd-config/applications.yaml
    ```

3.  **Vérification**
    ```bash
    # Vérifier la répartition des responsabilités
    oc get application -n argocd-rbac app-testappli-rbac -o wide
    oc get application -n argocd-gov app-testappli-governance -o wide
    oc get application -n argocd-dev app-testappli-apps -o wide

    # Test de robustesse :
    # - Ajouter un ResourceQuota dans le dossier apps/mysql -> Devra être refusé par AppProject dev-testappli
    # - Ajouter un Deployment dans le dossier gov -> Devra être refusé par AppProject gov-testappli
    ```

---

## 4. Description Détaillée des Paramètres

### 4.1 Configuration Git (`git-creds.yaml`)
| Paramètre | Description |
| :--- | :--- |
| `url` | URL HTTPS du dépôt Git. |
| `username` / `password` | Identifiants pour l'authentification Git. |
| `insecure: "true"` | **Indispensable en DMZ/Demo** : Permet d'ignorer la vérification SSL si le certificat du bastion n'est pas reconnu par le pod. |

### 4.2 Intégration LDAP/Dex (`argocd-instances.yaml`)
| Paramètre | Description |
| :--- | :--- |
| `spec.sso.dex.config` | **CRITIQUE (v1beta1)** : Emplacement de la config Dex. |
| `insecureSkipVerify: true` | Permet d'ignorer la validation du certificat FreeIPA si le trust nesting n'est pas complet. |
| `userSearch` / `groupSearch` | Mappage des attributs FreeIPA (`uid` pour l'utilisateur, `cn` pour les groupes). |

### 4.3 Configuration OIDC (`oidc.config`)
| Paramètre | Description |
| :--- | :--- |
| `issuer` | URL externe de l'instance ArgoCD (doit correspondre à la route). |
| `rootCAData` | **CRITIQUE** : Certificat de la route OpenShift. Sans cela, ArgoCD Server rejette le jeton de Dex car il ne truste pas le certificat SSL de la route. |

### 4.4 Pilotage des Namespaces (`namespaceManagement`)
| Paramètre | Description |
| :--- | :--- |
| `spec.namespaceManagement` | Remplace l'ancien champ `namespaces`. Liste les namespaces que cette instance ArgoCD a le droit de "voir" et gérer. |
| `allowManagedBy: true` | Autorise explicitement l'opérateur à configurer le RBAC système pour ce namespace. |

### 4.5 Isolation des Contrôleurs (`argocd-cm`)
| Paramètre | Description |
| :--- | :--- |
| `installationID` | Identifiant unique pour chaque instance. Empêche deux instances de se "voler" la gestion d'une ressource (Sync Collision). |
| `resource.exclusions` / `resource.inclusions` | Liste des GVK (Group/Version/Kind) que le contrôleur doit **ignorer totally** ou **inclure exclusivement**. C'est le cœur de notre SoD. |

---

## 5. Comparatif Technique

| Caractéristique | Implémentation A (AppProject) | Implémentation B (Exclusions) |
| :--- | :--- | :--- |
| **Niveau d'application** | API ArgoCD (Validating Webhook logique) | Contrôleur Kubernetes (Filtrage In-Memory) |
| **Flexibilité** | Haute (Chaque App peut avoir un Projet différent) | Basse (S'applique à toute l'instance ArgoCD) |
| **Sécurité** | RBAC logique (Soft) | Hardening binaire (Hard) |
| **Gestion des Conflits** | Via AppProject isolation | Via `installationID` et Tracking Annotation |
| **Expérience Utilisateur** | Erreur explicite "Permission Denied" | La ressource est ignorée silencieusement |

---

## 6. Analyse Technique Approfondie

### A. L'`installationID` : Pourquoi est-ce indispensable ?
Quand plusieurs instances ArgoCD tournent sur le même cluster, elles risquent d'entrer en conflit sur deux points :

1.  **Tracking des Ressources (Collision de Label)** : Par défaut, ArgoCD pose le label `app.kubernetes.io/instance` sur les ressources gérées. Si l'instance A déploie une application "mysql" et l'instance B déploie aussi une application "mysql", elles vont toutes les deux chercher à gérer les ressources avec le label `instance=mysql`.
    *   *Solution* : En définissant un `installationID` (ex: `argocd-dev`), ArgoCD modifie le label de tracking (ou l'annotation) pour inclure cet ID. Cela garantit que `argocd-dev` ne touchera jamais aux ressources de `argocd-gov`.
    *   *Note* : L'utilisation de `application.resourceTrackingMethod: annotation` renforce cette isolation en n'utilisant pas du tout le label standard.

2.  **Gestion du Cache (Performance)** : Si les instances partagent un Redis (rare via l'opérateur, mais possible), l'`installationID` sert de préfixe aux clés Redis pour éviter la corruption de cache.

### B. Les `AppProjects` : Le Pare-Feu Logique
Pensez à l'`AppProject` comme à un **pare-feu applicatif**.
*   Quand ArgoCD détecte une modification Git, il compare la ressource (ex: `Kind: RoleBinding`) avec la `whitelist` du projet.
*   Si le `Kind` n'est pas dans la liste, ArgoCD lève une alerte `SyncFailed`.
*   C'est une sécurité "douce" : le contrôleur est techniquement capable de déployer la ressource, mais il s'interdit de le faire par configuration.

### C. `resource.exclusions` : L'Aveuglement Volontaire
Pensez aux Exclusions comme à des **œillères**.
*   Quand on configure `resource.exclusions` dans la ConfigMap, on dit au binaire Go du contrôleur ArgoCD : "Ne perds même pas de temps à surveiller ces ressources".
*   Le contrôleur ne lance pas de `WATCH` sur l'API Kubernetes pour ces ressources.
*   **Conséquence de sécurité** : Même si un hacker prenait le contrôle de l'instance ArgoCD et essayait de créer un `RoleBinding` via l'interface, le contrôleur échouerait probablement car il n'a même pas initialisé le cache interne pour cet objet. C'est le niveau de sécurité maximal.
