# Company model services and personal WebIDE: release check (2026-09-24)

## Ownership and access contract

- A Workspace or GPU-container application and its saved files belong to the
  individual. Company administrators do not acquire the person's WebIDE by
  managing a model service.
- A `ModelApi` delivery and a machine order belong to the selected company.
  Active members of that company can see the shared model delivery. Each
  authorized developer obtains their own scoped API key or one-time MoonDesk
  handoff; no member shares the service creator's credential. A company
  administrator can manage the company model delivery, but cannot manage a
  member's personal application.
- A newly registered company can remain `OperatorReviewPending`. The public
  portal shows that status, and the Operator Users page has the approval action.
  No external identity provider callback is needed for this company review.
  Approval does not by itself lease a machine or buy a service.

## Public UI exercise

The following was exercised through the browser on
`https://suanli.kechuangfuwu.com:8443` using the existing technical test
account and organization; no real customer organization was approved.

1. Enterprise `/user/` loaded in Chinese. Navigation appeared in the user
   sequence: start, IaaS company machines, PaaS personal WebIDE, MaaS company
   models, company administration.
2. Enterprise **自助开通** showed the six-step order progress and service
   choices. The existing test organization's organization step showed
   **企业审核待完成**, explicitly said the registration had been sent to platform
   administrators without an external verification service, and offered
   **刷新审核状态**.
3. Operator `/mana/` → **用户与访问权限** showed the same test organization in
   **待审核企业注册**, with its legal details and **审核通过企业注册** button. The button was
   observed, not pressed in this check.
4. Enterprise **WebIDE** displayed the authorized `glm-5.3.flash` model, the
   individual MoonDesk choice, access steps, and one-click progress.
   **打开 MoonDesk / MoonCode** created a fresh one-time handoff and opened the
   local MoonDesk Code workspace. The model selector showed
   `moongate/glm-5.3.flash`.
5. In Code, a text-only test prompt returned `READY_OK` with state **DONE**.
   The **Ask MoonCode** input remained present and editable after sending and
   after the reply.

The GLM inference route is externally hosted on the two enterprise Spark nodes;
it is not a managed LunaNexa deployment assignment. Thus an empty managed
assignment list must not be read as proof that this external route is down.
The .176/.177 trial workloads were not changed during this rollout.

## Gateway and rollout checks

- The public gateway now accepts only an exact one-time handoff redemption
  without a browser session. API-key clients may call the model list, text
  inference, response/workload submission, and exact workload status/cancel
  paths. Other management routes continue to require the browser session.
- An invalid anonymous redemption reached the controller and returned 400;
  an invalid API bearer reached controller inference authorization and returned
  401. A cross-site browser-style redemption stayed blocked at the gateway
  with 401.
- Control, Operator, Enterprise, and the shared-domain identity gateway all
  rolled out successfully and were ready. The controller's public API base and
  desktop launch catalog both point to `/user/v1`, not the retired port 5002.
- Native LunaNexa tests: 1228 passed, 0 failed. The gateway allowlist's
  focused tests passed; two-member, same-company independent-key/handoff and
  revocation behavior is covered by `api/delivery_credentials_wbtest.mbt`.

This check is not a claim that every historical button on every page or the
external 443 route was exercised. The tested public entry point was 8443.
