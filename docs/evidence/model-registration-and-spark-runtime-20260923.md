# Model registration and Spark runtime check — 2026-09-23 CST

The Operator at `http://106.39.18.146:4174/console/` was refreshed after the
registration changes and console-only rollout. It shows 22 approved model
records and no "register as candidate" buttons for completed imports. All 20
verified ModelScope imports have matching approved registry
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
Their older import records still contain the pre-migration URI; the console
now canonicalizes that exact legacy prefix when matching by immutable manifest
digest, rather than misleadingly offering a second registration. The public
console JavaScript SHA-256 is
`b7c3f42f5bc6dd666f707adedbd07235580e06cff71e3a80c6e59a345bb61f45`,
served from image manifest
`sha256:c8f8da15b10310ef45fecb57de0750509737be2b145d862aff131d11da2c47ac`.
The prior console deployment was saved privately on the management node before
rollout. The public and LAN Operator auto-entry origin settings were retained.

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
`moon test --target native --deny-warn` passed (1,215/1,215 tests); the
focused console JS suite passed (92/92 tests).
