import { ClientError } from "./request-client.mjs";
import { MAX_REQUEST_HISTORY, requestBinding, requestMetadata, checkWorkloadOutcome } from "./recovery-client.mjs";

const usageFields = { input_units: "inputUnits", output_units: "outputUnits", accelerator_ms: "acceleratorMs", queue_ms: "queueMs" };
const terminalStates = new Set(["Succeeded", "Failed", "Cancelled", "Rejected"]);
const limitations = [
  "Selected recent client attempts only; this is not an account-wide usage ledger or an invoice.",
  "Status reads occur separately and are not an atomic snapshot. Nonterminal usage can change.",
  "Not found or unavailable does not prove a request never ran. Missing usage is null, never zero.",
  "No generated output is recovered and no workload is submitted or cancelled by this report.",
  "API base, opaque subject, workload IDs and public audit receipts are included. Review before sharing.",
];

function instant(now) {
  const value = now();
  if (!Number.isSafeInteger(value) || value < 0 || value > 8_640_000_000_000_000) {
    throw new ClientError("The local report clock is invalid.");
  }
  return value;
}
function decimal(value) {
  return typeof value === "string" && /^(0|[1-9][0-9]{0,18})$/.test(value) ? value : null;
}

/** One status read per selected attempt; no request replay, automatic retry or polling. */
export async function collectActivityReport({ entries, base, subjectRef, token,
  fetchImpl = globalThis.fetch, now = Date.now, signal, isCurrent = () => true,
  onProgress = () => {}, timeoutMs = 10000 }) {
  const binding = requestBinding(base, subjectRef);
  if (!Array.isArray(entries) || !entries.length || entries.length > MAX_REQUEST_HISTORY) {
    throw new ClientError(`Select between 1 and ${MAX_REQUEST_HISTORY} recent request attempts.`);
  }
  const selected = entries.map(requestMetadata);
  const ids = new Set();
  for (const entry of selected) {
    if (!entry || entry.baseUrl !== binding.baseUrl || entry.subjectRef !== binding.subjectRef || ids.has(entry.workloadId)) {
      throw new ClientError("Report selection must contain unique requests from this API base and workspace subject.");
    }
    ids.add(entry.workloadId);
  }
  const ensureCurrent = () => {
    if (signal?.aborted) throw new ClientError("Activity report cancelled. No workload was cancelled.");
    if (!isCurrent()) throw new ClientError("API base or workspace subject changed. The previous context's report was discarded.");
  };
  ensureCurrent();
  const started = instant(now);
  const requests = [];
  for (const entry of selected) {
    ensureCurrent();
    onProgress({ completed: requests.length, total: selected.length });
    let outcome;
    try {
      outcome = await checkWorkloadOutcome({ entry, base, subjectRef, token, fetchImpl, timeoutMs, signal });
    } catch {
      // Deliberately exclude error bodies and transport diagnostics from export.
      // Continue to the other explicitly selected attempts; this row stays unknown.
    }
    ensureCurrent();
    const evidence = outcome?.found ? "observed" : outcome ? "not_found" : "check_failed";
    requests.push({
      workload_id: entry.workloadId, attempted_unix_ms: entry.createdAt, mode: entry.mode,
      checked_unix_ms: instant(now), evidence, state: outcome?.state || "Unknown",
      terminal: outcome?.found ? terminalStates.has(outcome.state) : null,
      audit_receipt: outcome?.found && outcome.receipt !== "Not reported" ? outcome.receipt : null,
      usage: Object.fromEntries(Object.entries(usageFields).map(([field, key]) => [field, decimal(outcome?.[key])])),
    });
  }
  ensureCurrent();
  onProgress({ completed: requests.length, total: selected.length });
  return {
    format: "lunanexa.client-activity-report.v1", scope: { api_base: binding.baseUrl, subject_ref: binding.subjectRef },
    started_unix_ms: started, finished_unix_ms: instant(now),
    summary: {
      selected_attempts: requests.length,
      observed: requests.filter(row => row.evidence === "observed").length,
      not_found: requests.filter(row => row.evidence === "not_found").length,
      check_failed: requests.filter(row => row.evidence === "check_failed").length,
      terminal: requests.filter(row => row.terminal === true).length,
      nonterminal: requests.filter(row => row.terminal === false).length,
      states: Object.fromEntries([...new Set(requests.map(row => row.state))].sort().map(state => [state, requests.filter(row => row.state === state).length])),
      usage_coverage: Object.fromEntries(Object.keys(usageFields).map(field => [field, {
        reported: requests.filter(row => row.usage[field] !== null).length,
        missing: requests.filter(row => row.usage[field] === null).length,
      }])),
    },
    requests, limitations: [...limitations],
  };
}

export function activityReportJson(report) {
  return JSON.stringify(report, null, 2) + "\n";
}

function csvCell(value) {
  if (value === null || value === undefined) return "";
  let text = String(value);
  if (/^[\s]*[=+@-]/.test(text) || /^[\t\r\n]/.test(text)) text = "'" + text;
  return '"' + text.replaceAll('"', '""') + '"';
}

/** Per-request projection; JSON preserves exact text and coverage/limitation detail. */
export function activityReportCsv(report) {
  const header = ["report_format", "api_base", "subject_ref", "workload_id", "attempted_unix_ms", "mode", "checked_unix_ms", "evidence", "state", "terminal", "audit_receipt", ...Object.keys(usageFields)];
  const rows = report.requests.map(row => [report.format, report.scope.api_base, report.scope.subject_ref,
    row.workload_id, row.attempted_unix_ms, row.mode, row.checked_unix_ms, row.evidence, row.state,
    row.terminal, row.audit_receipt, ...Object.keys(usageFields).map(field => row.usage[field])]);
  return [header, ...rows].map(row => row.map(csvCell).join(",")).join("\r\n") + "\r\n";
}
