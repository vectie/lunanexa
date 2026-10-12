# Use a generated answer in its original selection

The VS Code client can now carry a successful **Send Selected Text** or **Ask About Selected Text** answer back
into the exact selection that produced it, after a separate local review. This
closes a small part of the actual PRD's lease-requester/API-developer job and
LN04 / LUNANEXA-B08 scoped-model-access journey. It is not evidence of paid
inference, live lease enforcement or the PRD's actual-response acceptance gate.
The existing preview-only client required manual copying without preserving the
connection to the source range.

1. Select the exact text to send and run **LunaNexa: Send Selected Text**. The
   request still sends only that selection; no filename, surrounding text or
   replacement instruction is added. Configure/use an appropriate model prompt.
2. With the successful result document active, run **LunaNexa: Review Selection
   Replacement**. A read-only plain-text diff shows only the captured selection
   and exact returned text, without receipts or other response metadata.
3. Inspect the diff. It does not edit the source. Generated code and prose may
   be incorrect; the extension neither executes nor verifies the answer.
4. With either side of that diff active, run **LunaNexa: Apply Reviewed
   Replacement**. Review the original local target in the confirmation and
   choose **Replace selected text**, or cancel to keep your document unchanged.
5. The original range is replaced in one editor edit with undo stops before
   and after. It is not saved, executed or transmitted again. Use normal editor
   Undo to revert, and Save only when ready.

## Scope and recovery

The separate [question workflow](SELECTED_TEXT_QUESTIONS.md) retains the original
selection for this same review, rather than treating its composed prompt as source.

Only nonempty direct text from a canonical matching `Succeeded` unary response
is eligible, at most 32,768 UTF-16 units. The existing supported `output` string,
`output.text` and `output.output_text` shapes are accepted. Empty, partial,
failed, interrupted, streamed, JSON-fallback and locally truncated results are
not replacement candidates. Ordinary previews and streaming are unchanged.

The source document object, its exact version, original selection range and
selected text are captured before the request. Any source edit, even outside
the range or an edit followed by Undo, requires a new request and review. Closing
the source also invalidates the candidate. Checks occur before review, before
and after confirmation, and immediately before creating the edit. The editor
can refuse the transaction; that is reported without claiming success.
Cancelling retains the review. A successful application is consumed once; it
cannot be repeated after Undo without a new request. If a transaction is refused,
inspect the original and deliberately reopen the still-available diff to retry.

At most five successful result candidates survive in activation memory. Oldest
candidates are retired when the limit is reached. Closing a result retires its
candidate and associated review. Closing one diff side drops that side's
content; its other side can remain usable. Reloading/deactivating the extension
clears everything. If a candidate has expired, use a new selection request.
No prompt, answer, source path or captured selection is added to global state,
SecretStorage or files. Existing metadata-only request history is unchanged.
Untitled result documents may be manually saved by the user as before.

Review/application are entirely local and do not recheck server state, submit
another inference, change a lease or establish commercial acceptance. A local
API or subject setting change does not alter the captured source-range binding.
This is an explicit text-edit workflow, not an editor agent or a remote shell.

## Focused verification

From the repository root:

    node --test extensions/vscode/*.test.mjs
    cd extensions/vscode && npm run check

The focused tests invoke the actual registered send/review/apply commands through
an injected editor contract and mock HTTP responses. They exercise exact selection
transmission, diff contents, unchanged surrounding text, one edit and undo-stop
options, cancellation, stale source, failed host transaction and candidate
retirement. The fixture's restoration check does not execute VS Code Undo.
Actual Extension Host commands, diff layout, readonly UI behavior, host Undo/Redo,
Save, filesystem permissions, native controller, providers and physical GPU
execution remain unqualified. No dependency install, network or Moon invocation
was used. R50 is the last fully verified cumulative result; R51–55 are separate.
