# Product simplification — 2026-11-04

## 2026-11-09 · Alternative registration contact and acquisition

- The unified gateway accepts exactly one email or mainland China phone. Phone usernames normalize to +86, have no fabricated email, and retain phone_number_verified=false. Minimum password length is six with no character classes; provider hashing, lockout and five-password history remain enabled.
- The existing signed X-LunaNexa-Identity-Email / Account.email slot carries the real contact identifier for compatibility. It is not proof of verified email or SMS ownership. Phone acceptance remains behind the same provider identity and HMAC assertion. Do not prefill billing email from a phone contact (onboarding regression covered).
- Optional acquisition source/campaign/entry are bounded ASCII marketing metadata stored in admin-managed provider attributes. They never assign roles. The private report/export helper writes mode-0600 records; do not commit exports, tokens or realm backups.
- Release evidence and backups: /home/HwHiAiUser/coffee-contact-20261109/. Controller c24f8af1e808dc990f0f54268acbb03a244ccaba21ab065743b0f9f7397e0e53; external gateway 20af766bffbd7ce85926d09b7c8ae69e0b16c936e75e1508b005d9512efffb69. Existing glm-control helper hash unchanged. Final user UI digest 1ce0dcd1c119ea5e475f0a187fb9abadf0edc2a64a1b246b007ef3df45c108bf.
- Full native 1972/1972, gateway 46/46, portal JS 73/73, isolation heuristic and native deny-warn checks passed. Canonical generated public interfaces unchanged. Live email and phone registration and provider attributes were checked; phone uses a deliberately non-routable QA number, no SMS was sent.
- DiskPressure evicted platform, registry and identity dependencies. Kubelet 5% hard threshold +10% minimum reclaim requires ~15% free and a five-minute transition. Reviewed inactive OCI export caches were removed; models, PVC/account/activity state, executable/venv dependencies and retained rollback archives were preserved. Never lower thresholds or force-clear taints to hide pressure.
- Registry 2.8.3 was restored from the retained original 46faa9a1 OCI archive. Keycloak retained original ff4257d0 index and amd64 child; the original index bytes were verified before cached import. Temporary importer pods dropped capabilities, mounted only k3s/socket and the public image archive, had no service-account token, and were deleted on exit. Only a terminating, never-started, exact-UID identity Pod was force-removed.
- Main PostgreSQL's unreachable mutable external alias was replaced with the already-qualified private 4fae780d metadata-only recovery image. Its original bb3e1a57 index, exact filesystem/config preservation and shared main/identity provenance are recorded in EVENT_TRIAL_REHEARSAL_20261022 and UNDERTAKING_TWO_SIDED_RECONCILIATION_20260922. StatefulSet/PVC/config/credentials retained; database and control recovered Ready.
- Check .mbtx scripts before upload. Source overlays need COPYFILE_DISABLE=1 and --no-xattrs; the Linux build's moonleaf sibling must contain CSV. Controller native release took about fifteen minutes and 6.6GB peak GCC RSS; avoid redundant rebuilds. The browser/portal is JS-only, so its tests must use --target js.

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

## Strict native gate and real GLM startup — 2026-11-07

The prior 53/45 warning failures are superseded. Replacing deprecated primitive,
array/map and optional conversions with `Json(value)` exposed downstream warnings
that had not been checked while prerequisites failed. All diagnosed conversions
were migrated without changing signed/persisted JSON representations. Iterator
`length` and array-view `to_array` aliases were replaced, map-pattern rest marks
and empty JSON array types made explicit, and strict unnecessary annotations
removed. Benchmark's reserved `namespace` field is now `run_namespace` in source
with both JSON directions retaining the exact `namespace` wire key; a round-trip
fixture protects existing saved reports. No warning was disabled in the gates.

Final acceptance: `moon info`, `moon fmt`, native `moon check --deny-warn`, and
`moon run scripts/test-native.mbtx` pass. The complete native workspace suite
reports 1,956 passed, zero failed. A stale UI assertion still expected the old
“Open one-click deployment / No managed deployments” copy; it now checks the
actual Deploy model action and No model services empty state. Browser release
build passes with deny-warn; isolation/public-response heuristics pass.

The workspace MoonLeaf dependency also needed four unnecessary enum qualifiers
removed from `pdf_text/recover_metadata.mbt`. That file was already untracked,
alongside unrelated pending dependency work; do not stage/push that work blindly.
Only the four-line companion patch is preserved under
`docs/development/moonleaf-native-annotations.patch`, and reverse-apply checking
confirms it matches the fixed local dependency. Full-workspace evidence uses that
local MoonLeaf tree, not a claim about its older published package version.

The authenticated live `/mana/` GLM Start button was exercised once. It really
started the existing .179 worker and .178 head at 23:32:38 CST. The head exited at
23:33:19: a 1M stream needs 12.76 GiB KV pages but its CUDA budget left 12.44 GiB.
The owned-pair supervisor retired the worker. No healthy model endpoint or valid
live inference resulted; about 41 seconds is failure time, not startup latency.
Qwen/MiniMax and existing files, keys, precision, context, concurrency and reserve
were unchanged. `docs/GLM_STARTUP.md` records the result. A host audio-service
restart was requested separately for confirmation because WirePlumber holds
about 580/960 MiB on the two machines. It has not been performed; do not lower
context/precision or assume approval from elapsed time.

Root UI fix: operator and customer readiness share the same endpoint observation.
The operator API adds a non-persisted `ready` field; active process state alone
does not produce Ready in the console. Startup-only refresh reuses the cluster
tick, has one outstanding read, and ends when the service is ready/stopped.
The endpoint check is bounded and outside resource admission; no inference hop,
per-token work or permanent idle polling was added. Native regression fixtures
cover missing/false readiness, stopped state, scope, and refresh overlap/end.

Release staging root: `/home/HwHiAiUser/native-glm-20261107`. The console image
was assembled with immutable base blobs hardlinked and only a new asset layer;
no redundant multi-gigabyte export was retained. Production logs and deployment
snapshots remain private. No new credential or grant was issued.

Final publication succeeded for controller and management UI. Control binary
SHA-256: `05c8533479c3cd85f5f59b4ce73b8e5f3080735e216de9b15b4da264d867d171`.
Console image: `sha256:70c5b672a42496c366923ae4f6bf6e851135ebe0a3827f2e0fc9db4e0a4e5348`;
public JS: `93c93987331dfc25632440f76bfdb065308a429c94b3581dbf5a0e8cbf0abb6d`
matches the tested local build over external 8443. Authenticated live `/mana/`
shows Qwen/MiniMax ready and GLM stopped. The API now supplies endpoint readiness;
live verification asserts GLM stopped/ready=false, six retained bindings and
unchanged Kubernetes GPU specs/UIDs, deployment/assignment/reservation counts and
membership rows. The controller restart issued no additional GPU start action.
Final private screenshot: `/tmp/native-glm-20261107/evidence/mana-final.png`.
Implementation commit `3035ed4` is pushed to both GitHub and Vectie main. The
audio-service confirmation remains unanswered; do not call GLM inference ready
or report a successful startup duration from this run.

## User-authorized GLM 512K — 2026-11-08

The user chose 512K instead of restarting host audio services. This supersedes
the previous no-context-reduction constraint and pending audio confirmation.
Do not restart/remove WirePlumber or other desktop services on that basis.
Both Ubuntu 24.04 hosts have GNOME 46, PipeWire and WirePlumber installed;
WirePlumber's vendor unit is wanted by PipeWire/PipeWire Pulse. It is host desktop
infrastructure, not a GLM/LunaNexa dependency. Its original installer was not
inferred from these package observations.

Only `--context 1048576` was changed to `--context 524288` in the two existing
TensorFold user units, while both were stopped and GPUs idle. An exact reverse
replacement matches both original unit files; all other settings, precision,
reasoning, output allowance, reserve, credentials and model paths are unchanged.
Private backups and bounded acceptance evidence are under
`/home/HwHiAiUser/glm-512k-20261108` on the manager. Native automation is private
`.mbtx`; do not commit host unit snapshots, credentials, logs or production state.

The live authenticated `/mana/` Start button was used. The service became healthy
and model discovery succeeded **41,788 ms after the head's systemd Started event**
(1.5-second readiness sampling). JSON arithmetic returned a correct result in
324 ms; SSE returned READY and a normal DONE marker in 234 ms. The page became
Ready without manual refresh. This is service-start plus small-request acceptance,
not a reboot/cold-filesystem or full-512K-prompt quality benchmark.

Both model aliases and the tokenizer declare 524,288 tokens. The runtime reports
eight execution lanes and 528,384 shared KV tokens (1,032 existing 512-token
pages). Eight lanes do not mean eight simultaneous full-context histories. The
live allocation ConfigMap now reflects these observed values; its stale 1M KV
byte estimate was removed, with the old metadata retained privately. No controller
restart, new image, model-specific backend path, key, grant or audio-service
mutation was needed. GLM is left running; Qwen/MiniMax remain running.

No native source changed, so the previous strict native check and 1,956-test gate
were not repeated for this configuration/documentation change. Actual runtime,
JSON/SSE, effective unit arguments and the official portal are the acceptance.

## Concurrent browser identity reads — 2026-11-08

Account authorization still checks the current session, expiry, revocation,
account state and required role on every call. Session activity is approximate
telemetry: touch it in memory and checkpoint globally once per 30 seconds, not
once per request or once per user. Security mutations retain immediate durable
persistence. Preserve `activity_checkpoint_ms` in both store constructors and
its failure rollback; the field is intentionally absent from saved snapshots.

Browser session storage now uses the existing four-worker asynchronous PgPool.
Every lookup remains a live database read. A refresh cannot move last-used time
backwards when requests finish out of order; deleted sessions cannot reappear.
The dedicated *_test database regression locks one session row while another
session remains readable. Do not point the database test at production, and use
the verified service IP when a management host cannot resolve cluster DNS.

GET `/v1/auth/self` sends a freshly authorized response before recording its
ordinary operational event in the same request task. Its metric can be lost if
the process crashes immediately after the response. Mutation audit ordering is
unchanged. A broken metrics store never grants a revoked session: the real HTTP
test returns 200 while valid and 401 after revocation. No completed authority
cache, timeout increase or TLS/origin bypass was added.

A later controller source snapshot had dropped the earlier activity-checkpoint
patch. Do not deploy just one layer of this fix. The final build receipt pins
both account/API source hashes and the resulting executable. Controller SHA256
is `7bef5632a0cabb04ed42020e9a5651bf3a2c2f105b416bcd823141671027b463`;
browser gateway SHA256 is
`2c973649c7d9c6d585289beb7f3d88cab01f9ea327a9b72815ccb5d4a26f7f9f`.
Current model configuration and runtime processes were preserved.

Twenty real identities completed sixty profile checks: gateway profile P95
57ms, session P95 42ms, direct controller profile P95 6ms. A sustained 1,000-read
twenty-client run returned 1,000 HTTP200. Strict native check passes; the complete
native workspace suite reports **1,959 passed, zero failed**. Native gateway
tests also passed **44/44** against the dedicated test database, and the deployed
source account package passed **16/16**. These identity measurements do not
constitute a model-serving or whole-cluster qualification.

## Progressive portal disclosure and responsibility audit — 2026-11-08

The per-page ledger is `docs/PORTAL_SIMPLIFICATION.md`. Keep code completion,
official-site acceptance, previously simplified pages, and remaining exceptional
scenarios separate. Do not infer that every route/state has been accepted from
one existing company account. Default surfaces show status and the next action;
technical details/history/settings use named native disclosures. Required
decisions, scope, payment, destructive confirmations and actual failures remain.

The official Users page rendered hundreds of full access-package milestone
cards at once. A separate `access_record_account` selector now constructs cards
only for the inspected person. It is transient UI state, retained across refresh,
and does not modify the grant form or authority. Organization labels replace raw
tenant pairs on cards; original identifiers/state remain in technical evidence.
Missing account/membership readiness must not direct operators to deploy a model.
Workspace/grant tables and role editing are progressively disclosed. No records
were deleted or reclassified to make the page look simpler.

Resource allocation forms open for explicit order/person handoffs; the resource
summary stays visible. Order actions precede secondary details; fulfillment
requirements are labeled and collapsed rather than displayed as completed checks.
Customer invitations, agreement hashes and payment history no longer dominate
the default page. Delivery failures still open the operator outbox. No backend
policy, model limit, runtime argument, resource allocation or inference hop changed.

