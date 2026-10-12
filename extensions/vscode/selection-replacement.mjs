// Local editor workflow. Captured selections/results live only for this activation.
import { ClientError } from "./request-client.mjs";

const LIMIT = 5;
const MAX_TEXT = 32 * 1024;

export function captureSelection(editor, text) {
  const document = editor.document;
  if (!document.uri || !Number.isInteger(document.version) || document.isClosed) return undefined;
  const range = editor.selection;
  return { document, version: document.version, range, text };
}

function replacementText(response) {
  if (response?.state !== "Succeeded" || response.error) return undefined;
  const output = response.output;
  const text = typeof output === "string" ? output
    : typeof output?.text === "string" ? output.text
    : typeof output?.output_text === "string" ? output.output_text : undefined;
  return typeof text === "string" && text.length > 0 && text.length <= MAX_TEXT ? text : undefined;
}

export function createSelectionReplacement(vscode) {
  const results = new Map(), reviews = new Map(), content = new Map();
  let next = 0, active = true, busy = false;
  const fresh = record => {
    if (!active || results.get(record.uri) !== record || record.source.document.isClosed || record.source.document.version !== record.source.version ||
        record.source.document.getText(record.source.range) !== record.source.text) {
      throw new ClientError("The original document changed or closed. Select its current text and request a new result before reviewing a replacement.");
    }
  };
  const remove = record => {
    results.delete(record.uri);
    for (const [key, value] of reviews) if (value === record) { reviews.delete(key); content.delete(key); }
  };
  const run = async operation => {
    if (busy) return vscode.window.showInformationMessage("Finish the current selection replacement first.");
    busy = true;
    try { await operation(); }
    catch (error) { await vscode.window.showErrorMessage(error instanceof ClientError ? error.message : "The local replacement could not be completed."); }
    finally { busy = false; }
  };
  return {
    register(context) {
      context.subscriptions.push(vscode.workspace.registerTextDocumentContentProvider("lunanexa-replacement", {
        provideTextDocumentContent: uri => content.get(uri.toString()) ?? "This replacement review is no longer available.",
      }), vscode.commands.registerCommand("lunanexa.reviewSelectionReplacement", () => run(async () => {
        const record = results.get(vscode.window.activeTextEditor?.document.uri?.toString());
        if (!record) throw new ClientError("Open a retained successful selected-text result first. Streaming, partial, empty and truncated results cannot replace text.");
        fresh(record);
        const original = vscode.Uri.parse(`lunanexa-replacement:/${++next}/original.txt`);
        const proposed = vscode.Uri.parse(`lunanexa-replacement:/${next}/proposed.txt`);
        // One review pair per result; reopening the review releases its previous pair.
        for (const [key, value] of reviews) if (value === record) { reviews.delete(key); content.delete(key); }
        for (const [uri, text] of [[original, record.source.text], [proposed, record.text]]) {
          reviews.set(uri.toString(), record); content.set(uri.toString(), text);
        }
        await vscode.commands.executeCommand("vscode.diff", original, proposed,
          "LunaNexa: original selection ↔ proposed replacement", { preview: false });
      })), vscode.commands.registerCommand("lunanexa.applyReviewedReplacement", () => run(async () => {
        const record = reviews.get(vscode.window.activeTextEditor?.document.uri?.toString());
        if (!record) throw new ClientError("Open Review Selection Replacement and inspect its diff before applying.");
        fresh(record);
        const action = "Replace selected text";
        const choice = await vscode.window.showWarningMessage("Apply this reviewed LunaNexa replacement?", { modal: true,
          detail: `Target: ${record.source.document.uri.toString()}\nOnly the originally selected range is replaced. Review generated text for correctness. This edits the local document without saving or running it.` }, action);
        if (choice !== action) return;
        fresh(record);
        const editor = await vscode.window.showTextDocument(record.source.document, { preview: false });
        fresh(record);
        if (editor?.document !== record.source.document) throw new ClientError("The original document is not available for editing.");
        // TextEditor.edit submits against the editor document's current version.
        // There is no await between the final freshness check and edit creation.
        const applied = await editor.edit(builder => builder.replace(record.source.range, record.text), { undoStopBefore: true, undoStopAfter: true });
        if (!applied) throw new ClientError("The editor did not apply the replacement. Check the original document before trying again.");
        remove(record);
        await vscode.window.showInformationMessage("Reviewed selection replaced. Use normal editor Undo to revert; save only when ready.");
      })));
    },
    remember(document, source, response) {
      const text = replacementText(response);
      if (!active || !source || text === undefined) return;
      const uri = document.uri.toString();
      results.set(uri, { uri, source, text });
      while (results.size > LIMIT) remove(results.values().next().value);
    },
    forget(document) {
      const record = results.get(document.uri.toString());
      if (record) remove(record);
      // Closing a diff side does not discard the other still-open side.
      reviews.delete(document.uri.toString()); content.delete(document.uri.toString());
    },
    deactivate() { active = false; results.clear(); reviews.clear(); content.clear(); },
  };
}
