# Ask about selected text without changing the source

**LunaNexa: Ask About Selected Text** lets an API developer ask for an explanation,
summary or rewrite of an exact editor selection. The instruction is composed
separately, so the user need not insert a prompt into their source document.
This is a narrow addition to the actual PRD's lease-requester/API-developer job
and LN04 / LUNANEXA-B08 scoped-model-access journey. It is not proof of live model
access, commercial eligibility, paid-response acceptance or GPU execution.

## Compose, inspect, send and use

1. Select the exact passage you want the configured model to receive. Run
   **LunaNexa: Ask About Selected Text** from the Command Palette or context menu.
2. Write an instruction such as `Explain this code's control flow` or `Rewrite
   this paragraph concisely; return only its replacement`. Cancel to stop.
3. A read-only plain-text document shows the API base, configured model, deadline,
   output limit and exact `payload.input`. The user instruction and selected
   source are separate; the source is represented as a quoted JSON string.
   Escapes such as `\n` represent the original newlines, not lost content.
4. Read and scroll the preview. In the nonmodal notification choose **Send
   reviewed prompt** to proceed, **Cancel**, or dismiss the notification. Closing
   the preview also prevents its pending send. No API request, lease discovery,
   request-history entry or inference occurs before choosing Send.
5. After confirmation, normal origin-bound token handling and current workspace
   lease discovery run, followed by one canonical unary request. If the token is
   absent, the existing token setup can still require its own explicit approval.
   The result opens as ordinary bounded plain text. No source text is changed.
6. If the answer is intentionally a replacement, use **Review Selection
   Replacement** and its separate **Apply Reviewed Replacement** confirmation.
   The original source range is retained, so the review compares its exact text
   to the answer, rather than comparing the composed prompt to the answer.
   Explanation text should normally remain a separate result document.

An answer is generated content requiring review. Quoting separates content for
the reader and model but cannot enforce prompt-injection protection, truth,
correctness or applicability. The extension never executes or automatically
applies a generated answer.

## Scope and interruption behavior

- Existing **Send Selected Text** and **Stream Selected Text** still send only
  the raw selected text. They do not add the new instruction or prompt review.
- Instructions must be nonblank, at most 4,096 UTF-16 code units and contain no
  NUL. The entire composed `{input: ...}` JSON must fit the existing 1 MiB limit,
  then the current lease input limit. JSON quoting can increase the payload size.
  Only the composed input is sent; source path, language, surrounding text,
  repository and workspace files are not added.
- The canonical request retains Confidential/Ephemeral policy, no cache or
  training reuse, origin-bound token, scoped lease limits and bounded output.
  The lease can reduce the previewed maximum output setting. Server authority
  remains necessary; this client does not confer access.
- A document edit (even outside the range), closure, or change to the reviewed
  destination/subject/model/deadline/output limit requires a new question. Checks
  run after asynchronous review, token handling and lease discovery and around
  the pre-dispatch journal write. Changing only the active editor does not alter
  the captured source selection. The user can inspect the preview freely.
- One question review may be pending at a time. A repeated gesture does not
  create another preview or request. Cancellation, dismissal or closing the
  review never counts as approval. Extension deactivation invalidates pending
  reviews. Source changes after dispatch do not cancel inference but prevent
  using a stale result in the separate replacement workflow.
- The prompt review is activation-memory-only and expires when its decision is
  made; its open virtual document changes to an expired notice. No instruction,
  source path or generated answer is added to global state or SecretStorage.
  Existing metadata-only history records attempts immediately before dispatch.
  If a last-moment change prevents dispatch after that write, the record remains
  an attempt, not evidence of execution. Results remain user-saveable untitled
  documents as before; no automatic filesystem save occurs.
- Request failure is reported without rewriting source or resubmitting. A timeout
  can leave an uncertain server outcome; use **Check Request Outcome** for
  status-only recovery. That command cannot retrieve missing generated output.

## Focused verification and limits

From the repository root:

```sh
node --test extensions/vscode/*.test.mjs
(cd extensions/vscode && npm run check)
```

Tests invoke the actual registered command with the existing injected editor
contract and mock Fetch responses. They verify exact preview/payload identity,
no requests before confirmation, source immutability, result-to-original diff,
metadata-only history, ordinary cancellation and repetition, and recovery from
source/setting changes or request failure. They do not contact a provider.

A real VS Code Extension Host, scrollable notification placement, readonly UI,
editor Undo/Save, native controller, live inference, provider, commercial and
physical GPU gates were NOT executed. No network, dependency installation or
Moon invocation was needed. R50 remains the last fully verified cumulative
result; R51–55 are separate.