Native info/format/deny-warn checks and the full native suite passed: 1,961/1,961.
The related JS suite passed 452/452, native UI tests 124/124, strict JS check and
both release bundles passed. JS-only compilation exposed deprecated JSON aliases
and test callback/state-type issues; these were corrected. The test that invokes
Rabbita's intentionally experimental server renderer uses the same local
`alert_unstable` annotation as existing rendering tests, without relaxing
production compiler warnings. No new polling, request or dependency was added.

Private browser release material is under
`/home/HwHiAiUser/progressive-portals-20261108`; immutable base blobs are hardlinked
instead of re-exported. Keep production deployment snapshots and logs private.
Before publication, both official portals were read while authenticated; the
browser transport subsequently closed. Final visual acceptance must be recorded
separately from deployed-byte and Kubernetes rollout verification.

Both portal rollouts succeeded; external 8443 JS matches the tested bundles:
console `b5d4bcdb107e9df92d6b4ebc02ae2961c358e05eb9d87915d68b223f06660477`,
enterprise `452682814c92ec9690fa8dff307e7cece8a1f0cf42a75286618c79041180eda9`.
Images are `sha256:0458f1ad453db22064875a471f32610f47ee5c58f55e33f8901f7dd3b63f8e90`
and `sha256:a7c4b4431c03cfedce14e5f20f2ab1ccc432acd17367836608c70fc5864b3a7e`.
The first image-push attempt used a tag outside the existing browser release
prefix; the retry used the supported prefix without weakening the uploader.
No backend or GPU runtime deployment was modified. Browser transport failure is
an outstanding acceptance limitation, not proof of sign-out or a reason to reset
someone's credentials. Existing unrelated tracked/untracked work remains unstaged.

## Pagination, exception handoffs and company scope — 2026-11-08

Continue from `docs/PORTAL_SIMPLIFICATION.md` second-round ledger. Six operator
lists now build only a 25-row/card window: accounts, selected-person company
access, workspace profiles, grants, audit and request receipts. Search resets
its page and lists retain independent UI state across refresh; a shrinking
result clamps its visible page. The existing API still returns snapshots: do
not claim server cursor pagination or reduced network bytes. Latest audit and
request records come first; the extra 50-receipt truncation/front-removal loop
was removed. Receipt expansion and copying retain the full value.

Delivery readiness timeouts offer same-operation retry. File/template/unknown
failures name the platform operator, expose a bounded failure reference copy,
and retain same-operation retry behind repair disclosure. No server-side
authorization or retry rule changed. Operator delivery failure links to
deployments; quarantined lease guidance points to node cleanup verification.
Rejected workspace requests explain the company-admin requirements handoff.

Company switching must clear the old organization's keys, contracts, costs,
machines, services, applications and payment projections before asynchronous
replacement. Same-company refresh retains order/draft state. Creation and join
advance session/poll generations. Invitation acceptance now retains the returned
organization ID, selects it for the bootstrap read and clears the invitation
draft. A missing explicit preferred organization must not silently select
another company. Existing companies are chosen before expanding creation/join;
rejected/suspended/closed companies are not labeled as pending verification.
Pending companies poll company status before application readiness, and old
scoped outcomes cannot repopulate the new view.

Final strict native and JS checks, release bundles, info/format pass. Native
workspace tests pass 1,963/1,963; related JS tests pass 460/460. The existing
native self-service HTTP test verifies multi-company isolation, approval and
invitation roles in independent temporary storage. No production identity,
membership, credential, order, grant or GPU service was mutated for acceptance.

Pitfall: two native suite invocations overlapped after a failed format-related
check and collided in two test packages' timestamp-based /tmp filenames.
`commercial/offline/store` and `notifications/store` now use independently
allocated temporary directories with deferred cleanup. The final full suite ran
serially and passed. Do not run another native matrix concurrently with a
still-running prior invocation, and do not continue the runner after a failed
prerequisite merely because shell commands used semicolons.

Private browser release root: `/home/HwHiAiUser/portal-pages-r2-20261108`.
Official-site visual acceptance is separate: management explicitly reported
session expiry, and the customer tab returned to login after session restore.
Sign-in was requested; do not claim new-company production UI-to-UI acceptance
from a single existing company account or infer permission to create test grants.

The final scope follow-up additionally preserves the machine/UI clock while
clearing organization projections, and uses the cleared self-service state when
no company remains; otherwise the command layer restored the old order/quote.
The enterprise UI/command suite passes 177/177 after those assertions. Final
customer image staging is under `/home/HwHiAiUser/portal-pages-r3-20261108`.

Both official portal rollouts succeeded. Final console image:
`sha256:e16ce392e21345b8fa9e21ea76bffcab0d8a5513cb717f50ce8a085a285d6588`;
customer image:
`sha256:ce1b6c19add59443052524dd04f85700a1ca94fd32c51233b5c3157d796b4e21`.
External HTTPS 8443 JS hashes match final tested assets: console
`af6b006243ea987b735d5ed9e463bd9c7748feef91434b2831f48eb9ddcf48fa`,
enterprise `ec7df985f19ea25e20ea86044bd5d500b8586917ff46aee8f9213375a3e245ce`.
No controller, node agent or GPU runtime rollout was required. Login-dependent
interactive acceptance remains pending; the user has not yet replied to the
current sign-in request. Do not repeatedly request passwords or reset accounts.

## Portal remaining implementation — 2026-11-08

The remaining implementation rows in `docs/PORTAL_SIMPLIFICATION.md` are closed:
six operator lists now read server windows of at most 25 records, with minimal
personnel choices kept separately. Model/catalog search and empty publishing,
company ownership labels, service handoff references, app refresh and mobile
cards, keyboard table scrolling and shared dialog interactions are implemented.
Contract revision and multi-organization behavior reuse the existing authority
and native HTTP regressions; no second set of resource/permission rules was added.

Pagination pitfalls:

- Read-only POSTs must bypass mutation/reconciliation fences while retaining
  route-specific operator/audit authorization. Exclude them from operator
  mutation-audit writes, or reading audit pages immediately invalidates cursors.
- Audit traffic is append-only: pin the highest sequence during traversal so
  new inference requests cannot keep returning the operator to page one.
- Keep choice metadata separate from the visible account page. Replacing the
  entire personnel chooser with the current 25 accounts loses off-page users.
- No selected person intentionally returns no access milestones. Do not use
  that empty array to infer an empty platform or auto-open authorization forms.
- Requests are generation/query/person/session-bound; a stale response or an
  abort from an earlier search must not clear or replace the current result.
- Stores still scan in-memory snapshots; do not claim indexed database cursors.
  The savings are bounded projection, serialization, network transfer and DOM.

Dialog mechanics live in JS-only `ui/browser_interactions`, shared by both
portals. Cancel IDs are explicit; Escape/backdrop never activate confirmation.
Modal focus is trapped, nonmodal panels leave background navigation usable,
and closing restores the triggering control. Tables remain native HTML.

Automation pitfall: MoonBit `String::replace` replaces only the first occurrence.
Use `replace_all` for intentional repeated source edits, then verify the complete
match count. Linux native controller compilation can spend 10–15 minutes in
`cc1`; keep optimization flags and avoid overlapping native suites.

Production build baseline is the identity-checkpoint/profile-response controller
under `coffee-auth-queue-20261107/profile-final-control`, SHA-256
`7bef5632a0cabb04ed42020e9a5651bf3a2c2f105b416bcd823141671027b463`.
Do not rebuild from the older `native-glm-20261107/control` binary/source alone.
The reviewed source preserves both identity fixes; the account source differs
from that production baseline only in formatting. Release preparation is under
`/home/HwHiAiUser/portal-finish-20261108` and portal assets under
`/home/HwHiAiUser/portal-finish-shipped-ui-20261108`. Snapshots remain private on the
host. No production identities, orders, permissions, keys or GPU runtime settings
were changed for this acceptance.

Current browser limitation: the official `/user/` tab can be inventoried but
both documented tab-binding APIs return `browser.user is unavailable`. This is
not evidence of an expired account. Do not ask for repeated sign-ins or use a
demo as a replacement; preserve the separate production visual/interaction gate.

Release completed: strict native and JS checks pass, full native 1,970/1,970,
related JS 444/444, final native UI 189/189. Controller and both portals rolled
out successfully. All six list endpoints and their available next cursors pass
live read checks; selected-company-person access is scoped correctly. Original
business identity references remain present, service owner/node/runtime bindings
and states agree with the private baseline, and all five GPU workload deployment
UIDs/specifications remain unchanged. Audit-only checks must use the audit-token
reference, not a static operator token; browser platform-operator sessions retain
their existing role implication. No authentication policy was widened.

Current controller SHA-256:
`98725a6c27d9f26762a9c21e643120de1ef496f5e873587fa229d293f068e1f7`.
Public JS hashes: console
`f0823d9977470c7ef59cdc8e3ad0d646b88fc59726227a002e2432c18b636fc3`,
enterprise `52aa7e7413f878f06d2e293b3c5372bb19d6c80cfa3fff3a7ee541f8a0f5e23f`.
All three supported public sites return HTTP 200. Official browser interaction
and production business/failure drills remain distinct, unclaimed gates.

## GLM pair paused through the operator UI — 2026-11-09

The user explicitly requested pausing .178/.179 using the UI. In the official
`/mana/` deployment page, stopped `glm-5.3.flash` / `service:service-company-text`
once and accepted its existing stop confirmation. The operation completed with
an explicit stopped receipt; the service row now shows stopped and Start.
Both named resources remain spark-57f5-98a504ed (.178) and spark-368c-0f2ee8b2
(.179). Their fresh UI node telemetry shows 112.1/112.7 GiB available memory
respectively (previously 4.0/4.5 GiB), and 0% GPU utilization. This was UI-only
acceptance, not a shell/process-list inspection. No node power-off or scheduling
cordon was requested or performed. Qwen on .177 remains ready; MiniMax on .176
was already stopped before this action and was not changed.

Screenshot: `output/cluster-status-20261109/glm-178-179-stopped.jpg`. The official
management tab is retained as the deliverable. Do not restart the pair without
a subsequent user request.

## Official portal state/button acceptance — 2026-11-09

Fresh official tabs restored browser control; an old tab-binding failure does
not imply session expiry. After a reload, allow the existing session restore
to finish before requesting another sign-in. Both guojiaan and operator were
verified through the real portals. Detailed pass/blocker matrix is in
`docs/PORTAL_SIMPLIFICATION.md`, fourth round.

Pitfalls fixed: a failed console commerce operation cleared global loading but
left its nested commerce view busy; terminal orders still offered evidence
review and a rejection could revive a cancelled order; shared trial status
compared a newly read heartbeat against an older request-start clock. Review
now obeys order lifecycle/deadline while preserving completed idempotent
receipts. Heartbeat checks observe time after the snapshot, keeping the same
timeout, pool and active-state rules. Live .177 telemetry additionally showed
about three seconds of positive agent clock skew: status checks must use the
same existing future replay-window bound as signed heartbeat admission, not
reject every future timestamp. Far-future timestamps remain rejected; do not
adjust host clocks or enlarge heartbeat limits to disguise this mismatch.
Quote UI and API share capability blocker
selection; unrelated historical diagnostics remain nonblocking.

Stopped owned services retain existing-key QR access. Default application
launches exclude models the current snapshot marks unavailable. QR selection,
outside/Escape dismissal and restored focus were exercised live. Key and URL
copy were verified by private clipboard readback; no secret or QR payload was
written to the repository. Passive access-loaded banners and credential advice
on copying public values were removed; explicit action feedback remains.
No-pending lease approvals omit the node picker. Linked historical rental
documents show the ended order state and cannot offer machine allocation,
even if the retained packet has its own effective state. Do not conflate a
packet's document lifecycle with the parent order's resource authority.

One nonbinding rental draft was created, observed in both portals, then normally
cancelled with a receipt explicitly confirming no access was activated. The
signed commerce readiness document is not configured, and online GPU inventory
has no capacity; full commercial conversion cannot be claimed. GLM and MiniMax
remain stopped. Do not restart them to turn a blocked acceptance gate green.
The user subsequently confirmed keeping GLM stopped and limiting this run to
stopped-state buttons, connection configuration and error handling.
Real multi-company creation/invitation/switching remains a separate production
gate; fixture coverage is recorded separately.

The actual production controller/enterprise baseline had advanced to the
coffee-contact release. Preserve its signed phone-contact registration
compatibility (never accept unsigned browser contact headers), and build portal
layers on the active image, not the earlier image recorded in the third round.
The existing gateway and profile helpers must remain in the controller volume.

Workspace lease acceptance found 848 lease records despite only six active
leases. The local page now shows 25, searches the whole snapshot, prioritizes
requested/active work, and scopes the optional lifecycle graph to that page.
Page/search actions do not call the server cursor API; the existing full
workspace read is unchanged. Request/benchmark metric caveats are inside the
data disclosure; default UI no longer exposes ConsoleState implementation text.

