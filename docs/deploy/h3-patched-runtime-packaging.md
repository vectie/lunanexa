# Package the existing H3 ARM64 compatibility runtime

`scripts/package-h3-runtime.mbtx` adds a small reviewed Python-source layer to
the existing ARM64 OCI export. It does not run inference, read model weights,
publish an image, or change the live cluster. It preserves the base image's
Entrypoint, Cmd, User, environment and working directory.

## Verified base

Management-node archive:
`/home/HwHiAiUser/.cache/lunanexa-spark-exports-20260914/vllm-omni-h3.tar`

Expected image manifest:
`sha256:474d635dc5dc2cf66f0df692ddef19967a920253826f431689af2b0e010afc4e`

This manifest was independently hashed from the archive. Its config digest
`c3cbf972d026ba07223135b1d6b603edb980aa3123c1ead1dc918f057f21f4e3`
matches the live H3 image IDs. The base is 10,826,014,720 archive bytes, not a
weight package. Its mutable image tag is not the final patched-image identity.

## Prepare exactly four reviewed code files

The bounded read-only collector is available as:

```sh
moon run scripts/capture-h3-runtime-patches.mbtx KUBECONFIG NEW_PATCH_DIRECTORY
```

It reads three named ConfigMaps and one explicit runtime source path. It does
not inspect secrets or change workloads. Compile the four source files without
imports before packaging; keep any `py_compile` cache outside the patch directory.

Use a new, deployment-owned patch directory containing only these files:

| File | Existing source | Final destination under `/usr/local/lib/python3.12/dist-packages/` |
| --- | --- | --- |
| `minimax_h3_transformer.py` | ConfigMap `minimaxh3-sm121-patch` | `vllm_omni/diffusion/models/minimax_h3/minimax_h3_transformer.py` |
| `serving_video.py` | ConfigMap `minimaxh3-serving-video-patch` | `vllm_omni/entrypoints/openai/serving_video.py` |
| `progress_bar.py` | ConfigMap `minimaxh3-progress-patch` | `vllm_omni/diffusion/models/progress_bar.py` |
| `api_server.py` | The patched source file in the running FL2VA pod, or the exact base file after applying the existing reviewed `patch-api-server-progress.py` | `vllm_omni/entrypoints/openai/api_server.py` |

All ConfigMaps are in namespace `lunanexa`. Read only these explicit code files;
do not export a running container filesystem or collect environment variables,
credentials, model directories, home directories or Python caches. Review the
API server file for `_live_video_progress` and its 80-percent in-progress cap;
100 must remain reserved for completed output. The packaging script does not
execute Python source. A code review and runtime test remain necessary.

The API-server patch is included as its already-patched source because leaving
the old startup patch command would require changing the preserved Entrypoint.
The deployed adapter should directly invoke the pinned runtime with its approved
arguments, without the old ConfigMap copy/patch shell prefix.

## Build, inspect, then publish

Run on the management build host with the explicit reviewed patch directory and
a new output path (example paths below must be prepared first):

```sh
moon run scripts/package-h3-runtime.mbtx \
  /home/HwHiAiUser/.cache/lunanexa-spark-exports-20260914/vllm-omni-h3.tar \
  sha256:474d635dc5dc2cf66f0df692ddef19967a920253826f431689af2b0e010afc4e \
  /home/HwHiAiUser/h3-reviewed-patches \
  /home/HwHiAiUser/h3-patched-output \
  lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/moon/h3-runtime:reviewed
```

Outputs:

- `<output>.oci.tar`: base blobs plus one code-only patch layer;
- `<output>/package-receipt.json`: base manifest, final manifest and each patch hash;
- `<output>/patch-layer.tar`: inspectable thin layer, no weights or secrets.

The final manifest digest is computed, never hard-coded. Publish that archive
through the existing containerd/registry deployment workflow and use its exact
digest in the runtime catalog. Do not confuse the base digest or config ID with
the final image manifest. Do not overwrite either running H3 Deployment until
its resource owner has coordinated the migration. Packaging alone does not
prove compatibility, readiness or successful generation.

## Local fixture

```sh
moon run scripts/test-package-h3-runtime.mbtx
```

The small ARM64 fixture builds twice and verifies identical final manifests,
preserved runtime configuration, exactly one added layer, expected code paths,
absence of weight filenames and rejection of an unexpected input file. Temporary
fixture directories are removed afterward. This does not replace physical
Spark inference acceptance. Repeatability is measured on the same packaging
host/toolchain; different tar implementations are not claimed byte-identical.

## Management-host packaging evidence, 2026-09-23

Dedicated output: `/home/HwHiAiUser/h3-runtime-package.xlJNr5/output.oci.tar`.
Receipt: `/home/HwHiAiUser/h3-runtime-package.xlJNr5/output/package-receipt.json`.
Final image manifest:
`sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`.

Exactly four source files (225,277 bytes total) were captured. All passed
`python3 -m py_compile` without executing their imports. Review confirmed the
SM121 native CUDA FP8 activation quantizer binding, segment-wise SDPA fallback,
MP4 encoding offloaded from the API event loop, and bounded denoising progress.
The existing base archive was preserved. No H3 Deployment was changed and no
new inference or model transfer was started. This is packaging evidence only;
the derived image still requires physical runtime acceptance before rollout.

The archive was imported with `--no-unpack --platform linux/arm64` and pushed
to the existing internal registry. Push completed in 82.3 seconds (10.1 GiB,
approximately 125.4 MiB/s). A subsequent TLS-verified registry HEAD returned
HTTP 200 and the exact `docker-content-digest` above at
`moon/h3-runtime:20260923-patched`. Deploy using:

```text
lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/moon/h3-runtime@sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c
```

This registry check does not imply any running H3 service was upgraded.
