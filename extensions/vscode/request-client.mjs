// Provider-neutral client transport. No VS Code, filesystem, or credential storage.
export class ClientError extends Error {}
export const MAX_RESPONSE_BYTES = 1024 * 1024;
export const MAX_DISPLAY_CHARACTERS = 32 * 1024;
const MAX_STREAM_BYTES = 16 * 1024 * 1024;
const MAX_STREAM_EVENTS = 65536;

export async function readBoundedJson(response) {
  if (Number(response.headers.get("content-length") || "0") > MAX_RESPONSE_BYTES) {
    throw new ClientError("LunaNexa returned an unexpectedly large response.");
  }
  const reader = response.body?.getReader();
  if (!reader) throw new ClientError("LunaNexa returned an invalid JSON response.");
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0;
  let text = "";
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_RESPONSE_BYTES) {
        throw new ClientError("LunaNexa returned an unexpectedly large response.");
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    return JSON.parse(text);
  } catch (error) {
    if (error instanceof ClientError) throw error;
    throw new ClientError("LunaNexa returned an invalid JSON response.");
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export function canonicalResponse(value, workloadId) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      value.version !== "lunanexa.v1" || value.workload_id !== workloadId) {
    throw new ClientError("LunaNexa returned a mismatched canonical response.");
  }
  return value;
}

function publicText(value, maximum) {
  return typeof value === "string"
    ? value.slice(0, maximum).replace(/[\r\n\u2028\u2029]/g, " ") : "";
}

export async function responseError(response) {
  const body = await readBoundedJson(response);
  const details = body?.error && typeof body.error === "object" ? body.error : body;
  return new ClientError(`${publicText(details?.code, 80) || `HTTP ${response.status}`}: ${publicText(details?.message, 400) || "Request rejected."}`);
}

/** Consume the published canonical SSE contract; never interpret provider events. */
export async function readCanonicalStream(response, workloadId, onUpdate = () => {}) {
  if (!response.ok) throw await responseError(response);
  if (!/^text\/event-stream(?:\s*;|$)/i.test(response.headers.get("content-type") || "")) {
    throw new ClientError("LunaNexa did not return a canonical event stream.");
  }
  const reader = response.body?.getReader();
  if (!reader) throw new ClientError("LunaNexa returned an empty event stream.");
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let pending = "";
  let data = [];
  let frameBytes = 0;
  let bytes = 0;
  let events = 0;
  let lastSequence = 0;
  let terminal = false;
  let snapshot = { state: "Streaming", text: "", truncated: false, receipt: "", complete: false };
  const emit = () => onUpdate({ ...snapshot });
  const appendText = delta => {
    if (snapshot.truncated) return;
    const combined = snapshot.text + delta;
    let text = combined.slice(0, MAX_DISPLAY_CHARACTERS);
    if (combined.length > MAX_DISPLAY_CHARACTERS && /[\uD800-\uDBFF]$/.test(text)) text = text.slice(0, -1);
    snapshot = { ...snapshot, text, truncated: combined.length > text.length };
  };
  const frame = () => {
    if (!data.length) { frameBytes = 0; return; }
    if (++events > MAX_STREAM_EVENTS) throw new ClientError("LunaNexa stream exceeded its event limit.");
    let event;
    try { event = JSON.parse(data.join("\n")); } catch {
      throw new ClientError("LunaNexa returned an invalid canonical stream event.");
    }
    data = [];
    frameBytes = 0;
    if (!event || event.workload_id !== workloadId || !Number.isSafeInteger(event.sequence) ||
        event.sequence <= lastSequence || !["Chunk", "Completed", "Failed", "Cancelled"].includes(event.kind)) {
      throw new ClientError("LunaNexa stream identity, sequence, or kind is invalid.");
    }
    lastSequence = event.sequence;
    if (event.kind === "Chunk") {
      const delta = typeof event.output?.text_delta === "string" ? event.output.text_delta
        : typeof event.output?.text === "string" ? event.output.text : "";
      appendText(delta);
    } else {
      const result = canonicalResponse(event.response, workloadId);
      // Completed means the stream ended, not the WorkloadState spelling.
      // The server also replays cached Failed/Cancelled/Rejected receipts in it.
      const compatible = event.kind === "Completed"
        ? ["Succeeded", "Failed", "Cancelled", "Rejected"].includes(result.state)
        : result.state === event.kind;
      if (!compatible) throw new ClientError("LunaNexa terminal stream state is inconsistent.");
      if (!snapshot.text && result.output !== undefined && result.output !== null) {
        const replay = typeof result.output === "string" ? result.output
          : typeof result.output.text === "string" ? result.output.text
          : typeof result.output.output_text === "string" ? result.output.output_text : "";
        appendText(replay);
      }
      terminal = true;
      snapshot = { ...snapshot, state: result.state, receipt: publicText(result.audit_receipt, 512), error: publicText(result.error?.message, 400), complete: true };
    }
    emit();
  };
  const line = value => {
    frameBytes += Buffer.byteLength(value, "utf8") + 1;
    if (frameBytes > MAX_RESPONSE_BYTES) throw new ClientError("LunaNexa stream event exceeded the 1 MiB limit.");
    if (value === "") frame();
    else if (value.startsWith("data:")) data.push(value.slice(5).replace(/^ /, ""));
  };
  try {
    while (!terminal) {
      const next = await reader.read();
      if (next.done) {
        pending += decoder.decode();
        if (pending) line(pending.replace(/\r$/, ""));
        // SSE requires a blank-line dispatch. EOF alone is not completion.
        break;
      }
      bytes += next.value.byteLength;
      if (bytes > MAX_STREAM_BYTES) throw new ClientError("LunaNexa stream exceeded its 16 MiB session limit.");
      pending += decoder.decode(next.value, { stream: true });
      let end;
      while (!terminal && (end = pending.indexOf("\n")) >= 0) {
        line(pending.slice(0, end).replace(/\r$/, ""));
        pending = pending.slice(end + 1);
      }
      if (Buffer.byteLength(pending, "utf8") > MAX_RESPONSE_BYTES) {
        throw new ClientError("LunaNexa stream event exceeded the 1 MiB limit.");
      }
    }
    if (!terminal) throw new ClientError("LunaNexa stream ended before a terminal event. Received text is incomplete.");
    return { ...snapshot };
  } finally {
    await reader.cancel().catch(() => {});
    reader.releaseLock();
  }
}

export async function invokeStream({ endpoint, token, subjectRef, envelope, timeoutMs, onUpdate, fetchImpl = globalThis.fetch }) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetchImpl(endpoint, {
      method: "POST", redirect: "error", signal: controller.signal,
      headers: { Accept: "text/event-stream", Authorization: `Bearer ${token}`,
        "Content-Type": "application/json", "X-LunaNexa-Subject": subjectRef },
      body: JSON.stringify({ ...envelope, stream: true }),
    });
    return await readCanonicalStream(response, envelope.workload_id, onUpdate);
  } catch (error) {
    if (error instanceof ClientError) throw error;
    if (controller.signal.aborted) throw new ClientError("The LunaNexa stream reached its local deadline. Received text is incomplete.");
    throw new ClientError("The LunaNexa stream was interrupted. Received text is incomplete.");
  } finally {
    clearTimeout(timeout);
  }
}
