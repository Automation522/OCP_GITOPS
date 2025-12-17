# Guide d'installation OpenShift Virtualization

Ce guide décrit l'installation et la configuration d'OpenShift Virtualization (CNV) sur le cluster OpenShift 4.18 en environnement déconnecté.

## Sommaire

1. [Prérequis](#prérequis)
2. [Installation de l'opérateur](#installation-de-lopérateur)
3. [Création du HyperConverged](#création-du-hyperconverged)
4. [Vérification de l'installation](#vérification-de-linstallation)
5. [Création d'une VM de test](#création-dune-vm-de-test)
6. [Dépannage](#dépannage)

## Prérequis

### Matériel

| Ressource | Minimum | Recommandé | Cluster actuel |
|-----------|---------|------------|----------------|
| CPU par worker | 4 vCPU | 8+ vCPU | ✅ 8 vCPU |
| RAM par worker | 16 GB | 32+ GB | ✅ 16-32 GB |
| Stockage | RWX capable | SSD recommandé | ✅ vSphere CSI |

### Logiciel

- ✅ OpenShift 4.18.27
- ✅ Cluster Operators sains
- ✅ StorageClass par défaut (`thin-csi`)
- ✅ CatalogSource avec `kubevirt-hyperconverged` disponible

### Version disponible

| Composant | Version |
|-----------|---------|
| OpenShift Virtualization | 4.18.17 |
| Channel | stable |
| CatalogSource | cs-redhat-operator-index-v4-18 |

## Installation de l'opérateur

### Étape 1 - Créer le namespace

```bash
export KUBECONFIG=/home/ocp-airgap/Installation/ocp4-vsphere-upi-automation-ocp4-upi/install-dir/auth/kubeconfig

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
```

### Étape 2 - Créer l'OperatorGroup

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
EOF
```

### Étape 3 - Créer la Subscription

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kubevirt-hyperconverged
  source: cs-redhat-operator-index-v4-18
  sourceNamespace: openshift-marketplace
  startingCSV: kubevirt-hyperconverged-operator.v4.18.17
EOF
```

### Étape 4 - Vérifier l'installation de l'opérateur

```bash
# Attendre que l'opérateur soit installé
oc get csv -n openshift-cnv -w

# Vérifier le statut
oc get csv -n openshift-cnv kubevirt-hyperconverged-operator.v4.18.17 -o jsonpath='{.status.phase}'
```

Le statut doit être `Succeeded`.

## Création du HyperConverged

Une fois l'opérateur installé, créer l'instance HyperConverged pour déployer tous les composants :

```bash
cat <<EOF | oc apply -f -
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
  annotations:
    deployOVS: "false"
spec:
  infra:
    nodePlacement:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
  workloads:
    nodePlacement:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
EOF
```

> **Note** : Les VMs seront schedulées uniquement sur les nœuds `worker`. Pour utiliser des nœuds dédiés, modifier `nodeSelector`.

## Vérification de l'installation

### Vérifier les pods

```bash
oc get pods -n openshift-cnv
```

Tous les pods doivent être en état `Running` ou `Completed`.

### Vérifier le HyperConverged

```bash
oc get hyperconverged kubevirt-hyperconverged -n openshift-cnv -o jsonpath='{.status.conditions}' | jq .
```

### Vérifier les composants

```bash
# KubeVirt
oc get kubevirt -n openshift-cnv

# CDI (Containerized Data Importer)
oc get cdi -n openshift-cnv

# Network Addons
oc get networkaddonsconfig cluster
```

### Vérifier la console web

Après installation, un nouveau menu **Virtualization** apparaît dans la console OpenShift :

```
https://console-openshift-console.apps.ocp4-upi.skyr.dca.scc
```

## Création d'une VM de test

### Option 1 - VM Fedora depuis un template

```bash
cat <<EOF | oc apply -f -
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: fedora-test
  namespace: default
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/domain: fedora-test
    spec:
      domain:
        cpu:
          cores: 2
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - masquerade: {}
            name: default
        machine:
          type: q35
        memory:
          guest: 2Gi
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        containerDisk:
          image: registry.redhat.io/rhel9/rhel-guest-image:latest
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: cloud-user
            password: redhat123
            chpasswd:
              expire: false
            ssh_pwauth: true
EOF
```

### Option 2 - VM depuis un fichier QCOW2

Pour importer une image QCOW2 depuis une URL :

```bash
cat <<EOF | oc apply -f -
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: rhel9-disk
  namespace: default
spec:
  source:
    http:
      url: "https://url-to-your-qcow2-image/rhel9.qcow2"
  storage:
    accessModes:
      - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
    storageClassName: thin-csi
EOF
```

### Accéder à la console de la VM

```bash
# Via virtctl (installer depuis OperatorHub ou télécharger)
virtctl console fedora-test

# Ou via la console web OpenShift
# Virtualization → VirtualMachines → fedora-test → Console
```

## Dépannage

### Les pods ne démarrent pas

```bash
# Vérifier les événements
oc get events -n openshift-cnv --sort-by='.lastTimestamp'

# Vérifier les logs de l'opérateur
oc logs -n openshift-cnv deployment/hco-operator
```

### La VM ne démarre pas

```bash
# Vérifier le statut de la VM
oc get vmi fedora-test -o yaml

# Vérifier les événements
oc get events --field-selector involvedObject.name=fedora-test
```

### Problèmes de stockage

```bash
# Vérifier que la StorageClass supporte le provisionnement dynamique
oc get sc thin-csi -o yaml

# Vérifier les PVC
oc get pvc -n default
```

### Images non disponibles (air-gap)

En environnement déconnecté, les images doivent être mirrorées dans Harbor :

| Image source | Image miroir |
|--------------|--------------|
| `registry.redhat.io/rhel9/rhel-guest-image` | `harbor.skyr.dca.scc/rhel9/rhel-guest-image` |
| `quay.io/kubevirt/...` | `harbor.skyr.dca.scc/kubevirt/...` |

## Ressources utiles

- [Documentation officielle OpenShift Virtualization](https://docs.openshift.com/container-platform/4.18/virt/about_virt/about-virt.html)
- [KubeVirt User Guide](https://kubevirt.io/user-guide/)
- [API Reference](https://kubevirt.io/api-reference/)
