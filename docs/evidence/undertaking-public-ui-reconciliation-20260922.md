# Public UI undertaking reconciliation — in progress

Latest checkpoint: the user completed test-account registration successfully.
An ordinary trial session is now available. Company onboarding, not password
entry, is the current acceptance blocker; the nine-step chain is not complete.

Scope: enterprise `http://106.39.18.146:5002/enterprise/` and Operator
`http://106.39.18.146:4174/console/`. Business actions and acceptance use the
browser UI only. The owner subsequently clarified that source fixes, tests and
deployment may use development tools. No backend calls substitute for the
customer journey. Offline commercial evidence may be technically waived, but
must never be described as real signed contracts, payment or invoices.

## UI action log

| Action | Observed feedback | Mutation |
|---|---|---|
| Open public Operator | Automatic entry, then live dashboard | None |
| Open public enterprise | Separate customer sign-in, not inherited Operator access | None |
| Click `Register a new account` | Email, display name, password and `Create account` appear; password requirements visible | Local form only |
| Enter test email and display name | Screenshot confirms email remains after focusing display name; name marks non-real test customer | Local form only |
| Inspect `Create account` | Disabled while password is empty; registration not submitted | None |
| Operator: click `线下商务` | Existing sample `technical-acceptance-ofl-order-20260922` shows `PendingInternalApproval`, generation 6 | None |
| Operator: click `合同资料` | Existing `technical-acceptance-ofl-packet-20260922` shows DOCX/PDF generated; preview updates then confirms synchronized, four physical pages | None |
| Operator: click `租约` | Initially false zero/empty state, then 17 active workspace leases; no exclusive machine leases | None |

The existing order and packet are historical technical samples, not a newly
completed customer workflow. No old lease was activated, cancelled or revoked.
No agreement, signature, payment, upload or permission grant was submitted.

## Findings and fixes

1. **Confirmed:** deferred page reads displayed empty records while loading and
   silently retained empty states after failure. Added explicit loading/failure
   projections with retry; hide dependent content until the read succeeds.
2. **Confirmed:** fulfillment policy requirements were displayed with checkmarks,
   implying completion. Changed to requirement bullets and an explicit note
   distinguishing requirements from evidence review and actual order status.
3. **Confirmed:** order expiry displayed raw milliseconds. Render a readable
   timestamp with explicit UTC offset; missing/invalid values are identified.
4. **Confirmed:** every node displayed `Placement model / One lease · one
   machine`, wrongly presenting the exclusive-machine contract as a universal
   model-placement policy. Removed the unsupported node fact; lease page copy
   distinguishes exclusive machine access from workspace capacity.
5. **Unconfirmed:** packet inbox shows no pending approval while the associated
   offline sample is pending internal approval. These may be different workflow
   authorities; a new correlated end-to-end run is required before calling this
   a defect or changing state transitions.
6. **Retracted:** an earlier text/DOM-tool observation suggested the email was
   cleared. Actual screenshots show the email present and retained on blur.
   This is not evidence of a broken registration field. No speculative form
   patch was made for it.

## Nine-step acceptance matrix

| Required step | Evidence / status |
|---|---|
| Register customer company | Not reached; ordinary test account registration not submitted |
| Select start time and term | Not reached for a new order |
| Generate undertaking | Existing sample preview only, not new-order acceptance |
| Manager confirms and executes | Not tested |
| Offline process technical waiver | Owner authorization exists; no new-order waiver applied |
| Reupload/register | Not tested |
| Provision access | Not tested |
| Customer receives permissions | Not tested |
| Launch IaaS/PaaS/MaaS | Not tested for the new customer |

## Local regression verification

- Targeted JS suites: 209 passed, 0 failed (console, enterprise, UI and offline
  commerce).
- Native suite: 1,142 passed, 0 failed; native warning-denying check passed.
- Generated interface adds explicit page-read state; existing telemetry change
  retains fractional power readings. No business admission rules were weakened.
- Fresh browser output required: the existing output contained private-font
  leftovers and the build correctly refused it. Used a new temporary directory
  rather than deleting unrelated files or disabling the font guard.

These tests do not establish completion of the nine-step public UI journey.

## Deployment and public browser verification

- Console and enterprise deployments rolled out image
  `sha256:85a5f52e48e2a262c2a7ff5990333a8f4e78102c567a89f01a92737da6821489`.
  Workbench, controller and GPU workloads were not changed.
- Public Operator: clicked `租约`, observed `正在加载此页面的数据…`
  instead of zero/empty records, then 0 exclusive machines and 17 active
  workspace leases after loading.
- Clicked `线下商务`: the sample still shows internal approval pending;
  expiry is now `2026-09-23T10:20:00Z`, with `履约要求` and bullets rather
  than misleading completion checkmarks. No approval or generation performed.
- Clicked `节点` then the first `查看详情`: live Spark telemetry remains;
  the unsupported placement-policy fact is absent.
- Found and fixed deployment drift: port 5002 served `/srv/portal/enterprise`
  from an old static directory even after updating the enterprise deployment.
  `route-enterprise-browser-service.mbtx` privately backs up the ConfigMap,
  changes only enterprise HTML/JS routes to the enterprise service, verifies
  mounted configuration propagation, syntax-checks and gracefully reloads nginx.
  Caller Authorization forwarding and `/auth/` remain unchanged; other assets
  retain their existing route. No authentication bypass was added.
- Independent public browser page confirmed enterprise script version
  `6ee0b8101962975f118bf8c7d3ab71146b37827aca2140a63ec7bb2213aa6055`,
  matching the local build. Operator version is
  `70e967313254f1ed1b32bf2c607db7beab570f6e149c11a43eb675276eb44207`.
