# LunaNexa for VS Code

This is a small northbound client for LunaNexa's canonical `lunanexa.v1`
provider contract. It can store a scoped bearer token, open the separately
hosted developer workbench, and send an explicitly selected editor range as a
non-streaming `TextGenerate` workload after resolving the active workspace
lease. Ask About Selected Text can separately compose and review an explicit
instruction with that selection before sending. It requires VS Code 1.100 or newer,
whose Node.js extension host supports ECMAScript module extensions.

## Trust boundary

- The access token is stored only in VS Code `SecretStorage`, under a key bound
  to the canonical API origin. It is never put in workspace/user settings, a
  URL, output, or a log. Changing the scheme, host, or port cannot silently
  reuse a token approved for another origin.
- **LunaNexa: Send Selected Text** sends only the current non-empty selection.
  **Ask About Selected Text** sends a separately reviewed instruction plus that
  quoted selection only after explicit preview confirmation. The extension does not send the whole file,
  filename, repository, workspace, language identifier, surrounding text, or
  editor telemetry.
- Every request uses `Ephemeral` retention with caching and training reuse
  disabled. The extension cannot opt selected text into evaluation capture or
  model training.
- HTTPS is mandatory except for `http://localhost`, `127.0.0.1`, or `[::1]`
  development. Redirects are rejected so the bearer token is not forwarded.
- This client provides no DGX login, remote shell, filesystem mount,
  repository checkout, or editor-agent runtime. Those capabilities do not
  belong on a LunaNexa managed node. The manifest classifies the extension as
  a local UI client rather than a remote workspace extension.
- The displayed output is limited to 32 KiB. The client accepts the current
  canonical `output.text` and `output.output_text` shapes, or a bounded JSON
  rendering of the `output` value only. It never renders the whole response.
  Results open as plain text so generated Markdown, images, and HTML cannot
  trigger external requests. Receipts and errors are separately bounded, and
  raw request payloads are never logged.

The opaque subject reference and model alias are normal VS Code configuration,
not secrets. The API URL and subject reference are machine scoped, preventing a
repository from selecting a different credential destination or loopback
identity. Production ingress must replace a client-supplied subject with its
authenticated identity mapping; the explicit setting supports a trusted proxy
or loopback acceptance. Keep identifiers free of personal, project,
repository, and product identity. Use a short-lived token limited to the
`inference` credential scope.

## Configure

Install or run the extension, then set:

- `lunanexa.apiBaseUrl` to the management ingress base URL in VS Code's user or
  machine settings. This setting is machine scoped and workspace overrides are
  refused. The extension posts to `<base>/v1/workloads`.
- `lunanexa.workbenchUrl` to the separately hosted Rabbita workbench.
- `lunanexa.subjectRef` in user or machine settings, to the opaque subject used
  by the trusted identity proxy or loopback controller. Like the API URL, a
  workspace override is refused. The extension discovers tenant scope and
  text-generation limits from `/v1/workspace/self`.
- `lunanexa.modelAlias` to an approved provider-neutral text model alias.
- Optional deadline and maximum-output settings.

Run **LunaNexa: Configure Access Token** from the Command Palette to store the
token securely. Confirm the exact canonical origin shown by the modal. Do not
put a token into `settings.json`. A token saved by the earlier unbound format
is migrated only after the same explicit origin confirmation; cancelling
leaves it unbound and sends nothing.

## Manual test

1. Open this directory in VS Code and press **F5** to launch an Extension
   Development Host.
2. In the development host, configure a loopback test controller such as
   `http://127.0.0.1:8080`, an opaque workspace subject, and a deployed model
   alias.
3. Run **LunaNexa: Configure Access Token** and enter a scoped test credential.
4. Open a scratch document, select only a harmless test phrase, and run
   **LunaNexa: Send Selected Text** from the Command Palette or editor menu.
5. Verify that a preview document shows bounded normalized output and the
   audit receipt. Verify that an empty selection sends nothing.
6. Stop or revoke the test credential and confirm the extension shows only the
   controller's bounded public error and any provided correlation receipt.
7. Run **LunaNexa: Open Developer Workbench** and confirm the configured URL
   opens without credentials in it.

For syntax and pure client-security tests (without installing dependencies),
run:

```sh
npm run check
npm test
```

## Current limitations

The extension does not implement automatic token issuance/refresh or
external-tool handoffs. It discovers the active
text-generation lease before each invocation, while final access and
concurrency enforcement remain server responsibilities. This initial client
expects a JSON response from `POST /v1/workloads` and shows only the canonical
text output and receipt.


## Stream selected text

Run **LunaNexa: Stream Selected Text** with a nonempty selection. It uses the
same origin-bound token and live workspace lease discovery as the unary command,
then calls the published canonical `/v1/workloads:stream` endpoint. A read-only
plain-text virtual document updates as normalized text arrives. Closing it never
reopens it on later chunks; it does not edit or insert into the source document.

The preview displays at most 32,768 UTF-16 code units, with explicit truncation.
A canonical terminal event and matching workload identity are required to show
completion. On an interrupted stream, received text stays visible and is labeled
incomplete. It is not automatically retried or resubmitted. Streaming output is
not resumable: the server deliberately omits generated output from durable
receipts. Nontext event metadata is not rendered or executed.

The reader bounds each event to 1 MiB, a stream to 16 MiB and 65,536 events, and
checks sequence order, workload identity, terminal state and JSON/UTF-8 framing.
The configured deadline covers the network request and body read. No prompts,
output, document paths or tokens are written to extension storage. The bounded
request metadata journal described below is the only additional persisted state.

