import { createSelectedPrompt } from "./selected-prompt.mjs";
import { captureSelection, createSelectionReplacement } from "./selection-replacement.mjs";
import { randomUUID } from "node:crypto";
import { collectActivityReport, activityReportJson, activityReportCsv } from "./activity-report.mjs";

import {
  LEGACY_TOKEN_SECRET,
  hasWorkspaceOverride,
  normalizeSuccessfulText,
  secureUrl as parseSecureUrl,
  tokenBindingForUrl,
} from "./client-core.mjs";

import { createRequestHistory, requestBinding, checkWorkloadOutcome, outcomePreview, requestTimeLabel } from "./recovery-client.mjs";
import { createWorkloadCancellation } from "./cancellation-client.mjs";
import { ClientError, invokeStream } from "./request-client.mjs";

export function createExtension(vscode, { fetchImpl = globalThis.fetch, now = Date.now, makeId = randomUUID } = {}) {
const previews = new Map();
const changes = new vscode.EventEmitter();
const histories = new WeakMap();
const replacements = createSelectionReplacement(vscode);
const selectedPrompts = createSelectedPrompt(vscode);
let outcomeGeneration = 0;
let activityGeneration = 0;
let cancellationBusy = false;
let cancellationGeneration = 0;
let activityController;

const MAX_PAYLOAD_BYTES = 1024 * 1024;
const MAX_DISPLAY_CHARACTERS = 32 * 1024;
const IDENTIFIER = /^[A-Za-z0-9_.:-]+$/;

/** @param {vscode.ExtensionContext} context */
function activate(context) {
  histories.set(context, createRequestHistory(context.globalState));
  replacements.register(context);
  selectedPrompts.register(context);
  context.subscriptions.push(changes, vscode.workspace.registerTextDocumentContentProvider("lunanexa-result", {
    onDidChange: changes.event,
    provideTextDocumentContent: uri => previews.get(uri.toString()) || "This LunaNexa preview is no longer available.",
  }), vscode.workspace.onDidCloseTextDocument(document => {
    if (document.uri.scheme === "lunanexa-result") previews.delete(document.uri.toString());
    replacements.forget(document);
    selectedPrompts.forget(document);
  }));
  context.subscriptions.push(
    vscode.commands.registerCommand("lunanexa.configureToken", () =>
      configureToken(context),
    ),
    vscode.commands.registerCommand("lunanexa.openWorkbench", openWorkbench),
    vscode.commands.registerCommand("lunanexa.cancelRecordedRequest", () => cancelRecordedRequest(context)),
    vscode.commands.registerCommand("lunanexa.exportActivityReport", () => exportActivityReport(context)),
    vscode.commands.registerCommand("lunanexa.checkRequestOutcome", () => checkRequestOutcome(context)),
    vscode.commands.registerCommand("lunanexa.askSelection", () => sendSelection(context, false, true)),
    vscode.commands.registerCommand("lunanexa.streamSelection", () => sendSelection(context, true)),
    vscode.commands.registerCommand("lunanexa.sendSelection", () =>
      sendSelection(context),
    ),
  );
}

function deactivate() { selectedPrompts.deactivate(); replacements.deactivate(); cancellationGeneration += 1; previews.clear(); outcomeGeneration += 1; activityGeneration += 1; activityController?.abort(); }

/** @param {vscode.ExtensionContext} context */
async function configureToken(context, approvedBase) {
  try {
    const base = approvedBase || configuredApiBaseUrl();
    const binding = tokenBindingForUrl(base);
    const existing = await context.secrets.get(binding.secretKey);
    const token = await vscode.window.showInputBox({
      title: "Configure LunaNexa access token",
      prompt: `Store a scoped token only for ${binding.origin}.`,
      password: true,
      ignoreFocusOut: true,
      validateInput: (value) =>
        value.trim().length === 0 ? "Enter a non-empty scoped token." : undefined,
    });
    if (token === undefined) return false;

    const action = existing ? "Replace token" : "Store token";
    const choice = await vscode.window.showWarningMessage(
      `${action} for ${binding.origin}?`,
      {
        modal: true,
        detail:
          "Confirm the exact API origin. The token will not be available to a different scheme, host, or port.",
      },
      action,
    );
    if (choice !== action) return false;

    await context.secrets.store(binding.secretKey, token.trim());
    // Once the user explicitly approves an origin, remove the old unbound key
    // so it cannot be offered for a second, unrelated origin.
    await context.secrets.delete(LEGACY_TOKEN_SECRET);
    await vscode.window.showInformationMessage(
      `LunaNexa access token stored for ${binding.origin}.`,
    );
    return true;
  } catch (error) {
    await showSafeError(error);
    return false;
  }
}

async function openWorkbench() {
  try {
    const configured = configuration().get("workbenchUrl", "");
    const workbench = secureUrl(configured, "Workbench URL");
    await vscode.env.openExternal(vscode.Uri.parse(workbench.toString()));
  } catch (error) {
    await showSafeError(error);
  }
}

/** @param {vscode.ExtensionContext} context */
async function sendSelection(context, streaming = false, ask = false) {
  const editor = vscode.window.activeTextEditor;
  if (!editor || !editor.selection || editor.selection.isEmpty) {
    await vscode.window.showWarningMessage(
      "Select the exact text to send to LunaNexa, then run this command again.",
    );
    return;
  }

  // The selection is read only after an explicit command invocation. The
  // document, workspace, path, language and surrounding text are not sent.
  const selectedText = editor.document.getText(editor.selection);
  const sourceSelection = streaming ? undefined : captureSelection(editor, selectedText);
  const bytes = Buffer.byteLength(JSON.stringify({ input: selectedText }), "utf8");
  if (bytes > MAX_PAYLOAD_BYTES) {
    await vscode.window.showErrorMessage(
      "The selected text exceeds LunaNexa's 1 MiB canonical payload limit.",
    );
    return;
  }

  try {
    const config = configuration();
    const base = configuredApiBaseUrl(config);
    const endpoint = workloadEndpoint(base);
    const subjectRef = configuredSubjectRef(config);
    const modelAlias = validConfiguredIdentifier(
      config.get("modelAlias", ""),
      "Model alias",
    );
    const deadlineSeconds = boundedInteger(
      config.get("deadlineSeconds", 60),
      5,
      3600,
      "Deadline",
    );
    const maxOutputUnits = boundedInteger(
      config.get("maxOutputUnits", 512),
      1,
      8192,
      "Maximum output units",
    );
    // The new question flow previews a bounded, explicit instruction plus the
    // captured selection. Existing raw-send and stream commands remain unchanged.
    const expectedSettings = JSON.stringify([base.toString(), subjectRef, modelAlias, deadlineSeconds, maxOutputUnits]);
    const assertSettings = () => {
      const current = configuration();
      const settings = JSON.stringify([configuredApiBaseUrl(current).toString(), configuredSubjectRef(current),
        current.get("modelAlias", ""), current.get("deadlineSeconds", 60), current.get("maxOutputUnits", 512)]);
      if (settings !== expectedSettings) throw new ClientError("LunaNexa request settings changed. Start a new question to review the current destination and limits.");
    };
    const reviewed = ask ? await selectedPrompts.review({ source: sourceSelection,
      destination: base.toString(), modelAlias, deadlineSeconds, maxOutputUnits, assertSettings }) : undefined;
    if (ask && !reviewed) return;
    const requestText = reviewed?.input ?? selectedText;
    const requestBytes = Buffer.byteLength(JSON.stringify({ input: requestText }), "utf8");
    const token = await tokenForOrigin(context, base);
    if (!token) return;
    reviewed?.assertFresh();
    const workspace = await loadWorkspaceAuthority(
      workspaceEndpoint(base),
      token,
      subjectRef,
      deadlineSeconds * 1000,
    );
    const tenantRef = validConfiguredIdentifier(
      workspace.tenantRef,
      "Authorized tenant reference",
    );
    reviewed?.assertFresh();
    const inputUnits = requestBytes;
    if (inputUnits > workspace.maxInputUnits) {
      throw new ClientError(
        "The selected text exceeds the active workspace lease input limit.",
      );
    }
    const requestedOutputUnits = Math.min(
      maxOutputUnits,
      workspace.maxOutputUnits,
    );

    const started = now();
    const suffix = makeId();
    const workloadId = `vscode-${suffix}`;
    const envelope = {
      version: "lunanexa.v1",
      idempotency_key: `vscode-${suffix}`,
      workload_id: workloadId,
      tenant_ref: tenantRef,
      credential_scope: "inference",
      capability: "TextGenerate",
      model_selector: modelAlias,
      payload: { input: requestText },
      data_policy: {
        classification: "Confidential",
        retention: "Ephemeral",
        allow_cache: false,
        allow_training_reuse: false,
      },
      deadline_unix_ms: String(started + deadlineSeconds * 1000),
      priority: "Interactive",
      latency_class: "Realtime",
      resource_ceiling: {
        max_input_units: Math.max(1, inputUnits),
        max_output_units: requestedOutputUnits,
        max_runtime_ms: String(deadlineSeconds * 1000),
        max_accelerator_memory_mib: 8192,
      },
      stream: false,
      output_format: "text",
      trace_token: `vscode:${suffix}`,
    };

    const beforeSubmit = async () => {
      reviewed?.assertFresh();
      await histories.get(context).record({
        baseUrl: base.toString(), subjectRef, workloadId, createdAt: started,
        mode: streaming ? "stream" : "unary",
      });
      reviewed?.assertFresh();
    };
    if (streaming) {
      const uri = vscode.Uri.parse(`lunanexa-result:/${workloadId}.txt`);
      let snapshot = { state: "Streaming", text: "", receipt: "", truncated: false, complete: false };
      const update = value => {
        snapshot = { ...value, cancellation: value.cancellation || snapshot.cancellation };
        // Closing a preview does not reopen it when a late chunk arrives.
        if (!previews.has(uri.toString())) return;
        previews.set(uri.toString(), streamPreview(snapshot));
        changes.fire(uri);
      };
      previews.set(uri.toString(), streamPreview(snapshot));
      const document = await vscode.workspace.openTextDocument(uri);
      await vscode.window.showTextDocument(document, { preview: true });
      try {
        await withWorkloadProgress({ base, token, subjectRef, envelope, beforeSubmit,
          title: "Streaming selected text from LunaNexa",
          onCancellation: status => update({ ...snapshot, cancellation: status }),
        }, () => invokeStream({ endpoint: workloadEndpoint(base, true), token, subjectRef,
          envelope, timeoutMs: deadlineSeconds * 1000, onUpdate: update, fetchImpl }));
      } catch (error) {
        update({ ...snapshot, state: "Interrupted", complete: false });
        throw error;
      }
      return;
    }

    const response = await withWorkloadProgress({ base, token, subjectRef, envelope, beforeSubmit,
      title: "Sending selected text to LunaNexa",
    }, () => invoke(endpoint, token, subjectRef, envelope, deadlineSeconds * 1000));
    const resultDocument = await showResponse(response, workloadId);
    replacements.remember(resultDocument, sourceSelection, response);
  } catch (error) {
    await showSafeError(error);
  }
}

/** Bind one explicit cancel gesture to the request that owns this progress UI. */
async function withWorkloadProgress({ base, token, subjectRef, envelope, title, beforeSubmit, onCancellation = () => {} }, operation) {
  return vscode.window.withProgress({ location: vscode.ProgressLocation.Notification, title, cancellable: true }, async (progress, cancellationToken) => {
    let dispatched = false;
    let cancelledBeforeSubmission = false;
    const cancellation = createWorkloadCancellation({ base, token, subjectRef,
      workloadId: envelope.workload_id, fetchImpl,
      onStatus: status => { progress.report?.({ message: status.message }); onCancellation(status); },
    });
    const listener = cancellationToken.onCancellationRequested?.(() => {
      if (!dispatched) cancelledBeforeSubmission = true;
      else void cancellation.request();
    });
    try {
      if (cancelledBeforeSubmission || cancellationToken.isCancellationRequested) {
        throw new ClientError("Request cancelled before submission. No workload was sent.");
      }
      await beforeSubmit();
      if (cancelledBeforeSubmission || cancellationToken.isCancellationRequested) {
        throw new ClientError("Request cancelled before submission. No workload was sent.");
      }
      dispatched = true;
      return await operation();
    } finally {
      listener?.dispose();
      cancellation.finish();
    }
  });
}

/** Explicit status-only recovery, never a resubmission or generated-text fetch. */
async function checkRequestOutcome(context) {
  const generation = ++outcomeGeneration;
  try {
    const config = configuration();
    const base = configuredApiBaseUrl(config);
    const subjectRef = configuredSubjectRef(config);
    const binding = requestBinding(base, subjectRef);
    const stillCurrent = () => {
      const current = requestBinding(configuredApiBaseUrl(), configuredSubjectRef(configuration()));
      return generation === outcomeGeneration && current.baseUrl === binding.baseUrl && current.subjectRef === binding.subjectRef;
    };
    const records = histories.get(context).list(base, subjectRef);
    if (!records.length) {
      await vscode.window.showInformationMessage("No recorded LunaNexa requests for this API base and workspace subject.");
      return;
    }
    const choices = records.map(entry => ({ label: `${requestTimeLabel(entry.createdAt)} · ${entry.mode}`,
      description: entry.workloadId, detail: "Inspect status and receipt only; generated output is not recovered.", entry }));
    const selected = await vscode.window.showQuickPick(choices, { title: "Check a LunaNexa request outcome", placeHolder: "Choose a recorded request attempt" });
    if (!selected || !choices.includes(selected) || generation !== outcomeGeneration) return;
    if (!stillCurrent()) throw new ClientError("API base or workspace subject changed. Choose the request again in its original context.");
    const token = await tokenForOrigin(context, base);
    if (!token || generation !== outcomeGeneration) return;
    if (!stillCurrent()) throw new ClientError("API base or workspace subject changed. The status check was not sent.");
    const outcome = await checkWorkloadOutcome({ entry: selected.entry, base, subjectRef, token, fetchImpl });
    if (generation !== outcomeGeneration) return;
    if (!stillCurrent()) throw new ClientError("API base or workspace subject changed. The previous context's result was not displayed.");
    const uri = vscode.Uri.parse(`lunanexa-result:/status/${selected.entry.workloadId}-${generation}.txt`);
    previews.set(uri.toString(), outcomePreview(selected.entry, outcome));
    const document = await vscode.workspace.openTextDocument(uri);
    if (generation !== outcomeGeneration || !stillCurrent()) { previews.delete(uri.toString()); return; }
    await vscode.window.showTextDocument(document, { preview: true });
  } catch (error) {
    if (generation === outcomeGeneration) await showSafeError(error);
  }
}

/** Recover cancellation after a progress notification or editor session was lost. */
async function cancelRecordedRequest(context) {
  if (cancellationBusy) {
    await vscode.window.showInformationMessage("A recorded-request cancellation is already in progress.");
    return;
  }
  cancellationBusy = true;
  const generation = ++cancellationGeneration;
  let cancellation;
  try {
    const base = configuredApiBaseUrl();
    const subjectRef = configuredSubjectRef(configuration());
    const binding = requestBinding(base, subjectRef);
    const ensureCurrent = () => {
      const current = requestBinding(configuredApiBaseUrl(), configuredSubjectRef(configuration()));
      if (generation !== cancellationGeneration || current.baseUrl !== binding.baseUrl || current.subjectRef !== binding.subjectRef)
        throw new ClientError("API base or workspace subject changed. Start cancellation again in its original context.");
    };
    const entries = histories.get(context).list(base, subjectRef);
    if (!entries.length) {
      await vscode.window.showInformationMessage("No recorded LunaNexa requests for this API base and workspace subject.");
      return;
    }
    const choices = entries.map(entry => ({ label: requestTimeLabel(entry.createdAt) + " · " + entry.mode,
      description: entry.workloadId, detail: "Read current status before requesting cancellation.", entry }));
    const selected = await vscode.window.showQuickPick(choices, { title: "Cancel a recorded LunaNexa request" });
    if (!selected) return;
    if (!choices.includes(selected)) throw new ClientError("Choose a request from the current list.");
    ensureCurrent();
    const token = await tokenForOrigin(context, base);
    if (!token) return;
    ensureCurrent();
    const outcome = await checkWorkloadOutcome({ entry: selected.entry, base, subjectRef, token, fetchImpl });
    ensureCurrent();
    if (!outcome.found) {
      await vscode.window.showWarningMessage("This workload was not found. No cancellation was sent; its execution outcome remains unknown.");
      return;
    }
    if (["Succeeded", "Failed", "Cancelled", "Rejected"].includes(outcome.state)) {
      await vscode.window.showInformationMessage("Workload " + selected.entry.workloadId + " is already " + outcome.state + ". No cancellation was sent.");
      return;
    }
    const action = "Request cancellation";
    const choice = await vscode.window.showWarningMessage("Cancel LunaNexa workload " + selected.entry.workloadId + "?", {
      modal: true, detail: "API: " + binding.baseUrl + "\nSubject: " + subjectRef + "\nObserved state: " + outcome.state +
        "\nThis can stop queued or running generation. An accepted request does not prove termination. Work may complete before cancellation arrives.",
    }, action);
    if (choice !== action) return;
    ensureCurrent();
    cancellation = createWorkloadCancellation({ base, subjectRef, token, workloadId: selected.entry.workloadId, fetchImpl });
    const receipt = await cancellation.request();
    ensureCurrent();
    let latest;
    try { latest = await checkWorkloadOutcome({ entry: selected.entry, base, subjectRef, token, fetchImpl }); }
    catch { /* An unavailable read cannot erase the cancellation request receipt. */ }
    ensureCurrent();
    const content = ["LunaNexa recorded-request cancellation", "", "Workload: " + selected.entry.workloadId,
      "API base: " + binding.baseUrl, "Subject: " + subjectRef, "Cancellation request: " + receipt.state,
      ...(receipt.receipt ? ["Cancellation receipt: " + receipt.receipt] : []), receipt.message, "",
      latest ? outcomePreview(selected.entry, latest) : "Follow-up status unavailable. The workload outcome remains unknown.", "",
      "Cancellation acceptance is not terminal execution evidence. Use Check Request Outcome for another explicit status read.",
      "No workload was resubmitted. No automatic retry or polling was started."].join("\n");
    const document = await vscode.workspace.openTextDocument({ language: "plaintext", content });
    ensureCurrent();
    await vscode.window.showTextDocument(document, { preview: false });
  } catch (error) {
    if (generation === cancellationGeneration) await showSafeError(error);
  } finally {
    cancellation?.finish();
    cancellationBusy = false;
  }
}

/** Review selected recent attempts in a saveable local report, without replaying them. */
async function exportActivityReport(context) {
  const generation = ++activityGeneration;
  activityController?.abort();
  const controller = new AbortController();
  activityController = controller;
  try {
    const base = configuredApiBaseUrl();
    const subjectRef = configuredSubjectRef(configuration());
    const binding = requestBinding(base, subjectRef);
    const stillCurrent = () => {
      const current = requestBinding(configuredApiBaseUrl(), configuredSubjectRef(configuration()));
      return generation === activityGeneration && current.baseUrl === binding.baseUrl && current.subjectRef === binding.subjectRef;
    };
    const ensureCurrent = () => {
      if (!stillCurrent()) throw new ClientError("API base or workspace subject changed. Start the report again in its intended context.");
    };
    const records = histories.get(context).list(base, subjectRef);
    if (!records.length) {
      await vscode.window.showInformationMessage("No recorded LunaNexa requests for this API base and workspace subject.");
      return;
    }
    const choices = records.map(entry => ({ label: requestTimeLabel(entry.createdAt) + " · " + entry.mode,
      description: entry.workloadId, detail: "Read current status and usage once; no generated output or resubmission.", entry }));
    const selected = await vscode.window.showQuickPick(choices, { canPickMany: true,
      title: "Export LunaNexa request activity", placeHolder: "Select recent attempts from " + binding.baseUrl + " · subject " + binding.subjectRef });
    if (generation !== activityGeneration || !selected?.length) return;
    if (!Array.isArray(selected) || selected.some(choice => !choices.includes(choice))) throw new ClientError("Choose request attempts from the current list.");
    ensureCurrent();
    const formats = [{ label: "JSON", description: "Exact text, coverage summary and limitations", format: "json" },
      { label: "CSV", description: "One row per attempt; blank usage means missing, never zero", format: "csv" }];
    const format = await vscode.window.showQuickPick(formats, { title: "Choose activity report format",
      placeHolder: "Includes API/subject, workload IDs and public audit receipts. Review before sharing." });
    if (generation !== activityGeneration || !format) return;
    if (!formats.includes(format)) throw new ClientError("Choose one of the report formats.");
    ensureCurrent();
    const token = await tokenForOrigin(context, base);
    if (!token || generation !== activityGeneration) return;
    ensureCurrent();
    const report = await vscode.window.withProgress({ location: vscode.ProgressLocation.Notification,
      title: "Reading LunaNexa request activity", cancellable: true }, async (progress, cancellationToken) => {
      const listener = cancellationToken.onCancellationRequested?.(() => controller.abort());
      if (cancellationToken.isCancellationRequested) controller.abort();
      try {
        return await collectActivityReport({ entries: selected.map(choice => choice.entry), base, subjectRef, token,
          fetchImpl, now, signal: controller.signal, isCurrent: stillCurrent,
          onProgress: ({ completed, total }) => progress.report?.({ message: completed + "/" + total + " status checks" }) });
      } finally { listener?.dispose(); }
    });
    if (generation !== activityGeneration || controller.signal.aborted) return;
    ensureCurrent();
    const content = format.format === "json" ? activityReportJson(report) : activityReportCsv(report);
    // Plain text avoids rendering external content. Normal Save As is the only disk write.
    const document = await vscode.workspace.openTextDocument({ language: "plaintext", content });
    if (generation !== activityGeneration || controller.signal.aborted || !stillCurrent()) return;
    await vscode.window.showTextDocument(document, { preview: false });
    if (generation !== activityGeneration || !stillCurrent()) return;
    await vscode.window.showInformationMessage("Activity report: " + report.summary.observed + "/" + report.summary.selected_attempts +
      " statuses observed. Use Save As with ." + format.format + ". Missing usage is unknown; this is not an invoice. Review before sharing.");
  } catch (error) {
    if (generation === activityGeneration && !controller.signal.aborted) await showSafeError(error);
  } finally {
    if (activityController === controller) activityController = undefined;
  }
}

/** @returns {vscode.WorkspaceConfiguration} */
function configuration() {
  return vscode.workspace.getConfiguration("lunanexa");
}

/**
 * Refuse stale or hand-authored workspace overrides even though the manifest
 * declares this security-sensitive setting as machine scoped.
 *
 * @param {vscode.WorkspaceConfiguration} [config]
 */
function configuredApiBaseUrl(config = configuration()) {
  const inspected = config.inspect("apiBaseUrl");
  if (hasWorkspaceOverride(inspected)) {
    throw new ClientError(
      "API base URL must be configured in user or machine settings, not workspace settings.",
    );
  }
  return secureUrl(config.get("apiBaseUrl", ""), "API base URL");
}

/** @param {vscode.WorkspaceConfiguration} config */
function configuredSubjectRef(config) {
  const inspected = config.inspect("subjectRef");
  if (hasWorkspaceOverride(inspected)) {
    throw new ClientError(
      "Workspace subject reference must be configured in user or machine settings, not workspace settings.",
    );
  }
  return validConfiguredIdentifier(
    config.get("subjectRef", ""),
    "Workspace subject reference",
  );
}

/**
 * Load only the token previously approved for this origin. A legacy unbound
 * token is migrated once, and only after the user confirms the exact origin.
 *
 * @param {vscode.ExtensionContext} context
 * @param {URL} base
 */
async function tokenForOrigin(context, base) {
  const binding = tokenBindingForUrl(base);
  const bound = await context.secrets.get(binding.secretKey);
  if (bound) return bound;

  const legacy = await context.secrets.get(LEGACY_TOKEN_SECRET);
  if (legacy) {
    const action = "Bind token and continue";
    const choice = await vscode.window.showWarningMessage(
      `Bind the existing LunaNexa token to ${binding.origin}?`,
      {
        modal: true,
        detail:
          "This one-time migration replaces the legacy unbound token. Confirm the scheme, host, and port before continuing.",
      },
      action,
    );
    if (choice !== action) return "";
    await context.secrets.store(binding.secretKey, legacy);
    await context.secrets.delete(LEGACY_TOKEN_SECRET);
    return legacy;
  }

  const choice = await vscode.window.showWarningMessage(
    `No LunaNexa access token is stored for ${binding.origin}.`,
    "Configure token",
  );
  if (choice !== "Configure token") return "";
  const stored = await configureToken(context, base);
  return stored ? (await context.secrets.get(binding.secretKey)) || "" : "";
}

/** @param {string} value @param {string} label */
function secureUrl(value, label) {
  try {
    return parseSecureUrl(value, label);
  } catch (error) {
    const message = error instanceof Error
      ? error.message
      : `${label} is not valid.`;
    throw new ClientError(message);
  }
}

/** @param {URL} base */
function workloadEndpoint(base, streaming = false) {
  const endpoint = new URL(base.toString());
  endpoint.pathname = `${endpoint.pathname.replace(/\/$/, "")}/v1/workloads${streaming ? ":stream" : ""}`;
  return endpoint;
}

/** @param {URL} base */
function workspaceEndpoint(base) {
  const endpoint = new URL(base.toString());
  endpoint.pathname = `${endpoint.pathname.replace(/\/$/, "")}/v1/workspace/self`;
  return endpoint;
}

/** @param {unknown} value @param {string} label */
function validConfiguredIdentifier(value, label) {
  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 256 ||
    !IDENTIFIER.test(value)
  ) {
    throw new ClientError(
      `${label} must be a non-empty opaque identifier using only letters, digits, '.', '_', ':', or '-'.`,
    );
  }
  return value;
}