- The temporary image-builder pod was deleted. Private rollback backups and
  image artifacts remain available; existing static assets were not deleted.
- Original registration tab is preserved for the user-required new-password
  entry/submission. No account or customer organization has been created by this
  run yet. The new business chain remains unverified.
- User performed a weak-password registration attempt. The public UI returned
  the identity-provider rejection with explicit minimum length, character-class
  and identity-content rules. This is a verified negative registration case,
  not a successful registration and not grounds to weaken password policy.

## Resumed trial-account acceptance

1. User completed registration; enterprise portal shows the named test user and
   a bounded trial membership (100 requests, text.qwen, 24 hours).
2. Clicked Chinese locale, `自助开通`, bare GPU `选择此服务`: incorrectly
   skipped organization creation and opened capacity configuration.
3. Clicked `账户与 API 密钥`: trial membership visible, no company creation.
4. Clicked `订单与材料`: no orders; project/service/SLA require raw input and
   draft creation is disabled without a project. No order was submitted.
5. Returned to `自助开通`, clicked `返回`: trial organization incorrectly
   displayed as `组织已就绪`; company form was unreachable.
6. Fixed the shared UI predicate to distinguish trial membership from customer
   membership, including expired/revoked trials. Shared MaaS retains its direct
   trial path. Removed unconditional enterprise-verification wording and
   clarified that catalog counts are not entitled-model counts.
7. Regression results: enterprise UI 38/38 and enterprise browser controller
   32/32 JS tests pass. No authority, contract or machine admission bypass added.
8. Public r5 UI exposes the company form. Entered explicitly non-real technical
   test entity and address, existing test email; left optional identifiers blank.
   `创建公司` failed (HTTP 400). Backend requires at least one company registration
   or tax identifier although both UI labels said optional. Fixed labels,
   validation and legal-name/address maximum lengths; individual remains optional.
9. Entered `TEST-ONLY-UI-20260922` as the clearly synthetic registration reference
   and clicked `创建公司`. Success: organization
   `organization-403efe8d5588af18406b8123f28a2d70`, pending verification. UI explicitly
   reports provider unavailable and keeps prepaid machine ordering closed.
10. Operator: `成本中心` → expand controller connection → enter this visible
    organization ID → `刷新`. Final state confirms one Default cost center and
    one project for the same organization. Initial transient read failure cleared;
    this is not an empty organization.
11. Enterprise `订单与材料` still required manual project ID despite the created
    default project. Fixed organization switching to initialize its order draft
    and clear previous organization order/artifact selection. Also stopped active
    trial data overwriting the selected customer's project ID.
12. Deployed r6 image `sha256:9819c8f536646b5b4be29f2270157747b45b9e3885fb89d4e3e3462b215e99e5`.
    Public reload preserves the signed-in session and selected enterprise. Order
    form now automatically shows its correct project. Selected `1 天 · 49 元`
    and clicked `创建订单草稿`: success, generation 1, order
    `offline-order-4e349988-6b8b-4f80-9492-9dab2b40b0cc`.
13. Operator `线下商务` → `刷新` → this exact order: both sides agree on Draft,
    project and generation 1. Tariff shows one day/49 CNY as selected by customer.
    Clicked `按承诺函价目报价` → reviewed one day × one device/49 CNY → confirmation.
    Order becomes Quoted, generation 2. No customer acceptance, payment or legal
    execution was performed.
14. Confirmed another friction point: management refresh after mutation switches
    selection to the first historical order. Re-selected the exact new order
    before proceeding; historical orders were not mutated.
15. Clicked `启动流程` → reviewed generation 2 → confirmation: UI reports workflow
    started. This requests internal review, not approval or resource activation.
16. Latest regression: 70 JS tests (38 UI + 32 browser), 1142 native tests passed;
    native deny-warning check passed. Temporary image-builder pod deleted;
    rollback image and private deployment backups retained.
17. Enterprise refresh confirms PendingInternalApproval, generation 3. Customer
    can upload internal approval, identity, signed agreement, payment and invoice;
    none uploaded. Operator document-generation request reported submitted but
    did not expose a resulting artifact or failed-job reason. Not counted passed.
18. Enterprise `合同表单` → OFL v2 undertaking → select new order → `准备文档`
    returned HTTP 400. A native API regression reproduced the exact cause:
    explicit JSON null for `preceding_packet_ref` fails derived decoding. Fixed
    frontend to omit the absent optional field; no backend policy bypass.
19. Fixed management commerce refresh to retain the selected order if it still
    exists, with a fallback only when removed. Added both regression cases;
    console JS tests 68/68 pass with warnings denied.
20. Deployed r8 image `sha256:b05329faf0aea13fb1287acc7446c41f7fb8b40cbd46e951e41053b0ee56f086`.
    Repeated `准备文档` in the public enterprise UI: success, packet
    `contract-1bd438a8-de6c-418f-aaac-3ebd6da48c8a`, revision 1. Native contract
    API tests now 12/12 pass, including the previously failing decode regression.
21. Enterprise entered clearly non-real test company and proposed date 2026-09-22,
    `保存资料`: revision 2 and four-page MoonLeaf preview. No signature or stamp.
22. Operator `合同资料` → selected test tenant → same packet/revision 2 visible.
    Entered draft start 2026-09-23, end 2026-09-24, total 49.00 → `保存资料`:
    revision 3, AwaitingConfirmation. These are proposed values, not activation.
23. Enterprise `刷新`: same revision 3; `审阅并确认` → `确认资料` locks draft fields
    at revision 4 (not execution/signature). `生成原格式 DOCX + PDF` → `申请生成`:
    revision 5, generating, fields read-only. Final artifact outcome still pending.