After merging upstream phone/email registration support, final strict native
checks and the complete runner pass 1,982/1,982; related JS UI/command tests
pass 441/441. Isolation/public-response heuristics pass.
Production controller SHA-256 is
`623773f93a317a800baa1b3bd73b5c8a6e7545b5d006f3a6b0b6d755e2a41118`.
Native release root: `/home/HwHiAiUser/portal-acceptance-control-r2-20261109`;
final console root: `/home/HwHiAiUser/portal-acceptance-ui-r6-20261109`;
enterprise overlay root: `/home/HwHiAiUser/portal-acceptance-ui-r7-20261109`.
Both remotes advanced to `74c3f21` during acceptance. Merge that registration
update instead of force pushing. Its provider phone-contact implementation
agreed with the already deployed controller; the only API merge conflict was
the duplicate explanatory comment. Preserve the merged gateway and signup
behavior as well as the tested portal fixes.

The final merged-page reload exercised a real transient Unknown observation.
The desired state stayed stopped and the UI retained the service and blocked
recreation/start. Read-only checks of the configured tensorfold rank units on
.178/.179 showed loaded/inactive; both adapter and controller recovered Stopped
without any lifecycle mutation. Adapter status took 0.65–0.83 seconds and the
controller credential reference matched. Do not disguise observation failures
as stopped, widen timeouts speculatively, or restart a model to clear this state.

## 2026-11-10 — delivery authentication and operator model handoff

Live user IaaS refresh exposed a swallowed HTTP 401: optional delivery reads
converted it into a model outage and hid setup. Full reload confirmed the real
session had expired. Preserve 401 through every optional delivery read and the
outer catch; after generation/company/poll fencing, recover the shared cookie
using the existing rejected-token bootstrap. Never replay a lifecycle mutation.
403 remains an authorization error; stale failures must not sign out a newer
scope. Enterprise command regressions cover these distinctions.

The operator's access-package model CTA went to Catalog's new-deployment form
even for an existing stopped service. It now opens Deployments, retaining the
person/organization context and return action. Context does not claim to filter
the platform's deployment list or confer company access. Navigation does not
start, create or change a service. GLM remains stopped by the user's instruction.

Read-only production inspection found the mounted offline readiness Secret has
all ten historical entries but expired at 2026-10-23 19:28:07 Asia/Shanghai; both
readiness env references are absent from the active controller. The old README
missing-implementation inventory predates later retained production evidence.
Do not invent fresh legal approval, dismiss existing exact-scope approvals, or
renew technical attestations by changing timestamps. Requalify current inputs
before configuring a fresh bounded signed document. PdfRenderer versus
MoonLeafPdfRendererPending is enum versus diagnostic, not a schema mismatch.

Phase checks: info/fmt, strict native/JS, native 1982/1982, related JS 443/443,
both release bundles. No backend binary, production records, credentials,
resource ownership or model lifecycle was changed. Real new-company/multi-org
UI acceptance remains distinct from passing isolated native HTTP scenarios.

Both portal layers were released from the actual R6 console / R7 enterprise
bases under `/home/HwHiAiUser/portal-session-recovery-20261110`. Public JS hashes:
console `d04aa6223dcb16a51e2f0a5f9206fbab44b76f63284d7e225eb06590973fafed`,
enterprise `7c0697fd2a1190c20becc17269f1786f0573e752aa7f0a97d6f8db42e46d1b01`.
All three supported sites returned HTTP 200. Live operator session recovered
after reload; person→Deployments→person preserved guojiaan and showed GLM
Stopped with company-reserved nodes. Final read-only service state remains
desired=false / Stopped. User session genuinely expired and is at login;
post-release user-session browser verification awaits the requested login,
not a controller change or a claim that fixtures constitute that acceptance.
Screenshot: output/portal-acceptance-20261110/person-deployments.jpg (private,
uncommitted, no secrets). SSH/scp can transiently close at the jump host; a
bounded reconnect worked. No credential reset was needed.

Screenshot review then caught deployment buttons clipped at a 1036px desktop
viewport: the table's global 48rem minimum plus a 12% action column squeezed
the stop label; start also reused the stop danger class. The deployment table
now has its own 36rem minimum, fixed status/action widths and nonwrapping action
buttons. Only stopped managed services get the primary Start action; Stop keeps
its danger style and existing confirmation. No lifecycle condition changed.
Final phase checks pass native 1983/1983 and related JS 444/444. The final console
overlay is `/home/HwHiAiUser/portal-deployment-actions-20261110`, JS SHA-256
`a4d35619cecbce27b92ff4701e2c7bfa46323373c6e6089dda17516ab548d2cb`.
Enterprise remains the session-recovery release above.
Final official browser screenshot at 1036px confirmed tables 728px within 730px
containers and all action buttons 80x44px without wrapping or clipping. Start
is primary, Stop is danger; no lifecycle button was clicked. Final screenshot
is output/portal-acceptance-20261110/deployment-actions.jpg. Public digest and
all three site HTTP checks passed again after the final console rollout.

## Management networking inventory / planned dual-port card — 2026-11-10

User plans to install a dual-port NIC in the current management host: existing
connection should become 192.168.2.173, new ports .174 and .175. Inventory only;
no address, route, bridge, service, node identity or switch configuration changed.
Current .175/24 is assigned to br-ngfw-in, whose physical member is eni3
(Intel I210, negotiated 1000 Mb/s), not directly to the physical interface.
Default route is via 192.168.2.1 on br-ngfw-in. eni4 (negotiated 2500 Mb/s)
belongs to a separate br-ngfw-out with 192.168.133.15/24; preserve that network.
eni0 is a separate Intel I219-LM link, not br-ngfw-in's current member.
K3s node ubuntu InternalIP and Flannel public-IP both currently use .175.
Host services bind .175 at 5908 (GLM lifecycle), 5911 (business apps), and other
existing ports; retaining .175 on this same host avoids gratuitous endpoint
renumbering. Do not globally replace .175 with .173 or start paused GLM.

Before applying the planned move, identify the installed card's actual port
names/MACs and switch VLANs, verify .173/.174 allocation, provide persistent
configuration and rollback, and keep a working management connection during
the .175 handover. Three independent links in the same subnet need deliberate
source routing/ARP behavior; distinct IPs alone do not ensure distinct physical
egress paths. Do not bridge multiple switch-facing links together casually.

### Existing management link moved to .173 — completed 2026-11-10

User subsequently authorized moving the existing link now, before installing
the dual-port card, and supplied sudo authentication for this host. No credential
was stored in scripts, snapshots or this record. A temporary authenticated root
SSH shell was closed after the operation.

`/etc/netplan/01-network-dhcp.yaml` now persistently lists .173/24 first and
.175/24 second on br-ngfw-in. The existing gateway, DNS, eni3 bridge member and
separate br-ngfw-out/192.168.133.15 configuration are unchanged. .175 remains a
temporary compatibility/service alias until the new card arrives: K3s advertises
.175 and existing service binds/DNS/NAT can keep using it. This is not a complete
removal of .175. .174 has not been assigned. Do not globally renumber existing
service references or start the paused GLM pair as part of this work.

BusyBox duplicate-address ARP probes for .173 returned zero responses before
assignment. The root-only source backup is under
`/var/lib/lunanexa/management-network-20261110/netplan-before`. The only source
change was one added address line before .175. `netplan generate` passed and
`netplan try --timeout 120` applied it with timed rollback. A new SSH connection
to .173, HTTPS and all four worker pings succeeded before accepting the change.
`ip route get 192.168.2.176` now selects source 192.168.2.173. There was no reboot.

Local SSH alias `lunanexa-management` now connects to .173 and retains
`HostKeyAlias 192.168.2.175` to validate the existing pinned host key, not bypass
validation. Local config backup: `~/.ssh/config.before-network173-20261110`.
Fresh alias connection succeeds. Controller, identity, portals and Qwen remain
ready, Qwen health returns 200, internal HTTPS on .173:443 and external HTTPS
8443 return 200, and the business backend on .175:5911 reports ok. Both TensorFold
rank units remain inactive. All five intended cluster nodes remain Ready;
the pre-existing unrelated .180 stays NotReady.

NIC discovery baseline (three pre-existing physical PCI interfaces):
- eni0: MAC 00:30:18:17:83:a1, PCI 0000:00:1f.6, Intel 8086:1a1c, e1000e.
- eni3: MAC 6c:b3:11:72:9b:9d, PCI 0000:04:00.0, Intel 8086:1533, igb;
  the current 1 GbE management bridge member.
- eni4: MAC 00:30:18:17:83:a2, PCI 0000:06:00.0, Intel 8086:125c, igc_226;
  the separate 2.5 GbE outer bridge member.

Machine-readable baseline: remote
`/home/HwHiAiUser/management-network-20261110/nic-baseline-before-card.json`,
local `output/network-migration-20261110/nic-baseline-before-card.json` (0600).
It includes names, current/permanent MACs, PCI identities, drivers, MTUs, links,
bridge members, addresses, routes and policy rules, without credentials.
`scripts/management-nic-inventory.mbtx` provides read-only inventory/discover.
Its remote copy is beside the JSON. Run it with `discover BASELINE.json` after
installation, inspect new/changed PCI/MAC entries, then map and assign the two
new ports deliberately. Before the card, discovery correctly reports zero new
NICs. Native standalone check and execution pass; no product code changed.

Netplan pitfall: this host's older `netplan set --origin-hint` cannot round-trip
the existing empty Ethernet maps (`eni3: {}`, `eni4: {}`), and rejected its
temporary output because eni4 was omitted. It did not modify the source or
runtime. The exact one-line source edit and a complete diff against backup
avoided changing unrelated bridge configuration.

### Dual-port card installed and assigned — 2026-11-10

User confirmed installation, continuing the explicit .173/.174/.175 plan.
Discovery against the saved three-NIC baseline found exactly two new functions:
Intel X540-AT2 8086:1528, ixgbe, PCI 0000:01:00.0/.1. Brought their links up;
after autonegotiation both report carrier and 10000 Mb/s, MTU 1500.

Final persistent mapping:
- .173/24 remains on br-ngfw-in via existing eni3, MAC 6c:b3:11:72:9b:9d.
- .174/32 is on enp1s0f0, MAC 1a:4b:24:b4:24:83.
- .175/32 is on enp1s0f1, MAC 1a:4b:24:b4:24:84. It is no longer an alias on
  the old management bridge.
- br-ngfw-out / eni4 / 192.168.133.15 is preserved.

The /32 addresses deliberately avoid competing automatically connected main
routes for three independent NICs on the same LAN. Source rules 10174/10175
use tables 174/175, each with the LAN link route and .1 gateway. Management's
ordinary main/default path remains .173. Destination exceptions 10042, 10043,
10133 keep pod CIDR 10.42/16, service CIDR 10.43/16, and the existing outer LAN
192.168.133/24 in the main table, before source rules. Omitting these exceptions
initially sent source-.175 host-to-pod traffic toward the router; fixed before
acceptance. Preserve them in future routing changes.

`/etc/netplan/01-network-dhcp.yaml` is root-owned 0600. MAC matching identifies
the two new functions. ARP ignore=1 / announce=2 is configured only for these
two interfaces and br-ngfw-in in `/etc/sysctl.d/70-lunanexa-multinic-arp.conf`;
existing loose reverse-path filtering and every firewall rule are unchanged.
No bonding, extra bridge between switch ports, switch/LACP change, model
parameter change or GPU runtime restart was performed.

Backup is `/var/lib/lunanexa/management-network-dualport-20261110/netplan-before`,
with prior ARP values in `arp-before.conf`. Generated configuration was checked,
then applied with a 180-second netplan try. Fresh SSH on all three IPs, correct
source routes, gateway and GPU reachability passed. Configuration was accepted;
the cluster/outer-LAN rule exceptions were subsequently persisted, generated and
reloaded. A second explicit networkctl reconfigure confirmed addresses/routes
return from persistent configuration. Reconfigure is asynchronous: immediate
`ip addr` can transiently omit an address; wait for actual configured state.

Physical-path acceptance: .178's neighbor table maps .173 to the original MAC
and .174/.175 to their respective new MACs. Qwen health through each new source
returns 200; the business backend at .175:5911 reports ok. All four Spark nodes
and management are Ready. The host had rebooted for hardware installation
before this task; K3s now automatically advertises .173 and flannel.1 binds
local .173 on br-ngfw-in. No K3s identity/config change was needed this turn.
GLM TensorFold rank0/rank1 remain inactive. No inference test job was submitted.

