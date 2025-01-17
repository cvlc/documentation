#!/bin/bash

set -euo pipefail

# Ondat Self-Evaluation This script will install Ondat onto a
# Kubernetes cluster
# 
# This script is based on the installation instructions in our self-evaluation
# guide: https://docs.storageos.com/docs/self-eval. See that guide for
# more information.
# 
# Expectations:
# - Kubernetes cluster with a minium of 3
#   nodes
# - kubectl in the PATH - kubectl access to this cluster with
#   cluster-admin privileges - export KUBECONFIG as appropriate

# The following variables may be tuned as desired. The defaults should work in
# most environments.
export OPERATOR_VERSION='v2.4.4'
export CLI_VERSION='v2.4.4'
export STOS_VERSION='v2.4.4'
export STORAGEOS_OPERATOR_LABEL='name=storageos-cluster-operator'
export STOS_NAMESPACE='kube-system'
export ETCD_NAMESPACE='storageos-etcd'
export STOS_CLUSTERNAME='self-evaluation'

# Define some colours for later
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color


# If running in Openshift, an SCC is needed to start Pods
if grep -q "openshift" <(kubectl get node --show-labels); then
    oc adm policy add-scc-to-user anyuid \
    system:serviceaccount:${ETCD_NAMESPACE}:default
    sleep 5
fi

echo -e "${GREEN}Welcome to the Ondat quick installation script.${NC}"
echo -e "${GREEN}I will install Ondat version ${STOS_VERSION} into${NC}"
echo -e "${GREEN}namespace ${STOS_NAMESPACE} now. If I encounter any errors${NC}"
echo -e "${GREEN}I will stop immediately.${NC}"
echo

# First, we create an etcd cluster. Our example uses the CoreOS operator to
# create a 3 pod cluster using transient storage. This is *unsuitable for
# production deployments* but fine for evaluation purposes. The data in the
# etcd will not persist outside of a reboot.
echo -e "${GREEN}Creating etcd namespace ${ETCD_NAMESPACE}${NC}"
kubectl create namespace ${ETCD_NAMESPACE}

