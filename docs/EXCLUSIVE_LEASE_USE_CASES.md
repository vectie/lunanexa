# Exclusive DGX lease use-case matrix

This matrix defines the production behavior for one user leasing one DGX. It
is both an operator runbook and a test inventory. In every case, the selected
node remains excluded from managed placement from reservation until verified
sanitization. `Completed` is the only normal release state; uncertainty becomes
`Quarantined`.

## Normal lifecycle

| ID | Use case | Expected result | Automated evidence |
| --- | --- | --- | --- |
| L01 | Reserve an empty DGX | Node is cordoned, then automatically enters `Provisioning` on its next authenticated lease poll | `api/nodelease_http_test.mbt` |
| L02 | Reserve a DGX still running a managed model | Lease remains `Reserved`; no login account is provisioned until desired assignments and observed runtimes are empty | `api/nodelease_http_test.mbt` |
| L03 | Future-start reservation | Node remains fenced but the agent performs no provisioning before `starts_unix_ms` | `nodelease/agent_test.mbt` and API time fence |
| L04 | Successful node provisioning | Only a fresh action/lease/generation-bound helper receipt changes `Provisioning` to `Active` | `api/nodelease_http_test.mbt` |
| L05 | Natural expiry | Controller changes the lease to `Expiring`; the local agent independently revokes at its recorded expiry | store, API and node white-box tests |
| L06 | Operator terminates active lease | Same revoke → sanitize path as natural expiry; no shortcut to node release | `api/nodelease_http_test.mbt` |
| L07 | Operator terminates before login is provisioned | Lease still enters cleanup; absent account/home state is verified and staged access material is removed | agent test and host simulation |
| L08 | Start the next user after cleanup | Old local lease state is cleared and a generation-one lease for a different user is accepted | `nodelease/agent_test.mbt` and API test |

## Failure and recovery

| ID | Use case | Expected result | Automated evidence |
| --- | --- | --- | --- |
| F01 | Management node unavailable at expiry | Transport failure is caught locally; access revocation is attempted without waiting for the controller | `cmd/node/main_wbtest.mbt` |
| F02 | Revocation receipt lost during outage | Receipt survives agent restart; sanitization waits until the controller acknowledges revocation and publishes the next generation | `nodelease/agent_test.mbt` |
| F03 | Receipt is older than the replay window | Agent reruns the idempotent helper action to obtain fresh evidence rather than releasing the node | node reconciler policy |
| F04 | Agent restarts between revoke and sanitize | Durable local state resumes the correct phase without re-enabling access | `nodelease/agent_test.mbt` |
| F05 | Controller commits but response is lost | Next lease poll observes the higher signed generation and suppresses the obsolete pending receipt | generation reconciliation tests |
| F06 | Account/session/process cannot be removed | Helper fails; node and lease become quarantined and remain unschedulable | host cleanup simulation |
| F07 | Container or volume cannot be removed | Sanitization fails before account deletion can hide residue | host cleanup simulation |
| F08 | Account or process inventory command fails | An infrastructure error is not interpreted as “absent”; cleanup fails closed | host cleanup simulation |
| F09 | Credential is missing or invalid | Provisioning fails before an account is created | host cleanup simulation |
| F10 | Ownership marker is missing or changed | Helper preserves the ambiguous data and quarantines for human investigation | helper policy and simulation |
| F11 | Operator recovers a quarantined node | Recovery explicitly returns to `RevokingAccess`, repeats revoke, sanitizes, then completes | agent and API tests |
| F12 | Quarantine observation is retried | Repeated bound evidence is idempotent and does not advance generations indefinitely | API test |

## Adversarial and concurrency cases

| ID | Attack or race | Required behavior | Automated evidence |
| --- | --- | --- | --- |
| A01 | Forge a generic “cleanup succeeded” string | Rejected; helper evidence must bind action, lease, generation and recent timestamp | API and agent tests |
| A02 | Replay evidence for another generation/action/lease | Rejected as stale or misbound | API and helper-receipt tests |
| A03 | Use the generic operator transition route to claim `Active` or `Completed` | Rejected with `NodeEvidenceRequired`; only reconciliation and verified node observations drive lifecycle state | API test |
| A04 | Termination races provisioning | Reserved/provisioning leases go to `Expiring`, never directly to `Cancelled`; the node stays fenced through cleanup | store, agent and API tests |
| A05 | Duplicate termination request | Current generation is idempotent while a stale generation is rejected | API lifecycle tests |
| A06 | Two leases target one node | Second non-terminal lease is rejected before provisioning | store and API tests |
| A07 | Path traversal or hostile runtime IDs | Rejected before any host command receives the value | lease-helper fuzz tests |
| A08 | Empty credential reference suffix | Rejected even when the scheme prefix is valid | nodelease validation tests |
| A09 | Persisted agent state names another node or impossible state | Rejected during restart instead of executing host actions | agent snapshot tests |
| A10 | Lease generation reaches `Int64` maximum | Further transition is rejected; generation cannot wrap into a usable value | nodelease lifecycle test |
| A11 | Helper prints extra text or forged suffix | Exact receipt parser rejects it | helper-receipt tests |
| A12 | Browser fields contain script/HTML text | Rabbita escapes the content and destructive scope stays explicit | `ui/console_test.mbt` |

## Operator recovery rule

Do not manually edit lease JSON, remove quarantine markers, or make the node
`Active`. Inspect the helper and node-agent evidence, repair the underlying host
condition, then invoke **Terminate & clean** again on the quarantined lease. The
controller moves it to `RevokingAccess`; the agent repeats the idempotent host
checks and only verified sanitization can return the DGX to managed service.

Physical acceptance must repeat L05–L08 and F01–F11 on every approved DGX host
image with real SSH sessions, user processes, rootless containers and volumes.
Repository simulation proves control-flow invariants, not kernel or driver
behavior.
