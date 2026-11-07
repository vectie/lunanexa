# Product simplification — 2026-11-04

Read this before continuing UI work, together with AGENTS.md.

## Current scope

Simplify the whole LunaNexa product: public site, user portal, operator console,
workbench, documentation and the two Qingchuang business applications. Preserve
working capabilities, organization permissions, saved work and model quality.
Use the current UI/UX Pro Max guidance with the established visual identity.
Default screens should show the task and its next action. Put occasional settings
and diagnostic evidence behind disclosure; explain failures where action is needed.

## Constraints and pitfalls

- HTTPS 443 and 8443 remain in simultaneous use. Keep navigation on the current
  origin and preserve shared-session support. Never force an external port in links.
- Model connection is application plumbing, not an extra user decision. Acquire or
  renew existing scoped credentials when an analysis is submitted; do not replay a
  submitted job automatically on authentication errors.
- Do not introduce concurrency limits, change model inference settings or restart
  GPU services for UI work. 176 is video, 177 Qwen, 178/179 GLM.
- Existing repository changes predate this task. Do not revert or bundle them blindly.
- Public API key and QR publishing was explicitly authorized by the owner. Preserve
  the deployed values without printing them in logs or committing them to source.
- The browser tool currently lists tabs but cannot attach (`browser.user is
  unavailable`). This is not proof of an expired login. Report visual acceptance
  separately from build, unit and HTTP checks; do not repeatedly request login.
- HostPath executable directories require explicit chmod 755: the host umask is 027.
- App release directories share venv/native symlinks with older releases. Do not
  delete those dependencies when cleaning builds.

## Baseline

The 2026-11-04 shared-session release is under
`/home/HwHiAiUser/business-login-shared-20261104` on the management host. User
portal, identity gateway and Qingchuang apps were released there. 443/8443 HTTP
checks passed; authenticated browser acceptance remains outstanding. Native full
checks have pre-existing deprecated-to_json warnings; document scoped checks.

## Acceptance

- Every route stays reachable; secondary navigation opens around the selected page.
- Home screens prioritize existing services and useful actions, not setup mechanics.
- Business users upload, review and run; model credentials renew without a manual
  connection step. Existing reports remain downloadable.
- No periodic DOM replacement while idle, no duplicate submissions, no new assets
  or animations that increase first-load cost.
- Verify builds, relevant behavior tests, live assets and service health. Record
  any verification gaps honestly.

## Released result

Global simplification is published under
`/home/HwHiAiUser/product-simple-20261104` on the management host.

- User navigation: five daily destinations; orders/contracts and usage/messages
  expand as needed and automatically reveal the active route. Home prioritizes
  authorized apps and existing services. Unconfigured app placeholders are gone.
- Operator navigation: six daily destinations; service configuration, commerce
  and diagnostics remain accessible in expandable groups.
- Public homepage: direct platform/FDE actions, concise service descriptions;
  existing approved API key, QR and brand assets retained verbatim.
- BP/procurement: automatic scoped model connection on analysis submission;
  explicit next-step names, no idle task-list replacement, resume polling on return.
- Workbench: external clients and usage are secondary details; blocked access has
  a direct account action. Documentation expands the current chapter only.

Published frontend image digests:

| Surface | SHA-256 |
| --- | --- |
| User | `3c208481e5ffb729667cae4eb747988d128224ad407bb64806a46fe7eb30f9b4` |
| Operator | `0183acabe528e4cb98eaccb413d43544241879bab79c83f559e8e8d82ecb9439` |
| Workbench | `a48f2c805e4781e7fb532ee4bf6538d9de8fe29e23b1131aa8016f49b14dadcd` |
| Docs | `701e21dfb3f760cf1b9d31d9d839f563ff449144bef40bf647a0f837354c610b` |

