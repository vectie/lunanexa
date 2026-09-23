# Exclusive workspace persistent storage

Use the prepared deployment profile in
[Shared workspace storage](shared-workspace-storage.md), whose StorageClass is
`lunanexa-workspaces-rwx`. The gateway configuration and storage-read RBAC below
use that exact same name.

## Observed deployment, 2026-09-23

Initial read-only queries against management node `192.168.2.175` found only the
`local-path` StorageClass (`rancher.io/local-path`, `WaitForFirstConsumer`,
reclaim policy `Delete`). All listed PVs were RWO. There were no registered
CSI drivers. Management had no mounted NFS filesystem and no populated NFS
export configuration in the inspected output. These observations do **not**
establish that the separate data node has no export: its address/export and
capacity have not been verified in this inspection.

The scoped gateway storage-read RBAC, management NFS, persistent TCP 2049
source firewall, upstream NFS CSI driver and non-default
`lunanexa-workspaces-rwx` StorageClass were subsequently installed. A scratch
RWX claim bound and two restricted UID 1000 Pods on different Sparks exchanged
files with matching SHA-256 in both directions. The scratch resources and
files were cleaned. No existing PVC or live workspace was migrated; public UI
save/close/reopen acceptance remains pending.

## Deployment-owned profile

The gateway HostConfig accepts `storage_access_mode`. Omission preserves
`ReadWriteOnce`. A shared profile explicitly sets, for example:

```json
{
  "storage_class": "lunanexa-workspaces-rwx",
  "storage_access_mode": "ReadWriteMany",
  "storage_gib": 20
}
```

These are fields in the existing complete HostConfig, not a complete config.
`lunanexa-workspaces-rwx` must be a real deployment-installed class backed by shared
storage. Configuring the string alone does not create a filesystem or make
`local-path` movable; `local-path` plus RWX is rejected.

For delivery-bound sessions the PVC name uses the stable tenant, subject,
organization, project and client identity. Runtime resource names additionally
include the delivery ID. ComfyUI and terminal clients therefore retain separate
data, and a new delivery of the same client reuses its existing PVC. Legacy
non-delivery identity is unchanged. Local PVC migration remains explicit.

## Single writer and launch preflight

Shared RWX storage means mountability from several nodes, **not** permission to
run two independently configured editors or ComfyUI databases against the same
home. Exclusive delivery launch acquires the PVC annotation
`lunanexa.io/storage-writer` using a Kubernetes resourceVersion JSON-patch CAS.
Another delivery receives `StorageBusy`; retrying the same delivery is
idempotent. Stop releases ownership only after Kubernetes reports all its pods
gone. A gateway restart discovers the persisted non-runnable recovery Secret
and repeats cleanup. Ownership has no timer that could let a second writer
enter while the first still runs.

Before launch the gateway checks the existing PVC class/access mode and the
bound PV's node affinity. A local volume on another Spark or a changed profile
returns `StorageMigrationRequired`, rather than recreating the PVC, changing
its class, or pretending the data moved. A missing shared StorageClass returns
`StorageNotConfigured`. The launch page explains the required operator action;
none of these responses expose internal volume names or filesystem paths.

The gateway service account needs its existing namespaced PVC get/list/create/
patch authority, plus **read-only** get on persistentvolumes and list on
storageclasses. It does not need PV mutation, host mounting, or export creation.
JSON Patch content type is used only for the PVC ownership CAS; manifests still
use server-side apply. Existing PVCs are not reapplied during exclusive launch.

The installed supplement is
[`deploy/cluster/webide-storage-read.yaml`](../../deploy/cluster/webide-storage-read.yaml).
Read-only inspection confirmed the live Deployment uses service account
`aigc-acceptance-20260915/webide-gateway`; the binding names that exact account.
It grants only PV `get` and StorageClass `list`, with the latter restricted to
`lunanexa-workspaces-rwx`. The lookup includes `fieldSelector=metadata.name=lunanexa-workspaces-rwx`,
as required for a resourceNames-restricted list. Update the allowed class name
alongside HostConfig if the approved profile uses a different name. There are
no wildcard resources, write verbs, PV listing, Secret access, or impersonation
in this supplement. Existing namespaced PVC authority is not expanded here.

It was applied after server-side dry-run. The gateway service account is
authorized to list the named `lunanexa-workspaces-rwx` StorageClass. The CSI
driver and scratch claim now prove the backend; the gateway's real bound-PV
read and workspace mount still need UI acceptance.

A resourceVersion race may produce Kubernetes HTTP 409 or HTTP 422 for JSON
Patch. A 422 becomes `StorageBusy` only after a read confirms that the PVC's
resourceVersion changed from the expected value; unrelated 422 validation
errors are not mislabeled as another writer. The raw Kubernetes error body is
never returned to the user.

## Remaining deployment work

1. Define backup, disk alert and recovery procedures for management `/data`;
   NFS/management is still a single point of failure.
2. For existing local workspaces, stop the runtime and prove no writer remains.
   Back up the PVC, copy into a distinct new shared PVC, verify file contents
   and ownership, and retain the original. Switching a config does not perform
   this copy. Bind/switch the stable workspace claim only in a documented
   maintenance migration; do not delete the original claim as a shortcut.
3. Set the gateway's shared profile only after the backend and any necessary
   migration are ready. Open, save, stop, allocate another Spark and reopen via
   the public portal. Check ComfyUI workflows/results and WebIDE files. Try a
   concurrent delivery and confirm it reports the existing writer instead of
   opening a second writable copy. Finally check expiry releases the writer
   while preserving the PVC.

Source tests cover profile rendering, CAS ownership, retained claim reuse and
explicit local-node/profile mismatch. The scratch Kubernetes probe proves
cross-node file bytes, not application persistence, NFS restart recovery or
backup recovery.