The reboot also exposed existing missing normalized containerd image-name
references. Homepage/login pods were in CreateContainerError (`docker.io/library`
aliases missing although the exact image manifests existed). Restored aliases
only, using existing pinned manifests, for identity login-20261020, web
login-20261020-final, and acceptance identity reg3. No image rebuild, deployment
spec change or permission expansion. Both identity deployments recovered 2/2
and homepage 1/1; internal 443 and external 8443 now return 200 again.

Distinct pre-existing issue found, not changed: comfyui-public-proxy cannot bind
0.0.0.0:5005 because the existing user `moonmoon-rabbita-alpha.service` owns
127.0.0.1:5005 (python3). Proxy is CrashLoopBackOff; do not claim 5005 acceptance
or stop MoonMoon as part of NIC assignment. Core website/Qwen checks are separate.

Inventories before and after card configuration are saved remotely beside the
original baseline (`nic-after-card-before-config.json`,
`nic-after-card-configured.json`) and mirrored to local
`output/network-migration-20261110/`. Final Netplan and ARP settings are in that
local artifact directory as well. Root SSH session was closed; the supplied
sudo credential was not saved to files. Keep both baselines for future changes.

### MoonMoon removal / 5005 recovery / six 10GbE links — 2026-11-10

User explicitly requested removing MoonMoon, restoring video proxy, and checking
.174 through .179 for 10GbE. Disabled/stopped the exact user unit
`moonmoon-rabbita-alpha.service`, archived its unit file to
`/home/HwHiAiUser/management-network-20261110/removed-moonmoon/`, then reloaded
the user manager. Unit now not-found/inactive; its default.target autostart link
is removed. Release/application data was retained. This is a reversible service
removal, not deletion of project files.

Rolled only `lunanexa/comfyui-public-proxy` to clear the prior crash backoff.
It is now 1/1 Ready and owns 0.0.0.0:5005. The root UI, system_stats and queue
endpoints return 200, including a request from .178 across the switch. These
are transport checks, not a newly completed video generation.

All six requested LAN interfaces report 10000 Mb/s, full duplex, carrier 1:
.174 enp1s0f0 and .175 enp1s0f1 on management (ixgbe); .176/.177/.178/.179 each
enP7s7 (r8127). This verifies negotiated link rates, not measured end-to-end
throughput. .173's separate management port remains 1GbE. Machine-readable
evidence: local `output/network-migration-20261110/ethernet-link-audit.json`,
also copied beside the remote NIC inventories. No switch or GPU configuration
was changed for these reads.

Generation-path finding and pending decision: `/h3/v1/models` through 5005
returns 502 because the old `minimaxh3-fl2va` Service has no endpoints. Its
vLLM-style CPU public-workspace workflows are different from the currently
running `lunanexa/comfyui-h3-native` on .176 (ComfyUI port 8188, NodePort 30188,
Service 10.43.101.131). The active native engine has a separate workspace under
`/var/lib/lunanexa/comfyui-h3-native/workspace`; do not publicly repoint its raw
history/files by assuming it is the old anonymous public PVC. Existing personal
and public workspace separation remains a user requirement. Asked the user
whether to expose that native workspace on 5005 (would expose existing workflows
and videos without login) or keep the original public workspace separate.
No answer received at this checkpoint; do not claim full generation acceptance
or start old GPU runtimes while that scope is unresolved.

Read-only node-schema inspection script:
`scripts/inspect-video-node-schemas.mbtx`. An initial broad name filter produced
excessive native experimental-node output; it now prints only four exact core/
legacy node schemas. Standalone native check and formatting pass. Saved node
catalogs on management contain schemas only, not workspace history/prompts.

### 5005 native H3 without login — published 2026-11-10

User answered the explicit public-workspace question: users should not log in
to use 5005. Continued the disclosed native-workspace public route; no repeated
confirmation was requested. Public proxy now targets the existing native H3
Service on .176, not the empty legacy vLLM Service. Its UI, native queue, GPU
metadata, nodes and WebSockets are anonymously available. Comfy Cloud's optional
account button is not a prerequisite; browser showed an enabled Run control
without an account. No personal LunaNexa gateway/session policy was changed.

`scripts/route-public-comfyui-native.mbtx` updates only the proxy ConfigMap with
resource-version/value fencing, snapshots old ConfigMap/deployment privately,
and rolls only the proxy. Native GPU runtime, model/quality/concurrency settings,
old public workspace and private account workspaces are unchanged. The old
public workspace PVC is retained. `/view` and `/api/view` fall back to that
previous public service for a file absent in the native workspace. The obsolete
`/h3/v1/` block was removed; old vLLM graphs are not native graphs. Existing UI
tabs should refresh and use native H3 workflows.

Remote snapshots/verification root:
`/home/HwHiAiUser/public-comfyui-native-20261110`. Rollback is the same script's
rollback phase; no previous data or model files were deleted.

Acceptance: public domain `http://suanli.kechuangfuwu.com:5005/` returns 200
from the development machine without cookies/authorization. Direct LAN .175
is not routed from that machine, so browser verification used a temporary
loopback SSH forward; this is not a direct-LAN browser claim. Native browser UI
and templates loaded anonymously with enabled Run and 0 active jobs; the test
tab was closed. Screenshot: `output/public-comfyui-native-20261110/anonymous-native-workspace.jpg`.
Temporary local port 15005 tunnel was terminated after acceptance.

`scripts/verify-public-native-video.mbtx` verifies anonymous CUDA GB10 runtime,
native H3 node catalog and queue, then media byte ranges and ffprobe using the
existing ffprobe inside the native runtime container (none installed on the
manager). Native in-memory history/output had no retained video for this check;
an initial history-based check correctly failed. Selected a retained MP4 on the
old public PVC instead and tested its fallback route. Both /view and /api/view
return 206. Final ffprobe plus complete ffmpeg decode via the domain URL from
the Mac and through the proxy from the native container pass without errors:
H.264, 608x352, 20.04 seconds (`LunaNexa20s_00001_.mp4`, retained old public
file). An initial arbitrary `seg1` clip gave metadata but produced partial/NAL
errors in the external HTTP probe; it is not playback acceptance. Verification
now rejects ffprobe stderr as well as failure exit codes and requires full
error-free decode. Existing media was not rewritten to hide that result.
New generation was not submitted; do not report a fresh
native video generation success. Verification JSON is mirrored under
`output/public-comfyui-native-20261110/`. Both new standalone scripts pass
native deny-warn checks and formatting. No product contract/library changed.

## MoonBook content audit and release — 2026-11-10

Reviewed all 41 coursebook pages and complete English/Chinese projections against
50 tracked sources at d255f4f3479fc15dce693b9ac6c3dea98eed5775 plus the existing
dirty checkout. The previous September content, October evidence and README
revision disagreed. Only three old tracked sources had hash drift, but new
implementation and deployment evidence revealed many more stale claims. Hash
refresh is not semantic review. The evidence ledger now records complete
per-page/source/locale review coverage, with regression checks.

Corrected contact registration versus ownership verification, shared sessions,
16 MiB body versus 10,000,000-byte input budget and 524,288-token configured GLM
context, generic service/resource ownership, optional evaluation, multi-file
modelstore materialization, retained idle caches, personal versus public native
ComfyUI, hosted plugin boundaries, company review, storage/registry and commerce
activation. Historical UI campaigns/planning are dated; old disconnected
screenshots and validation-process details are advanced-only. The current
reference identity and runtime-qualification guides were corrected too. See
docs/COURSEBOOK_CONTENT_AUDIT_20261110.md for all page outcomes and recipe bounds.

Only the three data JSON files were published. The deployed HTML, JS, CSS and
images were retained exactly; baseline shell files also match local source.
Final image: moon/lunanexa-coursebook@sha256:b7081f214296856ab52f19343db140632e58ed40d6d40a43289a44378b09827d.
Remote release/rollback snapshots:
/home/HwHiAiUser/coursebook-content-20261110-r2 (preceding reviewed candidate),
and /home/HwHiAiUser/coursebook-content-20261110 (original production image
c855ac6e29131adf9a1d76f1d84fbb3007b7aca98a0c14735bae7f6f9c4b8146).
The UID/image-fenced patch changed only lunanexa-coursebook-public-gateway.
All six served assets match expected bytes over public 8443 and internal 443;
all three supported portal/doc routes serve HTML after rollout. No controller,
GPU runtime, authorization, model lifecycle or business record was changed.

Final data SHA-256:
- coursebook.json: 934890f89fafbd529405f065182f82f739e1ca00a6217ddf77761ef266eb6b08
- coursebook.zh-CN.json: f5fc19497bf1f0a1f1bd5cceb621ddc5f7d6ef6c31cebf37a1880cc36ab0c661
- coursebook-evidence.json: c2af875b775ef0508333353af3be9f014df9364c3bf3fb247fa98f45ce2e3dd1

Validation: info/fmt, strict native, native 1983/1983, documentation/diagnostic/
support-report 54/54, manifest renderer, minimal image-context tests, 15 shell
recipe syntax checks and source drift 0/50. The three data files are 324,161
bytes versus 346,045 before review (6.3% smaller); no new frontend request or
runtime cost was introduced. Unrelated AGENTS.md trailing spaces predate this
work; scoped diff checking passes. Public interfaces remain unchanged.

Official /docs/ browser checks covered desktop Chinese/English, 390px English
registration and Chinese workspace table, menu navigation, revised-limit search,
empty search, keyboard dismissal/focus return, advanced evidence and final
standard-mode disclosure. Body width equals 390px; the 580px table scrolls inside
its 356px container. Locale and viewport were restored. Native AX represents
the technical-notes button as a checkbox; DOM correctly exposes a button.
Use DOM role button when testing it. After viewport override, tab.screenshot()
shows the correct narrow rendering; the combined native screenshot wrapper can
show a scaled stale image. Copy displayed its success toast, but the separate
clipboard reader returned empty, so exact OS clipboard bytes are unverified.
200% text zoom, print/reduced-motion, optional live-guide success and current
authenticated customer workflows were not re-certified. No inference/video job,
credential redemption, payment, signature or destructive cleanup was executed.

## AI foundations course expansion — 2026-11-10

Expanded the existing MoonBook site from 41 to 60 bilingual lessons. Nineteen
introductory lessons now precede platform documentation in five sections: LLM
basics; prompt/context/harness/agent engineering, loops/RSI and multi-agent;
chips/clusters/engines/metrics/token factories; coding/AIGC/AI4S/other work;
industry and LunaNexa's narrow platform role. The new default `ai-start` gives
a simple 120-minute speaking route including examples, questions and a break,
plus a 25-minute short route. Durations are suggested, not measured learning
outcomes. Each lesson has practice, transfer and retrieval with a revisit time.
All 41 previous platform pages and their Chinese overlays are semantically
identical to the start-of-task snapshot; their existing URLs remain valid.

`docs/AI_FOUNDATIONS.md` records definitions, original toy examples, checked
primary references and the platform boundary. Educational application examples
do not assert live offerings. Managed inference nodes remain free of application
agents, MoonSuite products, domain data and application credentials; separate
workspace domains retain their existing boundaries. RSI is distinguished from
retry/self-critique and bounded code search, and aggregate token throughput is
distinguished from individual latency and useful accepted work.

All 60 bilingual pages have review coverage; the evidence ledger has 51 source
digests. Its original content-audit report still describes the original 41-page
review, while the curriculum source describes the 19-page expansion. Independent
subject-matter review and representative beginner comprehension testing were
not performed and are explicitly recorded as missing evidence. No simulated
human comprehension result is claimed.

Authoring/release evidence is under `output/ai-foundations-20261110/`: five
lesson payloads, deterministic `assemble.mbtx`, semantic preservation and raw
byte measurement in `verify-content.mbtx`, before/stage snapshots, and a fenced
content-only `release.mbtx`. The three JSON assets grew from 324,161 to 457,722
raw bytes (+133,561). No new frontend code, image, CDN dependency, request path
or backend service was introduced. Release preserves the deployed shell and
image layers, changing only the three documentation JSON assets.

Published documentation image:
`moon/lunanexa-coursebook@sha256:e1502b1c48d870e1f1793304d7409f81d7625c311127ae6f46e13f93ad627897`.
Deployment UID/prior-image tests fenced the single docs-image replacement;
rollout completed. All six staged assets match exact bytes on public 8443 and
internal 443, and `/user/`, `/mana/`, `/docs/` serve HTML. No inference runtime,
GPU allocation, portal deployment or customer business state was changed.

Validation passed: 55 documentation tests; all 51 source digests unchanged;
15 existing shell recipes pass `bash -n` without execution; `moon info`,
`moon fmt`, native deny-warn check and all 1,983 native tests. Scoped whitespace
checking passes and public MoonBit interfaces remain unchanged.