Homepage ConfigMap: `nexai-public-landing-simple-20261104`. Per-surface
`*-before.json` files and `business-service.before` retain rollback settings.
Do not print the homepage ConfigMap: it intentionally contains the public key.

Validation: 252 MoonBit UI tests, 52 documentation tests, 18 business tests and
3 portal-session tests pass. One opt-in live GLM test was skipped. JS builds,
`moon info` and `moon fmt` pass. Full native `--deny-warn` checking still fails
on 53 existing deprecation errors; the native test harness stops on 45 such
errors in its prerequisite CLI build. Scoped UI changes add no new warning class.

Both public 8443 (from the development machine) and internal 443 (from the
management host, resolving the domain to its ingress IP) serve the released bytes:
9 assets and 7 HTML entry points checked on each. Anonymous business API requests
still return 401. The business service is active and all 6 completed jobs remain.
The canonical workbench path is `/user/workbench/`, not `/workbench/` on this host.
The development machine currently has no direct route to internal 443; use the
management host for that network check, not a login reset.

Browser attachment remains unavailable in the tool, including its documented
alternative interface. Screenshots, responsive visual review and authenticated
click-through acceptance have NOT been completed. Do not report HTTP byte checks
as browser acceptance. No new inference or GPU load test was run for this UI release.

## Second simplification pass — 2026-11-04

Current user/app release: `/home/HwHiAiUser/product-simple-r2-20261104`.
User image: `sha256:f54d77f4e94e5e8c30ef75b274e62638a7cad66ff199bca3431ede3101732ec1`.
The first-pass console, docs, workbench and homepage remain the current versions.

- Trial home has a primary workbench action. API configuration, QR, examples and
  key actions are grouped under API access; technical model IDs leave the summary.
- Organization permissions are expandable. Billing checkout opens when a quote or
  payment needs attention; payment history opens when it has records.
- Procurement results show labeled business fields; raw JSON remains available in
  a disclosure. HTML in uploaded content stays escaped. Pending submissions have
  an explicit label and connection failures point to retrying the operation.
- Polling pitfall fixed: if a later task fetch fails, progress already fetched for
  another task must still render in `finally`. Idle/hidden pages make no progress
  requests or list replacements. Regression tests cover both behaviors.

Validation: 98 scoped UI tests, 7 frontend behavior tests and 18 business tests
pass (1 opt-in GLM test skipped). JS build, info, fmt and scoped diff check pass.
Native gates retain the same 53/45 existing deprecation failures. Internal 443
and external 8443 each match all 10 release assets and serve the 7 HTML entries;
anonymous business API access remains 401. Browser attachment is still unavailable.
Rollback is the previous release recorded above; per-release backups are retained.

## Management workflow simplification — 2026-11-04

Current console release: `/home/HwHiAiUser/admin-simple-r2-20261104`.
Image: `sha256:f9b0acb8a9973745c6fed778d7cfd6a45a01e06c36263ff9e60aabfc7877bdc1`.
Console JS SHA-256: `71d72625d31f96d60a647e0b3850872a152e6f947d34556bb11a8f5c9afc33bc`.

- Service names are optional. The existing random identifier helper generates a
  name before submission, and the console retains it for subsequent retries in
  that session. Explicit names are preserved. The existing deployment intent,
  idempotency key, preflight and placement authority are unchanged.
- Model adoption fills model ID, revision and license ID from the selected verified
  import. Invalid/missing identifiers remain empty for correction. Architecture and
  minimum memory still require real information; no hardware requirements or legal
  acceptance are invented. The existing import eligibility check remains mandatory.
- Template model/runtime selectors already fill artifact/image metadata. Valid
  sections now collapse; invalid forms expand configuration, including cross-field
  failures. Do not collapse sections using individual format checks alone: a valid
  architecture string may still be incompatible with the runtime's architecture list.
- Normal template fields omit repetitive help; missing/invalid fields retain it.
  Static import/deployment instructions are disclosures. Placement remains visible
  above the deployment action.

