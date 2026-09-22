# Shared workspace storage preparation — 2026-09-23

Scope: prepare upstream NFS CSI manifests and reusable image artifacts only. No NFS service installed, export enabled, containerd image imported, DaemonSet applied or workspace/PVC changed.

## Completed

- Pinned upstream CSI v4.13.1 exact commit `d1b043ffd67318fa71b4b3d4508707882cf92fdc`; all six release image indexes fetched by actual registry digest and Linux amd64/arm64 platform entries checked.
- Generated management controller and two architecture-specific node DaemonSets with platform digest image refs. Snapshotter omitted (no snapshot feature/CRDs in this profile).
- MoonBit preparation ran to exit 0; standalone script formatted. Final cache mode compiled and ran to exit 0. Wrong-arguments check returns the expected usage failure, not a compiler error.
- Controller, corrected arm64 DaemonSet and StorageClass parsed by `kubectl create --dry-run=client --validate=false` using management kubeconfig, exit 0. This is not server-side admission/live mount acceptance.
- All eight Linux OCI archives downloaded using verified upstream crane v0.20.3, 241 MiB total. No Windows/other architecture layer download.
- Transferred eight archives to management and compared every remote SHA-256 with local values: all match.

Management artifact directory:

```text
/home/HwHiAiUser/shared-storage-preparation.yHhS6M/verified-bundle
```

Its parent contains the matching script/profile and verified private Linux crane binary; no system binary installed. Local prepared bundle/layouts: `/tmp/lunanexa-shared-storage.H3k8P5/verified-bundle`.

## Archive transfer checksums

```text
3d1bf1f989a83bea03f7a786f25680341e1805c2b352ce1a0ac59fc6ba89140b  csi-node-driver-registrar-amd64.oci.tar
07b9b55f3a98c80624c2a2fe271643d5030b5e7e51aea529fb01d511fd6e739b  csi-node-driver-registrar-arm64.oci.tar
9cd7d59ebacc98393901d402b90464dda8f65067e89f75864c39d561ad99cc4d  csi-provisioner-amd64.oci.tar
50a1f52689da683153994143a1e4fdc2e2bab040ebbc6c862008c47ec0aa4030  csi-resizer-amd64.oci.tar
5de7a1567442d0022d244d375042ad95e45a698e4283369cb771aac79f046706  livenessprobe-amd64.oci.tar
06628298f2d4a94515b8d9004c3ead80862884a448a33f7fbf41827e9170f70a  livenessprobe-arm64.oci.tar
86a23b429ef936fdec4dd8aa111bef5665349da68d4df97516116780638b6efc  nfsplugin-amd64.oci.tar
1eccfdc10f9819755fd1c0127238637f07cc666ad55d10d3d43095582520d4bd  nfsplugin-arm64.oci.tar
```

## Observed network issue and resolved artifact path

Management direct crane pull failed because registry.k8s.io redirected the first image to `europe-west4-docker.pkg.dev` (`173.194.202.82:443`) and that TCP connection timed out. The registry front door itself responded HTTP 401 normally. No repeated background retry was left running. Cache used the working local network to fetch the exact same pinned images, then transferred archives over the existing SSH route. Installation should use these offline archives, not assume direct registry pulls work.

## Remaining coordinated enablement

1. Install management NFS server packages, review TCP 2049 firewall scope and enable the dedicated restricted export.
2. Import amd64 archives to management **k3s** socket `/run/k3s/containerd/containerd.sock`; distribute/import three arm64 archives on each Spark (observed .176 socket `/run/containerd/containerd.sock`; confirm others).
3. Apply driver and non-default Retain StorageClass; inspect Pod readiness/events and actual PV subdirectory.
4. Configure gateway-created workspace claims to use RWX/new class; do not mutate old local-path claims in place.
5. Run cross-node write/reopen/download and cross-tenant denial tests. Actual server restart recovery, quotas/backups and management storage availability remain separate acceptance/operations work.

All four Sparks expose mount.nfs and their installed NVIDIA kernel's NFS module file. That proves client prerequisites exist, not that NFS mount/permissions work. Existing `glm53-nfs` on Spark .178 is unrelated and was neither stopped nor reused.

See [deployment procedure](../deploy/shared-workspace-storage.md) for exact preparation/install commands and isolation limits.