Official browser acceptance covered the new default Chinese desktop route,
English translation, concept search and navigation to the latency lesson,
390px English metric-table overflow, mobile menu navigation, Chinese opening
flow and retrieval-answer disclosure. Body width is 390px; the 580px metric
table scrolls in its 356px container. Restored Chinese and default viewport.
The course tab is retained as a deliverable. 200% text zoom, print and independent
audience testing remain unverified; no backend/model capability was exercised.

Pitfall: the previous compact helper locates locale objects by a key prefix.
Reusing a group slug as a page slug (`ai-industry`) makes it match the navigation
string before the page object and corrupt the locale structure. Checks caught
this before release. Rebuilt from the saved baseline and use the new assembler's
separate evidence formatter; do not run the old compact helper on this expanded
book. Regression checks require both complete bilingual pages and string-valued
navigation labels. Browser screenshots captured immediately after a viewport or
locale action can show the previous frame; inspect the resulting DOM and take
a subsequent screenshot to judge the actual layout.

## Classroom rewrite after user rejection — 2026-11-10

The user explicitly rejected the first AI introduction as unsuitable for a
classroom and too AI-written, then instructed: remove all hardening from the
introduction. This is a durable editorial requirement. Do not put permission,
acceptance, risk, SLO, readiness, platform-boundary disclaimers or engineering
review checklists back into introductory teaching. Do not reuse the repeated
practice/transfer/checkpoint/revisit template. The user's teaching direction
overrides those defaults in the MoonBook skill. Actual application controls and
the original platform operation guides were not changed.

Rewrote all 19 new lessons in both languages around a weekend-planning
conversation. Start with familiar events, explain them, then introduce names.
Tokenization uses pieces and IDs; next-token prediction uses sentence completion;
training/context uses learned ability versus a desk of materials; harness uses
weather-tool calls; loops use writing/running/changing code; multiple agents use
travel-planning division of work. Chips use a kitchen analogy and latency versus
throughput uses a coffee shop. Applications begin with actual kinds of work:
packing-list software, creative media, protein prediction and meeting notes.
The final platform page simply places LunaNexa in the picture. Main content
contains no hardening passages or workbook templates. The two-hour and short
speaking plans are advanced-only; the opening starts directly with a conversation.

Updated `docs/AI_FOUNDATIONS.md` to record this teaching approach and sources.
Retained all original 41 platform pages and Chinese overlays unchanged.
`output/ai-classroom-20261110/` contains the rejected-version snapshot, five
replacement payloads, assembly/preservation scripts and content-only release.
Combined JSON size is now 407,821 raw bytes, down 49,901 from the rejected
version. Shell assets and backend services are unchanged.

Published image:
`moon/lunanexa-coursebook@sha256:493f04e5a1b8f78c336fde3070d57906580b8287a12503e7a4d00109652abaa3`.
Documentation rollout completed. Six assets match staged bytes on external
8443 and internal 443; all three supported routes serve HTML. Passed 55 docs
tests, 51 unchanged source digests, native info/fmt/deny-warn and 1983 tests.
The curriculum regression now enforces absence of hardening/workbook blocks
and keeps the speaking schedule out of the normal opening.

Official browser showed the new Chinese desktop opening, Token explanation,
English translation and 390px Chinese typography with no body overflow. Restored
Chinese, default viewport and the new opening; retained the tab. No live
classroom trial was performed. Do not describe automated checks as teaching
quality or claim the user has accepted this rewrite.

## Animated classroom projection and full author walkthrough — 2026-11-10

User asked to go through the whole course as a teacher, make it directly
projectable, use concrete examples and diagrams, start immediately and avoid
small talk. They additionally required animation. Do not return to documentary
prose, decorative motion or the earlier hardening/workbook templates.

Added a projection view inside the existing MoonBook `/docs/` site. The normal
AI chapter header has “开始上课” / “Start presentation”. Direct entry:
`/docs/?view=lecture&page=ai-start`. It has 43 content screens plus a break and
questions (45 total), with a 120-minute speaking plan. Slides are manual;
animations have play/pause, next step and restart. Arrow keys turn slides,
Space advances a diagram, Escape exits. Speaker notes are separate from the
audience canvas. Chapter selection, both languages, refresh/deep links and exit
to the corresponding book chapter work. The initial screen directly shows
translation, summary and coding inputs/outputs; the travel-chat warm-up is gone.

Visuals are native SVG/DOM: token pieces/IDs, probability bars, autoregressive
feedback, context/tool paths, parameter updates, agent/RSI cycles, parallel-time
bars, latency timeline, batching, code/output, denoising and protein ribbon.
Motion explains data movement or changing values; it is finite and started by
the user. Animations stop when leaving a figure/view or hiding the document.
Reduced-motion CSS is included. No external runtime, CDN, font or model call
was added. Projection normally shows title, visual and one conclusion; detailed
explanations and transitions live in bilingual speaker notes.

Permanent content authoring: `scripts/build-ai-lecture.mbtx` produces
`docs-site/ai-lecture.json`; `scripts/sync-ai-coursebook.mbtx -- RFC3339_TIME`
updates the 19 book chapters, localized projections and evidence hashes.
The normal book reuses the same visuals. Chinese diagram overlays inherit the
bilingual canonical visual to avoid duplicate data. All original 41 platform
chapters and Chinese overlays remain semantically unchanged. The source ledger
now has 52 entries. Authoring rules/references are in `docs/AI_FOUNDATIONS.md`.

Completed an author walkthrough of every one of the 45 Chinese screens: opened
notes and advanced every diagram stage in order. Also walked all 45 English
screens. Found and fixed English label overflow on RAG, factory, scientific
search and recap screens; rechecked the four corrected screens. Fixed blank
code-line rendering, duplicate SVG marker IDs, stale slide URL parameters,
language-specific region names and static “10:00” that resembled a countdown.
Actual playback reached its final stage and stopped; pause held its stage;
restart, manual steps, Space, arrow keys, reload, exit and re-entry were checked.
This is author rehearsal, not a live two-hour audience trial. Do not claim
measured classroom comprehension or that the user has accepted the result.

`output/ai-projection-20261110/REHEARSAL.md` records the sequence and findings.
The output directory also holds before/stage snapshots, preservation checks,
test logs and release tooling. The classroom JS/CSS plus lazily fetched deck are
about 200 KB raw. Deck data is fetched only when entering projection. Current
figures have a few hundred nodes at most; there is no infinite animation or
background polling. No backend, model runtime or GPU resource was changed.

Updated both coursebook container packaging paths and optional browser-layer
assets so the viewer and deck ship together. Fixed versioned asset URLs to
avoid stale JS/CSS after refresh. Browser-layer helper retains compatibility
with historical staged bundles that lack the optional new assets.

Published documentation image:
`moon/lunanexa-coursebook@sha256:05c42cd25ef8b792d9a0f10b46d56f1fe2eca634d3805cbf7f3d0ebadfd345e8`.
Rollout completed. Nine assets match staged bytes on external 8443/internal
443; all three supported portal routes serve HTML. Passed 59 documentation
tests, minimal image-context tests, native info/fmt/deny-warn and 1,983 native
tests. Source drift is zero. Public MoonBit interfaces are unchanged.

Official-site browser checks covered entry from the book, probability playback,
parameter-update values, denoising animation, English latency timeline and
390px controls. Body remains 390px; wide figures scroll inside their viewport.
Restored Chinese/default viewport, retained the official first-screen tab and
closed the local rehearsal tab/server. No 200% text/print or real audience
trial was performed. Use “43 content slides and a 120-minute plan”, not an
assertion that an actual two-hour class was delivered.

## Public lecture research and original teaching art — 2026-11-10

User rejected the projection as too basic and explicitly asked to search other
public lecture designs, then revise. Inspected Li Hung-yi's actual introductory
PDF pages 7 and 17 (downloaded/rendered), 3Blue1Brown's GPT prediction image,
Jay Alammar's token/vector diagram, Transformer Explainer's interface and
Google PAIR's controlled-input explorable. Exact primary links, inspected
scope and derived decisions are in
`docs/AI_TEACHING_DESIGN_REFERENCES_20261110.md`. Do not claim to have studied
Stanford CS25 slide designs; its lecture links were found, not inspected.
No third-party artwork, slides or prose were copied.

Added `lecture-studio.js/css`: original SVG documents, model layers, editors,
GPU/memory/data buses, racks, queues, café denoising panels, video frames/audio
timeline and protein ribbons. Semantic colors and stable object positions
connect stages. Replaced the shared giant comparison boxes with ruled columns.
Three teaching experiments calculate actual results: temperature normalization
and sampling, gradient updates of y=w*x with MSE, and JavaScript default versus
numeric sorting. These are small teaching examples, not connected model runs.
Training's bilingual slides and notes now match the worked numerical example.
Normal book figures reuse the same new art. No hardening/workbook boilerplate
was restored; retain the user's direct classroom style requirements.

Walked all 45 Chinese and 45 English screens, advancing every diagram stage.
Found and fixed an English Output-label overflow; rechecked the corrected SVG
inside the visible lecture canvas. Important pitfall: querying the first SVG
without scoping to `.lecture-canvas` reads the hidden underlying book figure
and gives false projection geometry. Checked real temperature/sampling,
continued training (MSE falls 10.50→2.99→0.85), code execution, notes and playback
termination. Mobile keeps figures horizontally scrollable, as before. Restored
default viewport and Chinese. This is author review, not audience acceptance
or a measured two-hour class.

All 41 platform chapters/localizations remain semantically unchanged. There
are 54 source entries and zero drift. Passed 61 documentation tests, minimal
image-context checks, moon info/fmt/strict native and 1,983 native tests. Public
MoonBit interfaces unchanged. New studio JS/CSS are 40,478 raw bytes; total
classroom assets including the lazily fetched deck are 242,941 raw bytes.
No external fonts, CDN runtime, model weights, backend or GPU load were added.
Updated every documentation packaging path to ship the studio module/styles
before the viewer; versioned URLs prevent stale cached assets.

Published image:
`moon/lunanexa-coursebook@sha256:226ee8d16ac979e4a4fa01eee5ea90bafdab1b4665d9820532b63f1f66b20a2f`.
Rollout succeeded. All 11 assets match staged bytes on external 8443 and internal
443; all supported routes serve HTML. Official browser verified probability,
training, GPU and video scenes and language switching; no console errors.
Retained `/docs/?view=lecture&page=ai-start`, closed local preview and server.
`output/ai-studio-20261110/` holds prior snapshot, reference PDF renders, test
and release logs plus `public-gpu.jpg` and `public-video.jpg` screenshots.
Do not describe passing tests or publication as the user approving the design.

## Second lecture-design research and revision — 2026-11-10

User requested more examples and another revision. Added actual inspection of
five works: Anthropic's coding-agent swimlane image, Hugging Face's continuous
batching image, UW CSE599K serving PDF pages 10/11 (downloaded/rendered),
Diffusion Explainer (including timestep slider), and Bycroft's nano-gpt overview.
Separately read DeepMind's GNoME description to check scientific feedback.
Extended `docs/AI_TEACHING_DESIGN_REFERENCES_20261110.md` with precise inspection
scope, links and applied ideas. No source artwork is included in the website.

Rebuilt eight scenes: weather-dependent agent choices, fixed/dynamic workflows,
three distinct objects of improvement, hypothetical RSI version chain,
coding-agent message swimlanes, concrete multi-agent product handoffs, calculated
batch scheduling, and scientific candidate scatter/observations. Diffusion also
shows its text condition; café video frames use progressive camera cropping.
Added two-slot decode-only scheduling computation and a weather-result selector.
The former compares identical lengths [2,4,1,3], yielding 7 versus 6 rounds and
ten tokens each. The latter chooses between two prepared explanatory paths,
not a connected autonomous agent. Fictional/scientific values are identified.
Updated matching bilingual notes; keep the user's ban on introductory hardening
and repeated workbook templates. Original 41 platform chapters remain unchanged.

Walked 45 screens in each language and every diagram stage. Actual screenshot
review found overlapping branch labels and collapsed spaces between science
table values; fixed with separate label positions and independently placed
table columns. SVG collapses multiple ordinary spaces: do not align columns by
padding a text string. Rechecked both corrected scenes. Tested third-round
counts (5/10 vs 6/10), completion, reset, normal-step synchronization, weather
switching and 390px controls. Wide mobile figures still scroll internally.
This is author review, not a real audience trial or user acceptance.

