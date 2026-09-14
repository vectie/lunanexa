# Spark preparation cache: offline handoff

This is a download/cache acceptance bundle, not a GPU runtime certification.
The final authoritative receipt is `ready.json` in the preparation directory;
require `download_cache_ready: true` before treating finalization as complete.

## Locations on the data node

- SSH: `HwHiAiUser@106.39.18.146`, port `32123`.
- Content, models, wheels, sources, receipts:
  `/data/models/.spark-preflight-20260914`.
- Docker/OCI import archives on the node's NVMe disk:
  `/home/HwHiAiUser/.cache/lunanexa-spark-exports-20260914`.
- Original H3 HF/Diffusers model remains `/data/models/minimaxh3`.
- Corrupt/incomplete historical downloads are isolated under `quarantine/`;
  never install or register anything from there.

## Image import

Five pinned **linux/arm64** images have separate archives. Each contains OCI
metadata plus a Docker `manifest.json`, and only its required layers/config.
Model weights are **not** packaged in these archives.

| Archive | Imported Docker tag |
| --- | --- |
| `vllm-omni-h3.tar` | `lunanexa-cache/vllm-omni-h3:20260914` |
| `sglang-cu130.tar` | `lunanexa-cache/sglang-cu130:20260914` |
| `cuda-13.0.3-devel.tar` | `lunanexa-cache/cuda-13.0.3-devel:20260914` |
| `ubuntu-24.04.tar` | `lunanexa-cache/ubuntu-24.04:20260914` |
| `dockerfile-frontend.tar` | `lunanexa-cache/dockerfile-frontend:20260914` |

Copy the needed archives and `SHA256SUMS` from the NVMe directory to the Spark.
Verify their transfer before loading. For example, in a directory containing
all five archives:

```sh
sha256sum --check SHA256SUMS
docker load --input ubuntu-24.04.tar
docker load --input cuda-13.0.3-devel.tar
docker load --input vllm-omni-h3.tar
docker load --input sglang-cu130.tar
docker load --input dockerfile-frontend.tar
```

Use explicit tags/digests from `exports/summary.json` and `images/plan.json`;
do not replace them with `latest`. Importing does not start inference or prove
the image supports the arriving Spark driver/kernel. OCI content can also be
consumed from `images/oci-layout`, `images/index.json`, and `images/blobs/`.
The import archives use fully qualified `docker.io/lunanexa-cache/...`
references in their OCI indices. This avoids Docker/containerd accepting a
bare OCI name that is then invisible to ordinary Docker image lookup.

## Python offline installation

Use an ARM64 CPython **3.12** virtual environment. Four separate hash-locked
requirements files live under `wheels/requirements-offline-*.txt`. They are
independent plans; do not combine all four blindly into one environment.
For ComfyUI, after copying the `wheels` directory:

```sh
python3.12 -m venv comfy-venv
comfy-venv/bin/python -m pip install --no-index --require-hashes \
  --find-links ./wheels/comfy-requirements \
  --find-links ./wheels/torch-cu130 \
  -r ./wheels/requirements-offline-comfy-requirements.txt
comfy-venv/bin/python -m pip check
```

This lock retains `torch==2.14.0+cu130`, `torchvision==0.29.0+cu130`, and
`torchaudio==2.11.0+cu130`. It does not qualify SM121 kernels. The existing
cross-platform dry-run uses glibc tags through 2.39; actual installation must
still match the Spark's OS/ABI. CPU-only workspace images are a separate build.

General network package downloads use USTC first and TUNA second. Docker Hub
downloads use DaoCloud with original digest checks. New model weights come
from ModelScope.cn, not from the images or Python wheels.

## Verification and limits

- `images/summary.json`: all referenced manifest/config/layer SHA-256 checks.
- `model-final-verification.json`: original publisher-pinned SHA-256 receipts
  matched against current file size, modification/change times; files lacking
  an unchanged timestamp proof are freshly rehashed. This is not a claim that
  every model was reread during finalization.
- `wheel-final-verification.json`: wheel ZIP integrity checks.
- `locked-offline-wheel-verification.json`: no-index, hash-enforced dependency
  resolution for ARM64 CPython 3.12; not a live Spark install.
- `source-final-verification.json` and `source-tree-verification.json`: pinned
  source archive integrity and clean Git object/tree checks. Receipt hashes
  for source downloads record local integrity, not publisher signatures.
- `exports/summary.json`, `archive-full-verification.json`, and
  `import-smoke.json`: archive verification and the bounded import smoke test.

Remaining hardware checks: DGX OS/driver, SM121 kernels, memory headroom,
actual model loading/generation, and two-Spark network/NCCL operation. Do not
replace those with simulated evidence or mark a production release qualified.

The task-specific Mac relay/tunnel is no longer needed. The preparation
heartbeat is paused to avoid restarting obsolete download jobs.

## Operator revalidation

`finalize-cache.mbtx` is a dated, machine-specific operator tool for the Mac
and data-node paths above. In the LunaNexa repository it is preserved as
`scripts/finalize-spark-cache-20260914.mbtx`. Run phases sequentially, with
downloaders stopped; do not rewrite an archive while another process validates
or imports it. Mutating/revalidation phases invalidate `ready.json` first;
run the final `ready` gate again after all required evidence is current.

The `selftest` phase checks quoting, malformed descriptors/missing fields, and
rejection of an intentionally mismatched hash. `model-receipts` reuses unchanged
download checks; `models` is the optional much slower full-model reread.
Do not use `archive` unless you intentionally want an additional combined OCI
tar; the five per-image exports are already sufficient for this handoff.