/** @param {unknown} value @param {number} min @param {number} max @param {string} label */
function boundedInteger(value, min, max, label) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new ClientError(`${label} must be an integer from ${min} to ${max}.`);
  }
  return value;
}

/**
 * @param {URL} endpoint
 * @param {string} token
 * @param {string} subjectRef
 * @param {object} envelope
 * @param {number} timeoutMs
 */
async function invoke(endpoint, token, subjectRef, envelope, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(endpoint, {
      method: "POST",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        "X-LunaNexa-Subject": subjectRef,
      },
      body: JSON.stringify(envelope),
      redirect: "error",
      signal: controller.signal,
    });

    const body = await readBoundedJson(response);
    if (!response.ok) {
      const details =
        body?.error && typeof body.error === "object" ? body.error : body;
      const code = boundedString(details?.code, 80) || `HTTP ${response.status}`;
      const message =
        boundedString(details?.message, 400) || "Request rejected.";
      const receipt = boundedString(details?.correlation_receipt, 256);
      throw new ClientError(
        `${code}: ${message}${receipt ? ` Receipt: ${receipt}` : ""}`,
      );
    }
    return body;
  } catch (error) {
    if (error instanceof ClientError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new ClientError("The LunaNexa request reached its local deadline.");
    }
    throw new ClientError("The LunaNexa request could not be completed.");
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * @param {URL} endpoint
 * @param {string} token
 * @param {string} subjectRef
 * @param {number} timeoutMs
 */
async function loadWorkspaceAuthority(endpoint, token, subjectRef, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(endpoint, {
      method: "GET",
      headers: {
        Accept: "application/json",
        Authorization: `Bearer ${token}`,
        "X-LunaNexa-Subject": subjectRef,
      },
      redirect: "error",
      signal: controller.signal,
    });
    const body = await readBoundedJson(response);
    if (!response.ok) {
      const details = body?.error && typeof body.error === "object"
        ? body.error
        : body;
      const code = boundedString(details?.code, 80) || `HTTP ${response.status}`;
      const message = boundedString(details?.message, 400) ||
        "Workspace authority was rejected.";
      throw new ClientError(`${code}: ${message}`);
    }
    const lease = body?.authorized === true && body?.active_lease;
    const capabilities = Array.isArray(lease?.limits?.capabilities)
      ? lease.limits.capabilities
      : [];
    const textLimit = capabilities.find(
      (limit) => limit?.capability === "TextGenerate",
    );
    if (!lease || !textLimit) {
      throw new ClientError(
        "An active text-generation workspace lease is required.",
      );
    }
    return {
      tenantRef: lease.tenant_ref,
      maxInputUnits: boundedInteger(
        textLimit.max_input_units_per_request,
        1,
        10_000_000,
        "Workspace input limit",
      ),
      maxOutputUnits: boundedInteger(
        textLimit.max_output_units_per_request,
        1,
        1_000_000,
        "Workspace output limit",
      ),
    };
  } catch (error) {
    if (error instanceof ClientError) throw error;
    if (error instanceof Error && error.name === "AbortError") {
      throw new ClientError("Workspace discovery reached its local deadline.");
    }
    throw new ClientError("Workspace authority could not be loaded.");
  } finally {
    clearTimeout(timeout);
  }
}