Validation: 209 UI/controller-browser tests pass, covering generated-name retry
stability, explicit overrides, adoption metadata, hardware fields left unspecified,
and cross-field error disclosure. Release JS build, info, fmt and scoped diff
checks pass. The full native gates retain 53/45 pre-existing deprecation failures.
443 and 8443 each match all 10 current release assets and serve all 7 entry pages;
anonymous business API access remains 401. Console rollout is ready. This pass adds
no background requests: metadata comes from loaded state and deployment uses the
existing single request. No live GPU deployment was initiated for verification.
Browser attachment still fails; authenticated clicking and visual acceptance remain
unverified. Retain `console-before.json` in this and the preceding admin release
for rollback, rather than deleting either baseline.

## Registered-user onboarding simplification — released 2026-11-04

Request: select known people/organizations/machines, carry existing information,
combine preparation and enablement when eligible, retain necessary approvals.

Backend adds an operator-only options read and a registered-account form of the
existing package POST. It reads identity and tenant from authoritative stores,
uses the existing durable saga, and enables only when its existing gates pass.
No production account has been granted access as part of testing. UI keeps the
manual verified-identity path under disclosure; registered people need only name/
email selection, approved organization and duration. Node approval uses a picker.
Selector context survives core refresh; switching identities clears stale manual
identity verification. Permissions, scope and remaining milestones stay visible.

211 UI/browser-controller tests and 4 native onboarding tests pass; 52 docs tests
pass. Tests cover unknown/suspended accounts, operator authority, unapproved orgs,
forged client metadata, idempotency, expiry and reopening the durable journal.
The build machine had outdated test fixtures missing fields already added to its
runtime types. Only the six corresponding test files were synchronized; their
old copies are backed up, and they are excluded from production executable code.
Source comparison of the previous onboarding implementation showed only this
task's changes.

Current releases:
- Backend script: `scripts/release-access-onboarding.mbtx`, remote root
  `/home/HwHiAiUser/access-onboarding-20261104`. The controller mounts its `control`
  directory. Binary SHA-256:
  `bb378f0d3f799e069ef88b5affe60e96f8d18c035db5e78ee05ed76cd6a753d9`.
  Previous native binaries remain in `/home/HwHiAiUser/glm-tensorfold-20261104/platform`.
- Final UI root: `/home/HwHiAiUser/access-onboarding-ui-r4-20261104`.
  Image: `sha256:13a0c6141b1feffb13d6711d00ba7c9863033765b5b2d357d15b389017160912`.
  JS: `ed1caa0e4980140b10d86b0aff52bb73f17c60f0773a7df55ad7b7171783d68c`.
  Earlier staging roots are not the current release. The final refresh logic
  preserves an undecided organization for a selected person; a global commercial
  default must not silently fill an ambiguous organization choice.
- Docs root: `/home/HwHiAiUser/access-onboarding-ui-20261104`.
  Image: `sha256:c855ac6e29131adf9a1d76f1d84fbb3007b7aca98a0c14735bae7f6f9c4b8146`.
  The product contract and source digest were updated together.
- Controller, console and docs rollouts completed. Internal 443 and external 8443
  each match all 10 current assets and serve all 7 entry pages. The new operator
  options endpoint rejects anonymous requests with 401 on both ports. These are
  HTTP checks, not authenticated UI acceptance.

Performance: one additional options read only in the existing Users/Leases read
group; selecting a person makes no request. The ordinary approval is one POST,
with preparation and gated enablement on the server. Selected-person records
filter in memory, and unrelated trial/event management is disclosed on demand.
No trial/model concurrency configuration was changed. The native release build
took several minutes of CPU compilation, not model execution or GPU work.

Implementation pitfalls: decode a request as its concrete struct, not as
`Request?` via FromJson (the latter interprets the JSON as an Option and rejects
ordinary objects). The native HTTP regression test covers the real body shape.
Changing a selected person or a manual provider identity clears stale manual
identity-verification state. Keep core-refresh tests for selected person, loaded
organization choices and intentionally empty organization selections.

