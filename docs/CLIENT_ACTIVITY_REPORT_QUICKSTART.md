# Review and export recent client request activity

The existing LunaNexa VS Code client can now collect a local JSON or CSV report
from selected recent request attempts. This lets a developer inspect several
workload outcomes and reported usage together without resubmitting selected text
or copying one status preview at a time. It uses the same provider-neutral status
endpoint and origin-bound token as **Check Request Outcome**.

## Use the report command

1. Configure the existing client normally, then use **Send Selected Text** or
   **Stream Selected Text**. Their bounded metadata journal supplies recent
   attempts, including interrupted requests. It stores at most 20 attempts
   across all contexts; it is not a complete account history.
2. Run **LunaNexa: Export Request Activity Report**. Select one or more attempts.
   Only entries for the exact currently configured canonical API base path and
   workspace subject are offered. Picker times use Asia/Shanghai (UTC+08:00).
3. Choose **JSON** for exact strings, a state/coverage summary and embedded
   limitations, or **CSV** for one spreadsheet row per selected attempt. The
   picker explicitly names the API/subject, workload IDs and public audit receipts
   that will be included. Cancel either picker to leave without any status read.
4. The client reads each selected workload's current status once, sequentially.
   Progress shows completed/selected checks. Each has a 10-second local deadline;
   all 20 selected attempts can therefore take about 200 seconds if every read
   reaches its deadline. A failed check does not hide successful checks for the
   remaining requests. There is no retry, polling, inference POST or cancel POST.
5. Review the resulting plain-text, untitled document. Use normal **Save As**
   with a `.json` or `.csv` filename. No file is written automatically and the
   report is not stored in extension global state. The completion message gives
   the observed/selected count and warns that missing usage is unknown.

The export contains the API base, opaque subject, request IDs, attempt times,
request modes, individual check times, states, public audit receipts and four
reported usage fields. It excludes prompts, generated output, source document
paths, tokens, free-text error bodies and arbitrary response-envelope fields.
Review the included identifiers and receipts before sharing the file. This
command does not send or upload the report anywhere.

## Read the evidence correctly

JSON identifies itself as `lunanexa.client-activity-report.v1`. Each row's
`evidence` is one of:

- `observed`: a matching canonical status response was received. `terminal` is
  true for Succeeded, Failed, Cancelled or Rejected, and false for the other
  known states. Nonterminal state and usage can change after the check.
- `not_found`: the status endpoint returned 404. State is Unknown and terminal is
  null. This does not prove the attempt was never admitted or executed.
- `check_failed`: the check timed out, was denied, returned invalid data or
  otherwise failed. State remains Unknown; no usage is invented.

Input/output units, accelerator milliseconds and queue milliseconds are decimal
strings when reported. Missing or invalid metrics are JSON null and CSV blank.
A reported `"0"` is a known zero. Large integer strings are never converted to
floating-point totals. The JSON summary counts states and each metric's
reported/missing coverage; it does not sum potentially different model units,
price consumption, infer payment or create an invoice. The scope is selected
recent client attempts, not an organization, billing period or authoritative
usage ledger. Save the JSON if exact evidence text matters.

CSV uses UTF-8, quoted text and CRLF records. Formula-like text is prefixed with
an apostrophe for safer spreadsheet viewing; JSON preserves the original
projected text. Spreadsheet applications can still coerce quoted large numbers
or IDs: import those columns as text. CSV is a per-row projection and omits
JSON's aggregate coverage and limitations fields.

Each request is checked separately, so the report is not an atomic snapshot.
Timestamps are absolute Unix milliseconds, even though picker labels use
Asia/Shanghai. Public receipts retain the existing client's 512-character,
single-line bound; they are not independently authenticated by the export.
Successful status evidence does not recover a lost answer, prove GPU execution,
show an order/payment association or establish production qualification.

## Interrupted or changed context

Cancelling progress aborts the active status read, skips remaining reads and
opens no report. It never cancels a workload. A newer report command supersedes
an older report; extension deactivation aborts its pending read. If API base or
subject changes while choosing or collecting, subsequent reads stop and the old
report is discarded. Re-run in the intended context. These actions leave the
metadata journal unchanged. An ordinary per-row timeout or denial is instead
included as `check_failed`, so the other selected statuses remain useful.

## Verification boundary

From the repository root, without dependency installation:

```sh
node --test extensions/vscode/*.test.mjs
for file in extensions/vscode/*.mjs; do node --check "$file"; done
```

Ten new focused workflow tests run the shipped report and registered command
with Node Fetch/ReadableStream and the existing injected VS Code contract
fixture. They cover JSON and CSV review, selected subsets, known/missing usage,
partial status failures, format cancellation, progress cancellation, context
changes and supersession. The 39 existing client tests remain passing.

No real Extension Development Host, native controller, browser, provider,
physical cluster or GPU was executed for this client-only change. Actual host
Save As behavior and saved-file reopen remain unqualified. For an authorized
manual host check, select two harmless existing attempts, export each format,
save it, reopen the file as text, and compare IDs, timestamps, state and missing
usage with the displayed report. Test cancellation and a changed API context
without submitting another workload. This manual check has not been performed.

## Product rationale and limits

This is the bounded client evidence-inspection part of PRD LN09 and
LUNANEXA-R03, alongside the developer-client receipt/usage inspection in
`PLAN.md` phase 4b. It does not implement MoonGate commitment association,
commercial rating or paid-response acceptance. All control-plane, controller,
scheduler and node code remain MoonBit; the change extends the already shipped
JavaScript VS Code client without adding another backend or CLI.

For a request whose progress notification is gone, see [Cancel a recorded request](RECORDED_REQUEST_CANCELLATION.md).
