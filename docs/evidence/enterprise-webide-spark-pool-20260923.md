# Spark pool and enterprise WebIDE acceptance — 2026-09-23

## Scope and actual state

- `192.168.2.176` (`spark-25e2-3d35c8fd`) and `192.168.2.177`
  (`spark-3782-feee26eb`) are the **trial** pool. The existing MiniMax H3 and
  ComfyUI workloads were left running; the public ComfyUI route on port 5005
  remained HTTP 200 during this work. Additional trial apps/models require
  separate readiness and policy checks before being offered.
- `192.168.2.178` (`spark-57f5-98a504ed`) and `192.168.2.179`
  (`spark-368c-0f2ee8b2`) are the **enterprise-dedicated** pool. These
  classifications are stored in `deploy/cluster/cluster.json`, rendered into
  node inventory, and applied as `lunanexa.io/usage-pool` Kubernetes labels.
  All four nodes reported `Ready` with the expected labels at acceptance.
- A GLM-5.3-Flash EXL3 tensor-parallel inference service ran on `.178/.179`.
  LunaNexa exposed `glm-5.3.flash` only to the test tenant via an explicit
  external route and Developer workspace lease. This is a tenant-scoped
  inference acceptance path, **not** evidence of a paid machine order, an
  exclusive-node lease, or a LunaNexa-managed model Deployment.

## Separate account/company and UI path

The test used the existing `CeShi` account (`ceshi@lunanexa.local`) and a new
company, **企业专属云 WebIDE 验收** (`organization-93e05f3067946c079f9327a21926fb85`).
Its Developer workspace grant and lease are limited to one day and to
`glm-5.3.flash`; no platform-operator role or paid order was granted.

In the public enterprise portal (`http://106.39.18.146:5002/enterprise/`):

1. Signed in as the test account and confirmed the selected organization was
   **企业专属云 WebIDE 验收**.
2. Clicked **WebIDE**. The page showed `glm-5.3.flash` as the available model,
   an active Developer lease, and the four-step one-click connection progress.
3. Clicked **打开 MoonDesk / MoonCode** once. The handoff page showed the
   one-time-link, account/lease, MoonGate/model, and Code stages, then opened
   local MoonDesk directly on the Code destination.
4. In a new Code chat, entered: “请只在聊天中回答：写出 Python 函数 square(x)，并告诉我
   square(4) 的结果。不要读写文件。” The Code UI ended with `DONE` and displayed
   `def square(x): return x * x` and `square(4) = 16`. The MoonClaw journal
   recorded `runtime.planner_selected` with model `moongate/glm-5.3.flash`,
   one `finish` tool call, and `runtime.turn_finished`.

## Defects fixed during acceptance

- The deployed admin policy had an outdated default of 16 output units and a
  maximum of 512. MoonGate's streaming bridge omits the caller's output limit,
  so GLM could not finish a Code tool call. The live admin policy now matches
  the source baseline: default 1024 and maximum 131072 output units. A direct
  MoonGate streaming test then produced tool-call deltas and
  `finish_reason: tool_calls`.
- LunaNexa previously emitted `created` as a string in OpenAI-compatible SSE;
  Code expected a number. The control image was updated and rolled out with a
  numeric `created`, with regression coverage.
- On a fresh MoonDesk Code page, the model response could arrive after the
  JavaScript model selector was installed, leaving the selector disabled at
  “No models available.” The selector now synchronizes when the rendered model
  dataset changes. The final fresh-session UI test selected
  `moongate/glm-5.3.flash` and completed the chat.

## Verification and limits

- LunaNexa native MoonBit suite: **1223/1223 passed**; MoonDesk developer-tools
  JavaScript suite: **9/9 passed**; MoonDesk production build completed.
- Before the final isolation change, GLM `/glm53/health` was HTTP 200 and the
  runtime advertised `GLM-5.3-Flash-EXL3`. That old unauthenticated public
  proxy route was then removed from the live `operator-4173-proxy` ConfigMap;
  `/glm53/health` now returns 404. The operator UI and trial ComfyUI route
  remained HTTP 200, and an authenticated `glm-5.3.flash` inference request
  through LunaNexa remained HTTP 200. The model process on `.178/.179` was not
  stopped or restarted.
- The test company's legal identity remains pending external verification.
  The UI correctly reports no exclusive-resource authorization. This test does
  not validate purchase, contract, SSH, paid billing, or fully managed
  exclusive-node provisioning.
- Pool labels and inventory are persistent declarations. Any future Kubernetes
  workload must still select the intended pool explicitly; these labels alone
  do not prevent an arbitrary manifest from targeting another node.
