# Cancel a request after its progress UI is gone

The existing VS Code client now offers **LunaNexa: Cancel Recorded Request**.
Use it when an interrupted or closed request progress notification no longer
provides the original cancel button, while the server may still be working.
This extends the existing request journal and cancellation endpoint; it is not
an account-wide job manager or a new backend.

1. Restore the request's API base and subject in user/machine configuration.
2. Run **Cancel Recorded Request** and choose a recent attempt. Only the exact
   canonical API base path and subject are listed. Times use Asia/Shanghai.
3. The client reads current status once. Missing, unavailable or terminal status
   cannot authorize cancellation; no cancel request is sent in those cases.
4. For a known nonterminal state, review the modal's workload ID, API, subject
   and observed state, then explicitly choose **Request cancellation**.
5. One cancellation POST is sent. The client then makes one status read and
   opens an untitled plain-text review containing the cancellation receipt and
   available status evidence. Use normal Save As if a local copy is needed.
6. If it remains running or status is unavailable, use **Check Request Outcome**
   later. No automatic retry, resubmission or polling occurs.

The journal retains at most 20 attempts across contexts, including attempts
recorded before submission. This command cannot cancel an arbitrary typed ID or
recover a request no longer in the journal. Cancelling the picker or modal
sends no mutation. Concurrent command invocations are refused while one is in
progress. A changed API/subject or deactivated extension prevents a pending
confirmation from sending. A request already dispatched cannot be retracted by
changing settings or closing the editor.

A 202 cancellation receipt means the server accepted the request, not that the
workload terminated, freed capacity, produced no output, or avoided charges.
The workload may finish between the status read and cancellation. Server-side
live authorization and current workload state remain authoritative. An
unconfirmed cancellation may still have reached the server: inspect its outcome
before deciding to try again. A failed follow-up read does not erase an accepted
receipt. No provider/node credentials, prompts or output are added to history.

## Product rationale and qualification

This closes the developer's interrupted-request control loop in the existing
provider-neutral client. The actual PRD's lease requester/API developer job and
LN04 scoped-access boundary apply; `ARCHITECTURE.md` Data plane explicitly owns
cancellation, and `PLAN.md` phase 4b owns developer-client inspection. This is
client support only, not the PRD's actual model-response or physical service
acceptance gate, and it does not implement commercial cancellation/refunds.

From the repository root run:

    node --test extensions/vscode/*.test.mjs

Nine new focused tests execute the registered command using the injected VS Code
contract fixture and mocked HTTP responses; all 58 client tests pass. They cover
lost-stream recovery, confirmation, scoped journal selection, accepted versus
terminal evidence, missing status, changed context, no duplicate submission and
ordinary cancellation choices. No live workload was cancelled. Actual VS Code
host, Save As, native controller, provider, browser, physical cluster and GPU
execution remain unqualified. No dependencies were installed and no Moon command
was run. R50 remains the last fully verified cumulative result; R51–55 separate.
