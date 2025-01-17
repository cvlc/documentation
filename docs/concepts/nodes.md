---
title: "Nodes"
linkTitle: Nodes
---

An Ondat node is any machine (virtual or physical) that is running the
Ondat daemonset pod. A node must be running a daemonset pod in order to
consume and/or present storage.

Nodes can be run in several modes.

## Hyperconverged Mode

By default Ondat nodes run in `hyperconverged` mode. This means that the
node hosts data from Ondat volumes and can present volumes to applications.

A hyperconverged node can store data from a volume and present volumes to
applications regardless of whether the data for the volume consumed is placed
on that node or is being served remotely. Remote volumes like this are handled
by an internal protocol to present block device access to applications running
on different nodes from the one to which their backing data store is attached.

Ondat implements an extension of a Kubernetes Scheduler object that
influences the placement of Pods on the same nodes as their data.

## Compute-only Mode

Alternatively, a node can run in `computeonly` mode, which means no storage is
consumed on the node itself and the node only presents volumes hosted by
other nodes. Volumes presented to applications running on compute only nodes
are therefore all remote. Compute only nodes can be very useful for topologies
where nodes are ephemeral and should not host data, but the ephemeral nodes
host applications that require Ondat volumes. The nodes that are not
intended to hold data, but just to present Ondat volumes, can be set as
`computeonly`.

A node can be marked as compute only at any point in time by adding the label
`storageos.com/computeonly=true`, following the [labels reference](/docs/reference/labels).

## Storage Mode

Finally, nodes can be set to storage mode. Nodes set to storage mode don't
present data locally - instead all data is accessed through the network. This
topology is enforced by tainting the relevant nodes to ensure that application
workloads cannot be scheduled there.

This mode is ideal for ensuring maximum stability of data access as the node is
isolated from resource drains that may occur due to applications running
alongside. For redundancy purposes, in high load clusters it is ideal to have
several nodes running in this mode.
