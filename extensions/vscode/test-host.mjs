// Contract fixture for production extension code, not a real VS Code host.
import { tokenBindingForUrl } from "./client-core.mjs";
export function makeHost(overrides = {}) {
  const commands = new Map(), previews = new Map(), events = [], errors = [];
  const values = { apiBaseUrl: "https://cluster.example/control", subjectRef: "subject-1", modelAlias: "text.default", deadlineSeconds: 60, maxOutputUnits: 512, ...overrides };
  const secretKey = tokenBindingForUrl(values.apiBaseUrl).secretKey;
  const secretValues = new Map([[secretKey, "test-token"]]);
  const stored = new Map();
  const context = { subscriptions: [], globalState: { get: (key, fallback) => stored.get(key) ?? fallback, update: async (key, value) => { stored.set(key, structuredClone(value)); } }, secrets: {
    get: async key => secretValues.get(key), store: async (key, value) => secretValues.set(key, value), delete: async key => secretValues.delete(key),
  } };
  let provider, closeDocument, cancelListener, cancelled = false, listenerDisposed = false, selectedText = "only selected text", empty = false, sequence = 0;
  const disposable = { dispose() {} };
  const host = {
    EventEmitter: class {
      constructor() { this.event = listener => { this.listener = listener; return disposable; }; }
      fire(uri) { events.push(uri.toString()); if (provider) previews.set(uri.toString(), provider.provideTextDocumentContent(uri)); this.listener?.(uri); }
      dispose() {}
    },
    commands: { registerCommand: (name, fn) => { commands.set(name, fn); return disposable; } },
    ProgressLocation: { Notification: 15 },
    Uri: { parse: value => ({ scheme: value.split(":")[0], toString: () => value }) },
    workspace: {
      getConfiguration: () => ({ get: (key, fallback) => values[key] ?? fallback, inspect: () => ({}) }),
      registerTextDocumentContentProvider: (_scheme, value) => { provider = value; return disposable; },
      onDidCloseTextDocument: callback => { closeDocument = callback; return disposable; },
      openTextDocument: async value => {
        if (value.content !== undefined) return { uri: host.Uri.parse(`untitled:/${++sequence}`), content: value.content };
        previews.set(value.toString(), provider.provideTextDocumentContent(value));
        return { uri: value };
      },
    },
    window: {
      activeTextEditor: { get selection() { return { isEmpty: empty }; }, document: { getText: () => selectedText } },
      showQuickPick: async choices => choices[0],
      showWarningMessage: async message => { events.push(message); },
      showErrorMessage: async message => { errors.push(message); },
      showInformationMessage: async message => { events.push(message); },
      showTextDocument: async document => { events.push({ shown: document }); },
      withProgress: async (options, task) => {
        events.push({ progress: options }); listenerDisposed = false;
        return task({ report: value => events.push({ reported: value }) }, {
          get isCancellationRequested() { return cancelled; },
          onCancellationRequested: listener => { cancelListener = listener; return { dispose() { cancelListener = undefined; listenerDisposed = true; } }; },
        });
      },
    },
    env: { openExternal: async uri => { events.push(uri.toString()); } },
  };
  return { host, context, commands, previews, events, errors, values, stored,
    cancel: () => { cancelled = true; cancelListener?.(); }, isCancelDisposed: () => listenerDisposed,
    close: uri => closeDocument({ uri }), setSelection: (text, isEmpty = false) => { selectedText = text; empty = isEmpty; } };
}
export const leaseResponse = () => Response.json({ authorized: true, active_lease: { tenant_ref: "tenant-1", limits: { capabilities: [{ capability: "TextGenerate", max_input_units_per_request: 100000, max_output_units_per_request: 512 }] } } });
export const result = (id = "vscode-test-1", state = "Succeeded") => ({ version: "lunanexa.v1", workload_id: id, state, audit_receipt: "audit-test" });
export const frame = event => `data: ${JSON.stringify(event)}\n\n`;
export const chunk = (text, sequence = 1, id = "vscode-test-1") => ({ workload_id: id, sequence, kind: "Chunk", output: { text_delta: text }, response: null });
export const terminal = (sequence = 2, id = "vscode-test-1", state = "Completed") => ({ workload_id: id, sequence, kind: state, output: null, response: result(id, state === "Completed" ? "Succeeded" : state) });
export function streamResponse(text, sizes = [Infinity]) {
  const bytes = new TextEncoder().encode(text); let offset = 0, index = 0;
  return new Response(new ReadableStream({ pull(controller) {
    if (offset >= bytes.length) { controller.close(); return; }
    const size = sizes[index++ % sizes.length]; const end = Math.min(bytes.length, offset + size);
    controller.enqueue(bytes.slice(offset, end)); offset = end;
  } }), { headers: { "content-type": "text/event-stream" } });
}
