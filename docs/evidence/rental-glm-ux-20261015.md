# Rental and GLM portal handoff review — 2026-10-15

Acceptance targets: the deployed `/user/` and `/mana/` portals at
`https://suanli.kechuangfuwu.com:8443`. No demo deployment or demo session was
used.

## Changes

- The operator's initially selected rental order adopts the customer's requested
  tier. Refresh preserves an unfinished operator tier and device quantity.
- Operator identity references are disclosed under operator details.
- Customers receive the machine-access action after fulfillment; document
  approval alone retains the allocation wait and payment-evidence path.
- The allocation panel can return directly to the selected order at every stage.
- IaaS distinguishes company reservations from direct machine-login leases and
  links an existing company model to MaaS.
- Overview includes the company model's readiness. Overview and IaaS fetch that
  evidence on direct entry, without requiring a prior MaaS visit.
- GLM has a copyable OpenAI-compatible chat example and a key-management action.
  Its one-time key guide uses the same example, without infrastructure-envelope
  setup or embedded credentials. Other models retain their canonical guide.
- The shared model catalog is collapsed when a company model is present.

## Verification

- `moon info`, formatting, strict native check and diff whitespace checks pass.
- Full native runner: **1,813 passed, 0 failed**, using the documented C backend,
  unlimited stack and CLI fixtures.
- Portal suite: **380 passed, 0 failed**. This includes rental context, document
  approval versus fulfillment, quote-refresh preservation, private-model examples,
  reservation expiry and overview readiness regressions.
- Live: initial requested one-day tier; edited week/two-machine draft survives
  refresh; local draft restored without submitting a quote.
- Live: allocation-history recovery selects that exact order rather than the
  first order in the list.
- Live: two-machine reservation appears in IaaS; direct navigation reaches GLM.
- Live: fresh overview reports GLM API readiness. Endpoint/model/example copy
  values match the displayed values. Advanced catalog and launch settings remain
  closed by default.

## Boundaries of live acceptance

No contract was signed, payment confirmed, evidence fabricated or machine
reallocated. The live rental inventory has no allocatable idle pair, and the
company's GLM workload remains running. Approval, full-prepayment checks and
allocation rejection paths passed in the native integration suite; a new
physical rental is not claimed as live end-to-end acceptance.

The user approved the one-day GLM verification key. The live creation form
closed on success; secret-copy and first-call-copy values matched their UI
sources. Public model discovery and chat both returned HTTP 200, but the
128-token example exhausted its output budget before producing final content.
The example now allows 1,024 tokens. A matching request against the same GLM
runtime returned nonempty final content with `finish_reason=stop`. This last
check used the internal runtime route, not a second public test credential.
The temporary key's revoked state and closed confirmation were verified in
the live portal. Its temporary local secret file was deleted. The existing
customer key was not exposed or revoked.

## Released images

- Management: `sha256:0fd214d6edcd1f05f1f8ba4cc9aa01802678867da660b656a51f04e51c5ba4bc`
- Customer: `sha256:b92ae10efad16ddeca164e8186cef67f89e2f53433ea706ecbe1ae4d4c1973c0`

Public JavaScript matched the built artifacts byte for byte:

- Management: `c33aed58bac7e5afe631e731cd69a4c5aba7c7646b09d350e1938107043b01d6`
- Customer: `a728bab08f1b9fa2a892093780172eb0da689fcc408dba1d13b0cac63fa3648f`

Deployment backups and pinned OCI artifacts are retained in the private
management-host release directory `lunanexa-flow-20261015`.
