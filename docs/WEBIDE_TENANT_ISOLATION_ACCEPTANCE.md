# Hosted workspace isolation acceptance — 2026-09-16

## Scope and environment

Two real disposable accounts, separate organizations/projects and private-cloud
administrator authorization were exercised in the isolated Kubernetes acceptance
namespace. The second account used a signed TEST ONLY registration assertion,
not a real public OIDC/browser or verified-mailbox flow. No rental contract was
required. Neither hardware identity nor GPU evidence was changed.

These workspace Pods ran on the actual AMD64 manager node, not a Spark. Media
was an explicitly marked test-provider video, not model-generated content.

## Observed results

| Requirement | Evidence |
| --- | --- |
| Organization self-service | Existing second account created its own organization/default project; identical idempotency-key replay returned the same response. |
| Authorization prerequisite | Enable before preparation returned 409 AccessPackageNotReady. Operator preparation then enable moved ReadyToEnable to Ready, with contract_required=false. |
| Foreign scope rejection | Second account requesting the first organization's/project's ComfyUI handoff received 403. |
| Independent workspaces | Both users connected with HTTP 204 and opened their own roots with HTTP 200; distinct workspace Deployments/PVCs. |
| Output isolation | Second user's asset listing excluded both first-user videos; exact first-user output path returned 404. Positive control downloaded the original with the known hash. |
| Workflow save/isolation | Second user saved an empty TEST ONLY workflow through userdata; exact bytes read back. Original user requesting the same path received 404. |
| Workflow recovery | Actual second-workspace rollout replaced the Pod. A fresh handoff in read-only mode retrieved identical bytes without rewriting. |
| Uploaded input | Authenticated multipart upload saved the marked test video in input/isolation; subsequent download matched its prechecked SHA256. Original user received 404 for that input. |
| Input recovery | Another successful workspace rollout followed by a fresh read-only handoff preserved both input video hash and workflow bytes. |
| Traversal | Encoded parent traversal through userdata, v2/userdata and output view, and an absolute filename attempt, returned 403, 400, 403 and 400. |
| Bounded network probe | Cross-workspace TCP connection to the live original Pod port 8188 was refused. Both localhost listener controls connected. This is not proof of every possible network path. |

The media SHA256 used for upload/download positive controls was
`8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.

NetworkPolicies were inspected live: workspace ingress permits gateway Pods on
8188; egress permits DNS, controller and model gateway destinations. curl was
absent in the workspace image, so attempted curl executions are not counted as
passes. Installed openssl with a five-second timeout supplied the bounded TCP
probe: cross-workspace errno 111 versus localhost TLS wrong-version responses
from plain HTTP listeners. This does not attribute rejection to a particular rule.

## Regression coverage and limits

The host manifest regression varies tenant, organization, project and subject
independently. All five authority scopes have distinct PVC resource names, one
own claim, no hostPath, and exactly one ComfyUI container without the model
credential mount or literal credential. Missing containers/mount arrays cannot
silently make the credential checks pass.

Local temporary download files were removed; bounded handoffs and clearly named
fixtures remain for further UI/cleanup acceptance. No production resources were
deleted. The scripts and protected acceptance configuration remain outside Git.

This checkpoint does not close the full platform acceptance: public identity UI,
all media formats, exhaustive network/traversal paths, current order/payment
browser E2E, live provider partition recovery and cleanup still require their
own evidence. Actual Spark/model compatibility and performance remain deferred.
