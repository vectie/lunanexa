# Beginner UX implementation checklist

Baseline: `7dde11e`, 2026-09-16. Attachment claims are hypotheses, not acceptance
evidence. Parallel owners work on disjoint packages; implementation and rendered
acceptance are recorded separately. Preserve MaaS API, PaaS WebIDE/ComfyUI and
IaaS exclusive-machine delivery boundaries. No domain, certificate or trust change.

## Verified corrections

- The current coursebook has 27 pages, not the attachment's 34. The named trial,
  enterprise-day-one and exclusive-machine-basics pages are absent; create them
  rather than pretending to update existing guides.
- Exclusive-lease expiry revokes access and starts staged cleanup; it is not
  proof of instantaneous physical disk erasure. Hosted workspace expiry can stop
  access while retaining its volume, not merely stop model calls.
- A trial workbench button needs an actual session-authorized invocation path;
  UI navigation alone is not sufficient.
- Contract renewal is not machine-lease extension. Use an honest contact-operator
  recovery path unless the lease authority really supports extension.
- Workbench drafts are page-memory only, not durable browser storage. Export is
  required before closing the page; hosted ComfyUI volumes are a separate system.
- Cost export is the current tenant's cost-center summary, not itemized invoices
  or an assertion of payment settlement.

## Deployment settings and safety

The enterprise browser shell reads `globalThis.LUNANEXA_DOCS_URL` before startup.
Set it in the deployment-owned HTML/bootstrap template to the separately hosted
coursebook's HTTPS base URL (loopback HTTP is accepted for local development).
Credentials, query strings and fragments are rejected/removed; unset configuration
hides tutorial/error links rather than guessing a public domain. This change
does not alter DNS, certificates or browser trust.

The first-call API origin comes from the existing controller client-launch
configuration. Missing origin/model memory metadata produces an explicit operator
placeholder, not a fabricated endpoint or hardware ceiling. Examples are canonical
text requests; other capabilities require their matching request contract.

Trial workbench requests use the same-origin identity gateway session bootstrap,
then an explicit trial-only API. They do not mint a key or bypass model, account,
membership, lease, expiry, rate or concurrency checks. API keys and browser trials
share a durable total counter. The account and key stores are separate commits:
a failure between them may conservatively reserve quota, not give free requests.
This does not claim cross-store transactional billing.

## Implementation TODO

| ID | Deliverable | Owner | Status |
| --- | --- | --- | --- |
| W1 | Real API entrance, authorized alias, canonical first-call example and error help | enterprise/backend | Implemented |
| W2 | Copy connection/fingerprint, safe SSH tunnel and next steps | machine | Implemented |
| W3 | Six frequent failures: localized cause/action and sanitized secondary detail | enterprise | Implemented; raw secret-bearing errors not exposed |
| A1 | Remove nonexistent machine-renewal action; honest operator contact | machine/enterprise/docs | Implemented as honest guidance, not automatic extension |
| A2 | Distinguish machine lifetime and credential-claim lifetime | machine | Implemented |
| A3 | Explain workspace allowance versus exclusive machine access | machine | Implemented |
| A4 | One-time trial-key warning and honest recovery | enterprise/docs | Implemented |
| A5 | Explain operator/customer login audience and separate sessions | root/enterprise | Implemented |
| A6 | Persistent submitted-request status and manual-review expectation | enterprise | Implemented |
| A7 | Accurate expiry/access/data consequences | machine/docs | Implemented |
| B1 | Authorized model selector with advanced manual input | workbench | Implemented |
| B2 | Browser-local draft export and loss warning | workbench | Implemented |
| B3 | Copy user-facing diagnostic identifiers | workbench/enterprise/contract | Implemented; no secret handoff code added |
| B4 | Relative plus absolute trial/key/agreement times | enterprise/contract | Implemented; unknown clock handled explicitly |
| B5 | Trial workbench entry backed by real authority | workbench/backend/gateway | Implemented; live IdP end-to-end acceptance pending |
| B6 | Textual and visual API-key quota warning | enterprise | Implemented |
| B7 | Friendly errors link to configured error guide | enterprise/docs | Implemented; deployment must configure docs URL |
| B8 | Per-page configured tutorial links | enterprise/docs | Implemented |
| B9 | Deduplicated one-hour trial-expiry reminder | backend | Implemented |
| B10 | Narrow-screen validation, no invented new feature | root | 390px workbench and portal checked; complete release matrix remains |
| C1 | Searchable exact-code error FAQ with recovery actions | docs | Implemented |
| C2 | Explain requirements-based machine allocation | enterprise | Implemented |
| C3 | Copy model aliases, capability and key-allowlist status | enterprise | Implemented |
| C4 | Tenant-scoped safe CSV cost export | enterprise | Implemented cost-center summary, formula-injection hardened |
| C5 | Authorized durable platform announcements and visible UI | backend/root | Implemented; no live announcement sent |
| C6 | Preserve existing coursebook strengths | docs | No redesign required |
| D1 | Test documented UI actions against source contracts | docs | All 31 coursebook pages classified; 18 named actions bound; historical SOP separate |
| D2 | Persistent demo labels on both portals | enterprise/root | Verified present in browser |
| D3 | Keyboard/modal accessibility release checks | root | Creation-dialog focus/Tab/Escape/restore verified; full release matrix retained |
| D4 | Shared locale selection and package-owned bilingual message catalogs | all UI owners/root | Implemented static catalogs + completeness tests; dynamic typed messages retained |
| D5 | Operator-only read-only trial/conversion aggregates | backend/root | Implemented; conversion is not payment |

## Validation and handoff

- [x] Package tests and generated interfaces reviewed; scoped `moon info` and `moon fmt` completed.
- [x] Browser bundles build; 211/211 selected UI/command JS tests pass with `--deny-warn`; coursebook/diagnostics tests pass 35/35.
- [x] API authorization, tenant isolation, deduplication and leak regression tests pass in the native functional suite (820/820, `--warn-list -92-20`).
- [x] Targeted desktop/390px portal and workbench checks completed. Creation and demo one-time-secret dialogs cycle focus, Escape clears/closes, and restore the opener. CSV/draft download initiation feedback checked; downloaded file bytes and OS clipboard contents were not independently inspected.
- [x] Functional and strict results recorded separately: full native strict checking still reports the 63 baseline diagnostics; it is not a passing release gate.
- [x] Commit coherent changes on main and push GitHub/GitLab: backend `699d00e`, UI `ab97aeb`, and documentation `6a773f6`.

The previous baseline passed 803 native functional tests with warnings 92/20
disabled; full strict checking still had 63 diagnostics. These are baseline
facts, not acceptance results for this change set.

Final local campaign (2026-09-16) found and fixed an optional-workspace JSON
compatibility regression before the 820/820 rerun. Demo secret previews issue no
credential, and no live announcement, payment, lease or model inference was
created. These changes have not been rolled out to the remote cluster. Real IdP
session-to-trial inference acceptance and the complete accessibility/responsive
release matrix remain outstanding; targeted browser checks are not that matrix.