/** @param {Response} response */
async function readBoundedJson(response) {
  const contentLength = Number(response.headers.get("content-length") || "0");
  if (contentLength > MAX_PAYLOAD_BYTES) {
    throw new ClientError("LunaNexa returned an unexpectedly large response.");
  }
  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > MAX_PAYLOAD_BYTES) {
    throw new ClientError("LunaNexa returned an unexpectedly large response.");
  }
  try {
    return JSON.parse(text);
  } catch {
    throw new ClientError("LunaNexa returned an invalid JSON response.");
  }
}

/** @param {unknown} response @param {string} expectedWorkloadId */
async function showResponse(response, expectedWorkloadId) {
  if (!response || typeof response !== "object") {
    throw new ClientError("LunaNexa returned an invalid canonical response.");
  }
  if (response.version !== "lunanexa.v1" || response.workload_id !== expectedWorkloadId) {
    throw new ClientError("LunaNexa returned a mismatched canonical response.");
  }

  const state = boundedSingleLine(response.state, 40) || "Unknown";
  const receipt = boundedSingleLine(response.audit_receipt, 512) || "Unavailable";
  const normalized = normalizeSuccessfulText(
    response,
    MAX_DISPLAY_CHARACTERS,
  );
  const errorCode = boundedString(response.error?.code, 80);
  const errorMessage = boundedString(response.error?.message, 500);
  const failure = errorCode || errorMessage
    ? `${errorCode || "Request failed"}: ${errorMessage || "No public error details returned."}`
    : "";
  const output = failure || normalized.text || "No text output returned.";
  const truncated = !failure && normalized.truncated;
  const content = [
    "LunaNexa result",
    "",
    `State: ${state}`,
    `Audit receipt: ${receipt}`,
    `Output bounded to: ${MAX_DISPLAY_CHARACTERS} characters`,
    "",
    "Normalized text output",
    "",
    output,
    ...(truncated ? ["", "Output was truncated locally."] : []),
  ].join("\n");

  const document = await vscode.workspace.openTextDocument({
    // Plain text prevents model output from rendering Markdown links, images,
    // or raw HTML that could trigger unintended external requests.
    language: "plaintext",
    content,
  });
  await vscode.window.showTextDocument(document, { preview: true });
  return document;
}

