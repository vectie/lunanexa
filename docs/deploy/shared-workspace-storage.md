# Shared workspace storage: management NFS + upstream CSI

Status, 2026-09-23: management NFS, dedicated export, persistent TCP 2049
firewall, upstream CSI driver and non-default RWX StorageClass are installed.
A disposable two-Spark Kubernetes PVC read/write probe passed. Real workspace
reopen, tenant isolation and NFS restart acceptance remain pending. This does
not migrate existing local-path PVCs or make the management disk highly available.

## Deployment profile

- Server: management `192.168.2.175`, dedicated `/data/lunanexa-workspaces`; never `/`, `/home`, `/data` itself or the model store.
- Existing `/data` capacity observed by main: 7.2 TiB total / about 4.6 TiB free. Inspect it again before installation. The script requires `/data` to be a real mountpoint to avoid filling the root disk.
- Export clients: exact five management/Spark IPs `.175`–`.179`. `sync,all_squash,anonuid=1000,anongid=1000`, root ownership `1000:1000`, mode `0770`.
- StorageClass `lunanexa-workspaces-rwx`; NFS v4.1, hard mounts; one directory per namespace/PVC/PV. Both Kubernetes reclaim policy and CSI deletion behavior retain data.
- Runtime must select this class, `ReadWriteMany`, and run the workspace with UID/GID/fsGroup 1000. The example claim is not installed automatically; gateway owns namespace and per-workspace claims.
- CSI is upstream `kubernetes-csi/csi-driver-nfs` v4.13.1 at commit `d1b043ffd67318fa71b4b3d4508707882cf92fdc`, not a custom driver. Controller is management-only. Two architecture-filtered node DaemonSets cover Linux amd64 and arm64, with a dedicated opt-in node label.
- Profile records six genuinely resolved upstream index digests. Preparation selects exact Linux child digests for images actually used, with no mutable tags. Snapshotter is omitted because this profile does not install snapshot CRDs/controller. Controller resizer remains upstream, but StorageClass expansion is disabled: ordinary NFS directories do not enforce capacity quotas.

## Prepare artifacts (no cluster/host changes)

From repository root on a machine with MoonBit and curl:

```text
moon run scripts/prepare-shared-storage.mbtx prepare /absolute/new/bundle
```

Choose a new, nonexistent output directory. This downloads source manifests from the exact upstream commit and indexes by their real digest, verifies Linux amd64/arm64 availability, writes architecture-specific pinned manifests and the narrow exports configuration. Existing generated files are not overwritten.

For an offline image cache, install/use `skopeo` on the designated preparation host, using the administrator's existing package mirror configuration, then:

```text
moon run scripts/prepare-shared-storage.mbtx cache-images /absolute/new/bundle
```

It downloads five amd64 images (NFS plugin, provisioner, resizer, liveness probe, registrar), and three arm64 images (plugin, liveness probe, registrar). It does **not** copy the complete liveness index, which also contains Windows images. `--preserve-digests` preserves the exact platform references used by the rendered workloads. Failed/partial archives need inspection before retry; this command deliberately does not silently overwrite an existing archive.

An optional third argument selects an existing verified `crane` executable instead of skopeo:

```text
moon run scripts/prepare-shared-storage.mbtx cache-images /absolute/new/bundle /absolute/private/crane
```

This uses upstream `crane pull --format=oci --annotate-ref` into individual OCI layouts and then tar archives; no daemon or system package installation. For this preparation, upstream go-containerregistry v0.20.3 Linux x86_64 release archive SHA-256 is `36c67a932f489b3f2724b64af90b599a8ef2aa7b004872597373c0ad694dc059`, verified against its official release `checksums.txt` and again after transfer to management. OCI layouts are retained beside the archives for inspection/reuse.

Copy the prepared bundle and repository script/profile to the intended hosts through the existing trusted SSH route. Cache files are artifact inputs, not user workspaces. On each node, after confirming its containerd socket, import that node's platform cache:

```text
sudo /absolute/path/to/moon run scripts/prepare-shared-storage.mbtx import-images /absolute/bundle /run/containerd/containerd.sock
```

The script calls `ctr --namespace k8s.io images import --digests --base-name ... --platform linux/<architecture>` and imports only the matching architecture. Confirm the pinned references appear in the CRI image inventory before proceeding. Cache download, transfer and import passed on management and all four Spark nodes. The Spark Kubernetes socket is `/run/k3s/containerd/containerd.sock`, not the generic example socket above. Direct registry pulls remain possible when nodes have registry access.

Management uses k3s: its actual socket is `/run/k3s/containerd/containerd.sock` (confirmed through the existing artifact-builder workflow), not the Spark example socket above. The existing `lunanexa-runtime-qualification/offline-production-builder` has `/host/k3s ctr` and its corresponding socket; it may be reused for explicit coordinated image imports without creating another privileged Pod. Do not delete that shared builder.

## Enable host and driver

On management, from the repository root, with an interactive authorized sudo session (no password in command arguments):

```text
sudo /absolute/path/to/moon run scripts/prepare-shared-storage.mbtx install-server /absolute/bundle
```

This runs `apt-get update`, installs `nfs-kernel-server nfs-common` without rewriting mirrors, creates only the dedicated export directory/configuration, enables NFS and reloads exports. It refuses unexpected existing export ownership/configuration instead of recursively changing permissions. Host firewall must permit NFS v4 TCP 2049 from the five node IPs only; do not expose NFS publicly. The script does not rewrite existing firewall rules.

