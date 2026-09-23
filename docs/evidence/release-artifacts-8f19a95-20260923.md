# Staged release artifacts — 8f19a95

Build/publish evidence only; no live rollout or resource grant was performed.

Source is clean `git archive` of
`8f19a957f0eb1016f082408feb70dfc3a03c4def`, archive SHA-256
`a0c393194c64c48b45eeb71c8602d93586f5c675b2b6a26e857cea90626ae9ac`.
MoonLeaf dependency remains clean archive
`066efc2f4d8f4acdb2e13aec2a7cd9103fb028db` from the previous receipt.
Existing `.mooncakes` dependency caches were reused; no uncommitted source was
included. New directories are management `/home/HwHiAiUser/release-8f19a95`
and Spark .176 `/home/wlc001s/release-8f19a95`.

Registry prefix: `lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/`.

| Component | Repository | Verified manifest SHA-256 |
| --- | --- | --- |
| Web, amd64 | `moon/lunanexa-web` | `17a13c86cddd8316493d5c49aa834557efc5bc1ce5d8edd77bbefa44f5a44fcf` |
| Gateway, amd64 | `acceptance/webide-runtime` | `0222e747b120a4a6067dd08c6864fbc783815e043f411bb88c914e0edd34f568` |
| Node, arm64 | `lunanexa/node` | `11e2bc59289412f01bc7711262f25867cf2daecb3028b2769894282150522287` |
| Controller, amd64 | `moon/lunanexa-control` | `861127562aa3d01d5f0e96fc198bfcf3ba0efba8cbf80727d29c88833f752a29` |
| WebIDE model proxy, arm64 | `acceptance/webide-model-proxy` | `3f24dd1ad7caad14b5adf9294ef889453845971c2742d4cf63cba63bdf94e02e` |
| GPU browser terminal, arm64 | `acceptance/gpu-terminal` | `aae41c0b6c7d63b5ed7d03b2043fbb9707fb72f9430167d22b66b1b314b219f6` |
| ComfyUI workspace, arm64 | `acceptance/comfyui-workspace` | `489212562530724c6699f312577e9777bc800fd271556c7b5d08f07b8245a59e` |

The first three images returned TLS-verified registry HEAD HTTP 200 with matching
`docker-content-digest`. The controller and ARM model proxy were independently
read back with `crane digest` over the same verified registry TLS connection;
the GPU terminal and ARM ComfyUI were verified the same way.
Their immutable output archives are under
`/home/HwHiAiUser/offline-production-build.TT3wLN/`, named
`web-8f19a95.oci.tar`, `webide-8f19a95.oci.tar`, and
`node-8f19a95-arm64.oci.tar`; the new controller OCI archive is
`/home/HwHiAiUser/release-8f19a95/control-image.oci.tar` and the ARM proxy
layout is `/home/HwHiAiUser/release-8f19a95/model-proxy-arm64`.
Previous archives were preserved.

Native node compilation completed 92 build tasks. Binary SHA-256:
`d38d655be07dc7d572f82ae69d7557f408a15b9697f66a98701f90302af7b7d6`.
Gateway amd64 binary SHA-256:
`d9185912dcd3199013b8984e8b5aff1eca1aa062a8f9720bbe3877f7672356b5`.

Browser build completed 48 tasks; source/bundle/HTML and OFL font checks passed.
An existing installer-ui unused-import warning remains. Dist is
`/home/HwHiAiUser/release-8f19a95/browser-dist`. Public origins were rendered
through the existing committed tool to Operator `http://106.39.18.146:4174`
and Enterprise `http://106.39.18.146:5002`; operator-open is restricted to the
same explicit Operator origin, not a wildcard. The full dist replaces the
static image directory via the existing opaque-whiteout packager; no stale
private fonts or old bundles are inherited into that directory.

Controller compilation completed from the staged source. Its binary SHA-256 is
`7125bf10c870d2eb7e8a442a655d4c8856fd8eb8d45b150970c9ef4fa6e82696`.
The controller image was packaged from that binary and the staged contract
assets, then published and read back from the registry.

The ARM model proxy was compiled on Spark .176 from the same staged source.
Its binary SHA-256 is
`f61c11f91ea09b045ba85153ae0ee5c5132dc532e782220bea310086c2e74244`.
The image config reports `linux/arm64` and the proxy entrypoint. A native
initializer smoke test produced nonempty `comfy.settings.json` and
`LunaNexa Video.json` files in a temporary directory; that directory was
removed after inspection. This is not yet a workspace or browser acceptance.

The GPU terminal image uses the ARM64 CUDA 13.0.1 base manifest
`sha256:351f28235bee49fbfd8eb97819e8e24934ca33b369edc9656c6d5668bc64ed6c`,
independently resolved identically through 1ms, DaoCloud, and NGC. The ttyd
1.7.7 ARM executable SHA-256 is
`b38acadd89d1d396a0f5649aa52c539edbad07f4bc7348b27b4f4b7219dd4165`.
The published config reports `linux/arm64` and the ttyd entrypoint. No live
terminal pod has been started from this image yet. The same SHA-checked static
ARM binary executed on Spark .176 and printed `ttyd version 1.7.7-40e79c7`.

## ARM ComfyUI workspace

The source is ComfyUI commit `e80c1570b6b44a2557d5d8e341e05782d18c9bbb`
and the clean `apps/ComfyUI-vLLM-Omni` subtree at commit
`0d339e25755f067d2f6981ffa7ac998127612163`. The subtree archive SHA-256
is `931ed87bd3e4c923d837844400b86095bd4884aae2e5f2db070b1417707c7d21`.
The included `video_transport.py` SHA-256 is
`b2e10c5c7402ac1fa453c6db28c9c9cf32321d687ef223bf4394deec411367b1`.
No model weight is in the package.

The pinned Python 3.12 ARM base is
`sha256:eb5be8e5b4d0a159c237946bbdd06356dda5d19c30fc4f7843e8046d3a590333`.
USTC returned an empty `comfy-angle` wheel and pip rejected the SHA mismatch.
Tsinghua supplied the remaining 84 wheels; the compatible PyTorch CPU trio
`torch 2.11.0+cpu`, `torchvision 0.26.0+cpu`, `torchaudio 2.11.0+cpu` came
from the official PyTorch CPU index. The 87-wheel set installed into an
isolated build directory. The frontend 1.51.9 output-list patch verified its
original SHA and emitted the reviewed SHA
`a413a8e373f569276609be5eea3b905dc1415fbac07835099b2f03ed17829660`.

The image's 846,021,121-byte compressed layer was transferred to Spark .176
for native import smoke with its SHA-256 intact. ComfyUI 0.34.0 started on a
temporary loopback port with CPU PyTorch 2.11.0, PyAV 18.1 and the whitelisted
plugin. HTTP `/object_info` returned
`VLLMOmniGenerateVideo`, `VLLMOmniDiffusionSampling`, and core `SaveVideo`.
`MarkdownNote` is a frontend-only node present in the pinned frontend JS;
it does not appear in backend `/object_info`. This was an import/readiness
smoke, not a model generation or browser persistence acceptance.

The staged 8f19a95 artifacts predate the
current workspace/model service changes; rebuild all changed components from
the next complete commit before live rollout.
