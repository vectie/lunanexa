# Model registration and Spark runtime check — 2026-09-23 CST

The Operator at `http://106.39.18.146:4174/console/` was refreshed after the
registration changes. It shows 22 approved model records and no pending import
queue. All 20 verified ModelScope imports have matching approved registry
records. The registry contains 24 records in total: 22 Approved, zero Candidate,
and two older Qwen3-0.6B `nvidia-sm120` qualification revisions left Verified;
those two historical revisions were not promoted for the `nvidia-sm121` Spark
fleet.

The newly adopted revisions are:

| Revision | Registry state | Runtime evidence |
| --- | --- | --- |
| `minimax-h3-fl2va@modelscope-57559a67` | Approved | Spark 25e2, `/h3/v1/models` HTTP 200; real `/h3/v1/videos/sync` returned a valid MP4 (221,393 bytes). |
| `minimax-h3-ref2va@modelscope-57559a67` | Approved | Spark 3782, `/h3r/v1/models` HTTP 200; real video/audio reference request returned a valid MP4 (497,161 bytes). |
| `comfy-org-z-image-turbo@modelscope-master` | Approved | Spark 57f5, CUDA ComfyUI internal canary `1/1` Ready. Official-style BF16 workflow returned a 512×512 PNG (239,399 bytes; SHA-256 `0d162690cec94cb5915741ffdf9ebef70baa1a9bce866dfcc8a3ecaa06552769`). |

The Qwen3-0.6B and MiniCPM5-1B ModelScope candidates had old artifact URIs
that omitted the `models/` directory. Their existing manifest hashes were
rechecked against the on-disk manifests, the URI and signature reference were
corrected, managed-revision verification succeeded, and both were approved.

Z-Image's 40.67 GB verified model tree was copied from the data node to the
Spark 57f5 local disk and all 12 manifest-listed files passed SHA-256 checks.
The runtime mounts it read-only. Its workspace is separate, writable, and
persistent at `/home/wlc003s/workspaces/comfyui-z-image-internal`; the PNG was
verified again after a pod replacement. The Spark service is ClusterIP-only:
it is **not** yet a customer WebIDE session, a MaaS alias, or a public
ComfyUI route. The customer gateway remains unchanged. Registry approval
likewise does not imply that all 20 models have dedicated serving instances;
the fleet cannot run all of them at once.

The GPU packaging script now preserves the CUDA PyTorch base instead of copying
the CPU wheel and configures the base's Python module path and writable ComfyUI
directories. `moon check --target native --deny-warn` and
`moon test --target native --deny-warn` passed (1,215/1,215 tests).