Keep `controller-before.json` and per-site `*-before.json` for rollback. Controller
deployment snapshots may contain credentials; do not print or commit them. The
tests used isolated temporary stores and did not grant access to production users.

Native full gates remain blocked by the same 53/45 deprecation failures;
isolation heuristic still flags the existing shared-trial fixture. Browser
attachment remains unavailable; do not confuse it with an expired login.

## User onboarding journey — 2026-11-04, released and accepted with ceshi

User requested registration/application/approval/application launch with known
information carried forward, no repeated login or copying identifiers. They
subsequently chose the existing `ceshi` account rather than a new registration.
Do not ask them to create another account. Their user and operator logins have
both been observed successfully in new browser tabs.

User portal changes: account metadata loads before organization setup and is
reused by the full account read, so contact name/email populate even without an
organization. Only blank drafts are filled; legal identity is not guessed.
Display name follows the legal name until explicitly customized, with its
override disclosed. The approved default project carries into the order form,
and the machine request uses a model selector plus an advanced multi-model
override. A valid editable Unix username derives from the existing account.

Pending company/machine approval checks use the existing read endpoints every
10 seconds while the relevant page is visible, with context fencing and no
timeout that forces another sign-in. New membership, including upgrade from an
expired trial, is picked up from the authoritative organization list. A single
new customer organization is selected; ambiguous choices remain explicit. Old
organization/session responses cannot replace current onboarding/order data.
The shared-service flow has no purchase/quote/payment stepper, gives an expired
trial a company-access action, defaults that action to joining a company, and
offers direct application entry when approved applications are ready. Necessary
legal, billing and permission checks remain. Initial authenticated loading no
longer flashes an empty catalog/new-service order screen. Infrastructure 5xx
failures retain the session and give a recovery message rather than raw errors.

Actual browser findings: `cua.getTab()` for old user-owned tabs still fails with
`browser.user is unavailable`, but `cua.createBrowserTab('2', URL, ...)` works.
The persistent bindings are `journeyFreshTab` (tab 9, user) and `journeyAdminTab`
(tab 10, operator), with `journeyBrowser` for browser 2. Tab 9 is the final
deliverable; the temporary operator tab 10 was closed after acceptance. The
user signed in as guojiaan first, then switched the user
tab to ceshi on request. guojiaan opened procurement and BP directly from the
portal, without another password; procurement refresh retained its draft and
three completed tasks. No new business inference job was submitted.

ceshi's original trial expired 2026-10-31 23:47:15 Beijing time. Do not extend it
as a test shortcut. Its contact fields were visibly prefilled. The operator
form was prepared with ceshi, Energy Valley Qingchuang organization, and the
existing one-hour test Developer template (text generation, 2 concurrent,
100/hour). The user explicitly approved that one-hour access, and it was
submitted through the UI. Exactly one new grant appeared (844 → 845), and the
new company access package shows Ready. Do not repeat the approval or extend it.
No exclusive machine, SSH, operator role or model configuration is part of it.

The actual operator UI exposed another root cause: access-package readiness
called `serving_client_model_aliases` without the membership tenant/org. Ready
external GLM was therefore reported as ModelRequired. Both projection and
enablement now pass the authoritative membership context and require a serving
approved model in that context. Four native onboarding tests passed, including
a real loopback model-list server proving wrong tenant/offline model are
blocked and the right ready tenant can enable. Existing contract, suspension,
idempotency, expiry and durable reopen checks remain. The controller release
finished successfully (about ten minutes of GCC compilation) and was published.
Actual operator UI now shows guojiaan as Ready / application access ready,
where it previously showed ModelRequired; this check made no grant changes.

