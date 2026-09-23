# H3 exclusive-node materialization

Implementation and rollout note, 2026-09-23. A catalog template and patched
runtime image now exist, but this document is **not** an end-to-end acceptance
record until an exclusive-node assignment finishes transfer, model startup,
video generation, and ComfyUI output retrieval.

## Current rollout checkpoint (2026-09-23)

- FL2VA is registered as `minimax-h3-fl2va@modelscope-57559a67`, with
  `video.minimax-h3-fl2va` canary alias and component digest
  `sha256:0964a2d8823de7d0a40d3cfa01acd1aa08c3aec632b9b6c25330a158bbe98e73`.
- The code-only ARM64 runtime is published at
  `moon/h3-runtime-serving@sha256:d9f25180c4cb6a2889f19ee66fbf2db54741f1f382b599c0196c4fcf9f95b0d6`.
  A GPU pod passed `vllm --version`; this does not prove that H3 weights load.
- The immutable ComfyUI template is `minimax-h3-fl2va-comfyui@20260923-r2`.
  The node-specific media binding ConfigMap uses that exact version. The
  enterprise catalog hides the superseded `20260923` revision.
- Spark `spark-368c-0f2ee8b2` is Ready and was observed idle before the
  proposed exclusive test. No FL2VA transfer to its verified node cache or
  successful video response has been recorded yet.

## Workload reset later on 2026-09-23

At the owner's request, all running model, ComfyUI, and per-user WebIDE
workloads were removed before a fresh acceptance run. The legacy
`minimaxh3-fl2va`, `minimaxh3-ref2va`, `lunaflux-runtime`,
`comfyui-acceptance`, `comfyui-z-image-spark`, and two zero-replica WebIDE
Deployments, plus their workload-facing Services, were deleted. Four Spark
nodes then reported no GPU compute process; the LunaNexa assignment and
resource-reservation lists were empty. Account, identity, database, portal,
controller, node agents, model files, persistent volume claims, and user work
files were not deleted. This reset does not itself validate the new one-click
pipeline, and the new H3 template remains catalog-only until a fresh launch.

The observations below explain the migration decisions made earlier that day;
their imperative “Do not create an enabled template yet” was superseded only
after the catalog/image prerequisites above were implemented. It is **not**
evidence that the remaining real transfer and generation checks passed.

## Read-only deployment observations (2026-09-23)

The management node already has a 62,299-byte source manifest at
`/data/models/MiniMax/MiniMax-H3/lunanexa-source-manifest.json`. Its exact SHA-256 is
`f7f70408dcc8b939379548bb74354fd02a2ca184d3ddb7a37cc827684b3d3683`.
It records ModelScope model `MiniMax/MiniMax-H3`, observed revision `57559a67`,
and 281 files totaling **498,474,765,023 bytes**. This inventory read hashes only
the manifest, not the weights and does not renew their integrity certification.

The manifest contains self-contained component subtrees:

| Component | Files | Declared bytes |
| --- | ---: | ---: |
| FL2VA | 81 | 144,051,182,625 |
| Ref2VA | 81 | 144,051,182,613 |

The remaining bytes are root-layout weights and auxiliary files. Do not use the
whole-manifest digest with a component-only byte count. A component-only download
needs a separately published canonical manifest with stripped component prefix,
its own computed digest, and explicit registry admission. The full-manifest
alternative downloads about 498 GB and is not a sensible silent migration.

`scripts/prepare-model-component.mbtx SOURCE_MANIFEST COMPONENT NEW_OUTPUT`
now derives that component manifest without copying weights. It retains the
upstream model/revision and per-file hashes, strips only the selected directory
prefix, and refuses to overwrite an existing output. Run its `--self-test` for
component selection, byte accounting and path checks. Derived from the exact
source manifest above on 2026-09-23:

- FL2VA: `sha256:c21d65b05fbc8b8c3906196f8e4495fb086f5d7f90103b4580751f25b8f1c6f6`.
- Ref2VA: `sha256:35943f5f54661a6e244ec6900c90e2d117520fad904fd896f939ab9841e88c6b`.

These are metadata derivations, not new verification of weight contents or
registry admission. Place an admitted manifest at the corresponding component
source root; normal node materialization must still verify each transferred file.

The live model-source Deployment is on management `ubuntu`, mounts host
`/data/models`, and serves port 8090 (`lunanexa-model-source` ClusterIP
`10.43.10.20`). This observation does not establish a direct data-node source.
Spark node agents currently use
`http://127.0.0.1:18080/v1/artifacts`; its loopback proxy targets
`lunanexa-control.lunanexa.svc.cluster.local:8080`, and the controller mounts
`/data/models`. This is a controller-mediated path, not direct S3. Verify actual
assignment-scoped range responses before a real transfer. Existing FL2VA's runtime
mount has no canonical source manifest at its root (depth-two name search).

