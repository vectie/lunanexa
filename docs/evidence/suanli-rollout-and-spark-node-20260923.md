# 2026-09-23: three-site rollout and Spark node recovery

## Deployment verified

- `https://suanli.kechuangfuwu.com/mana/`, `/user/`, and `/docs/` each returned HTTP 200 from the management node with TLS verification result 0. The served HTML declares `zh-CN`; the docs fallback action is `问指南`.
- The management, enterprise, and identity gateway Deployments rolled out successfully. The docs gateway was updated to `moon/coursebook@sha256:12e3b179b01ee2d4a092ffc99a5a2745facb991194be1dd3aa20fc0ea572b143`.
- This is an origin-side check, not an independent WAN-browser acceptance. The user confirmed the public site is reachable and can log in to `/mana`; our in-app browser's HTTPS tunnel could not reach that host during this run. The older HTTP 4174 operator console remained available for UI verification.

## Spark `57f5` recovery

The fourth row of the operator node table is `spark-57f5-98a504ed` (`192.168.2.178`), while the fourth physical Spark is `spark-368c-0f2ee8b2` (`192.168.2.179`). Kubernetes reported both Ready; only the former's LunaNexa heartbeat was stale. Its node-agent process repeatedly failed cleanup of an already-absent runtime, so reconciliation stopped before heartbeat and telemetry publication.

The live node-agent Deployment had an explicit projected-token audience `https://kubernetes.default.svc`. The k3s API returned 401 for that token even before its expiry. Omitting the audience yielded the cluster default (`https://kubernetes.default.svc.cluster.local`, `k3s`); the same API request then returned the expected 404 for the missing runtime resource. The repository's node-agent template already omits this field and now documents why. The three affected live Deployments were converged to that template behavior.

The old online node image also preceded the durable missing-resource cleanup fix. The current native agent was built on an arm64 Spark and published as `lunanexa/node@sha256:85a5464f0f3c6de6a5757a8bf65284a2f446e31c55f74ea1ace3c58df134e48d`; all four node-agent Deployments rolled out to this digest. The stale runtime journal cleared without manually deleting its record. The operator UI then showed **4/4 active nodes**, no unresolved alerts, and fresh unified-memory and GPU samples for `57f5`. Temporary diagnostic Pods were removed.

## One-click model-service smoke

From the operator UI, `Qwen3-0.6B Spark text smoke · v1` was selected, service `qwen3-06b-oneclick-20260923-r2` was submitted, and the UI reported a durable coordinating operation. Placement selected `spark-368c-0f2ee8b2`; the artifact reached the node and a Kubernetes runtime Pod was created. That Pod failed with `exec /opt/lunaflux/supervisor/lunaflux-supervisor: exec format error`. Registry inspection confirmed that the pinned LunaFlux image digest `sha256:bec873094c71e35bdba5497f8ef42845318ff6af5e8bedc873d89a7558aaecbb` declares `linux/amd64`, as do the other three LunaFlux image digests in this repository. The Spark is arm64. The test operation was explicitly rolled back in the UI; it must not be counted as a successful serving or PaaS launch. A real arm64 LunaFlux release, registry qualification, and new immutable template version are still required before this button can pass end-to-end.

## Local validation

- `moon info && moon fmt`
- `moon test`: 122/122 wasm and 1096/1096 native passed.
- Docs Node.js tests: 35/35 passed.
- `git diff --check` passed.
