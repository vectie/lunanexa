import * as vscode from "vscode";
import { randomUUID } from "node:crypto";

import {
  LEGACY_TOKEN_SECRET,
  hasWorkspaceOverride,
  normalizeSuccessfulText,
  secureUrl as parseSecureUrl,
  tokenBindingForUrl,
} from "./client-core.mjs";

const MAX_PAYLOAD_BYTES = 1024 * 1024;
const MAX_DISPLAY_CHARACTERS = 32 * 1024;
const IDENTIFIER = /^[A-Za-z0-9_.:-]+$/;

/** @param {vscode.ExtensionContext} context */
export function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("lunanexa.configureToken", () =>
      configureToken(context),
    ),
    vscode.commands.registerCommand("lunanexa.openWorkbench", openWorkbench),
    vscode.commands.registerCommand("lunanexa.sendSelection", () =>
      sendSelection(context),
    ),
  );
}

export function deactivate() {}

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
async function sendSelection(context) {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.selection.isEmpty) {
    await vscode.window.showWarningMessage(
      "Select the exact text to send to LunaNexa, then run this command again.",
    );
    return;
  }

  // The selection is read only after an explicit command invocation. The
  // document, workspace, path, language and surrounding text are not sent.
  const selectedText = editor.document.getText(editor.selection);
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
    const token = await tokenForOrigin(context, base);
    if (!token) return;
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
    const inputUnits = bytes;
    if (inputUnits > workspace.maxInputUnits) {
      throw new ClientError(
        "The selected text exceeds the active workspace lease input limit.",
      );
    }
    const requestedOutputUnits = Math.min(
      maxOutputUnits,
      workspace.maxOutputUnits,
    );

    const now = Date.now();
    const suffix = randomUUID();
    const workloadId = `vscode-${suffix}`;
    const envelope = {
      version: "lunanexa.v1",
      idempotency_key: `vscode-${suffix}`,
      workload_id: workloadId,
      tenant_ref: tenantRef,
      credential_scope: "inference",
      capability: "TextGenerate",
      model_selector: modelAlias,
      payload: { input: selectedText },
      data_policy: {
        classification: "Confidential",
        retention: "Ephemeral",
        allow_cache: false,
        allow_training_reuse: false,
      },
      deadline_unix_ms: String(now + deadlineSeconds * 1000),
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

    const response = await vscode.window.withProgress(
      {
        location: vscode.ProgressLocation.Notification,
        title: "Sending selected text to LunaNexa",
        cancellable: false,
      },
      () => invoke(
        endpoint,
        token,
        subjectRef,
        envelope,
        deadlineSeconds * 1000,
      ),
    );
    await showResponse(response, workloadId);
  } catch (error) {
    await showSafeError(error);
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
function workloadEndpoint(base) {
  const endpoint = new URL(base.toString());
  endpoint.pathname = `${endpoint.pathname.replace(/\/$/, "")}/v1/workloads`;
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
    const response = await fetch(endpoint, {
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
    const response = await fetch(endpoint, {
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

class ClientError extends Error {}
