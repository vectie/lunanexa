import test from "node:test";
import assert from "node:assert/strict";
import { createExtension } from "./extension-host.mjs";
import { makeHost, leaseResponse, result } from "./test-host.mjs";

function setup(output = "a clearer sentence", state = "Succeeded") {
  const h = makeHost(), requests = [], providers = new Map(), edits = [], diffs = [];
  const selection = { isEmpty: false, start: { line: 0, character: 7 }, end: { line: 0, character: 22 } };
  let text = "before original words after", previous;
  const source = { uri: h.host.Uri.parse("file:///local/draft.txt"), version: 1, isClosed: false,
    getText: range => range ? text.slice(range.start.character, range.end.character) : text };
  // The chosen range contains fifteen characters, including its trailing space.
  const sourceEditor = { document: source, selection, edit: async (callback, options) => {
    const operations = [];
    callback({ replace: (range, value) => operations.push({ range, value }) });
    if (h.rejectEdit) return false;
    previous = text;
    for (const { range, value } of operations) text = text.slice(0, range.start.character) + value + text.slice(range.end.character);
    source.version++; edits.push({ operations, options }); return true;
  } };
  h.host.window.activeTextEditor = sourceEditor;
  h.host.workspace.registerTextDocumentContentProvider = (scheme, provider) => { providers.set(scheme, provider); return { dispose() {} }; };
  let sequence = 0;
  h.host.workspace.openTextDocument = async value => value.content !== undefined
    ? { uri: h.host.Uri.parse(`untitled:/result-${++sequence}`), content: value.content }
    : { uri: value, content: providers.get(value.scheme).provideTextDocumentContent(value) };
  h.host.window.showTextDocument = async document => {
    h.events.push({ shown: document });
    const editor = document === source ? sourceEditor : { document };
    h.host.window.activeTextEditor = editor; return editor;
  };
  h.host.commands.executeCommand = async (command, original, proposed, title, options) => {
    assert.equal(command, "vscode.diff");
    const left = await h.host.workspace.openTextDocument(original), right = await h.host.workspace.openTextDocument(proposed);
    diffs.push({ left, right, title, options }); await h.host.window.showTextDocument(right);
  };
  h.host.window.showWarningMessage = async (_message, _options, action) => action;
  const extension = createExtension(h.host, { makeId: () => "test-1", fetchImpl: async (url, init) => {
    requests.push({ url: String(url), init });
    if (String(url).endsWith("/workspace/self")) return leaseResponse();
    return Response.json({ ...result("vscode-test-1", state), output });
  } });
  extension.activate(h.context);
  return { ...h, requests, source, sourceEditor, edits, diffs, extension,
    send: () => h.commands.get("lunanexa.sendSelection")(),
    review: () => h.commands.get("lunanexa.reviewSelectionReplacement")(),
    apply: () => h.commands.get("lunanexa.applyReviewedReplacement")(),
    change: value => { text = value; source.version++; }, getText: () => text,
    undoFixture: () => { text = previous; source.version++; },
  };
}

test("sent selection becomes reviewed local replacement with isolated edit transaction", async () => {
  const h = setup({ text: "better words " });
  const original = h.getText(), selected = h.source.getText(h.sourceEditor.selection);
  await h.send();
  assert.equal(JSON.parse(h.requests[1].init.body).payload.input, selected);
  assert.equal(h.requests.length, 2);
  assert.equal(h.getText(), original);
  await h.review();
  assert.equal(h.diffs[0].left.content, selected);
  assert.equal(h.diffs[0].right.content, "better words ");
  assert.equal(h.getText(), original);
  await h.apply();
  assert.equal(h.getText(), "before better words after");
  assert.equal(h.requests.length, 2, "review and apply make no network calls");
  assert.deepEqual(h.edits[0].options, { undoStopBefore: true, undoStopAfter: true });
  assert.equal(h.edits[0].operations.length, 1);
  // This fixture models restoration only; it does not qualify actual VS Code Undo.
  h.undoFixture(); assert.equal(h.getText(), original);
  assert.equal(JSON.stringify([...h.stored.values()]).includes("better words"), false);
  assert.equal(JSON.stringify([...h.stored.values()]).includes("original words"), false);
  h.host.window.activeTextEditor = { document: h.diffs[0].right };
  await h.apply(); assert.equal(h.edits.length, 1);
});

test("cancelling confirmation preserves document and permits later explicit application", async () => {
  const h = setup("approved text "); await h.send(); await h.review();
  const original = h.getText(); h.host.window.showWarningMessage = async () => undefined;
  await h.apply(); assert.equal(h.getText(), original); assert.equal(h.edits.length, 0);
  h.host.window.showWarningMessage = async (_message, _options, action) => action;
  await h.apply(); assert.equal(h.edits.length, 1);
});

test("a source edit before review requires a new selection request", async () => {
  const h = setup(); await h.send(); h.change("a revised source"); await h.review();
  assert.equal(h.diffs.length, 0); assert.match(h.errors.at(-1), /changed or closed/);
  assert.equal(h.requests.length, 2); assert.equal(h.getText(), "a revised source");
});

test("a source edit during confirmation cannot be overwritten by the old result", async () => {
  const h = setup(); await h.send(); await h.review();
  h.host.window.showWarningMessage = async (_message, _options, action) => { h.change("newer manual work"); return action; };
  await h.apply(); assert.equal(h.edits.length, 0); assert.equal(h.getText(), "newer manual work");
  assert.match(h.errors.at(-1), /changed or closed/);
});

test("only complete direct text can enter the replacement journey", async t => {
  for (const [name, output, state] of [["failed", "partial", "Failed"], ["empty", "", "Succeeded"],
    ["truncated", "x".repeat(32769), "Succeeded"], ["JSON fallback", { other: "data" }, "Succeeded"]]) {
    await t.test(name, async () => {
      const h = setup(output, state); await h.send(); await h.review();
      assert.equal(h.diffs.length, 0); assert.equal(h.edits.length, 0);
      assert.match(h.errors.at(-1), /retained successful/);
    });
  }
});

test("closed source and extension deactivation retire captured replacement authority", async () => {
  const h = setup({ output_text: "candidate" }); await h.send(); await h.review();
  h.source.isClosed = true; await h.apply(); assert.equal(h.edits.length, 0);
  h.source.isClosed = false; h.extension.deactivate(); await h.apply();
  assert.equal(h.edits.length, 0); assert.match(h.errors.at(-1), /inspect its diff/);
});

test("failed editor transaction retains the review for a deliberate retry", async () => {
  const h = setup(); await h.send(); await h.review(); const review = h.diffs[0].right;
  // Replace edit with a host refusal, then retry through the still-open review.
  const edit = h.sourceEditor.edit; h.sourceEditor.edit = async () => false;
  await h.apply(); assert.equal(h.edits.length, 0); assert.match(h.errors.at(-1), /did not apply/);
  h.sourceEditor.edit = edit; h.host.window.activeTextEditor = { document: review };
  await h.apply(); assert.equal(h.edits.length, 1);
});

test("closing the originating result while confirmation is pending prevents application", async () => {
  const h = setup(); await h.send(); const resultDocument = h.host.window.activeTextEditor.document;
  await h.review(); h.host.window.showWarningMessage = async (_message, _options, action) => { h.close(resultDocument.uri); return action; };
  await h.apply(); assert.equal(h.edits.length, 0); assert.match(h.errors.at(-1), /changed or closed/);
});
