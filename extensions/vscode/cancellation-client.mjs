import { secureUrl } from "./client-core.mjs";
import { ClientError, readBoundedJson, responseError } from "./request-client.mjs";

export function workloadOperationEndpoint(base, workloadId, operation = "") {
  if (typeof workloadId !== "string" || [".", ".."].includes(workloadId) || !/^[A-Za-z0-9_.:-]{1,256}$/.test(workloadId)) {
    throw new ClientError("The workload reference is invalid.");
  }
  const url = secureUrl(base, "API base URL");
  url.pathname = `${url.pathname.replace(/\/$/, "")}/v1/workloads/${encodeURIComponent(workloadId)}${operation === "cancel" ? "/cancel" : ""}`;
  return url;
}

/** A local cancellation gesture requests server cancellation, never invents it. */
export function createWorkloadCancellation({ base, workloadId, token, subjectRef,
  fetchImpl = globalThis.fetch, timeoutMs = 10000, onStatus = () => {} }) {
  const endpoint = workloadOperationEndpoint(base, workloadId, "cancel");
  let finished = false;
  let pending;
  let controller;
  const publish = status => { if (!finished) onStatus(status); return status; };
  return {
    request() {
      if (finished) return Promise.resolve({ state: "ignored" });
      if (pending) return pending;
      pending = Promise.resolve().then(async () => {
        if (finished) return { state: "ignored" };
        controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), timeoutMs);
        publish({ state: "requesting", message: "Requesting server cancellation…" });
        try {
          const response = await fetchImpl(endpoint, {
            method: "POST", redirect: "error", signal: controller.signal,
            headers: { Accept: "application/json", Authorization: `Bearer ${token}`,
              "X-LunaNexa-Subject": subjectRef }, body: "",
          });
          if (response.status !== 202) throw await responseError(response);
          const receipt = await readBoundedJson(response);
          if (!receipt || receipt.workload_id !== workloadId || receipt.accepted !== true ||
              typeof receipt.receipt !== "string" || !receipt.receipt || receipt.receipt.length > 512 ||
              /[\r\n\u2028\u2029]/.test(receipt.receipt)) {
            throw new ClientError("The cancellation receipt did not match this workload.");
          }
          return publish({ state: "accepted", receipt: receipt.receipt,
            message: "Server cancellation accepted. Waiting for the request's terminal outcome." });
        } catch (error) {
          const detail = error instanceof ClientError ? error.message
            : controller.signal.aborted ? "The cancellation request reached its local deadline."
            : "The cancellation request could not be completed.";
          return publish({ state: "unconfirmed", message: `Cancellation is not confirmed. ${detail}` });
        } finally {
          clearTimeout(timeout);
        }
      });
      return pending;
    },
    finish() {
      finished = true;
      controller?.abort();
    },
  };
}
