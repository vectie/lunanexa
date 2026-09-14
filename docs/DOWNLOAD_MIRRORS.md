# Dependency download mirrors

General Python downloads prefer USTC:
`https://mirrors.ustc.edu.cn/pypi/simple`.
The secondary mirror is TUNA:
`https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple`.
Retry sequentially; `extra-index-url` is not a strict priority list.

`images/Containerfile.comfyui-workspace` defaults its general-package pip index
to USTC. Override the `PIP_INDEX_URL` build argument with TUNA when retrying a
failed build. The separate CPU PyTorch index remains necessary to preserve the
CPU wheel variant. Never replace CPU or CUDA-specific artifacts with arbitrary
PyPI candidates just to make a download succeed.

`images/Containerfile.python-mirror` applies the same default to an already-built
Python image without reinstalling any packages. Supply an inspected immutable
base image. The new image needs its own digest and rollout; changing the recipe
does not mutate an existing image or a running production pod.

Docker images and Docker engine installation packages are different services.
As checked on 2026-09-14, [USTC's registry cache is suspended](https://mirrors.ustc.edu.cn/help/dockerhub.html),
while [TUNA's docker-ce mirror is not Docker Hub](https://mirrors.tuna.tsinghua.edu.cn/help/docker-ce/).
Do not populate daemon registry-mirrors with these unavailable/inapplicable
endpoints. Existing digest-pinned private/local caches remain authoritative.
Selecting another public registry requires a separately verified source.

No model weights belong in these images. Registered model artifacts continue to
use the configured artifact transfer path; new preparation downloads use
ModelScope.cn as requested.

## Verification on 2026-09-14

The Mac user and data-node user pip configurations now default to USTC.
Separate real wheel-download probes succeeded against both USTC and TUNA on
the data node. The remaining `comfy-tools` and `comfy-requirements` ARM64 wheel
plans completed against USTC, retaining the cached CUDA 13.0 PyTorch pins.
The preparation runner performs sequential fallback and publishes receipts at
`/data/models/.spark-preflight-20260914/wheels/mirror-summary.json`.

The local ComfyUI mirror-overlay image builds successfully and exposes the
expected pip configuration. Actual pip download probes inside the dedicated
Colima Docker environment did not pass: USTC reported a connection timeout,
and the TUNA fallback also failed to resolve a package. This is not evidence
that the package is absent from either mirror. Container egress still needs
qualification; no production daemon configuration or running pod was changed.
