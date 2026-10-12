# Review and download a guide diagnostic support report

The existing bilingual administrator Guide Diagnostics page can now turn its
last successfully displayed response into a selected local JSON report. An
operator can retain the relevant troubleshooting evidence with its support
receipt instead of copying cards or forwarding a screenshot without context.
The prior page had no downloadable handoff. This is a focused output workflow
for the actual PRD's cluster-operator job and LN01 discrepancy inspection, using
the allowlisted administrator diagnostics in
[Operations §5](OPERATIONS_COMMERCE_ACCESS_AND_GUIDE.md#5-guide-pet-and-administrator-diagnostics).
It does not perform reconciliation, request support, or establish LN01's
named-cluster acceptance.

## Use the existing operator page

1. Open `admin.html` on your already authorized LunaNexa coursebook deployment.
   Its existing role-protected diagnostics request must succeed. No new identity,
   token, permission, controller endpoint or deployment setting is introduced.
2. In **Local support report / 本地支持报告**, choose the sections to retain.
   Component health/reconciliation, alert codes/counts and knowledge freshness
   are selected by default. Fleet counts and skill dependencies are opt-in.
3. Choose **Review report / 查看报告**. Read the complete scrollable JSON. Review
   does not download, upload, mutate a cluster, or make another API request.
4. Choose **Download reviewed JSON / 下载已审阅的 JSON**. The browser receives
   exactly the previewed UTF-8 JSON, with a suggested filename such as
   `lunanexa-guide-support-1780000000000.json`. The page reports only that a
   download was requested. Verify the file in your browser downloads or save
   dialog; the page cannot confirm that the filesystem save completed.
5. Alternatively, choose **Cancel / 取消** to discard the review without a
   download. A new review is required after a successful download or failed
   download attempt. Keep the file in authorized private storage and review it
   again before separately sharing it with a support recipient.

Selections affect only the output, not the existing diagnostic request. This is
not a way to fetch otherwise unavailable evidence. The JSON field names,
protocol values and limitations are stable English text; the surrounding
controls and status messages support English and Simplified Chinese.

## What the file means

`lunanexa.guide-support-report.v1` contains:

- `observed_unix_ms`: the original server diagnostic projection timestamp.
  It is not overwritten by review/download time, and is not a guarantee that
  the separate controller observations were simultaneous or current.
- `report_created_unix_ms`: the local browser timestamp when this exact report
  was prepared for review. It is not a receipt of a completed file save. Browser
  and server clocks can differ; no clock synchronization is claimed.
- `correlation_receipt`: the existing diagnostic support reference, retained
  exactly. This file does not independently authenticate a receipt or revision.
- `selected_sections` and `sections`: only the explicitly selected aggregate
  sections, emitted in stable order regardless of selection order.
- `missing_evidence` and `limitations`: always present so a narrow report does
  not silently lose unavailable-evidence warnings and scope limitations.

The health section contains component states and the reconciliation count;
alerts contain typed codes/counts; fleet contains node/lease state counts and
truncation flags; knowledge contains revision/age/staleness; skills contain
names, versions, enabled/health state, required/missing evidence and runbook IDs.
The report intentionally projects these fields rather than copying arbitrary
response properties. It does not include raw logs, prompt/answer text, node IDs,
lease IDs, subject identities, credentials, server-side actor/audit records,
source paths, arbitrary upstream properties or the full controller snapshot.
Runbook IDs remain identifiers, without an added deployment URL.

When the diagnostic response lists alerts, nodes, leases or reconciliation as
missing evidence, the corresponding exported subsection says
`"evidence": "missing"` and omits the fallback numeric counters. Missing is
unknown, not zero. A reported zero with available evidence is preserved as zero,
but the file still does not prove complete collection or absence of a problem.
Known truncation flags are preserved; other upstream partial collection may not
be detectable. No totals are extrapolated or priced.

This is a bounded operational report, not a public-data sanitizer, registry
backup, live incident feed, authoritative billing statement, signed attestation,
or proof of physical service. Receipts, configuration revisions, capability
names and aggregate infrastructure state can still be private.

## Refresh, changes and limits

- Changing a section clears the old preview and requires another review.
- Refresh clears the old payload and review immediately, disables output while
  pending, and enables review only after a new successful response. A failed
  refresh cannot download the previous observation. Language changes retain
  the existing page behavior of refreshing, so they also invalidate review.
- Cancellation clears the generated report but leaves the current displayed
  observation available for another deliberate selection/review.
- No report is stored in local/session storage or sent anywhere. Existing locale
  preference storage is unchanged. The report and its source response remain
  page-memory state; normal browser lifecycle/cache behavior is not a secure
  erasure guarantee. Downloaded copies are controlled by the user.
- Output is capped at 128 KiB UTF-8 and validates the selected fields and their
  bounds before exposing any preview. Invalid/oversized evidence produces an
  error, not a partial file. The existing diagnostics response budget remains
  64 KiB. At least one section is required.
- The export never refreshes or rechecks live authority on its own. It uses the
  response already available on the page; refresh if a newer observation is
  needed. Nothing changes tenant, operator or controller authority.

## Focused verification and remaining gates

Run from the repository root, without installing anything:

```sh
node --test docs-site/admin-report.test.mjs docs-site/guide-diagnostics.test.mjs extensions/vscode/*.test.mjs
node --check docs-site/admin-report.js
node --check docs-site/admin.js
```

The new tests execute the shipped page's actual event handlers, with small
DOM/download adapters, and the real server-side diagnostic projection. They
cover both the current controller aggregate shape and legacy projection inputs,
selected outputs, exact preview/download identity, timestamps, missing/zero
counts, stale/truncated state, cancellation, repeated actions, refresh success
and failure, language changes and download refusal. Fetch responses and browser
interfaces are fixtures. No socket listener, external request, provider,
dependency installation or Moon invocation is used.

The broader `node --test docs-site/*.test.mjs extensions/vscode/*.test.mjs`
run also encounters an existing coursebook source-digest failure for
`README.mbt.md`. The same failure was reproduced on the exact unchanged R544
baseline. The published source ledger is retained unchanged rather than being
relabeled as newly inspected. This report does not fix or qualify that ledger.

Actual browser layout, focus/keyboard/screen-reader behavior, Content Security
Policy download handling, browser Back/Forward/cache lifecycle and filesystem
Save/Reopen have not been executed. Neither a live authenticated proxy/controller,
container image build, native application, provider, payment nor physical GPU
has been qualified. R50 remains the last fully verified cumulative result;
R51–55 remain separate.