This host step completed on 2026-09-23. `/data` remains a separate mount with
about 4.6 TiB available; the export root is UID/GID 1000 mode 0770. UFW is
inactive, so a dedicated persistent `lunanexa-nfs-firewall.service` and an
`nfs-server.service` dependency were installed. Its IPv4 chain allows only
192.168.2.175 and 192.168.2.176–179 on TCP 2049; its IPv6 chain drops that
port. No other ports are changed. The source files are under `deploy/cluster/`.
The export ACL additionally names the exact five hosts. A public TCP connect
to 106.39.18.146:2049 persisted even when management NFS was stopped, while
RPC v4 reset in both states. That public listener cannot be attributed to this
service without router inspection, and is not evidence of a public NFS mount.

A direct NFS v4.1 hard mount on Spark `.176` and `.177` succeeded. Each node
wrote a distinct 4096-byte file as UID/GID 1000; the other node read the same
SHA-256 (`425b4b1e…ffeec` and `229755d9…0abc8`). Both mounts were unmounted,
the two test-only files deleted, and their temporary mountpoint directories
removed. This proves host-level cross-node read/write, not PVC isolation,
reconnect behavior or a user workspace reopen.

On management with the existing kubeconfig:

```text
moon run scripts/prepare-shared-storage.mbtx install-driver /absolute/bundle /home/HwHiAiUser/.kube/lunanexa-management
```

This opts in the five named nodes, applies upstream RBAC/CSIDriver, management controller and architecture-specific node DaemonSets, creates the non-default StorageClass and waits for all rollouts. It does not change existing default/local-path StorageClasses, PVCs, workspaces or model-serving workloads. Driver privilege and kubelet mount propagation are confined to kube-system platform components.

The controller reached 1/1, the amd64 node DaemonSet 1/1 and all four arm64
node Pods 3/3. A disposable claim `cross-spark-probe` bound to a dynamically
provisioned PV with source subdirectory
`lunanexa-storage-probe-20260923/cross-spark-probe/pvc-45e15abe-2d2d-4995-b5ae-e4d3c5d00a7f`.
Restricted UID/GID 1000 Pods on Spark `.176` and `.177` mounted it and wrote
4096-byte files in both directions; opposite-node SHA-256 matched
`011d8da6…40116` and `10a42b24…1a52`. Only the exact disposable Pods, claim,
PV, namespace and two retained probe files/directory were removed afterward.
The production driver, StorageClass, NFS export and image caches remain.

Read-only host checks: all four Spark nodes have `/usr/sbin/mount.nfs` and `/lib/modules/7.0.0-1019-nvidia/kernel/fs/nfs/nfs.ko.zst`; .176 has `/usr/bin/ctr` and `/run/containerd/containerd.sock`. Management has `/usr/local/bin/ctr`; inspecting its socket requires elevated permissions. The management NFS server and firewall are active; the two-node direct-mount probe above now supersedes the earlier kernel-only observation.

## Isolation and acceptance

Per-workspace PVCs expose their own provisioned directory, never the entire shared export. Keep workload non-root UID 1000, no host networking, no mount capabilities, no Kubernetes service-account token, namespace-scoped RBAC, and existing deny-by-default workspace egress. In particular user Pods must not directly connect to management TCP 2049. AUTH_SYS trusts the host; exporting to node IPs alone is not a tenant boundary (Pod traffic can be SNATed). Trusted node administrators and CSI can access the export root.

Before changing production workspace configuration, verify with disposable authorized test workspaces:

1. PVC binds; actual PV source is the namespace/PVC/PV subdirectory, not export root.
2. Workspace A writes a file and workflow/output using its real runtime UID. Close it, reschedule to another Spark with the same claim, reopen and compare file bytes; download the generated result through the authenticated gateway.
3. Workspace B cannot mount A's claim or see A's files; user Pod direct NFS RPC is denied by NetworkPolicy. Check actual CNI enforcement, not just existence of policy YAML.
4. Stop/reopen preserves A's data. Confirm Retain policy before any disposable claim deletion; namespace deletion does not authorize storage erasure.
5. NFS restart restores access without losing committed files. Hard mounts may block I/O while server is unavailable; management remains a single point of failure.

No hard storage quota, snapshot service, encrypted-at-rest tenant separation or HA is claimed. Add disk usage alerts/backup policy before customer use. Do not automatically delete retained directories. For rollback, stop new workspace allocation and return new-workspace configuration to its prior class; keep existing shared claims/export intact while referenced. Never disable the driver/NFS server while shared workspaces remain mounted.

Existing local-path workspaces require an explicit quiesced data copy into a newly provisioned shared claim, ownership verification and reopen test; changing StorageClass does not migrate their contents. Model weights remain node-local CAS/cache and are outside this NFS export.

Sources: [upstream v4.13.1 manifests](https://github.com/kubernetes-csi/csi-driver-nfs/tree/v4.13.1/deploy/v4.13.1), [driver parameters](https://github.com/kubernetes-csi/csi-driver-nfs/blob/v4.13.1/docs/driver-parameters.md), [node mount implementation](https://github.com/kubernetes-csi/csi-driver-nfs/blob/v4.13.1/pkg/nfs/nodeserver.go).