echo -e "${GREEN}Creating etcd ClusterRole and ClusterRoleBinding${NC}"
kubectl -n ${ETCD_NAMESPACE} create -f-<<END
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: etcd-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: etcd-operator
subjects:
- kind: ServiceAccount
  name: default
  namespace: ${ETCD_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: etcd-operator
rules:
- apiGroups:
  - etcd.database.coreos.com
  resources:
  - etcdclusters
  - etcdbackups
  - etcdrestores
  verbs:
  - "*"
- apiGroups:
  - apiextensions.k8s.io
  resources:
  - customresourcedefinitions
  verbs:
  - "*"
- apiGroups:
  - ""
  resources:
  - pods
  - services
  - endpoints
  - persistentvolumeclaims
  - events
  verbs:
  - "*"
- apiGroups:
  - apps
  resources:
  - deployments
  verbs:
  - "*"
# The following permissions can be removed if not using S3 backup and TLS
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
---
END

# Create etcd operator Deployment - this will deploy and manage the etcd
# instances
echo -e "${GREEN}Creating etcd operator Deployment${NC}"
kubectl -n ${ETCD_NAMESPACE} create -f-<<END
apiVersion: apps/v1
kind: Deployment
metadata:
  name: etcd-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      name: etcd-operator
  template:
    metadata:
      labels:
        name: etcd-operator
    spec:
      containers:
      - name: etcd-operator
        image: quay.io/coreos/etcd-operator:v0.9.4
        command:
        - etcd-operator
        env:
        - name: MY_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
END

sleep 5

# Wait for etcd operator to become ready
phase="$(kubectl -n ${ETCD_NAMESPACE} get pod -lname=etcd-operator --no-headers -ocustom-columns=status:.status.phase)"
while ! grep -q "Running" <(echo "${phase}"); do
    sleep 2
    phase="$(kubectl -n ${ETCD_NAMESPACE} get pod -lname=etcd-operator --no-headers -ocustom-columns=status:.status.phase)"
done

# Create etcd CustomResource
# This will install 3 etcd pods into the cluster using ephemeral storage. It
# will also create a service endpoint, by which we can refer to the cluster in
# the installation for Ondat itself below.
echo -e "${GREEN}Creating etcd cluster in namespace ${ETCD_NAMESPACE}${NC}"
kubectl -n ${ETCD_NAMESPACE} create -f- <<END
apiVersion: "etcd.database.coreos.com/v1beta2"
kind: "EtcdCluster"
metadata:
  name: "storageos-etcd"
spec:
  size: 3
  version: "3.4.9"
  pod:
    etcdEnv:
    - name: ETCD_QUOTA_BACKEND_BYTES
      value: "2589934592"  # ~2 GB
    - name: ETCD_AUTO_COMPACTION_MODE
      value: "revision"
    - name: ETCD_AUTO_COMPACTION_RETENTION
      value: "1000"
#  Modify the following requests and limits if required
#    requests:
#      cpu: 2
#      memory: 4G
#    limits:
#      cpu: 2
#      memory: 4G
    resources:
      requests:
        cpu: 200m
        memory: 300Mi
    securityContext:
      runAsNonRoot: true
      runAsUser: 9000
      fsGroup: 9000
# The following toleration allows us to run on a master node - modify to taste
#  Tolerations example
#    tolerations:
#    - key: "role"
#      operator: "Equal"
#      value: "etcd"
#      effect: "NoExecute"
    affinity:
      podAntiAffinity:
        preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchExpressions:
              - key: etcd_cluster
                operator: In
                values:
                - storageos-etcd
            topologyKey: kubernetes.io/hostname
END


# Now that we have an etcd cluster starting, we need to install the Ondat
# operator, which will manage the install of Ondat itself.
echo -e "${GREEN}Installing Ondat Operator version ${OPERATOR_VERSION}${NC}"
kubectl create --filename=https://github.com/storageos/cluster-operator/releases/download/${OPERATOR_VERSION}/storageos-operator.yaml

# Wait for the operator to become ready
echo -e "${GREEN}Operator installed, waiting for pod to become ready${NC}"
phase="$(kubectl -n storageos-operator get pod -l${STORAGEOS_OPERATOR_LABEL} --no-headers -ocustom-columns=status:.status.phase)"
while ! grep -q "Running" <(echo "${phase}"); do
    sleep 2
    phase="$(kubectl -n storageos-operator get pod -l${STORAGEOS_OPERATOR_LABEL} --no-headers -ocustom-columns=status:.status.phase)"
done

echo -e "${GREEN}Ondat Operator installed successfully${NC}"

# The Ondat secret contains credentials for our API, as well as CSI
echo -e "${GREEN}Creating Secret definining the API Username and Password${NC}"
kubectl create -f - <<END
apiVersion: v1
kind: Secret
metadata:
 name: "storageos-api"
 namespace: "storageos-operator"
 labels:
   app: "storageos"
type: "kubernetes.io/storageos"
data:
 # echo -n '<secret>' | base64
 username: c3RvcmFnZW9z
 password: c3RvcmFnZW9z
 
END

# Now that we have the operator installed, and a secret defined, it is time to
# install Ondat itself. We default to the kube-system namespace, which
# gives us some protection against eviction by the Kubelet under conditions of
# contention.
# In the Ondat CR we declare the DNS name for the etcd deployment and
# service we created earlier.
echo -e "${GREEN}Installing Ondat Cluster version ${STOS_VERSION}${NC}"
kubectl create -f - <<END
apiVersion: storageos.com/v1
kind: StorageOSCluster
metadata:
 name: ${STOS_CLUSTERNAME}
 namespace: ${STOS_NAMESPACE}
spec:
 secretRefName: "storageos-api"
 secretRefNamespace: "storageos-operator"
 k8sDistro: "upstream"  # Set the Kubernetes distribution for your cluster (upstream, eks, aks, gke, rancher, dockeree, openshift)
 images:
   nodeContainer: "storageos/node:${STOS_VERSION}" # Ondat version
 # storageClassName: fast # The storage class creates by the Ondat operator is configurable
 kvBackend:
   address: "storageos-etcd-client.${ETCD_NAMESPACE}.svc:2379"
END

phase="$(kubectl --namespace=${STOS_NAMESPACE} describe storageoscluster ${STOS_CLUSTERNAME})"
while ! grep -q "Running" <(echo "${phase}"); do
    echo "Waiting for Ondat pods to become ready"
    sleep 10
    phase="$(kubectl --namespace=${STOS_NAMESPACE} describe storageoscluster ${STOS_CLUSTERNAME})"
done

echo -e "${GREEN}Ondat Cluster installed successfully${NC}"

# Now that we have a working Ondat cluster, we can deploy a pod to run the
# cli inside the cluster. When we want to access the cli, we can kubectl exec
# into this pod.
echo "Deploying the Ondat CLI as a pod in the kube-system namespace"
# Deploy the Ondat CLI as a container
kubectl -n kube-system run               \
--image storageos/cli:${CLI_VERSION}     \
--restart=Never                          \
--env STORAGEOS_ENDPOINTS=storageos:5705 \
--env STORAGEOS_USERNAME=storageos       \
--env STORAGEOS_PASSWORD=storageos       \
--command cli                            \
-- /bin/sh -c "while true; do sleep 999999; done"

# Check if Ondat cli is running
phase="$(kubectl --namespace=${STOS_NAMESPACE} describe pod cli)"
while ! grep -q "Running" <(echo "${phase}"); do
    echo "Waiting for the cli pod to become ready"
    sleep 10
    phase="$(kubectl --namespace=${STOS_NAMESPACE} describe pod cli)"
done

echo -e "${GREEN}Ondat CLI pod is running${NC}"

echo -e "${GREEN}Your Ondat Cluster now is up and running!${NC}"
echo
echo -e "${GREEN}Now would be a good time to deploy your first volume - see${NC}"
echo -e "${GREEN}https://docs.storageos.com/docs/self-eval/#a-namestorageosvolumeaprovision-a-storageos-volume${NC}"
echo -e "${GREEN}for an example of how to mount a Ondat volume in a pod${NC}"
echo
echo -e "${GREEN}Don't forget to license your cluster - see https://docs.storageos.com/docs/operations/licensing/${NC}"
echo
echo -e "${GREEN}This cluster has been set up with an etcd based on ephemeral${NC}"
echo -e "${GREEN}storage. It is suitable for evaluation purposes only - for${NC}"
echo -e "${GREEN}production usage, see our etcd installation nodes at${NC}"
echo -e "${GREEN}https://docs.storageos.com/docs/prerequisites/etcd/${NC}"

