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

## 1.1 Prérequis de Connexion Git

Les 3 instances ArgoCD doivent se connecter à votre dépôt Git (`https://bastion.skyr.dca.scc:3000/demoscc/OCP_GITOPS.git`).
Comme il s'agit d'un dépôt privé/interne, vous devez configurer les identifiants via un Secret Kubernetes dans chaque namespace.

**Fichier fourni** : `manifests-exclusion/instances/git-creds.yaml`

**Procédure (À faire une fois pour les 3 instances)** :
1.  Editez le fichier `manifests-exclusion/instances/git-creds.yaml`.
2.  Remplacez `votre-username` et `votre-password` par vos identifiants Git.
    *   **Note pour les Tokens** : Si vous utilisez un Token d'accès (PAT), mettez le token dans le champ `password`. Le champ `username` peut souvent être n'importe quoi (ou votre nom d'utilisateur associé).
    *   **Note pour SSL/TLS** : Le fichier inclut désormais le certificat CA de `bastion.skyr.dca.scc`. Vous n'avez pas besoin de toucher à `tlsClientConfig.caData` sauf si le certificat du serveur change.
3.  Appliquez le secret :
    ```bash
    oc apply -f manifests-exclusion/instances/git-creds.yaml
    ```


---

## 1.2 Authentification Centralisée (FreeIPA)

Pour garantir une gestion unifiée des accès, les 3 instances ArgoCD sont connectées au serveur FreeIPA de l'entreprise.

### Architecture d'Authentification
*   **Protocole** : LDAP over SSL (LDAPS) sur le port 636.
*   **Broker** : Dex (intégré à ArgoCD) agit comme intermédiaire OIDC.
*   **Certificats** : Le CA de FreeIPA est monté dans chaque instance pour valider la connexion sécurisée.

### Configuration Commune
Chaque instance ArgoCD (`argocd-rbac`, `argocd-dev`, `argocd-gov`) dispose de sa propre configuration Dex dans le champ `spec.dex` de sa ressource Custom `ArgoCD`.

**Ressources déployées par namespace :**
1.  **Secret** `freeipa-ldap-secret` : Contient le mot de passe du compte de service `uid=openshift`.
2.  **ConfigMap** `argocd-tls-certs-cm` : Contient le certificat CA public de FreeIPA.

**Extrait de Configuration (ArgoCD CR) :**
```yaml
spec:
  dex:
    config: |
      connectors:
      - type: ldap
        id: freeipa
        name: FreeIPA
        config:
          host: idm.skyr.dca.scc:636
          insecureNoSSL: false
          rootCAData: LS0tLS... # Certificat CA encodé en Base64
          bindDN: uid=openshift,cn=users,cn=accounts,dc=skyr,dc=dca,dc=scc
          bindPW: Redhat2025!
          userSearch:
            baseDN: cn=users,cn=accounts,dc=skyr,dc=dca,dc=scc
            filter: "(objectClass=person)"
            username: uid
            idAttr: uid
            emailAttr: mail
            nameAttr: cn
          groupSearch:
            baseDN: cn=groups,cn=accounts,dc=skyr,dc=dca,dc=scc
            filter: "(objectClass=groupOfNames)"
            userMatchers:
            - userAttr: dn
              groupAttr: member
            nameAttr: cn
  extraConfig:
    argocd-cm: |
      oidc.config: |
        name: FreeIPA
        issuer: https://<argocd-server-host>/api/dex
        clientID: argo-cd
        clientSecret: $oidc.dex.clientSecret
        requestedScopes: ["openid", "profile", "email", "groups"]
        rootCAData: LS0tLS... # Certificat CA de la Route OpenShift (pour que ArgoCD truste Dex)
```

> **Note** : Pour plus de détails sur le dépannage de l'authentification, référez-vous au guide dédié : [Configuration de l'authentification FreeIPA](freeipa-authentication.md).

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

### B.3 Guide d'Installation (Variante Exclusions)

**Prérequis** : Opérateur OpenShift GitOps installé.

1.  **Déploiement des Instances Configurées**
    Cette étape est critique : elle déploie les ArgoCD déjà "durcis" avec les exclusions.
    ```bash
    oc apply -f manifests-exclusion/instances/namespaces.yaml
    oc apply -f manifests-exclusion/instances/argocd-instances.yaml
    # Attendre le redémarrage des statefulset argocd-application-controller pour prise en compte de la CM
    ```

2.  **Déploiement des Applications**
    On déploie les applications qui utiliseront le projet `default` (mais seront filtrées par le contrôleur).
    ```bash
    oc apply -f manifests-exclusion/testappli/argocd-config/applications.yaml
    ```

3.  **Vérification**
    ```bash
    # Vérifier que les exclusions fonctionnent (Test de robustesse)
    # Tentez d'ajouter un ResourceQuota dans le repo de argocd-dev -> Il sera ignoré.
    ```

---

## 4. Comparatif Technique

| Caractéristique | Implémentation A (AppProject) | Implémentation B (Exclusions) |
| :--- | :--- | :--- |
| **Niveau d'application** | API ArgoCD (Validating Webhook logique) | Contrôleur Kubernetes (Filtrage In-Memory) |
| **Flexibilité** | Haute (Chaque App peut avoir un Projet différent) | Basse (S'applique à toute l'instance ArgoCD) |
| **Sécurité** | RBAC logique (Soft) | Hardening binaire (Hard) |
| **Gestion des Conflits** | Via AppProject isolation | Via `installationID` et Tracking Annotation |
| **Expérience Utilisateur** | Erreur explicite "Permission Denied" | La ressource est ignorée silencieusement |

---

## 5. Deep Dive Technique

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