### Focused verification boundary

`node --test *.test.mjs` executes the production transport and registered command
logic with built-in Fetch/ReadableStream and an injected VS Code contract
fixture. It includes incremental Unicode, interrupted streams, close while
pending, identity/sequence rejection, receipt states and bounded display. These
are client behavior tests, not a real VS Code Extension Host, native controller,
provider or GPU qualification. `node --check` validates each shipped module.
The repository's native/console phase gate still needs its unavailable dependency
prerequisites and was not run for this JavaScript-only change.

For host verification, run the development extension against an authorized test
controller, use a long selected-text request, observe text before completion,
then disconnect once midstream and inspect the incomplete preview. Close a
preview while pending and confirm it stays closed. This host journey remains
unperformed in the dependency-free environment.


## Cancel the current request

Both **Send Selected Text** and **Stream Selected Text** expose a Cancel control
in their progress notification. The control sends one cancellation request for
that exact workload to the captured API base, using the same origin-bound token
and subject. Repeated cancellation gestures never submit additional requests.
Cancelling before submission prevents the workload POST entirely.

A matching HTTP 202 cancellation receipt means the server accepted the request;
it does not mean the workload has reached `Cancelled`. The existing invocation
continues to observe the actual result. A generation can finish successfully
while cancellation is racing, in which case `Succeeded` remains the outcome.
A denial, missing workload, timeout, invalid receipt or transport error is shown
as unconfirmed cancellation, without automatic retry. Local network abort is
never presented as confirmed server cancellation. Cancellation has its own
10-second response deadline and cannot outlive the completed invocation's UI.

A streamed preview preserves received text and shows cancellation status plus
any accepted receipt. Late cancellation responses cannot overwrite a terminal
result. Closing a preview still does not reopen it. These client semantics are
covered through the registered command and transport adapter in Node; actual
VS Code controls and server resource release remain unqualified here.


## Check an uncertain request outcome

After a timeout, disconnection or lost preview, run **LunaNexa: Check Request
Outcome**. Choose a recent request attempt for the currently configured API base
and workspace subject. The command performs one authenticated status GET and
shows canonical state, usage and audit receipt in a plain-text preview. It never
submits the original selection again, automatically polls, or fetches generated
output. A `404` is shown as unknown; it does not prove that the request never ran.
`Succeeded` confirms the recorded outcome, not recovery of missing answer text.

Before each unary or streamed workload dispatch, the extension saves a bounded
journal of at most 20 attempts in VS Code global state. Each record contains only
the approved API base URL, opaque subject, generated workload ID, timestamp and
request mode. It contains no prompt, generated output, document path or token.
Picker timestamps use Asia/Shanghai (UTC+08:00), while stored timestamps remain
absolute milliseconds. Records are attempts, not proof of server admission. A cancellation during a
pending journal write can leave an attempt that was never submitted. A failed
journal write prevents dispatch and reports that no workload was submitted.
Concurrent writes are serialized; a new extension activation can read the same
metadata. Only references in this extension's generated `vscode-*` namespace are
accepted, and dot-segment IDs are rejected before URL construction.

The picker filters the exact canonical API base (including path) and subject.
Changing either while choosing or loading a record prevents cross-context
requests or display. Tokens still come only from origin-bound SecretStorage.
Cancelling the picker does nothing; an older status response cannot overwrite a
newer explicit check. Every status request has a local 10-second deadline.

Focused combined verification is `node --test *.test.mjs`: production command,
transport and metadata logic run through Node/VS Code contract adapters. The
actual Extension Host global-state durability and native controller integration
remain unperformed, as do all MoonBit/native/hardware gates. For an authorized
host check, interrupt a test request, reload the extension, choose its recorded
attempt, and verify the one GET result without any second workload POST.

## Export selected request activity

Run **LunaNexa: Export Request Activity Report**, select recent attempts from the
current API base and subject, then choose JSON or CSV. The command reads each
selected status once and opens a plain-text report for normal **Save As**. It
includes exact reported usage and explicit unavailable/missing evidence without
resubmitting requests, recovering generated text, pricing usage or writing the
report to extension storage. Cancel stops the reads, not the workloads.

See [the activity report guide](../../docs/CLIENT_ACTIVITY_REPORT_QUICKSTART.md)
for field meanings, incomplete checks, context changes, privacy and verification
limits. The report includes identifiers and public receipts; review before
sharing. Ten new workflow tests extend the dependency-free client suite to 49
passing tests. Real VS Code Save As and native/provider integration were not run.

## Review and apply a local selection replacement

After **Send Selected Text**, activate its successful result and run **Review
Selection Replacement**. Inspect the original/proposed plain-text diff, then
run **Apply Reviewed Replacement** from the diff and confirm the original
local target. The extension edits only the captured unchanged range, in one
undo-delimited editor transaction, without saving or another inference call.
See [the replacement guide](../../docs/REVIEWED_SELECTION_REPLACEMENT.md) for
eligible outputs, five-candidate memory retention, stale-source recovery and
qualification limits. Actual VS Code Undo and diff UI were not executed here.

## Ask a question about the selection

Use **LunaNexa: Ask About Selected Text** to explain, summarize or request a
rewrite without inserting prompt instructions into the source document. Inspect
the exact read-only preview, then choose **Send reviewed prompt** or Cancel.
See [the question workflow](../../docs/SELECTED_TEXT_QUESTIONS.md) for exact
payload, interruption, privacy and verification boundaries.
