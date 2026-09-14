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

### Isolated controller build and PostgreSQL verification

The clean `fb1adba` native release controller build completed successfully
(71 build tasks). `cmd/control` source is unchanged through `9627bd8`.
The resulting executable SHA-256 is
`7fc3316414ddc8098397ba1068d61cfd842c1751766bd322ff2ca120c72e0c2f`.
This is build evidence only; the controller has not yet passed isolated startup
or full pipeline acceptance.

Subsequent isolated startup **passed**: the executable acquired PostgreSQL
leadership using the explicit `development-single-instance` profile and bound
only to `127.0.0.1:5880` (API) and `127.0.0.1:5882` (identity listener).
`GET /health` returned 200. Anonymous `GET /v1/accounts` returned 401; an
operator-authenticated `POST /v1/accounts` created the test-only enterprise
account `acceptance-user-20260915` with HTTP 201. Its public response did not
contain the raw provider subject or its digest. A direct SQL query confirmed
the `accounts` and `client_handoffs` snapshot domains exist in
`acceptance_controller`, along with the other initialized stores.

This is not public registration or identity-provider integration: the account
was created using the operator API and a test-only identity receipt. No model
deployment or readiness was asserted. The runtime endpoint is an unused
loopback fixture address, and its configured artifact digest identifies the
marked test MP4, not model weights. Cosign is not yet provisioned in this
isolated host profile; actual artifact admission remains unqualified and must
not be bypassed. The placeholder launch URL is not a working authenticated
ComfyUI launch. Cross-process media acceptance remains outstanding.

An independent PostgreSQL 16.15 pod and 5 GiB PVC were created in
`aigc-acceptance-20260915`, without a Service or public ingress. Namespace
default-deny ingress/egress remains applied. An administrator-only localhost
port-forward provides test access; this disposable instance uses trust auth and
must not be exposed or reused as a production database.

All four `database` tests passed against its `acceptance_only` database:
atomic snapshots, account/client-handoff domains, transaction rollback/mutex
release, and exclusive leadership transfer after connection close. A separate
empty `acceptance_controller` database was created for the subsequent controller
startup so fixture snapshot contents do not contaminate that check. No
production database or controller was changed.

### Native API regression revalidation

The clean `fb1adba` source archive (API/account/commerce/media/workspace sources
unchanged through `f192258`) passed all **125 native API tests** again on Linux
with the isolated MoonBit 0.10.10 toolchain. The full log was captured at
`aigc-spark-preflight/native-api-acceptance.log`; the adjacent
`run-native-api-acceptance.mbtx` records the exact command and checks its exit
code and complete summary.

The first attempt failed because extracted libpq headers were not on the C
include path. Setting `C_INCLUDE_PATH` to the extracted PostgreSQL headers,
with corresponding `LIBRARY_PATH` and `LD_LIBRARY_PATH`, resolved that build
environment issue without modifying dependencies or system packages.
Warning 92 was disabled, and existing deprecation warnings remain; this is not
the warning-clean release gate. Tests use disposable fixture state, including
synthetic inventory confined to tests, not a modified physical node report.

Coverage includes registration without machine authority, bounded trials,
organization isolation, paid endpoint/video order handling, usage, revocation
and cross-store onboarding restart recovery. Existing media fixture content is
not playable video. These passes do not establish real identity/payment provider
integration or the cross-process ComfyUI/MoonGate pipeline.

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
