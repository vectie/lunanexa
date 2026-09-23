# Public UI checkpoint before exclusive-delivery rollout

This is a read-only business checkpoint against the existing live browser
bundles, not acceptance of the pending source changes. No grant was renewed,
order signed, payment recorded or service launched in this check.

## Recorded UI actions

1. Opened public Operator `http://106.39.18.146:4174/console/` in the in-app
   browser. Loading screen completed; the deployment-open same-origin operator
   session entered without a password form.
2. Read Overview: four of four nodes reported active heartbeats, 17 registry
   approvals, zero queued requests and zero open alerts. The UI explicitly
   distinguishes heartbeat health from model/business acceptance. These are
   displayed values, not independent inference or telemetry-accuracy proofs.
3. Observed disabled “打开一键部署” alongside a global production acceptance
   blocker `CommercialProviderAdapterUnavailable`. Source is being corrected
   so catalog navigation is not gated by unrelated commercial integrations;
   actual authorization/deployment preflight is retained. The fix was not live
   during this observation.
4. Opened public Enterprise `http://106.39.18.146:5002/enterprise/`, entered the
   previously supplied test account's existing credentials and pressed “登录”.
   Login completed into the previously created 双端对账 UI 测试 organization.
   No new credentials or account were created; secrets are omitted here.
5. Pressed “WebIDE”. “打开 MoonDesk / MoonCode” was disabled and the page said
   no operator-enabled workspace access was available. No launch was attempted.
   The old live copy says “等待运维人员启用”, which fails to distinguish expiry
   from never-authorized access. Updated source has a no-valid-access message;
   post-rollout expiry-state verification is still required.
6. Observed the old Overview checklist still saying “运维分配一个节点”. This
   contradicts the new node-set architecture; its source copy is being fixed.
7. Opened Operator “模型”. The live registry showed `minimax-minimax-h3` /
   `modelscope-master` as approved with an accepted license and service alias.
   The separate ModelScope import list showed the 281-file whole-model import
   with checksum verification complete but four subsequent gates still pending.
   These are different records and do not establish approval for either new
   81-file FL2VA/Ref2VA component digest. No license/approval button was
   pressed in this inspection.

## Not proven

This check does not establish current resource entitlement, model readiness,
ComfyUI output/download, file persistence, isolation, expiry cleanup or matching
operator/customer delivery states. A newly confirmed bounded test grant and
updated deployed components are still required for the complete UI campaign.
Public HTTP is the explicitly approved acceptance setup, not production-safe
transport. The pages' presence does not prove public workspace port 5000 works.

The user subsequently approved a **45-minute** acceptance grant. This approval
does not itself create a lease or start its clock. The grant must be opened
through the public UI after the updated path is ready, then both sites must
show its actual effective interval and expiry.
