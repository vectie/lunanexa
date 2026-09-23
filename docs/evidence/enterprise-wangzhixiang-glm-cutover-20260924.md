# Enterprise GLM handoff to wangzhixiang (2026-09-24)

## Scope and authority

The operator approved a one-day test for `wangzhixiang@wlkxcgs.com` in
`能源谷青创街区` (`organization-4a2394cf9b9a6b3c02697fab0097489a`). No platform
administrator role, contract signature, payment, or exclusive-machine lease
was issued. The company had already been approved and its founder remains its
company administrator. This exercise used the existing external GLM route on
Spark `.178/.179`; the `.176/.177` trial pool was not modified.

## Cutover and observations

1. The existing account `subject-c83af2a3503e34aaae05c511` received an
   active Developer membership in the company. Its pre-existing workspace
   user `trial-user-c83af2a3503e34aaae05c511` was reused; no duplicate
   identity was created.
2. Grant `grant-wangzhixiang-enterprise-20260924` and lease
   `lease-wangzhixiang-enterprise-20260924` were issued for the company tenant,
   TextGenerate only. Both expire at **2026-09-25 06:10:17 Beijing time**.
3. The external `glm-5.3.flash` route was moved from the CeShi test tenant to
   `tenant-4a2394cf9b9a6b3c02697fab0097489a`. The live ConfigMap and this
   repository's route file agree. The controller rolled out and was 1/1 Ready.
   The controller-local GLM proxy returned `/health` 200 and advertised the
   pinned `GLM-5.3-Flash-EXL3` model.
4. CeShi's exact enterprise WebIDE lease `lease-20260923-enterprise-webide`
   was ended and grant `grant-20260923-enterprise-webide` revoked. His separate
   personal trial grant and lease were left alone. The API rechecks the active
   workspace lease on every client-handoff-key request, so ending that lease
   invalidates CeShi's former company access even if a desktop still holds a
   previously redeemed key.
5. In the public `/user/` UI, the company was selected and WebIDE reported
   Developer membership, active workspace lease, and **one callable model:
   `glm-5.3.flash`**. `打开 MoonDesk / MoonCode` opened the local desktop client
   through a one-time handoff; Code selected `moongate/glm-5.3.flash`.
6. A new Code conversation returned `WANG_GLM_UI_OK` with state DONE. A second
   turn returned `SECOND_TURN_OK` with state DONE. The composer remained visible
   and editable after both responses.

## Limits and follow-up defects

- The route is a single-tenant, externally operated GLM service, not a managed
  LunaNexa `ModelApi` delivery or a physical exclusive-machine lease. This
  confirms the test-company cutover and inference path, not the complete
  production one-click provisioning or multi-member managed-delivery flow.
- On this Mac, the existing MoonDesk installation displayed 22 earlier local
  MoonCode sessions after the new cloud-account handoff. The model credential
  is lease-scoped in LunaNexa, but the desktop's local workspace/session data
  and MoonGate provider configuration are not separated by LunaNexa account on
  a shared OS profile. Do not claim per-person WebIDE data isolation on the
  same computer until account-scoped local profiles are implemented and
  retested. Do not delete those pre-existing sessions as a workaround.
- The operator's `创建 WebIDE 访问` form derived a different subject for this
  already self-registered account. Submitting it would have created duplicate
  identity state; the existing user was granted access through the supported
  operator membership and workspace APIs instead. Fix this onboarding form so
  it can select and reuse an existing account before calling it one-click.