Current final portal release:
- Root `/home/HwHiAiUser/user-journey-r9-20261104`.
- Image `sha256:e7a032b8c061283a8d4b4390fe935ac4ac803565a9dc9284c7c795d6c8ecb64d`.
- JS `94cdc0193227a10ea286ab53c402c3fb737f50b2ec23b60ce5057b75938a2fae`.
- `scripts/release-user-journey.mbtx` stages from the existing local
  `tmp/user-journey-20261104/browser-dist/enterprise` folder. Prior r3/r5/r6/r8
  portals were briefly live; r4/r7 were prepared but not published. R9 is live.
- 443 internal and 8443 external each match the compiled bundle. The manager
  does not listen on its private address at 8443; verify internal 443 there and
  external 8443 from the development machine. A private-IP 8443 refusal is a
  verifier-address error, not a login or ingress regression.
- Backend target `/home/HwHiAiUser/access-onboarding-r2-20261104`, using
  `scripts/release-access-onboarding.mbtx`. Only the onboarding handler and its
  regression test were copied into the existing remote build checkout. Its
  `control` directory is now mounted by the controller deployment. Binary SHA:
  `ae2916350301201328c3012a71a70187ac349d83ce489727db2c73e9aed12615`.
  All helper executables were preserved; the rollout completed. Rollback remains
  in the preceding `/home/HwHiAiUser/access-onboarding-20261104/control` directory.
  Deployment rollback snapshots
  are mode 600 and may contain credentials; never print or commit them.

Release incident: staging crossed the management machine's disk threshold and
Kubernetes evicted controller, registry and several frontends. The first live
procurement launch returned 503; it recovered after disk cleanup. The space
check happened too late. Do not compensate by changing eviction thresholds,
removing taints or changing node permissions. Kubelet uses 5% eviction hard
thresholds, 10% minimum reclaim and a 5-minute pressure transition period.
Just clearing the hard threshold was insufficient while reclaim was active.

Cleanup removed 102 redundant OCI/base/layer tar exports (33,021,184,000 bytes)
only where corresponding extracted OCI manifests/blobs remained, plus unused
old Comfy image assembly layers and rebuildable native/debug/build caches with
no deployment/process reference. Root-owned caches were skipped (one attempted
cleanup returned permission errors); no sudo/permission expansion was used.
The cleanup scripts are `scripts/clean-redundant-image-exports.mbtx` and
`scripts/recover-user-journey-disk.mbtx`; inventory is retained remotely in
`user-journey-20261104/cleaned-exports.txt`. Model weights, PVC data, user files,
mounted native binaries and registry image contents were retained. Node
DiskPressure is now false; controller, registry, identity, postgres and portal
deployments recovered. Free space was about 59 GiB during the controller build.

The real ceshi journey discovered a second-stage refresh race: membership was
visible before the workspace lease became active. The page automatically
selected Energy Valley without a password or ID, but still showed its previous
application snapshot. A manual status refresh confirmed that authority was
already Ready. R9 adds a lightweight application-catalog check after membership
approval, continuing until applications are actually ready, then reloading the
full projection once. Its regression covers the empty/pending then ready
sequence and stops checking after readiness. No additional grant or extension
was used to test this repair. ceshi then entered its own empty BP workspace
through the normal application card without another sign-in. After the R9
release, returning to the portal retained ceshi and the selected company, and
the procurement card opened ceshi's own empty procurement workspace directly.
The user application tab is marked as the final deliverable. The original
guojiaan documents/tasks were absent from ceshi's workspace as expected.

Validation: 171 UI/browser-controller tests and four native onboarding tests
pass; native API check (without deny-warn), `moon info`, `moon fmt`, and scoped
diff checks pass. Full native deny-warn and native-runner gates still fail on
the pre-existing 53/45 deprecations. Isolation still flags the pre-existing
shared-trial fixture. These are not successful full-workspace gates. The real
account acceptance used the existing ceshi registration at the user's request;
do not claim that a new account was registered in this run. The activation race
was found live, then fixed and regression-tested, rather than manufacturing a
second grant or changing the approved one-hour lifetime for another replay.

