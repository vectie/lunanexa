# Public HTTP exclusive ComfyUI checkpoint — 2026-09-23

This is a live two-sided UI checkpoint, **not** a successful H3 generation or
full ComfyUI acceptance record. The owner explicitly chose plain HTTP for this
test and confirmed this particular 45-minute Developer grant and exclusive
Spark reservation. No password, session token or model weight is recorded here.

## Buttons pressed and visible feedback

1. On the public Operator site (`http://106.39.18.146:4174/console/`), opened
   **策略**, selected **授予限定范围的访问权限**, filled the typed grant for the existing
   b0cc test user and organization, then pressed **验证并提交**. The page reported
   `grant-access 已完成`. The resulting grant is
   `grant-ui-b0cc-exclusive-20260923`, Developer, effective
   `2026-09-23 01:49:10.946 UTC` through `02:34:10.946 UTC`.
2. In the same form, selected **创建工作区租约** and pressed **验证并提交**.
   The page reported `create-compute-lease 已完成`. Opened **租约** and pressed
   **激活** for `lease-ui-b0cc-exclusive-20260923`; the page reported
   `工作区租约 ... 已激活`. No administrator role was granted.
3. In **租约 → 整机资源交付**, selected the b0cc enterprise organization (not the
   same account's trial organization), selected `spark-25e2-3d35c8fd`, marked
   **确认所选节点无其他任务**, and pressed **预留所选整机**. Prior read-only host and
   Kubernetes inspection had found no business GPU process or running inference
   Pod on that Spark. The Operator page showed **1 台 · Reserved** with the same
   expiry. The recorded reservation ID is
   `reservation-e0d90ec3-9568-4f6f-be64-82c115d88ecb`.
4. On the public Enterprise site (`http://106.39.18.146:5002/enterprise/`),
   the existing test account logged in over the explicitly enabled HTTP origin.
   After **WebIDE** and **刷新状态**, the delivery panel showed the exact b0cc
   resource grant, one node, and the `02:34:10 UTC` expiry. A page reload also
   showed **开发者租约已生效** in the access progress list.
5. Selected **ComfyUI**. The user-facing text correctly said it needs an active
   GPU delivery and that a workspace lease alone does not reserve a machine;
   **打开 ComfyUI** remained disabled. The delivery template selector contained
   only GLM/Qwen PaaS/MaaS entries, not a MiniMax-H3/ComfyUI template. No
   service was started, no video was generated, and download/persistence were
   not tested. Do not count this as a passed ComfyUI trial.

## Exact remaining blocker

The ModelScope UI shows two MiniMax-H3 component imports at 81/81 verified files
each, but both still have license, provenance/integrity, exact-digest evaluation
and explicit approval gates. Opening **登记为候选模型…** confirmed that registry
identity, verified architecture and measured minimum accelerator memory must be
provided; it was cancelled without creating a candidate or asserting evidence.
The approved whole-H3 alias is distinct from those components and is not proof
that FL2VA can be placed and served on this exclusive node. The catalog lacks a
published H3 delivery template and pinned, qualified runtime binding. These
must be completed before real browser generate/download/save/reopen can pass.

## Public HTTP packaging correction

The initial rebuilt Enterprise image had an empty public-HTTP origin meta,
which blocked public password login despite the backend's explicit HTTP mode.
The deployed page was rendered for the exact Enterprise origin and login was
verified in the public browser. A misleading session-strip label calling that
plain HTTP session "secure" was corrected to explicitly say "unencrypted".
The targeted Enterprise JavaScript test suite passed 33/33; the corrected web
image digest `sha256:81fcce01a97a1634410a441b681e6ea8db147244f376f97ec6a4e23ff9619247`
rolled out, and the public UI visibly displayed the corrected label. This
deployment is an owner-approved test transport, not an encrypted production
ingress claim.
