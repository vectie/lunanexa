# Cache and native workspace follow-up — 2026-09-15

## Scope and result

The data-node readiness receipt at
`/data/models/.spark-preflight-20260914/ready.json` reports
`download_cache_ready: true`. This is offline preparation evidence, not a
production release or GPU qualification. See `SPARK_CACHE_HANDOFF_20260914.md`
for import instructions and the original verification details.

- 26 model files, 276,854,506,911 bytes; 25 unchanged verification receipts
  reused and one file freshly rehashed.
- 108 image blobs and five fully validated offline image archives.
- 212 wheel files checked and four locked offline dependency plans verified.
- Model weights remain separate from application images.

## Native workspace fixes and observed checks

The previous native helper image had root-owned mode-0750 executables, which
UID 1000 could not run. Its proxy binary also lacked workspace initialization
mode despite its recent build timestamp. Both are real packaging failures.

`Containerfile.webide-runtime` now normalizes executable permissions, requires
source revision metadata, and exercises the actual initializer as UID 1000.
A build using the stale binaries failed the initializer gate as expected.
Fresh binaries built from a clean archive of
`fb1adba8e881e59c5aae3214430c6cd1fde798fd` passed it.

Native helper executable SHA-256:

- proxy: `14b7007d5015bf26f6ac7c1855e908643294e4847695f725a240e4df046caff1`
- gateway: `9bd707c1443d0a02977768c04ea480dc49fc4ecd6df3d42a68025e16747144e9`

Images imported into the private registry, and pulled successfully by the
management node over certificate-validated HTTPS:

- `acceptance/webide-runtime@sha256:7c554a7076df577d6ca826d5aa7f2c11b7cbb4630cc41b71c84ab3b2992ec5e7`
- `acceptance/comfyui-workspace@sha256:4a48ba086b05c3988694c62c42ac87bfdb4654c536a6bf42650113b15388ed9e`

Registry prefix:
`lunanexa-registry.lunanexa-registry.svc.cluster.local:5000`.

The isolated `aigc-acceptance-20260915` namespace runs the actual ComfyUI
workspace on native AMD64 CPU, with a PVC, non-root containers and read-only
container roots. Initialization completed and the deployment became Ready.
The private port-forward `/system_stats` returned HTTP 200, ComfyUI 0.34.0,
frontend 1.51.9 and CPU-only PyTorch 2.14.0. The video custom node schema was
available. A QEMU-only `kornia_rs` crash was not reproduced on native AMD64;
no production dependency downgrade was made.

## Registry configuration maintenance

The management host lacked private-registry DNS resolution and trust. A scoped
hosts entry, K3s registry configuration and containerd registry hosts file were
installed; TLS verification remains enabled. Temporary host-maintenance pods
were removed. Existing hosts entries were preserved and backed up.

The pinned registry certificate expires **2026-11-28**. Rotate the trust file
with the registry certificate before expiry. Update the hosts entry if the
registry Service IP changes. This repair is management-node-specific; it does
not establish trust automatically on future Spark nodes.

## Still not qualified

### Subsequent native persistence check

The actual ComfyUI HTTP API accepted a clearly marked `TEST ONLY / NO GPU MODEL`
PNG and MP4 fixture. Downloaded PNG bytes matched the uploaded source. A real
`LoadVideo -> SaveVideo` queue execution completed successfully, prompt ID
`41f4808d-f34d-4d44-bf62-9afd23ee6889`, producing
`output/acceptance/test-only_00001_.mp4`. This was video loading/saving, not
inference. A workflow was saved through `/userdata` as `Acceptance Saved.json`.

The test deployment was then restarted. The old pod
`comfyui-acceptance-6487b97576-v9pqp` was replaced by
`comfyui-acceptance-55776cb75c-78vpj`; rollout completed successfully. Through a
new port-forward targeting that exact replacement pod, the saved workflow,
uploaded PNG and output MP4 were downloaded again. All three compared
byte-for-byte equal to their pre-restart copies. Evidence files are in the
operator's `aigc-spark-preflight/persistence-*` directory. This proves persistence
for these files across this container/pod replacement on the same local-path
PVC, not storage-node loss recovery, tenant isolation or browser authentication.

The replacement pod's `/ws` endpoint also returned HTTP 101 with the correct
WebSocket accept value and an initial `status` frame reporting an empty queue.
The observation was deliberately bounded to three seconds (curl exit 28 after
the successful upgrade); this is not a complete WebSocket lifecycle test.
A `/view` request attempting traversal to `../../../../etc/passwd` returned
403. These are direct private ComfyUI checks, not bridge authentication tests.
The now-unused `image-import` and `workspace-volume-inspect` pods were deleted;
the workspace PVC, downloaded caches and registry images were retained.

These checks do not prove authenticated provisioning, tenant isolation,
the full MoonGate inference pipeline,
payment/lease integration, or fault recovery. Those remain separate acceptance
work. No real model was deployed and no Spark GPU or dual-node performance was
tested. The production controller was not upgraded during this follow-up.

The existing compute node has DiskPressure and roughly 436 MiB free on its
1.8 TiB filesystem. It cannot be treated as ready for new workloads. Its model
backups and historical temporary files were not deleted; identifying safe
cleanup targets remains necessary before scheduling there.