## Models grouped by family — 2026-11-07

Models now browse family → generation → variant. Known families are Qwen,
DeepSeek, Kimi, GLM, StepFun and MiniMax; empty families are omitted and unknown
identities remain in Other. Generations derive from model identity, never the
artifact revision (`modelscope-master` is not a model generation), and sort by
numeric components newest first. Family/generation counts both count unique
model IDs; qualification artifacts remain available inside each variant.

Import is a separate disclosure, automatically open for an empty registry,
search results, pending imports or a registration draft. Normal-state runbook
copy and duplicate identifiers are removed. Metadata/API names live in Details;
each row promotes its next action and keeps the other existing commands in More.
No command, approval authority, licence acceptance or backend verification was
removed. No model/GPU setting, grant, concurrency limit or runtime was changed.

Live acceptance found legacy `Accepted` versus `accepted` casing: normalize only
for UI action choice so approved models do not request licence acceptance again.
The controller remains authoritative. Regression tests cover this, numeric
version order, family detection and preservation of variants/qualifications.

Final console release: `/home/HwHiAiUser/models-simple-r2-20261107`, image
`sha256:f16e5ead7b441a3318ef7eba05bdd793c7fddd747ac3d3525f2a76080bb64a26`.
Release helpers are private task files under `/tmp/models-simple-20261107`;
remote `console-before.json` retains rollback and must not be printed/committed.
The earlier `models-simple-20261107` release is superseded. Browser reload can
briefly show the login form while its existing gateway session restores; wait
for restored navigation before treating it as an expired login.

215 UI/controller-browser tests pass. JS release build, info, fmt and scoped
check/diff checks pass (scoped check excludes existing deprecated diagnostics).
The complete native gates still fail on the existing deprecated JSON calls;
the full native test runner stops in its CLI prerequisite build. Do not call
these full-workspace passes. The first deployed bundle matched external 8443
bytes exactly; final bundle/health checks are recorded with task evidence.
Authenticated live browsing verified family → Qwen 3.8 → six variants, corrected
3.8/3.6/3 ordering, and More exposing the original commands. No live approval,
licence acceptance, alias promotion or rollback was submitted.

Performance: all grouping uses the already-loaded registry and native details;
no additional polling, requests, dependencies, assets or GPU inference load.
Management disk space was checked before staging (about 45 GiB free). Preserve
other dirty workspace changes and existing image/rollback references.
Final JS SHA-256: `f8c5a569f106cccc7e25e4a8033a1f11a093dc161f7c025513e788e28f6ffc8a`;
external 8443 matches the local release bytes. At 390px the document width is
390px; the existing table container owns horizontal scrolling. Viewport reset
and the live Models page retained. Screenshot: private task evidence at
`/tmp/models-simple-20261107/evidence/models-family.jpg` (not committed).

## Deployment page and authority clarification — 2026-11-07

User requested the same family/generation grouping as Models, with default
running status/common operations and tuning/benchmarks in Advanced. They also
asked whether customer and operator deployment could collide on one machine.

The operator page now distinguishes the fixed shared model pool from ordinary
managed assignments. Pool summary shows current generation, participating nodes
and observed readiness (an enabled route is not proof that the runtime is ready).
Node/model changes are under a separate disclosure; speculative/cache tuning and
benchmarks remain in Advanced. Available model options are grouped by family /
generation without inventing unsupported aliases. Managed assignments group by
registry artifact identity, not arbitrary deployment display names. Their rows
show observed state, actual node and platform/company ownership; desired state,
assignment receipt and placement evidence are secondary details. Unknown artifact
mappings remain explicitly unidentified. The UI read payload now carries digest,
node ID and reservation tenant from existing assignment data; no new API/read.