Passed 62 docs tests, image-context tests, moon info/fmt/strict native; no public
MoonBit interface changes. Source drift zero across 54 entries. Full native run
was **1981/1983**, failing operator_reads_wbtest.mbt's reconciliation read test
(401 vs 200) and trial_key_repair_wbtest.mbt's legacy trial-key test
(AccountError.Unauthorized). Isolated sequential rerun of those two files passed
**5/5**. Their fixtures use 60-second credentials; load/timing is a plausible
cause, not proven. No auth/backend files were modified. Do not claim the full
matrix passed. Preserve both full and retry logs. Contract preview computation
made the full run slow under current host load; the process was progressing.

Published docs image:
`moon/lunanexa-coursebook@sha256:5828a816f9f74803855fdd52385bf04d910a51d31a1e33324c2df78a284ace0c`.
All 11 resources match exact staged bytes on external 8443/internal 443, and all
supported routes serve HTML. Fresh remote release directory ends in
`ai-studio2-20261110-final`; an earlier prepared candidate was superseded before
publication by screenshot corrections. Local release helper points to final.
Official browser checked scheduling, weather choice and corrected English
scientific table; no console errors. Restored Chinese/default viewport and
retained the course opening; closed localhost tab/server.

Evidence is in `output/ai-studio2-20261110/`, including REVIEW.md, references,
logs and public-batching.jpg/public-agent.jpg. Classroom assets total 255,811
raw bytes, up 12,870 bytes from the first studio release, with no external
runtime/model download, polling or GPU/backend load.

## 2026-11-10 — Local build disk cleanup

The Mac data volume had only 1.3 GiB free; the management server was not full
(96 GiB free). The largest recurring source was accumulated MoonFish installed
payloads in both the Desktop app workspace and `/Users/kq/moonsuite`, alongside
regenerated compiler/script caches. Removed 559 obsolete payloads and 583 unused
cache directories; the Mac had 49 GiB free after cleanup. Concurrent LunaChip
and LunaFlux native test builds were left running and continue writing output.

Preserved active MoonFish 0.22.358, rollback payloads 0.22.357/0.22.356, original
pack manifests/receipts/uninstall notes at their canonical paths, product data,
models, and running app resources. Do not treat MoonRobo `target` (experiments
and checkpoints), LunaFlux `_build/models`, or active LunaChip hardware output
as disposable compiler caches. MoonDesk runs directly from its native build
and UI dist paths; preserve those while live, and preserve primary native CLI
build outputs for cold launches.

Reusable standalone tools are `scripts/clean-local-build-caches.mbtx` and
`scripts/prune-obsolete-moonfish-builds.mbtx`, each accepting `report` or `clean`.
They inspect live references and recent files; the pack helper also fences the
active pointer and retains provenance. No automatic retention schedule was
installed. Private manifests and receipt backups are under
`output/build-cleanup-20261110/`; post-clean MoonFish report found zero eligible
payloads. Both helpers passed formatting and standalone native deny-warn checks.
MoonDesk 4199/4200, MoonFish 4318/4319 Paiwork UI, and public video 5005 returned
HTTP 200 after cleanup. No product source or remote service configuration changed.

## 2026-11-10 — Automatic local build retention

User authorized hourly automatic pruning. Codex heartbeat `automation-2`, named
`旧构建自动清理`, is ACTIVE with failure-only notifications. It runs
`moon run /Users/kq/Workspace/lunanexa/scripts/maintain-local-builds.mbtx clean`.
This is a local Codex scheduler task: Codex must be running on this Mac; there
is no separate launchd daemon. No remote cluster cleanup is authorized here.

The historically named `prune-obsolete-moonfish-builds.mbtx` now reads all Moon/
Luna active pack pointers in the Desktop/home stores and top-level Moon/Luna
Git workspaces. Retain the active release plus two latest complete older
installed releases, using numeric three-part version order, not patch-number
subtraction. Metadata-only previously pruned directories are not rollbacks.
Unknown/prerelease versions and versions newer than current are untouched.
Running references and builds changed in the past 24 hours are additionally
protected; active pointers are rechecked during removal. Canonical receipts,
manifests, uninstall notes and unknown/data directories remain untouched.

Cache cleanup now defers while compiler/build-tool processes are running and
rechecks immediately before deletion. Retains primary native build outputs,
LunaChip, model/experiment directories, tracked files, live references, and
everything modified within 24 hours. OS advisory lock prevents overlapping
maintenance and releases on exit/crash. New generated manifests live under
`~/Library/Logs/MoonSuite/build-retention/` and expire after 30 days; earlier
manual cleanup evidence in `output/build-cleanup-20261110/` is retained. Less
than 20 GiB free after safe cleanup raises a failure for notification, rather
than deleting protected content. This cannot cap growth of ongoing builds or
other user data; a low-space alert still needs investigation.

Validation: standalone native deny-warn checks, scoped `moon info` and format
passed; self-tests cover gapped/cross-major versions, no older versions, invalid
versions, real payload deletion, repeat runs, preserved receipt/user data,
changed active pointer, symlink rejection, compiler exclusion and overlapping
locks. A real clean took 4.59 seconds: after another workflow published 0.22.359,
it retained 359/358/357 and removed two obsolete 356 payloads (381096 KiB).
Cache cleaning deferred because live MoonBit/hardware compilation was detected.
No compiler, service, deployment or model was stopped or changed.

Schedule correction: user's latest request is once daily. `automation-2` now
runs every 24 hours, with the same retention, live-build protections and
failure-only notifications. Earlier hourly/half-day schedules are superseded.

## 2026-11-11 — Whole-course teaching and animation revision, round 3

User requested more reference collection and a complete teacher-style rehearsal,
not isolated page changes. Revisited original Distill attention diagrams, MLU
Explain neural-network/error diagrams and Jay Alammar's GPT-2 output animation.
TensorFlow Playground was read as a primary reference; its browser page did not
load successfully, so no interactive inspection is claimed. Research scope and
design decisions are in `docs/AI_TEACHING_DESIGN_REFERENCES_20261110.md`.

All 43 content scenes now have explicit bilingual stage speech, causal motion
and a spoken bridge in `docs/ai-class-storyboard.json`. The build validates exact
scene/stage coverage. Examples include numerical attention weighting, jointly
changing training slope/residual/MSE, shifted next-token training pairs, cache
reuse through prefill/decode, actual GPU dot products, diffusion update feedback,
audio/transcript/field-table/software handoffs and concrete classification,
forecasting and route-planning examples. Original artwork remains locally owned.
Fuller background notes are collapsed; current speech follows the current stage.

Playback uses finite requestAnimationFrame movement, writes, quantity growth,
path drawing and numerical updates. Pause/resume retains exact progress and
stops when hidden or unmounted. Rehearsal caught and fixed stale animated values
overwriting manual input, missing Pause labels after manual advance, internal
diagram overlaps, a route crossing obstacles and a symbolic 21-token drawing in
the 101-token/100-gap explanation. Counted examples now match their arithmetic.

Author rehearsal covered all 45 screens in Chinese and English (90 total),
including notes, every stage and bridges. All ten contact sheets were visually
reviewed; no desktop SVG text overflow or vertical canvas scroll remained.
This is author rehearsal, not a real audience trial or a two-hour timed class.
Full evidence is under `output/ai-course3-20261110/rehearsal/`; the index is
`output/ai-course3-20261110/REHEARSAL.md`. Official-site training screenshots also
produce `output/ai-course3-20261110/public-training.gif` (960x540, 3.10 seconds,
479206 bytes). Verified pause at progress .229 (w=.66/MSE=8.38), resume to
w=1.20/MSE=2.99, then another update to w=1.57/MSE=.85; attention swap, sampling
and continuous batching also retain correct interactive state.

Validation passed: 64 documentation tests, minimal image context, moon info/fmt,
native deny-warn check and full native suite 1983/1983. All 41 original platform
chapters and both localizations were preserved; 56 tracked sources have zero
drift. Public .mbti interfaces are unchanged. Classroom assets total 398030 raw
bytes (+142219 from round 2), with lazy lecture data loading, finite animation,
no new dependencies, external assets, polling or backend inference cost.

Deployed image:
`moon/lunanexa-coursebook@sha256:e6e1151c9c718d8c193c4f940f30e0d7b729f800aca6c86ebcb438e0e43b9d79`.
All eleven assets match staged bytes through external :8443 and internal :443;
all supported /user/, /mana/ and /docs/ routes serve HTML. Official browser checks
covered classroom entry, attention/notes, diffusion, training, English cache and
390px layout with no console errors. Kept the official course tab, restored its
Chinese opening/default viewport, closed the temporary preview tab and stopped
the local preview server. This does not imply user acceptance or audience testing.

## 2026-11-11 — Beginner comprehension walkthrough, round 4

User requested a complete zero-prerequisite audience review: unexplained terms,
missing reasoning steps and diagrams/animations whose mechanism cannot be
followed. All 43 content scenes received new bilingual stage explanations and
bridges. `docs/AI_BEGINNER_WALKTHROUGH_20261111.md` records the specific gap and
correction for every page; it is now a tracked coursebook source. The storyboard
also owns optional bilingual title/lead/key/caption/stage-label overrides, which
the builder validates. The 19 chapters, 120-minute plan and original 41 platform
chapters plus Chinese localizations are preserved (semantic comparison passed).

Teaching changes include removing Token/context/harness/engine/GPU jargon from
the early three-layer figure; explaining IDs and vectors before using them;
defining probabilities/sampling/temperature; splitting attention multiplication
and entry-wise addition; replacing anonymous x/y regression with quantity,
unit price and total; labeling predictions, target points and the changing error
formula; defining the app/tool/harness/agent sequence and all requested engineering
terms; defining bit/byte/FP16/quantization/cache before storage arithmetic; showing
prefill A/B/C cache reuse followed by appending D; introducing three arrivals/two
gaps before 101/100; defining slots/A1 and the decisive third batching round;
showing a diffusion cell's 0.60-0.20=0.40 update and decode separately; using a
single protein chain; labeling scientific axes and candidate-selection reasons;
and correcting the final diagram's hardware support versus response path.

Playback now plays only the current step and holds the result and explanation.
It never automatically advances steps. Future SVG groups are fully hidden.
Compute animations have mechanism-specific finite durations; batching unfolds
over 8.4 seconds and retains the manual one-round button. Sampling now actually
selects on reaching the selection stage; its cue follows the sampled result and
current probabilities. The next slide explicitly fixes blue as a teaching example
so a preceding gray/dark draw does not contradict the transition. Attention motion
calls computed weights proportions, rather than confusing them with learned
parameters. No introductory hardening or repeated exercise template was added.

Rehearsal: Chinese 45 screens and English 45 screens, 274 stage explanations,
notes and bridges; ten contact sheets visually inspected. No recorded desktop
text overflow or canvas scroll. This remains author review, not a real audience
trial or two-hour timed delivery. Local whole-course screenshots/step text are
under `output/ai-course4-20261111/rehearsal/`; final focused production checks are
in `public-checks.json` there. Final checks explicitly cover late sampling,
attention and diffusion corrections in addition to the complete walkthrough.

Official-site checks confirmed first-step playback still at step 1 after five
seconds; temperature 2 changes bars to widths 189.09355/133.70933/77.19712 (sum
400), percentages and actual selected-token explanation agree; swapping attention
weights gives [0.20,0.80]; training moves w=.50 to1.20 with error10.50 to2.99,
then another step reaches1.57/.85. Both languages' new diffusion/grid cell and
English cache explanations were inspected; book exit/re-entry works and captured
browser console errors are empty. Kept official tab2 at the Chinese opening,
closed preview tab11 and stopped local preview server50338; no viewport override
was applied in this round.

Validation: all 64 documentation tests and minimal image-context test pass;
moon info/fmt, native deny-warn check and full native suite1983/1983 pass. Public
.mbti files are unchanged. Source drift is0/57. Classroom assets total441062 raw
bytes (+43032 from round3); all eleven updated static files total986113 raw bytes
(+62393). No new dependency, external media, model calls or polling; lecture data
remains lazy-loaded and animation stops on pause/hidden/unmount.

Published and verified image:
`moon/lunanexa-coursebook@sha256:936f7b2f8353ecaf3bd6aa88dfb5aa77e7dbac481152e5a089de871fa7e942d8`.
All eleven assets match staged bytes externally on:8443 and internally on:443;
supported /user/, /mana/, /docs/ routes serve HTML. Release, validation and byte
comparison logs are in `output/ai-course4-20261111/`. An actual production training
recording (69 captured frames over2665ms) is exported as `public-training.gif`
(960x540,4.31 seconds including holds,1059049 bytes); `public-diffusion.jpg` shows
the final diagram. These artifacts are evidence, not new website dependencies.