The functioning H3 image tag is `lunanexa-cache/vllm-omni-h3:20260914`, with
observed running image ID
`sha256:c3cbf972d026ba07223135b1d6b603edb980aa3123c1ead1dc918f057f21f4e3`.
An image ID alone is **not** a verified registry manifest digest; export/publish
the cached OCI image and resolve its manifest digest before creating a pinned
catalog template. Preserve the current `minimaxh3-sm121-patch` and
`minimaxh3-serving-video-patch` ConfigMap changes, plus FL2VA's
`minimaxh3-progress-patch`, in a reviewed derived runtime image or equivalent
immutable configuration. The current runtime applies them before `vllm serve`.

Do not create an enabled template yet: component manifest publication,
registry/license admission evidence, immutable patched OCI digest, actual
artifact source routing, and fresh exclusive resource authorization are still
required. No source hashes, approvals or image digests may be invented to fill
those fields. `scripts/inspect-model-manifest.mbtx` reproduces metadata counts
without reading weight contents.

## Source and local cache preparation

The node materializer supports multi-file models using a `modelstore://<directory>`
artifact URI. The source must expose `lunanexa-source-manifest.json` with:

- `schema_version`: `lunanexa.modelsource.verified.v1`;
- nonempty `model_id` and immutable `observed_revision`;
- `files`: relative `path`, SHA-256 `sha256`, and Int64 `size` for every file.

The assignment artifact digest is the SHA-256 of the exact manifest bytes;
its size is the sum of listed file sizes. Use the established model-source
manifest writer and preserve MoonBit's Int64 JSON representation. Register and
approve that version through the normal license and model workflow.

For the existing FL2VA and Ref2VA directories:

1. Inventory the data-node source and existing Spark copies without stopping
   unknown workloads or changing their files.
2. Produce and verify the canonical manifest at the data source; confirm the
   manifest covers configuration, tokenizer and weight files needed by the
   chosen pinned H3 runtime.
3. Publish the directory through the configured assignment-authenticated model
   source endpoint, including HTTP Range support. `modelstore://` uses that
   endpoint; the URI alone is not evidence of direct S3 transport.
4. Publish an approved template with that manifest digest and byte size.
5. After fresh resource authorization, reserve the complete exclusive node set
   and issue the signed assignment. The node materializer resumes into
   `<cache>/sha256/<manifest-digest>.revision.partial`, verifies every file,
   then atomically publishes `.revision` and its `.revision.ready` marker.
6. The runtime receives the resulting local directory read-only. Do not keep a
   hard-coded raw H3 hostPath in the new delivery adapter.

The old `/var/lib/lunanexa-models/minimaxh3/...` directories are **not** automatic
cache hits. No unchecked symlink or fabricated ready marker should import them.
The current supported path is verified materialization from the data source;
a future offline adoption utility must verify every manifest file before
publishing through the same cache protocol. Avoid downloading a second copy
until disk capacity and migration scope have been confirmed.

## Observable preparation stages

The existing node telemetry route now receives per-node, per-deployment samples
during materialization, not just after a long download completes:

| Metric | Meaning |
| --- | --- |
| `artifact_preparation_stage` | 1 checking, 2 transferring, 3 verified, 4 failed |
| `artifact_cache_hit` | 1 only after successful existing-cache verification; otherwise 0 |
| `artifact_bytes_present` | Completed-file bytes plus current-file bytes, including resumed bytes |
| `artifact_bytes_total` | Signed assignment model size |
| `artifact_transfer_bytes` | Model response-body bytes received during this materialization attempt |

Manifest and detached-signature transfer bytes are excluded from model progress.
Bytes present do not imply integrity verification until stage 3. A verified
cache does not imply inference readiness: require the existing fresh ready
runtime endpoint heartbeat and an actual model response. Stale telemetry must
not advance an operation. These samples contain no local paths or credentials.

Directory cache reuse verifies the manifest digest and listed file sizes, not
every weight byte on every reconciliation. Initial materialization verifies
every file digest. Same-size post-publication corruption needs an explicit
integrity check/rebuild; do not claim it is detected by the fast reuse check.

## Cache lifetime

Node reconciliation retains idle model cache for seven days by default, with
oldest-idle eviction above a 1 TiB cache budget until 768 GiB remains. Configure
`LUNANEXA_MODEL_CACHE_IDLE_MS`, `LUNANEXA_MODEL_CACHE_HIGH_BYTES`, and
`LUNANEXA_MODEL_CACHE_LOW_BYTES` to leave room for system and user volumes.
These are cache-byte budgets, not filesystem-percentage measurements.
`LUNANEXA_MODEL_CACHE_PINNED_DIGESTS` accepts comma-separated full digests.
Assignments, supervisor references and pinned digests are never evicted.