Authority findings (do not overstate these as one unified control plane):
- Ordinary management preflight excludes scheduler-reserved/exclusive nodes.
  Assignment publication repeats reservation owner/service checks under the
  resource mutex (`api/deployment_http.mbt`).
- Customer delivery plans within its reservation; service claims account for
  per-node memory/GPU/concurrency budgets (`scheduler/node_reservations.mbt`).
  ReservationHost refuses unrelated running/terminating workloads and checks
  ownership before/after applying the reservation taint.
- The fixed model pool changes saved Kubernetes deployments directly. Preparation
  checks reservations, but do NOT claim that every pool mutation repeats the
  ordinary assignment ownership checks. The UI distinction is not a backend fix.
- The user's existing GLM service is an explicitly configured external text
  backend (`api/external_text.mbt` + `cmd/control/main.mbt` callback), not an
  ordinary managed assignment. Its start/stop does not mean choosing an arbitrary
  free node. An empty managed assignment table does not prove GLM is absent.
  These fixed-service paths are not fully unified in the managed deployment
  ledger; a future resource-authority integration must preserve live services.

No backend authority, inference configuration, concurrency, grant, route or GPU
runtime was changed/restarted for this UI work. Do not add cosmetic disabled
buttons or claim perfect cross-path conflict isolation without resolving that
actual integration. No production deployment/stop was submitted as a test.

217 UI/controller-browser tests and 18 native scheduler/reservation-host tests
pass. JS build, info, fmt and scoped checks pass with existing deprecated
warnings excluded from the scoped check. Full native deny-warn still fails on
53 existing deprecations; the full runner stops in prerequisite CLI compilation.
No new background requests or assets; JS grew about 16 KiB uncompressed (~0.21%).
Management disk free space was checked before staging (~43 GiB).

Release root: `/home/HwHiAiUser/deployments-simple-20261107`.
Console image: `sha256:17ae31af8dc145c762e48e9f2ee711fe34201d79f3bb0815b295be1d32889f39`.
The private release helper is `/tmp/deployments-simple-20261107/release.mbtx`;
remote `console-before.json` retains rollback. Never print/commit deployment
snapshots. Prior Models release and its runtime/identity services were retained.
Final console JS SHA-256:
`d086b4a3e85bb42f5bec7b06db498c273a67bbbba74e9b1c9bc3eeb8347a7c16`;
external 8443 matches local release bytes. Authenticated browser acceptance
verified the shared-pool summary, model-generation option grouping, expandable
node/model controls and all three tuning/benchmark sections under Advanced.
They were restored closed without submitting an action. At 390px viewport the
page width remains 390px; viewport reset after inspection. Managed assignment
family/ownership grouping was regression-tested; the live managed list is empty,
so no production row was invented for a screenshot. The currently observed pool
reports route enabled but runtime not ready; this is displayed truthfully and
was not treated as a request to restart/change its model. Screenshot is private
at `/tmp/deployments-simple-20261107/evidence/deployments.jpg`.
# Unified model-service authority — 2026-11-07

The current task supersedes the authority gaps described in the earlier
“Deployment page and authority clarification” entry below. Both portals now
submit lifecycle intent through the durable model-service ledger and the same
reservation, node-lease, company ownership and overlap admission checks. Ordinary
signed assignment publication, customer delivery, fixed pool mutations and
adopted process groups register/check this authority before runtime writes.
Direct assignment PUT delegates to the same publisher; client-supplied reservation
ownership is not trusted. The legacy external-service API delegates to the common
dispatcher, preserving published URLs rather than retaining a second authority.

Runtime differences are data/configuration: node assignment, Kubernetes binding
or management-host process group. No controller selects GLM or Qwen by name.
Approved artifact/architecture runtime profiles retain existing parser/MTP and
process order settings. The active user-level GLM TensorFold control daemon was
replaced by `lunanexa-runtime-control.service`; its host config retains exact
targets, image identity, start/stop order and memory settings. The new controller
uses the generic private endpoint and a host/deployment secret reference. No
MoonSuite application or product credential was placed on a managed node.

