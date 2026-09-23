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
each. Read-only import inventory identifies `ms-4b61ebb895fe7f9f161ae418` as
FL2VA, with manifest digest
`sha256:0964a2d8823de7d0a40d3cfa01acd1aa08c3aec632b9b6c25330a158bbe98e73`;
`ms-3a45d5defabb0df653382579` is Ref2VA, not the text-to-video target.
The recorded manifest digest matches the FL2VA source file on management.

After the owner's specific license confirmation, Operator **登记为候选模型…**
created `minimax-h3-fl2va / modelscope-57559a67` with `nvidia-sm121` and a
100,000 MiB placement floor informed by the previous FL2VA Spark memory
observation. **接受许可证** recorded MiniMax H3 Community License against this
exact version and the SHA-256 of the source `LICENSE` file; **验证制品** changed
the row to **已验证** and displayed the exact FL2VA manifest digest. These are
real registry transitions, not a runtime evaluation or deployment approval.
The license itself excludes the EU, UK, Republic of Korea and United States
from its applicable territory and has hosted-service terms; a broad public
launch needs its own distribution/access review.

The reviewed ARM64 code-only H3 runtime image already exists in the internal
registry at manifest digest
`sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c`.
Operator **注册运行时** recorded it as a video-capable `nvidia-sm121` runtime.
The UI explicitly says image-digest verification is still needed before any
deployment. A **记录验证** request for the exact OCI manifest was rejected by the
typed API; no verification receipt was created. The internal registry has the
image, but its manifest presence is not a Cosign signature. No evaluation is
recorded, no FL2VA alias is promoted, and no H3 delivery template is published.
The approved whole-H3 alias is distinct from the FL2VA component and cannot
substitute for these gates. Real browser generate/download/save/reopen therefore
remains blocked.

## Template-type defect found and corrected in source

The live delivery-options API offered every text model template twice: once as
`ModelApi` and once as `Workspace` with `client_id=comfyui`. Selecting the latter
would present a text model as a ComfyUI video workspace. The source now lists
only `VideoGenerate` templates for the current ComfyUI Workspace profile and
rejects a crafted Workspace start using a text template; text `ModelApi`
remains available. This controller change is **not yet rolled out** in this
checkpoint. The native API suite passed 175/175 and the complete native suite
passed 1212/1212 with warnings denied. No claim is made that the current public
template selector has already changed.

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
