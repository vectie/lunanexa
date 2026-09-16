# Fresh managed TEST ONLY provider acceptance

After the prior r9 lease expired, the managed acceptance namespace contained no
runtime pods. A fresh bounded deployment `managed-test-video-20260915-r10` was
created through the controller service-deployment API, using the existing
`acceptance-test-video:kubernetes-v1` template and a two-hour lease. No model
weights or real inference engine were deployed.

Assignment `managed-test-video-20260915-r10-r1` started pod
`lunanexa-d9704f7868df8055b23ab760b83b52e59ecc7c4a` on physical compute node
`lunanexa-gpu-180`, IP `10.42.1.34`, ready with zero restarts. Hardware identity
was not changed. The runtime reserves GPU capacity for allocation testing but
returns the explicitly marked CPU-generated protocol fixture.

Direct runtime verification passed unauthorized 401, queued/in-progress/completed
states, premature content 404, fixture content download, deletion followed by
job/content 404, unchanged pod UID and zero restarts. The temporary downloaded
file was removed.

A new private scoped handoff advertised the deployment-owned MoonGate API base.
A fresh per-run idempotency key created job
`video-1b7d107feb38cf5e0abf343281c0f10f1790b8c1de4aa0a5a545eae55630c5e7`
through MoonGate; retry through the controller returned the same job. Polling
through MoonGate reached completed and content download matched SHA-256
`100f5f75c28643c855e503d16b0a1b6941fbfceb2d0b0881f16d7a420df54f91`.
The test cleaned its provider job, temporary download, handoff and login session.
The bounded managed deployment is intentionally retained for subsequent fault
tests until lease expiry; it is not a permanently available model endpoint.

This verifies the API/protocol route, not a new browser generation, provider
process durability, replacement fencing, actual model quality or Spark hardware.

## Controller outage and workspace preservation

The isolated controller was stopped for 45 seconds after a fresh job was queued.
The runtime Pod UID/container IDs/restart counts remained identical. The hosted
workspace also retained its Pod/container identities and restart counts, both
containers Ready, with no deletion timestamp. This spans the configured
30-second gateway reconciliation interval but does not instrument the exact
reconciliation iteration, so it is direct preservation evidence rather than
proof of every internal branch.

After controller restoration, the same idempotency key returned job
`video-fbbe91a86105b8a0d4961d2d5e2e3e78c9f27d6628c68218765c0c0abc941703`.
It progressed to completed through MoonGate, returned the expected fixture
hash, and had exactly one `private-workspace-video-job` usage observation with
quantity one. A separate job
`video-e067d2b5979fa6f3f36d4b98156782a22de90c2c75d650554c3c141fb2ebd48c`
was explicitly cancelled with `deleted:true`. Recovery-script temporary output,
handoff and login were cleaned on exit; the controller was restored. This does
not test provider-process loss, automatic controller HA failover or real GPU work.

## Local replacement and cancellation boundaries

An API binding identity regression confirms that instance replacement changes
the binding even with an identical address; address, generation, node and
provider-model changes also fence old jobs, while bearer rotation does not.
This test passed with the repository's existing warning exclusions.

The provider strict suite passes 6/6: cancellation rejects 404, 409, a mismatched
job ID and `deleted:false`, and accepts a positive acknowledgement for the exact
job. The runtime strict suite passes 7/7: a 404 leaves cancellation nonterminal,
retains capacity across serialized store restoration, then releases capacity
only after a positive acknowledgement, with exactly one settlement across
reconciliation retries. These are local protocol tests, not live provider-loss
recovery evidence. A permanently lost provider still requires independently
verified termination before old capacity can safely be released.

After the live recovery and cancellation run, the operator pending-job endpoint
returned `{"data":[],"truncated":false}`. This checks that those acceptance jobs
left no unresolved execution, cancellation or settlement records; it is not a
general proof that a future provider-loss event can always be resolved.

## Real idle-provider replacement

With the operator pending-job list verified empty, the exact r10 test Pod was
deleted normally (no forced node deletion). Old UID
`de65f2c0-5350-4e54-ae95-12fdc3ded7b3` disappeared. The node agent automatically
recreated the same assignment/name with UID
`4cce6332-021c-4525-b227-6eacbb8d673e`, address `10.42.1.35`, Ready and zero
restarts. This removed only the disposable TEST ONLY provider process; no model
weights or workspace volumes were removed.

Direct runtime protocol checks passed again. A fresh MoonGate job
`video-6cff4302e0a313d0233914f47176563a37bcc615e97b5c68dbf6594b5f54a147`
completed through the discovered replacement route, preserved cross-entry
idempotency and returned the expected marked-video digest. Probe jobs,
downloads and scoped credentials were cleaned; the pending-job endpoint again
returned an empty, untruncated list.

This proves automatic replacement and routing for new requests after idle
provider loss. It deliberately does not claim recovery of in-memory jobs that
were running at process loss, nor automatic resolution of their reserved quota.
