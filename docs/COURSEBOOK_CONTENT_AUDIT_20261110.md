# Coursebook content review — 2026-11-10

Scope: all 41 English pages and their complete Simplified Chinese overlays in
`docs-site/`. Inspected source revision:
`d255f4f3479fc15dce693b9ac6c3dea98eed5775`, with a dirty working tree.
The evidence ledger records hashes of the reviewed bytes. This review preserves
unrelated changes already present in the checkout.

## Findings and corrections

- Reconciled September content metadata, October evidence metadata and the older
  revision quoted in the site README. Source hashes alone had not represented
  a complete semantic review.
- Replaced email-only registration instructions with the deployed email or
  mainland-China-phone flow. Documented six-character minimum passwords and
  distinguished registration from email/SMS ownership verification and MFA.
  The stricter reference identity deployment remains separately documented.
- Re-read the deployed non-secret generation-7 settings: request body
  16,777,216 bytes and input budget 10,000,000 bytes. Replaced the old 1 MiB and
  850,000-token advice. The 524,288-token GLM configuration comes from the dated
  2026-11-08 runtime acceptance; this review did not start the stopped service.
- Checked TRAE's current official custom-model instructions on 2026-11-10:
  [custom models](https://docs.trae.cn/ide_custom-models). Updated the image-input
  location and canonical documentation URL. No new TRAE client session was run.
- Added unified service/resource ownership, existing-service navigation,
  actual-readiness requirements, Unknown observations, company-allocation
  retention and non-replay of lifecycle mutations after authentication recovery.
- Replaced simulator-only/two-node-pilot/no-model-service assertions with dated
  retained physical deployment, adoption and runtime evidence. Did not turn
  those bounded checks into HA, sustained-load, reclaim or launch certification.
- Removed the obsolete single-file-only materializer limitation. Reviewed the
  `modelstore://` signed-manifest multi-file path, corruption/restart fixtures,
  and idle-cache retention/pressure tests. Retained the separate qualification
  requirement for each selected model/runtime and arbitrary archive extraction.
- Corrected ComfyUI lessons that assumed every workspace used a generic local
  Stable Diffusion checkpoint. Distinguished personal CPU workspaces and remote
  providers, native anonymous H3 on 5005, and self-managed exclusive machines.
  Removed unverified speed guarantees, blanket whole-disk erasure claims and
  hosted custom-node installation recipes. No fresh video generation was run.
- Updated approved application, storage, registry, organization-review and
  commerce guidance. Distinguished implemented contracts from enabled provider
  services and future general self-service products. Kept managed-node isolation.
- Marked the 2026-08-20 UI campaign historical and advanced-only; dated the
  2026-08-21 planning status and line-count estimates. Retained their original
  results without presenting them as today's acceptance inventory.
- Labelled the two retained disconnected screenshots historical and made them
  advanced-only. They illustrate an access boundary, not the current layout.
  Dated public-video validation details also remain in Technical notes.
- Replaced abbreviated environment-variable names with exact names and current
  S3 SigV4/managed-revision distinctions. Corrected active-key retrieval advice.

## Page coverage

Each row covers the English lesson and Chinese overlay. Source IDs are retained
on every page; the machine-readable review in `coursebook-evidence.json` must
cover the exact same page set and source lists.

| Page ID | Review result |
| --- | --- |
| trial-quickstart | Updated contact registration and verification boundary; checked issuance/copy actions. |
| enterprise-portal-day-one | Updated session sharing, personal applications and active-key retrieval. |
| exclusive-machine-basics | Retained separate bare-machine contract, handoff clock, non-root access and staged cleanup. |
| comfyui-quickstart | Updated personal/public/native profiles, task recovery and privacy. |
| welcome | Updated dated deployment-evidence boundary. |
| readiness | Replaced old simulator-only inventory with retained physical evidence and remaining acceptance. |
| boundaries | Checked provider-neutral API, managed-node prohibition and explicit exclusive-machine exception. |
| feature-map | Updated shared service authority and personal application scope. |
| architecture | Updated qualified multi-node binding versus arbitrary sharding. |
| state-ownership | Checked PostgreSQL authority, independent model source, persistent workspaces and HA limitation. |
| request-flow | Checked canonical admission, idempotency, ownership, pre-output retry and terminal failures. |
| deployment-flow | Updated optional evaluation, common ownership, multi-file verification and retained caches. |
| enrollment-flow | Checked first-time Kubernetes versus product enrollment and stable node identity. |
| access-flow | Updated identity verification, app entry and exact whole-node-set authority. |
| local-quickstart | Checked local/simulation boundaries and repository-owned command references. |
| operator-console | Updated existing-service actions, resource retention and historical screenshot label. |
| developer-workbench | Checked browser-local drafts, capability admission and external-client scope; dated screenshot. |
| client-api | Updated limits, configured context, readiness, active-key handling and TRAE instructions. |
| tomorrow-deployment | Checked installer flags/action bindings; dated Ascend qualification; made evaluation optional. |
| dgx-runtimes | Updated managed revisions and retained LunaFlux/TensorFold evidence; retained qualification scope. |
| daily-operations | Checked fixed read routes, alert/notification actions, independent commerce evidence and diagnostics boundary. |
| ui-end-to-end-sop | Retained canonical production portals, authorized actions and external-receipt requirements. |
| production-ui-validation | Preserved exactly 50 historical scenarios; dated and removed from ordinary navigation/search. |
| observability-recovery | Checked complete authority backup, fencing, reconciliation and no blind workload replay. |
| debug-controller | Checked scoped credentials, trusted ingress, epoch and optional diagnostics failure paths. |
| debug-node-runtime | Removed mandatory evaluation; distinguished process state, serving readiness and Unknown claims. |
| debug-access-database | Added session recovery/non-replay boundary; checked ownership/rate/database failures. |
| configuration | Replaced abbreviations with exact variable names and effective-policy distinctions. |
| error-reference | Checked public codes; corrected active-key retrieval and authentication recovery. |
| future-expansion | Preserved the dated plan and independent offering gates; corrected its claimed currency. |
| source-ledger | Updated semantic-review scope and removed a hand-maintained stale release assertion. |
| choose-your-path | Removed universal contract gate, fixed-trial-duration promise and blanket disk-cleanup wording. |
| comfyui-first-image | Replaced unsupported generic-image recipe with approved-profile workflow and task/result checks. |
| comfyui-next-steps | Removed arbitrary hosted plugin installation and whole-disk erasure promises. |
| planned-interactive-access | Corrected current hosted/SSH paths; preserved managed-node application prohibition. |
| planned-app-catalog | Corrected current approved applications versus future community marketplace. |
| planned-workload-exposure | Corrected current published endpoints versus general tenant port/YAML controls. |
| planned-elastic-batch | Preserved explicit non-goals; corrected blanket execution/request-count cap wording. |
| planned-storage-registry | Corrected deployed persistent/RWX/OCI scope, explicit migrations and retained cache policy. |
| planned-commerce-identity | Corrected implemented authorities versus current external commercial readiness. |
| planned-chat-playground | Checked that a separate inline portal chat remains planned; workbench remains the existing browser path. |

## Recipe execution boundary

All 15 shell code blocks were extracted and passed `bash -n`; syntax checking
executes none of their commands. Text blocks containing URLs, settings or field
examples are reference values, not scripts. Existing coursebook tests validate
the sample request JSON and actual named UI event bindings.

| Page / recipe | Prerequisite for execution in its intended environment |
| --- | --- |
| enrollment-flow / node identity | Authorized cluster kubeconfig and exact selected node names; placeholders must be replaced. |
| local-quickstart / repository gates | MoonBit workspace dependencies and native toolchain; the phase gate is run separately for this review. Full composed simulation/release recipes are not inferred from syntax checking. |
| local-quickstart / kind start-stop | Docker, kind, kubectl and a dedicated local simulation environment; not executed on the production cluster. |
| local-quickstart / macOS Colima | Installed Colima and enough local VM capacity; a new VM was not created for this content review. |
| client-api / discovery, JSON, SSE | Current scoped customer key, matching organization/model access and a ready service. No key was retrieved and no stopped model was started for this review. |
| tomorrow-deployment / render | Exact immutable images, selected management node and a new protected output directory. Existing render tests cover accepted flags. |
| tomorrow-deployment / secrets | New protected destination and a deployment secret-management procedure; no production credential was generated. |
| tomorrow-deployment / installer | Local browser bundles, loopback static server and native installer companion; applying infrastructure is outside the content review. |
| dgx-runtimes / qualification apply | Explicitly selected ARM64 GPU, qualified model directory, trust and pinned image. These commands mutate the cluster and were not executed. |
| daily-operations / alerts, events, metrics | Correct operator/monitoring credentials and trusted API origin. No raw operational/customer records were exported. |
| daily-operations / orders | Correct customer/operator scopes and client-certificate identity; no order, payment or signature was created. |
| daily-operations / machine access | Exact customer authority and client certificate; no credential redemption or machine termination was performed. |
| daily-operations / guide health/admin | Configured coursebook service origin; administrator page additionally requires the signed identity proxy. Public-site reachability does not prove administrator activation. |

## Remaining qualifications

This audit establishes source-grounded content at the recorded dirty snapshot,
not exhaustive equivalence between every prose sentence and every production
deployment. Current authorized customer/member browser workflows, external
mail/SMS/payment/invoice/signature delivery, HA restore, sustained GPU load,
destructive machine reclaim, and new native video generation require their own
scoped acceptance. Optional guide success is not established by static content
tests. Screenshots of older disconnected UIs remain historical.

Repeat the source-drift and coursebook checks after subsequent source edits;
update the affected lessons before renewing their review timestamp. Never make
stale content appear reviewed by updating hashes alone.

## Automated validation and delivery cost

`moon info`, `moon fmt`, strict native checking and the standalone native check
of `scripts/audit-coursebook.mbtx` pass. The complete native runner passes
1,983/1,983 tests. Coursebook, guide-diagnostics and support-report checks pass
54/54. Management-manifest renderer and minimal coursebook-image-context tests
pass; all 15 published shell recipes pass syntax checking. No public interfaces
changed. Recipe syntax checks are not a claim that their production effects ran.

The three coursebook data files total 324,161 bytes, versus 346,045 in the
preserved pre-review snapshot: 21,884 fewer uncompressed bytes (about 6.3%).
The release retains the deployed HTML, JavaScript, CSS and images, adding no
request, animation, font, polling or inference hop. Live asset equality and
rendered-site observations are recorded separately in `HANDOFF.md` after release.
