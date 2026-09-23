# Release image receipts — abd980b

Image build and registry-readback evidence only. Live rollout and application
acceptance are tracked separately.

The final browser bundle was built from clean `git archive`
`abd980b5da54a5166d3e779c708c722cd2de0ea0`, archive SHA-256
`9d8b4243b36f75bc632aa0f316a05494caebd7976d5b67dd449cd4c0fdd645b4`.
Native service binaries were compiled from clean `git archive`
`22321f28847637b9b3c5d72c78dfa5a033cba1f2`, archive SHA-256
`1b89bf4309161b22e9d41cd0a458a1531f4e9366cfd1bdfcfa3123cd7a4ee01d`.
`git diff --name-only 22321f2..abd980b` contains only
`docs/deploy/exclusive-public-route.md`,
`scripts/prepare-exclusive-comfyui.mbtx`, `ui/console.mbt`, and
`ui/console_test.mbt`; no native runtime source changed. The browser image
uses the final UI copy. Both archives were SHA-checked after transfer to the
management node; the native archive was also checked on Spark `.176`.

Registry prefix:
`lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/`.
Each digest below was independently returned by `crane digest` after push.

| Component | Immutable reference |
| --- | --- |
| Browser/console, amd64 | `moon/lunanexa-web@sha256:aef4a2e7e351aee5c9a94b0b354075d992212abe47f0d905bf754e0260c78a3e` |
| Controller, amd64 | `moon/lunanexa-control@sha256:a783785c5f84a3a4eee7bb43d8f0939df47bc60924b8242058c30a8a8f142cf7` |
| WebIDE gateway, amd64 | `acceptance/webide-runtime@sha256:3979a3ca5dd426fd3516c1aa4d75aef64b5e4b942dcf4f97611482828b8fb515` |
| Model-source adapter, amd64 | `moon/lunanexa-model-source@sha256:58c467d69743092ce9b325d08fec48734df049c2a3e0957f10f1b47a0f7c9e74` |
| Node, arm64 | `lunanexa/node@sha256:46f7fcd2bab407806736d5ec33df31834e7028bdad403c5a811e84ae278a47cb` |
| WebIDE model proxy, arm64 | `acceptance/webide-model-proxy@sha256:e057e8fad540076aba6a2a06707c5cd568c61dd64d6233243a56fba944a75e14` |

Binary SHA-256 values, respectively: controller
`26569a89d065111e2d13bc3ee9b8dac3312b877d760ae129895bff8903517569`,
gateway `a372b94e6fddea9ef4b966d513e6a019f57cb823cfef23f0b0aff8d60768ebaf`,
model-source `ae23cd658c1f5459f6c9ab9351caa1623e47735863bd5e0cd19c376eccfbb210`,
node `22b83fd4f18fbb1acc6f7a264f7c4b4346a0570cb7d193af148cabd4d2606436`,
and model proxy `93d6f72ef02997555e70cec4f4994b953a13b3463d43df74c364e9a671567eba`.

The browser bundle verification passed for console, enterprise, workbench and
installer. The public HTTP origin was rendered to the exact Operator `:4174`
and Enterprise `:5002` origins; operator-open was restricted to exact `:4174`.
The open Noto Sans SC font SHA-256 matched
`c7763f454946833081cc90e73186615f8e1189de9c5e5a5a8752871fd79fddbc`.

The following immutable **runtime-only dependencies** were built and verified
earlier, independently of LunaNexa source. They were not reuploaded solely
for the final commit:

| Runtime dependency | Immutable reference |
| --- | --- |
| ARM ComfyUI workspace | `acceptance/comfyui-workspace@sha256:489212562530724c6699f312577e9777bc800fd271556c7b5d08f07b8245a59e` |
| ARM GPU browser terminal | `acceptance/gpu-terminal@sha256:aae41c0b6c7d63b5ed7d03b2043fbb9707fb72f9430167d22b66b1b314b219f6` |

The ComfyUI image contains pinned ComfyUI
`e80c1570b6b44a2557d5d8e341e05782d18c9bbb` and the
ComfyUI-vLLM-Omni plugin from clean commit
`0d339e25755f067d2f6981ffa7ac998127612163`, including the idempotent
video POST/poll transport. Native ARM import smoke returned
`VLLMOmniGenerateVideo`, `VLLMOmniDiffusionSampling`, and `SaveVideo` from
`/object_info`; `MarkdownNote` is supplied by the pinned frontend. No model
weights are packaged. The loopback smoke process and scoped temporary test
directories were confirmed gone afterward. The GPU terminal used pinned ttyd
1.7.7 ARM and passed native `ttyd version` smoke. Neither image's previous
smoke is a claim of live workspace, model-generation, or browser acceptance.
