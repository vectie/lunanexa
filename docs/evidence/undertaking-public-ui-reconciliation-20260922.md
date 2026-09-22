# Public UI undertaking reconciliation — in progress

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
