---
title: Self Evaluation Guide
linkTitle: Self Evaluation Guide
weight: 900
description: >
  Guide to self-evaluate Ondat as a secure, high-available, and performant data management platform.
---

Following the [Ondat deployment on a Kubernetes cluster](install), this comprehensive set of How-Tos help to evaluate key funtionalities like:

* __Availability__ - how to embrace failures
* __Encryption__ - how to secure data
* __Benchmarking__ - how and what to mesure 

## Feedback - Sharing is caring!  
Should you have a question, join us on [our public Slack channel](https://slack.ondat.io).  
Should you spot a *pearl*, open an issue or contribute by creating a Pull Request to address it on [our public documentation repository](https://github.com/ondat/documentation).  

## Prerequisites
* Ondat deployed on a production-grade kubernetes cluster
* root access to the nodes

## Preparing the environment 
The overall YAML defintions are available on [our public use-case repository](https://github.com/ondat/use-cases) within the folder ```self-evaluation```.  Browse it, fork it, or just clone it:

```
git clone https://github.com/ondat/use-cases.git
```

### Provisioning ReadWriteOnce Example



### Provisioning ReadWriteMany Example

## Provision an Ondat Volume

Now that we have a working Ondat cluster, we can provision a volume to test
everything is working as expected.

1. Create a PVC

    ```bash
    kubectl create -f - <<END
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: pvc-1
    spec:
      storageClassName: "storageos"
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 5Gi
    END
    ```

1. Create 2 replicas by labeling your PVC

    ```bash
    kubectl label pvc pvc-1 storageos.com/replicas=2
    ```

1. Verify that the volume and replicas were created with the CLI

    > `pvc-1` should be listed in the CLI output

      ```bash
      POD=$(kubectl -n storageos get pod -ocustom-columns=_:.metadata.name --no-headers -lapp=storageos-cli)
      kubectl -n storageos exec $POD -- storageos get volumes
      ```

1. Create a pod that consumes the PVC

    ```bash
   kubectl create -f - <<END
   apiVersion: v1
   kind: Pod
   metadata:
     name: d1
   spec:
     containers:
       - name: debian
         image: debian:9-slim
         command: ["/bin/sh","-c","while true; do sleep 3600; done"]
         volumeMounts:
           - mountPath: /mnt
             name: v1
     volumes:
       - name: v1
         persistentVolumeClaim:
           claimName: pvc-1
   END
    ```

1. Check that the pod starts successfully. If the pod starts successfully then
   the Ondat cluster is working correctly

    ```bash
    kubectl get pod d1 -w
    ```

    The pod mounts an Ondat volume under `/mnt` so any files written there
    will persist beyond the lifetime of the pod. This can be demonstrated using
    the following commands.

1. Execute a shell inside the pod and write some data to a file

    ```bash
    kubectl exec -it d1 -- bash
    # echo Hello World! > /mnt/hello
    # cat /mnt/hello
    ```

    > `Hello World!` should be printed to the console.

1. Delete the pod

    ```bash
    kubectl delete pod d1
    ```

1. Recreate the pod

    ```bash
   kubectl create -f - <<END
   apiVersion: v1
   kind: Pod
   metadata:
     name: d1
   spec:
     containers:
       - name: debian
         image: debian:9-slim
         command: ["/bin/sh","-c","while true; do sleep 3600; done"]
         volumeMounts:
           - mountPath: /mnt
             name: v1
     volumes:
       - name: v1
         persistentVolumeClaim:
           claimName: pvc-1
   END
    ```

1. Open a shell inside the pod and check the contents of `/mnt/hello`

    ```bash
    kubectl exec -it d1 -- cat /mnt/hello
    ```

    > `Hello World!` should be printed to the console.

## Ondat Features

Now that you have a fully functional Ondat cluster we will explain
some of our features that may be of use to you as you complete application and
synthetic benchmarks.

Ondat features are all enabled/disabled by applying labels to volumes.
These labels can be passed to Ondat via persistent volume claims (PVCs) or
can be applied to volumes using the Ondat CLI or GUI.

> 💡 The following is not an exhaustive feature list but outlines features which are
> commonly of use during a self-evaluation.

### Volume Replication

Ondat enables synchronous replication of volumes using the
`storageos.com/replicas` label.

The volume that is active is referred to as the master volume. The master
volume and its replicas are always placed on separate nodes. In fact if a
replica cannot be placed on a node without a replica of the same volume, the
volume will fail to be created. For example, in a three node Ondat cluster
a volume with 3 replicas cannot be created as the third replica cannot be
placed on a node that doesn't already contain a replica of the same volume.

> 💡 See our [replication documentation](concepts/replication) for more
> information on volume replication.

1. To test volume replication create the following PersistentVolumeClaim

    ```bash
   kubectl create -f - <<END
   apiVersion: v1
   kind: PersistentVolumeClaim
   metadata:
     name: pvc-replicated
     labels:
       storageos.com/replicas: "1"
   spec:
     storageClassName: "storageos"
     accessModes:
     - ReadWriteOnce
     resources:
       requests:
         storage: 5Gi
   END
    ```

    > 💡 Note that volume replication is enabled by setting the
    > `storageos.com/replicas` label on the volume.

1. Confirm that a replicated volume has been created by using the Ondat CLI
   or UI

    ```bash
    POD=$(kubectl -n storageos get pod -ocustom-columns=_:.metadata.name --no-headers -lapp=storageos-cli)
    kubectl -n storageos exec $POD -- storageos get volumes
    ```


1. Create a pod that uses the PVC

    ```bash
    kubectl create -f - <<END
    apiVersion: v1
    kind: Pod
    metadata:
      name: replicated-pod
    spec:
      containers:
       - name: debian
         image: debian:9-slim
         command: ["/bin/sleep"]
         args: [ "3600"  ]
         volumeMounts:
           - mountPath: /mnt
             name: v1
      volumes:
       - name: v1
         persistentVolumeClaim:
           claimName: pvc-replicated
    END
    ```

1. Write data to the volume

    ```bash
    kubectl exec -it replicated-pod -- bash
    # echo Hello World! > /mnt/hello
    # cat /mnt/hello
    ```

    >`Hello World!` should be printed to the console.

1. Find the location of the master volume and shutdown the node

    Shutting down a node causes all volumes, with online replicas, on the node
    to be evicted. For replicated volumes this immediately promotes a replica
    to become the new master.

    ```bash
    kubectl get pvc
    ```

    ```
    NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
    pvc-replicated Bound    pvc-29e2ad6e-8c4e-11e9-8356-027bfbbece86   5Gi        RWO            storageos       1m
    ```

    ```
    POD=$(kubectl -n storageos get pod -ocustom-columns=_:.metadata.name --no-headers -lapp=storageos-cli)
    kubectl -n storageos exec $POD -- storageos get volumes
    ```

    ```
    NAMESPACE  NAME                                      SIZE     LOCATION              ATTACHED ON   REPLICAS  AGE
    default    pvc-4e796a62-0271-45f9-9908-21d58789a3fe  5.0 GiB  kind-worker (online)  kind-worker2  1/1       26 seconds ago

    ```

1. Check the location of the master volume and notice that it is on a new node.
   If the pod that mounted the volume was located on the same node that was
   shutdown then the pod will need to be recreated.

    ```bash
    POD=$(kubectl -n storageos get pod -ocustom-columns=_:.metadata.name --no-headers -lapp=storageos-cli)
    kubectl -n storageos exec $POD -- storageos get volumes
    ```

    ```
    NAMESPACE  NAME                                      SIZE     LOCATION               ATTACHED ON   REPLICAS  AGE
    default    pvc-4e796a62-0271-45f9-9908-21d58789a3fe  5.0 GiB  kind-worker2 (online)  kind-worker2  1/1       46 seconds ago
    ```

1. Check that the data is still accessible to the pod

    ```bash
    kubectl exec -it replicated-pod -- bash
    # cat /mnt/hello
    ```

    > `Hello World!` should be printed to the console.

&nbsp;
## Benchmarking

Benchmarking storage is a complex topic. Considering the many books and papers
that have been written about benchmarking, we could write many paragraphs here
and only begin to scratch the surface.

Taking this complexity into account we present recipes for both synthetic
benchmarks using [FIO](https://github.com/axboe/fio), and a sample application
benchmark to test PostgreSQL using
[pgbench](https://www.postgresql.org/docs/current/pgbench.html). The approaches
are complementary - synthetic benchmarks allow us to strictly control the
parameters of the IO we put through the system in order to stress various
aspects of it. Application benchmarks allow us to get a sense of the
performance of the system when running an actual representative workload -
which of course is the ultimate arbiter of performance.

Despite the inherent complexity of benchmarking storage there are a few general
considerations to keep in mind.

### Considerations

### Local vs. Remote Volumes

When a workload is placed on the same node as a volume, there is no network
round trip for IO, and performance is consequently improved. When considering
the performance of Ondat it is important to evaluate both local and remote
volumes; since for certain workloads we want the high performance of a local
attachment, but we also desire the flexibility of knowing that our less
performance-sensitive workloads can run from any node in the cluster.

### The Effect of Synchronous Replication

Synchronous replication does not impact the read performance of a volume, but
it can have a significant impact on the write performance of the volume, since
all writes must be propagated to replicas before being acked to the
application. The impact varies in proportion to the inter-node latency. For an
inter-node latency of 1ms, we have a max ceiling of 1000 write IOPS, and in
reality a little less than that to allow for processing time on the nodes. This
is less concerning then it may first appear, since many applications will issue
multiple writes in parallel (known as increasing the queue depth).

### Synthetic Benchmarks

#### Prerequisites

* Kubernetes cluster with a minimum of 3 nodes and a minimum of
30 Gb available capacity
* Ondat CLI running as a pod in the cluster

Synthetic benchmarks using tools such as FIO are a useful way to begin
measuring Ondat performance. While not fully representative of application
performance, they allow us to reason about the performance of storage devices
without the added complexity of simulating real world workloads, and provide
results easily comparable across platforms.

FIO has a number of parameters that can be adjusted to simulate a variety of
workloads and configurations. Parameters that are particularly important are:

* **Block Size** - the size of the IO units performed.
* **Queue Depth** - the amount of concurrent IOs in flight
* **IO Pattern** - access can be random across the disk, or sequentially. IO
    subsystems typically perform better with sequential IO, because of the
    effect of read ahead caches, and other factors

For this self-evaluation we will run a set of tests based on the excellent
[DBench](https://github.com/leeliu/dbench), which distills the numerous FIO
options into a series of well-crafted scenarios:

* **Random Read/Write IOPS and BW** - these tests measure the IOPS ceiling
  (with a 4k block size) and bandwidth ceiling (with a 128K block size) of the
  volume using a random IO pattern and high queue depth
* **Average Latency** - these tests measure the IO latency of the volume under
  favourable conditions using a random access pattern, low queue depth and low
  block size
* **Sequential Read/Write** - these tests measure the sequential read/write
  throughput of the volume with a high queue depth and high block size
* **Mixed Random Read/Write IOPS** - these tests measure the performance of the
    volume under a 60/40 read/write workload using a random access pattern and
    low blocksize

For convenience we present a single script to run the scenarios using local and
remote volumes both with and without a replica. Deploy the FIO tests for the
four scenarios using the following command:

  ```bash
  curl -sL https://raw.githubusercontent.com/ondat/use-cases/main/scripts/deploy-synthetic-benchmarks.sh | bash
  ```

> 💡 The script will take approximately 20 minutes to complete, and will print the
> results to STDOUT.

The exact results observed will depend on the particular platform and
environment, but the following trends should be observable:

* local volumes perform faster than remote volumes
* read performance is independent of the number of replicas
* write performance is dependent on the number of replicas

### Application Benchmarks

While synthetic benchmarks are useful for examining the behaviour of Ondat
with very specific workloads, in order to get a realistic picture of Ondat
performance actual applications should be tested.

Many applications come with test suites which provide standard workloads. For
best results, test using your application of choice with a representative
configuration and real world data.

As an example of benchmarking an application the following steps lay out how to
benchmark a Postgres database backed by an Ondat volume.

1. Start by cloning the Ondat use cases repository. Note this is the same
   repository that we cloned earlier so if you already have a copy just `cd
   storageos-usecases/pgbench`.

    ```bash
    git clone https://github.com/storageos/use-cases.git storageos-usecases
    ```

1. Move into the Postgres examples folder

    ```bash
    cd storageos-usecases/pgbench
    ```

1. Decide which node you want the pgbench pod and volume to be located on. The
   node needs to be labelled `app=postgres`

    ```bash
    kubectl label node <NODE> app=postgres
    ```

1. Then set the `storageos.com/hint.master` label in
   20-postgres-statefulset.yaml file to match the Ondat nodeID for the node
   you have chosen before creating all the files. The Ondat nodeID can be
   obtained using the cli and doing a `describe node`

    ```bash
    kubectl create -f .
    ```

1. Confirm that Postgres is up and running

    ```bash
    kubectl get pods -w -l app=postgres
    ```

1. Use the Ondat CLI or the GUI to check the master volume location and the
   mount location. They should match

    ```bash
    POD=$(kubectl -n storageos get pod -ocustom-columns=_:.metadata.name --no-headers -lapp=storageos-cli)
    kubectl -n storageos exec $POD -- storageos get volumes
    ```

1. Exec into the pgbench container and run pgbench

    ```bash
    kubectl exec -it pgbench -- bash -c '/opt/cpm/bin/start.sh'
    ```

&nbsp;
## Conclusion

After completing these steps you will have benchmark scores for Ondat.
> 💡 Please keep in mind that benchmarks are only part of the story and that there
> is no replacement for testing actual production or production like workloads.

Ondat invites you to provide feedback on your self-evaluation to the [slack channel](https://storageos.slack.com) or by directly emailing us at <info@ondat.io>.