/** @param {unknown} value @param {number} maximum */
function boundedString(value, maximum) {
  return typeof value === "string" ? value.slice(0, maximum) : "";
}

/** @param {unknown} value @param {number} maximum */
function boundedSingleLine(value, maximum) {
  return boundedString(value, maximum).replace(/[\r\n\u2028\u2029]/g, " ");
}

/** @param {unknown} error */
async function showSafeError(error) {
  const message =
    error instanceof ClientError ? error.message : "The LunaNexa operation failed.";
  await vscode.window.showErrorMessage(message);
}

function streamPreview(snapshot) {
  return ["LunaNexa streaming result", "", `State: ${snapshot.state}`,
    `Audit receipt: ${snapshot.receipt || "Not yet available"}`,
    ...(snapshot.error ? [`Public error: ${snapshot.error}`] : []),
    ...(snapshot.cancellation ? [`Cancellation: ${snapshot.complete ? "Cancellation was requested; the terminal outcome is shown above." : snapshot.cancellation.message}`] : []),
    ...(snapshot.cancellation?.receipt ? [`Cancellation receipt: ${snapshot.cancellation.receipt}`] : []),
    snapshot.complete ? "A canonical terminal event was received." : "Received text is incomplete until a canonical terminal event arrives.",
    `Output bounded to: ${MAX_DISPLAY_CHARACTERS} characters`, "", "Normalized text output", "", snapshot.text,
    ...(snapshot.truncated ? ["", "Output was truncated locally."] : [])].join("\n");
}
return { activate, deactivate };
}
