import { secureUrl } from "./client-core.mjs";
import { workloadOperationEndpoint } from "./cancellation-client.mjs";
import { ClientError, canonicalResponse, readBoundedJson, responseError } from "./request-client.mjs";

export const REQUEST_HISTORY_KEY = "lunanexa.requestHistory.v1";
export const MAX_REQUEST_HISTORY = 20;
const IDENTIFIER = /^[A-Za-z0-9_.:-]{1,256}$/;
const STATES = ["Submitted", "Admitted", "Queued", "Running", "Streaming", "Succeeded", "Failed", "Cancelled", "Rejected"];

export function requestBinding(base, subjectRef) {
  const url = secureUrl(base, "API base URL");
  url.pathname = url.pathname.replace(/\/+$/, "") || "/";
  if (typeof subjectRef !== "string" || !IDENTIFIER.test(subjectRef)) {
    throw new ClientError("The workspace subject reference is invalid.");
  }
  return { baseUrl: url.toString(), subjectRef };
}

export function requestMetadata(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      typeof value.workloadId !== "string" || !/^vscode-[A-Za-z0-9_-]{1,249}$/.test(value.workloadId) ||
      !Number.isSafeInteger(value.createdAt) || value.createdAt < 0 || value.createdAt > 8_640_000_000_000_000 ||
      !["unary", "stream"].includes(value.mode)) return null;
  try {
    // Explicit projection: never persist any additional request/envelope fields.
    return { ...requestBinding(value.baseUrl, value.subjectRef), workloadId: value.workloadId,
      createdAt: value.createdAt, mode: value.mode };
  } catch { return null; }
}

/** Small metadata journal; prompt, output and credential bytes never enter it. */
export function createRequestHistory(storage) {
  let writes = Promise.resolve();
  const read = () => {
    const stored = storage.get(REQUEST_HISTORY_KEY, []);
    return Array.isArray(stored) ? stored.slice(0, MAX_REQUEST_HISTORY).map(requestMetadata).filter(Boolean) : [];
  };
  return {
    list(base, subjectRef) {
      const binding = requestBinding(base, subjectRef);
      return read().filter(item => item.baseUrl === binding.baseUrl && item.subjectRef === binding.subjectRef);
    },
    record(value) {
      const entry = requestMetadata(value);
      if (!entry) return Promise.reject(new ClientError("Request recovery metadata is invalid. No workload was submitted."));
      const write = writes.catch(() => {}).then(async () => {
        try {
          const previous = read().filter(item => !(item.workloadId === entry.workloadId &&
            item.baseUrl === entry.baseUrl && item.subjectRef === entry.subjectRef));
          await storage.update(REQUEST_HISTORY_KEY, [entry, ...previous].slice(0, MAX_REQUEST_HISTORY));
        } catch {
          throw new ClientError("Request recovery metadata could not be saved. No workload was submitted.");
        }
      });
      writes = write;
      return write;
    },
  };
}

function displayText(value, maximum) {
  return typeof value === "string" ? value.slice(0, maximum).replace(/[\r\n\u2028\u2029]/g, " ") : "Not reported";
}
function units(value) {
  if (Number.isSafeInteger(value) && value >= 0) return String(value);
  if (typeof value === "string" && /^(0|[1-9][0-9]{0,18})$/.test(value)) return value;
  return "Not reported";
}

/** Exactly one read-only check. Generated output is deliberately discarded. */
export async function checkWorkloadOutcome({ entry, base, subjectRef, token, fetchImpl = globalThis.fetch, timeoutMs = 10000, signal }) {
  const saved = requestMetadata(entry);
  const current = requestBinding(base, subjectRef);
  if (!saved || saved.baseUrl !== current.baseUrl || saved.subjectRef !== current.subjectRef) {
    throw new ClientError("This request belongs to a different API base or workspace subject.");
  }
  const endpoint = workloadOperationEndpoint(current.baseUrl, saved.workloadId);
  const controller = new AbortController();
  const abort = () => controller.abort();
  signal?.addEventListener("abort", abort, { once: true });
  if (signal?.aborted) controller.abort();
  const timeout = setTimeout(abort, timeoutMs);
  try {
    if (signal?.aborted) throw new ClientError("The status check was cancelled. The workload outcome is still unknown.");
    const response = await fetchImpl(endpoint, {
      method: "GET", redirect: "error", signal: controller.signal,
      headers: { Accept: "application/json", Authorization: `Bearer ${token}`, "X-LunaNexa-Subject": current.subjectRef },
    });
    if (response.status === 404) {
      await response.body?.cancel().catch(() => {});
      return { state: "Unknown", receipt: "Not available", found: false };
    }
    if (!response.ok) throw await responseError(response);
    const result = canonicalResponse(await readBoundedJson(response), saved.workloadId);
    if (!STATES.includes(result.state)) throw new ClientError("LunaNexa returned an invalid workload state.");
    return { state: result.state, found: true, receipt: displayText(result.audit_receipt, 512),
      inputUnits: units(result.usage?.input_units), outputUnits: units(result.usage?.output_units),
      acceleratorMs: units(result.usage?.accelerator_ms), queueMs: units(result.usage?.queue_ms),
      error: result.error ? displayText(result.error.message, 400) : "" };
  } catch (error) {
    if (signal?.aborted) throw new ClientError("The status check was cancelled. The workload outcome is still unknown.");
    if (controller.signal.aborted) throw new ClientError("The status check reached its local deadline. The workload outcome is still unknown.");
    if (error instanceof ClientError) throw error;
    throw new ClientError("The status check could not be completed. The workload outcome is still unknown.");
  } finally {
    clearTimeout(timeout);
    signal?.removeEventListener("abort", abort);
  }
}

export function outcomePreview(entry, outcome) {
  return ["LunaNexa request outcome", "", `Workload: ${entry.workloadId}`, `API base: ${entry.baseUrl}`,
    `State: ${outcome.state}`, `Audit receipt: ${outcome.receipt}`,
    ...(outcome.found ? [`Input units: ${outcome.inputUnits}`, `Output units: ${outcome.outputUnits}`,
      `Accelerator time (ms): ${outcome.acceleratorMs}`, `Queue time (ms): ${outcome.queueMs}`]
      : ["No receipt is currently available. This does not prove the request was never admitted."]),
    ...(outcome.error ? [`Public error: ${outcome.error}`] : []), "",
    "This is a status-only check. No workload was resubmitted.",
    "Generated output is not recovered. Any missing streamed text remains unavailable."].join("\n");
}


/** Display-zone policy only; stored request instants remain absolute milliseconds. */
export function requestTimeLabel(createdAt) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Shanghai",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit",
    minute: "2-digit", second: "2-digit", hourCycle: "h23",
  }).format(createdAt) + " (Asia/Shanghai, UTC+08:00)";
}