Production adoption is metadata-only: six bindings registered, five Kubernetes
GPU deployment UIDs and complete specs unchanged. Qwen and MiniMax remain
running; GLM was already stopped before migration and remains stopped. No GPU
runtime start/stop, model switch or real GLM inference was issued during this
task. Ten service deployments, four assignments, the existing reservation and
all membership rows were retained. Fixed company nodes remain allocated despite
the stopped service and the historical released reservation; no expired grant
was reactivated. API aliases, client secrets, files and billing history were not
rotated or deleted.

Operator Deployments now groups all services by family/version, showing status,
resources and common actions. Idle platform pool bindings and tuning remain in
Advanced. The customer projection is company scoped, hides physical node/binding
details and excludes personal delivery replicas; multiple shared models get a
selector while a single model needs no extra step. Both official portal bundles
are published. Authenticated live `/mana/` confirms Qwen, GLM and MiniMax with
aligned columns and Advanced closed. Screenshot is private task evidence at
`/tmp/unified-services-20261107/evidence/mana-deployments.png`. The inspectable
`/user/` session belongs to an unrelated acceptance account; a company-member
browser check was requested and remains pending. Do not claim it was performed
or reset/impersonate a member to manufacture evidence.

Acceptance: API native 228/228, UI/browser 389/389, contract/controller/scheduler
35/35, Linux store/model-pool/runtime-control 23/23 pass. Additional portal privacy
fixtures (2) and final alignment/grouping fixtures (7) pass. Isolation and response
leak checks pass. `moon info` and `moon fmt` ran. Full native deny-warn still fails
on 53 existing deprecated JSON warnings; the full native runner stops in CLI
prerequisite compilation on 45 existing warnings. No full-native-pass claim.
No inference hop or per-token persistence was added. Runtime observations run
outside the global resource mutex with bounded timeouts and stale-generation
rejection; Kubernetes capacity is retained until matching pods terminate.

Production release roots (private snapshots/credentials must not be committed):
`/home/HwHiAiUser/unified-services-20261107` (controller/adoption),
`/home/HwHiAiUser/unified-services-ui-final-20261107` (customer portal), and
`/home/HwHiAiUser/unified-services-align-20261107` (final operator alignment).
Active control binary SHA-256:
`40dc698cedf92740dd6cc0035f3322e06673b9612ccf84331802464bc9eb254c`.
Public operator JS SHA-256:
`ce694abda401fb5c414f6e8b1d79730fd7d263e496eebb5202c8ac285dbf2a3f`;
customer JS: `d995428e153441d6f7e979f9cdce109e50f4f7af4b17abd86cd0bc7b56f2ff21`.
Final immutable operator image:
`sha256:50b8cd1fd97d14615fdd40e98f17ba1312f118c3588171fbc66f2effba612896`;
customer image:
`sha256:b11acf6463a17accc3b8c5f6b1289fcb4bbbfaf450c53b5e77337628602386ef`.
External 8443 bytes match. The unrelated older system-level GLM adapter is outside
the active platform path and was left untouched after its sudo credential was
rejected; the active old user-level adapter is disabled. Do not claim all legacy
daemons were deleted. Disk free space after final publication is about 32 GiB;
avoid accumulating further OCI base exports.

Pitfalls: fixed company allocations survive a stopped runtime, but stopped
reservation-scoped delivery replicas must release ended ownership. Desired
replicas=0 is not proof that GPU pods have terminated. Never observe a runtime
under the global admission mutex or apply old observations to a new generation.
Preserve the old signed v2 catalog serialization; the service ledger has its own
versioned snapshot. Restart reconciliation observes/adopts without replaying
start/stop. Family grouping is presentation only, never a resource authority.