Rehearsal pitfalls: local server JS/CSS responses cache for300 seconds, so a
normal reload can retain an earlier same-version script during iterative editing.
Use a fresh asset version for releases and inspect final late changes on the
official origin; do not infer runtime freshness from new JSON alone. Screenshot
bytes from this browser are JPEG even when a caller chooses a .png filename;
rename according to the actual encoding before ffmpeg contact-sheet decoding.
The final storyboard JSON is the editing source; historical output helpers are
not prerequisites and should not be blindly rerun over later authoring changes.

## 2026-11-11: fifth classroom rehearsal and searchable directory

Completed the user's full-class teaching simulation request and subsequent
request for a listing page. Every one of 43 content scenes now has an individually
authored bilingual opening, three answered beginner questions (why, how, link),
a concrete demonstration and pause, and optional details to shorten if behind.
The authoritative new source is `docs/ai-class-rehearsal.json`; the builder copies
its teacher material separately from audience-facing stage explanations. The
129 questions are on-demand substitutes for explanations, not extra material to
read in full on top of the two-hour talk. Corrected probability provenance,
training versus language targets, attention weights versus learned parameters,
tool-description origin, workflow branching versus model-directed actions,
multi-agent contexts, cache causality, throughput versus individual wait,
diffusion training, and science feedback. Added actual parameter update arithmetic,
pretraining probability example, GPU operands, tool description, and cache labels.

`scripts/rehearse-ai-class.mbtx` estimates speech in both languages, reserves
demonstration/processing/questions/transitions, and rejects overfull segments.
The first pass found 18 overfull scenes; revised repetitions and openings. Final
content checkpoints are 26,50,87,108,115 minutes, with break50–60 and questions
115–120. Normal CN210 units/minute and EN135 words/minute yield2920 seconds of
speech,692 seconds of margin,800 seconds of optional details. Slower CN180/EN115
and a separate six-extra-minute-question simulation recover at checkpoints using
declared optional cuts. These are author planning estimates, not a measured
two-hour class or evidence of learner understanding. Summary:
`docs/AI_CLASS_TEACHING_REHEARSAL_20261111.md`; full page-by-page report:
`output/ai-course5-20261111/TEACHING_REHEARSAL.md`.

Added `?page=ai-course-map`: five topic groups,43 concept entries, bilingual/NFKC
keyword matching, exact book figure anchors, and exact presentation slide links.
The classroom Contents dialog uses the same outline, pauses animation, restores
focus on close, and can jump or exit to the matching book figure. AI chapters also
link back to the directory. It is not a forced opening slide. Counts are now61
bilingual book pages:19 teaching chapters+one directory+41 original platform pages.
All41 original pages and their Chinese overlays match the pre-round snapshot.

Browser verification walked all45 screens in both languages and expanded all129
questions per language; evidence is `browser-teacher-walk.json` under the output
directory. Inspected changed training/pretraining/tool/cache/diffusion drawings;
tested CN/EN search, fullwidth RAG, no results, direct Read/Present, dialog Escape
and focus, and classroom exit to book. At390px the directory has43 rows and no
document horizontal overflow; modal remains usable. Viewport override reset.
Fixed pale inherited text on the speaker-note paper and stale browser titles
after classroom navigation. Final static cache version is20261111-course5-3.

Checks:66/66 docs tests, minimal image-context check, moon fmt/info, native
deny-warn check, and1983/1983 full native tests pass. Public .mbti files unchanged.
Source drift0/58. Final evidence review time2026-11-11T05:18:50Z. Classroom assets
636060 raw bytes; all11 changed assets1196913 raw bytes, +210800 from round4.
Lecture JSON gzip size111943 bytes versus67764 previously (compression estimate;
not a claim that the current server sends gzip). No new dependency, external
search service, model calls, polling, or media assets; deck remains lazy loaded.

Published and verified content-only image:
`moon/lunanexa-coursebook@sha256:4de93e823a06ca1ef6688301a79d7629d5d9ae2b61690f47b81408143a15431f`.
All11 assets match staged bytes externally on8443 and internally on443; supported
/user/, /mana/, /docs/ return HTML. Official tab2 verified actual new directory,
teacher questions/pacing/contrast, training arithmetic, bilingual cache labels,
and directory-to-class-to-book navigation; console errors empty. Kept it on the
Chinese directory. Closed preview tab12 and stopped local server48408. Official
proof screenshot: `output/ai-course5-20261111/public-course-directory.jpg`.

Pitfall: book deep links scroll on requestAnimationFrame with smooth behavior;
an immediate bounding-box read can precede the scroll. Observe the settled screen
before diagnosing broken anchors. The RAG second-figure anchor settles at132px
below the fixed header. Keep rehearsal/storyboard JSON authoritative; historical
output authoring helpers overwrite later refinements if rerun blindly.

## 2026-11-14 — /lead 4K exhibition carousel

User-requested collage split and static display published at `/lead/` with a
port-preserving `/lead` redirect. Source and maintenance notes are in
`public-site/lead/README.md`; source crops, ZIP and live 4K screenshot are in
`output/lead-20261114/`. Deterministic crop helper removes the door/fire gaps
and measurement labels without regenerating text or photographs.

Isolated `lunanexa/nexai-lead-display` Deployment, Service and IngressRoute use
the existing qualified homepage NGINX image, management node `ubuntu` (.173),
read-only static release `/home/HwHiAiUser/lead-display-20261114-r1/site`.
Receipt and complete manifest are in its parent directory. Homepage and GPU
services were not modified. Browser verified 3840×2160 and 375×812, all three
images, manual switches, pause/play and automatic 20-second advancement, no
horizontal overflow or console errors. Fullscreen control changes state.
Asset SHA256 matched external served bytes; internal 443 HTML matched release.

Pitfall: Mac external 443 handshake fails while management-local 443 with
correct Host/SNI works. External acceptance and user link use :8443; internal
users can omit the port. Keep redirects relative and assets relative so both
origins work. Do not overwrite existing routes or run the new-release-only
publisher twice; it deliberately refuses existing named resources.

### /lead r2 correction

User corrected playback to right → middle → left (03,02,01), each 15 seconds.
Updated HTML initial image/preload/accessible numbering and JS interval 15000;
versioned JS URL prevents an old cached timer. Published isolated static release
`/home/HwHiAiUser/lead-display-20261114-r2/site` with only the display Deployment
volume path changed. r1 content and `deployment-before.json` are retained for
rollback. Update helper: `scripts/update-lead-order.mbtx`.

### /lead r3 subtle width adjustment

User requested slight horizontal stretch. Applied centered `scaleX(1.03)` to
all slide images, height unchanged; original order 03,02,01 and 15-second timer
retained. CSS URL versioned r3. Published isolated static release
`/home/HwHiAiUser/lead-display-20261114-r3/site`, with r2 and previous Deployment
saved for rollback. Browser at 3840×2160 verified matrix(1.03,0,0,1,0,0), all
images loaded, image bounds within viewport, no overflow or console errors.
Proof: `output/lead-20261114/lead-r3-live-4k.jpg`.

### /lead r4 width adjustment

User requested slightly wider again: `scaleX(1.05)` replaces 1.03. Height,
order and 15-second timer retained. Live static release is now
`/home/HwHiAiUser/lead-display-20261114-r4/site`; previous r3 retained.
4K browser confirmed matrix(1.05,0,0,1,0,0), all images loaded and contained
painted image bounds within the viewport. Served CSS SHA256 matches source.
Proof: `output/lead-20261114/lead-r4-live-4k.jpg`.

## 2026-11-14 — Seven board photographs expanded into the course

Inspected the seven newest top-level Downloads images by modification time
(including nanoseconds), all seven full previews and all 28 native-resolution
quadrants. Sanitized local copies and selection hashes are recorded under
`output/ai-course-images-20261114/`; originals are unchanged. Original filenames
contain web download query parameters: do not commit, publish or repeat them.
No photographs are shipped in the website.

The explicit reading order is download rank **7 → 6 → 5 → 4 → 3 → 2 → 1**.
Seven bilingual `ai-board-*` chapters expand 186 identifiable board entries
across 47 sections. The atomic crosswalk is
`docs/AI_WHITEBOARD_COVERAGE_20261114.md` and
`docs/ai-whiteboard-coverage.json`; authoring lives in `docs/ai-whiteboard/`.
Six literal readings remain explicitly unresolved: Opus version, ecosystem
parenthesis, NPC abbreviation, Kimi number, DeepSeek comments and small
Context/Harness wording. Two asynchronous transcription questions were sent;
no response had arrived at handoff. Concepts are explained, but do not claim
confirmed verbatim transcription or zero unresolved handwriting.

Build with `moon run scripts/build-ai-whiteboard.mbtx`, then run
`scripts/sync-ai-coursebook.mbtx` with the actual review timestamp. The original
19 AI chapters, 41 platform chapters and 120-minute/43-content-slide deck are
structurally unchanged in both languages. Board expansions are additional
reading, not an assertion that all extra material fits into the two-hour talk.
The directory now searches 90 concepts, including group names, with correct
reading anchors and reading-only actions for expansion sections. Filtered
right-hand navigation follows the filtered groups. The class directory can
also open these reading sections and exit presentation correctly.

`docs-site/whiteboard-studio.js` adds nine worked SVG mechanisms, used among
25 figures in the seven chapters. Inputs change computed results: ReLU,
negative log probability, baseline/advantage, fixed-budget scaling, multi-GPU
communication, top-2 expert routing, signed INT4 clipping, task evaluation and
model/harness comparisons. Synthetic examples and measured model specifications
are distinguished; primary references are available in collapsible source lists.
Raw static assets total 1,381,903 bytes, +184,990 over the before snapshot;
the new module is 12,371 bytes and adds no external media or network calls.

Validated 68 documentation tests, minimal image context, 0/70 source drift,
`moon info`, `moon fmt`, warning-free native check, and 1983/1983 native tests.
Both languages were walked through all seven chapters and all figures to their
final stages; no chapter errors, horizontal page overflow or new SVG text
outside its frame. Live directory-to-MoE interaction, English navigation,
90-concept total, group-name search, filtered TOC and 390px directory were
verified. Preview tab and local server were closed; official tab 2 remains on
the complete Chinese directory. Proof and browser walk JSON are in the output
directory, including `public-moe.jpg` and `public-board-directory.jpg`.

Final content-only image:
`moon/lunanexa-coursebook@sha256:e1ba1d4087be3639f03817535d0e700db2aab0791d29a65bd759588ccb440201`.
Release helper and rollback snapshot are under
`output/ai-course-images-20261114-r2/` locally and
`/home/HwHiAiUser/ai-course-images-20261114-r2/` on management. All 12 assets
matched exact published bytes on external 8443 and management-local 443;
`/user/`, `/mana/` and `/docs/` returned HTML on both routes. Only the docs
Deployment image changed. No commit was made; unrelated dirty work is retained.

Pitfalls: some existing studio objects have no `kind`; integration must use
`studio?.kind?.startsWith(...)`. Missing the second optional check breaks
chapters at their first such figure. Version changed JS URLs on every preview
iteration because a reload can reuse a 300-second cached asset. The final
lecture/app cache key is `20261114-board3`, whiteboard module `board2`, and
lecture CSS `board1`. Browser viewport overrides apply to the selected tab;
read the actual rendered width before asserting a mobile check. Smooth anchor
scrolls need a settled observation before screenshot assessment. A global
`git diff --check` still reports pre-existing whitespace in user AGENTS.md;
the changed documentation/runtime/build paths pass the scoped check.

## 2026-11-14 — Board material now drives the main curriculum

User rejected the separate expansion route and asked for the photograph content
to be integrated into the chapters as the main material. This supersedes the
previous section's optional-reading design and its unchanged-43-slide claim.

All 186 identifiable entries now form 47 primary sections inside 24 normal AI
chapters. They occupy 33 of 46 content scenes and 78 of 105 content minutes;
13 supporting scenes occupy 27 minutes. Break is still 50–60, questions
115–120, giving 48 total screens and 120 minutes. The book has 66 bilingual
pages: 24 AI chapters, a 60-concept directory and the same 41 platform pages.
The seven `ai-board-*` pages and `ai-board-notes` navigation were removed.
Legacy page URLs, including the 47 heading anchors, route to the matching
normal chapter. Six uncertain handwritten readings remain explicitly open.

Authoritative sequence and ownership: `docs/ai-integrated-course.json`.
New questions, demonstrations, short narration, titles and all causal bridges:
`docs/ai-integrated-teaching.json`. Full primary prose remains in
`docs/ai-whiteboard/`; it is rendered as ordinary book text and expanded primary
detail in the teacher panel, not hidden as optional background. The crosswalk
now links every board entry to both its chapter and actual main-class scene.
Related directory concepts can share a scene via `slide_id`; never pass the
section ID blindly to the presentation controller.

