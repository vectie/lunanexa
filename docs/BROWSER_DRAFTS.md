# Create, manage and reopen browser-local drafts

LunaNexa's developer workbench is part of the infrastructure/model-service
plane. This feature does not introduce a company front door, repository checkout
or managed-node file access.

## Create and manage files

1. In **Project drafts**, choose **New draft**. Enter a unique **Draft name**
   and a **Draft language** label, then choose **Save draft**. The new, empty
   file becomes active in the existing editor. An empty project supports this
   same flow; no seed file is required.
2. Type in the editor. Choose **Duplicate** to name an exact copy of the active
   draft. Its content and language are preserved; the copy is appended and
   becomes active. No name is generated silently.
3. Choose **Rename**, edit the name, then **Save draft**. The active draft keeps
   its position, language and exact content. Other files are untouched.
4. Choose **Cancel** to discard a staged name/language change without changing
   files or selection. Opening or repeatedly clicking a control never creates
   a file; only one successful Save applies. Repeated Save is inert. Navigating
   to a file, reopening a packet, changing connection/identity, or selecting an
   editor/integration handoff dismisses an unfinished form.
5. **Export drafts** to save the complete authored file set. Reopen it using
   the preview-and-confirm flow below. There is no automatic persistence.

Names and language labels retain their exact Unicode, whitespace and casing;
only blank/whitespace-only values are rejected. Names must be exactly unique.
The form explains validation failures and stays open for correction. Empty
content is valid. Creation, duplication, renaming and editing are atomic: a
size/count/name failure changes no files, selection or input revision.

Local file changes clear prior generated output/receipt. If a request was
already running, editing, creating, duplicating, renaming, changing the selected
file, instruction or model does not send or cancel another request. The original
request remains busy until it settles. Its completion still records usage;
output/receipt are hidden if its input revision has changed. Late failures are
marked as belonging to the earlier input, and authorization failures still
invalidate the lease. Consecutive requests carry distinct context generations,
so a duplicate old callback cannot finish a newer request. Repeated Send while
busy emits no additional command.

## Save and continue

1. In the existing authorized developer workbench, choose **Export drafts**.
   Keep the downloaded `lunanexa-browser-drafts.json` private: it contains your
   authored draft text.
2. In the workbench's Project drafts panel, use **Reopen exported drafts** to
   choose that file with the ordinary browser file picker.
3. Inspect **Preview imported drafts**. Expand each name to read its text.
   Choosing a file only prepares this preview; your current drafts stay intact.
4. Export your current drafts first if you need to keep them. Choose **Replace
   current drafts** to replace the complete draft list. Generated output and its
   receipt are cleared because they belong to the previous drafts.
5. Continue editing in the existing editor, then export again to save changes.
   The exported v1 packet can be reopened through the same flow.

**Cancel reopen** discards a preview or pending read. Closing the native file
picker without selecting a file leaves drafts unchanged. Editing or switching a
draft, choosing an external-editor handoff, starting an inference request,
changing the connection/identity, opening a New/Duplicate/Rename form, or
selecting a newer file invalidates an
older read/preview. Repeated callbacks cannot replace drafts. Selecting the same
file again is supported. While an inference request is in flight, reopening and
replacement are disabled so its result cannot attach to newly replaced drafts.

## Format and limits

The format remains `lunanexa.browser-drafts.v1`, with exactly `format` and `files`
at the top level. Each file has exactly `path`, `language`, and `content`, all
strings. The order of files, Unicode, quotes, CRLF/LF newlines and text are
preserved. Draft names are exact, case-sensitive virtual labels. A name that
resembles a relative path, absolute path or URL is still only a label; no path
normalization, filesystem write, URL navigation or code execution occurs.

Import accepts UTF-8 JSON up to 16 MiB and 4 Mi UTF-16 code units, with parser
nesting limited to 8. A packet contains 1–64 files. Names and languages must not
be blank; names are at most 512 code units, languages 64, and each file's content
1 Mi code units. Total field text must fit 4 Mi code units. Duplicate decoded
names, unsupported formats, malformed/wrong-type/missing/extra fields and
over-limit packets are rejected. Empty file content is allowed; an empty packet
is rejected to avoid accidental clearing. Local creation, duplication, rename
and editing reuse the same field bounds and also check the actual serialized v1
JSON size, including escaping and formatting, against the 4 Mi code-unit read
limit. This ensures newly saved edits can be reopened. Larger historical exports require
reducing their contents to these displayed import bounds before reopening.

The file-read bridge captures the selected File synchronously, clears the
native input for retry, validates both declared and actual byte bounds, and
strictly decodes UTF-8. It reads only that selected File. Read/parse errors show
bounded localized messages without echoing private file contents or host errors.

## Boundaries

Only authored draft fields are exported. Authentication, current identity,
endpoint, model selection, lease, usage, instruction, integrations, generated
output and receipts are not in the packet. Import cannot replace those
authorities or grant request access. Text and names are rendered through Rabbita
text nodes, including in the expandable preview.

Reopening performs no upload, inference request, provider call, local-storage
save or filesystem write. Explicit export invokes the existing browser download
bridge. An explicit later **Send request** remains subject to the existing live
lease, model and request rules. Drafts still live only in this page; export
before reloading, closing the page or changing browsers.

## Verification scope

Regression tests cover packet validation, exact text roundtrips, preview and
replacement, creation from empty, duplicate/rename, exact Unicode/newline text,
preservation of current authority, size/count/escaped-JSON bounds, cancellation,
repeat actions, stale workload/read callbacks and navigation. Compiled JS host
fixtures execute the production File reader and Blob/download bridge plus the
actual application reducer. They use real host File and Blob objects, with a
synthetic DOM/download host and controllable File reads. Local actions are
asserted to return the exact no-effect command. These are not claims of
physical browser file-picker clicks, disk-save acceptance, provider execution or
deployment. Native tests cover the shared UI state/decoder and renderer.