Build: `moon run scripts/build-ai-whiteboard.mbtx`, then
`moon run scripts/sync-ai-coursebook.mbtx ACTUAL_RFC3339_TIME`.
The former safely orchestrates the support-art builder and
`scripts/integrate-ai-course.mbtx`. `scripts/build-ai-lecture.mbtx` now writes
only `output/ai-course-authoring/base.json`; it must not overwrite the final
integrated deck. The obsolete `docs/ai-whiteboard-outline.json` was removed.
The sync rebuilds the AI route while preserving the 41 platform objects and
their Chinese overlays exactly. Existing source guides now identify the
older 43-scene material as historical supporting artwork.

Teaching corrections include an article-specific prompt illustration, actual
17×23 checking for inference-time compute, explicit meaning of natural log in
the probability/loss example, a consistent fare/a/b reference, and a break
handoff into corpora/training rather than directly into a GPU picture. No new
external media, model requests, polling, runtime or infrastructure coupling.

Checks: 68 documentation tests; native info/fmt/check and 1983/1983 tests;
minimal image-context check; 0/73 source drift; scoped whitespace check.
Walked all 48 class screens in each language, advancing all 46 diagrams through
their final steps. No canvas overflow or SVG text outside its frame; primary
teacher detail visibly expanded on all 33 primary scenes. Walked all 24 book
chapters in both languages (120 section headings, 92 diagram instances), no
load failures, duplicate main-content IDs or page overflow. Tested seven old
deep links, the shared-scene Qwen directory link, changed MoE routing and a
390px directory. Official tab 2 remains on the full Chinese directory; preview
tab 3 and local server were closed.

`output/ai-course-integrated-20261114/timing.json` estimates per-stage spoken
narration plus causal bridges at 220 Chinese characters/min or 150 English
words/min. All 46 fit their speech/transition budget, with separate demo and
processing allowances. Full book prose, teacher detail and all 138 prepared
student questions are not recited verbatim. This is not an audience trial.
Raw twelve-asset total: 1,982,294 bytes, +600,391 from the previous release;
content archive ~407 KiB. This archive size is not an HTTP compression claim.
Only current-chapter figures are instantiated; presentation data loads on demand.

Published image:
`moon/lunanexa-coursebook@sha256:20bb99b80b2dc7d8aae049613f51f182515a18ba42a2a255ee5e7f8b949da588`.
Release helper, snapshots, walks, timing and proofs are under
`output/ai-course-integrated-20261114/`; management release/rollback directory
is `/home/HwHiAiUser/ai-course-integrated-20261114/`. All 12 assets matched exact
bytes externally on 8443 and internally on 443; all three supported portals
served HTML. Changed only the docs Deployment image. Official browser verified
the 60-concept directory, integrated MoE scene 38/48 at 100–103 minutes, Chinese
and English chapter titles, and old quantization link migration into chapter 14.
Proof: `public-main-class.jpg` and `public-integrated-directory.jpg`.

Pitfalls: a book heading and an unchanged-art figure may share the same ID;
book rendering drops the figure ID when a preceding heading owns it. Primary
section IDs differ from shared scene IDs. Chinese presentation language toggle
is labelled `中文`, not `简体中文`; CUA role locators do not support a heading
`level` option, so use a known h1 locator. Allow normal page loading and smooth
anchor scrolling to settle before assessing a migrated live URL. Runtime cache
keys: lecture `20261114-integrated2`, app `20261114-integrated1`.

## 2026-11-16 — Complete speaking manuscripts for every class screen

The existing 48-screen main class now has a complete Chinese manuscript for
every screen, including the break and discussion. Four sources in
`docs/ai-speaking/` supply openings, 149 animation-stage actions and actual
spoken paragraphs, closings and conditional discussion guidance. The core
spoken text contains 15,084 characters, excluding conditional guidance.
No separate curriculum was added. All 66 existing bilingual book page objects,
the 46 content scenes, visuals, ordering and durations remain structurally
unchanged. The seven-photo, 47-section, 186-entry mapping remains primary.
The existing six uncertain handwriting readings remain unresolved.

The Chinese **讲稿** panel displays the current page's manuscript. Each
**演示这一步** button resets the example's default values before selecting the
stage, so the numerical script matches the diagram after experimenting.
Existing teaching detail and answered questions live in expandable preparation
reference. English keeps its prior teaching notes and a clearly named link
to the complete Chinese manuscript; there is no new full English verbatim copy.
The book's **逐页讲稿** link opens `/docs/ai-speaker-script.html`: a 48-item
directory with deep links to actual class scenes, print CSS and Markdown
download. Editable local copy: `docs/AI_PAGE_SPEAKER_SCRIPT_20261116.md`.
This release adds web manuscripts, not an exported PPTX or PDF file.

Build `scripts/build-ai-whiteboard.mbtx` now runs the base builder, integrated
curriculum builder, then `scripts/build-ai-speaker.mbtx`. The last step checks
all 48 page IDs, all stage counts and the total 120-minute route, emits the
HTML/Markdown and `docs/ai-speaking-audit.json`, and budgets time for the fuller
narration. All content pages fit at an assumed 220 Chinese characters/minute,
with separate control, observation, question and transition time. Speech may
accompany animation; it is not double charged as silent demo time. This is an
estimate, not a live audience trial. The print stylesheet starts each slide's
script on a fresh page and also has an introductory page; 48 slide scripts
does not imply exactly 48 physical printed pages.

Validation: 70 documentation tests; one opt-in headless browser integration
test walks all 48 screens and drives all 149 manuscript action buttons, checks
MoE defaults restore after selecting B, English notes, all directory links,
actual Markdown download bytes, print media visibility and 390px reading.
It passed on localhost and on the supported public `/docs/` deployment.
Native phase gate: info/fmt/check and 1983/1983 tests passed. Minimal image
context test passed; 0/81 source drift. Kimi K3's 2.8T and the Qwen3.6 model
card's 35B total/3B activated example were rechecked against their primary
report/card. Notes and screenshots are under
`output/ai-course-speaker-20261116/`; `browser-walk.json` records the checked
origin. Browser uses an isolated headless profile, not a personal browser.

Published final image:
`moon/lunanexa-coursebook@sha256:68268293ae13b2f1e33764b4aae1c87d7328e4d2457e67d3d495b729b8584445`.
Release helper is `output/ai-course-speaker-20261116/release.mbtx`; final remote
release/rollback directory is `/home/HwHiAiUser/ai-course-speaker-20261116-r2/`.
Only the docs Deployment image changed. Runtime now includes 16 files;
the four new files are the manuscript HTML/Markdown and its CSS/JS. All 16
match exact published bytes externally on 8443 and internally on 443, and
`/user/`, `/mana/`, `/docs/` still serve HTML. Raw static total: 2,233,256 bytes,
+250,962 bytes from the prior release; manuscript HTML/Markdown load only
when opened, and the enriched lecture JSON still loads on demand. No new
external runtime, network library, polling or model request.

Cache keys: app/lecture JS `20261116-script1`, lecture CSS
`20261116-script2`, standalone print CSS/JS `20261116-script1`.
Pitfalls: route scene IDs differ from some concept IDs; always bind speaking
pages by actual flattened scene ID. Gray stage directions are not spoken.
Do not restore the old outline in place of the full Chinese manuscript.
The task-owned localhost server on port 4396 was stopped after final public
verification; no shared browser or other development server was changed.

## 2026-11-17 — Manual local build cleanup

- User requested another Mac-only MoonSuite/LunaNexa compiled-artifact cleanup.
  Existing maintenance removed 33 stale generated build/cache directories
  (2,570,776 KiB). Found an additional gap: old local deployment staging
  `tmp/<stage>/*browser-dist*` bundles were outside its candidate scan.
- Added only these generated staging bundle directories to the existing
  cache helper. All existing tracked-file, open/running reference, compiler
  exclusion and 24-hour protection checks still apply. Staging sources,
  receipts, OCI evidence and other adjacent files remain untouched.
- Reviewed a report containing 21 eligible old browser bundles, then ran the
  same maintenance entry to remove them (472,364 KiB). Total 54 directories,
  3,043,140 KiB (~2.90 GiB) released; final available ~8.04 GiB. The entry's
  exit 1 reflects the existing <20 GiB free-space alert after safe deletion.
- Current plus two complete rollback installations, primary native outputs,
  recent/running builds, models, learning runs, hardware evidence and user
  data retained. MoonRobo `target/learning` is experiment data, not a Cargo
  build tree; never delete `target` based on its name. No remote operation,
  .191 test/reboot or service stop was performed.
- Compiler exclusion self-test, scoped formatting and actual eligible-path
  report passed. Evidence and both manifests are linked in
  `~/Library/Logs/MoonSuite/build-retention/manual-cleanup-20261117.json`.

## 2026-11-17 — Deeper unused-artifact cleanup

- User explicitly requested wider inspection while preserving live services,
  models, user data and rollback releases. Read-only inventory found real
  MoonFish raw/normalized datasets and exports (~43 GiB in home-suite state),
  LunaChip hardware/experiment workspace (~52 GiB), MoonRobo learning data
  (~15 GiB), and a stopped LunaChip Colima VM (~19 GiB). All were preserved.
  Never treat a directory named `target`, `objects`, `artifacts`, or a stopped
  VM as disposable solely from its name. No VM was started or deleted.
- Cleared npm `_cacache` downloads using vendor npm CLI (its source maps
  flatOptions.cache to `_cacache`; `_npx` retained), pip HTTP/wheel downloads,
  and pnpm's unreferenced package store using vendor non-force prune. Installed
  environments, project node_modules and tool binaries were retained.
- Root cause of a remaining cleanup gap: archived Git repositories under
  `~/moonsuite/development` were outside the main Workspace scan. Existing
  cache helper now discovers those checkouts to depth 5 and applies the same
  protections, retaining primary native builds. Report-reviewed 65 old test,
  check and JS/wasm caches removed (du total ~7.25 GiB; shared blocks overlap).
- One-time `scripts/clean-extra-build-artifacts.mbtx` removed 80 old Homebrew
  download archives and 84 file-format-checked Verilator .o/.a files. Retained
  executables, generated source, simulation TSV/VCD output, logs and receipts.
  Uses the same OS maintenance lock, compiler exclusion, open-file and 24-hour
  age checks. This one-time helper was not added to the daily schedule.
- Final free space 16.27 GiB, net ~8.24 GiB gain from this pass's 8.03 GiB
  baseline. Do not sum `du` deletion totals as physical recovery on APFS:
  cloned/shared data means the `df` gain is smaller. Still below the existing
  20 GiB alert threshold; main helper exit 1 was that alert, not a delete error.
- Compiler exclusion self-test, candidate review, actual runs and scoped
  formatting passed. No running service stopped, no remote operation or .191
  test/reboot. Evidence, retained categories and both deletion manifests:
  `~/Library/Logs/MoonSuite/build-retention/deep-cleanup-20261117.json`.

## 2026-11-17 — Stopped LunaChip VM retained after offline audit

- User conditionally authorized deletion only if the stopped validation VM
  held unused rebuildable artifacts. Inspected both raw disks offline using
  Sleuth Kit; did not boot, mount, mutate or delete the VM. Final Colima state
  remains Stopped. No cluster or running-service operation was performed.
- The separate Docker data disk has 458 volume entries and 5,326 regular files
  under volume data, including 42 VCD traces, proof logs, source HDL, status
  databases and solver models. These are protected experiment results. Do not
  infer a stopped VM or anonymous Docker volume is disposable build cache.
- No complete byte comparison with retained host archives establishes these
  results are redundant. LunaChip requires that comparison before deleting
  redundant evidence copies, including failed runs. VM therefore retained
  intact (~18.90 GiB allocated); do not add it to automatic build cleanup.
- Homebrew Sleuth Kit was installed with dependencies for read-only ext4
  inspection; old kegs retained and auto cleanup disabled. This cost roughly
  0.6 GiB. Final measured free space about 17.5 GiB; below the 20 GiB target, with
  no VM space reclaimed. Full decision, example trace hash and private file
  inventories: `output/vm-audit-20261117/REPORT.md`.
- Follow-up role check: creation record explicitly disables host mounts; VM
  is the local pinned Yosys/SBY/Bitwuzla/Verilator toolbox, distinct from the
  separate workstation Vivado build guest. Found one exact host copy of the
  sampled trace at `lunachip/artifacts/prx100-layer-20261018/work/formal-run-a2/output/result/engine_0/trace.vcd`.
  This proves partial duplication, not that every guest result is backed up.
  Current offline-gate recipes still reference the local Docker context.
