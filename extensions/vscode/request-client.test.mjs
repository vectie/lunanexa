import assert from "node:assert/strict";
import test from "node:test";
import { invokeStream, readCanonicalStream, MAX_DISPLAY_CHARACTERS } from "./request-client.mjs";
import { frame, chunk, terminal, streamResponse } from "./test-host.mjs";
const id = "vscode-test-1";

test("canonical streaming emits incremental Unicode text before its terminal receipt", async () => {
  const updates = [];
  const value = await readCanonicalStream(streamResponse(frame(chunk("hello 🐈\n")) + frame(chunk("world", 2)) + frame(terminal(3)), [1, 2, 7]), id, update => updates.push(update));
  assert.equal(updates[0].text, "hello 🐈\n"); assert.equal(updates[0].complete, false);
  assert.equal(value.text, "hello 🐈\nworld"); assert.equal(value.complete, true); assert.equal(value.receipt, "audit-test");
});

test("canonical parser handles comments CRLF and multiline data without interpreting nontext metadata", async () => {
  const event = JSON.stringify(chunk("safe"));
  const split = event.indexOf(',"sequence"');
  const wire = `: keepalive\r\ndata: ${event.slice(0, split + 1)}\r\ndata: ${event.slice(split + 1)}\r\n\r\n` + frame({ ...chunk("", 2), output: { internal_secret: "never display", tool_call: { command: "never run" } } }) + frame(terminal(3));
  const value = await readCanonicalStream(streamResponse(wire, [5]), id);
  assert.equal(value.text, "safe"); assert.doesNotMatch(JSON.stringify(value), /never/);
});

test("failure cancellation and replay terminals are canonical outcomes", async () => {
  for (const state of ["Failed", "Cancelled"]) {
    const value = await readCanonicalStream(streamResponse(frame(chunk("partial")) + frame(terminal(2, id, state))), id);
    assert.equal(value.state, state); assert.equal(value.text, "partial"); assert.equal(value.complete, true);
  }
  const replay = terminal(1); replay.response.output = { output_text: "cached replay" };
  assert.equal((await readCanonicalStream(streamResponse(frame(replay)), id)).text, "cached replay");
});

test("wrong identity sequence terminal or event shape fails closed", async () => {
  for (const wire of [
    frame(chunk("wrong", 1, "other")),
    frame(chunk("a")) + frame(chunk("b", 1)),
    frame({ ...chunk("a"), sequence: 0 }),
    frame({ ...chunk("a"), kind: "ProviderEvent" }),
    frame({ ...terminal(1), response: null }),
    frame({ ...terminal(1), response: { ...terminal(1).response, workload_id: "other" } }),
    frame({ ...terminal(1), response: { ...terminal(1).response, state: "Running" } }),
    'data: {malformed}\n\n',
  ]) await assert.rejects(readCanonicalStream(streamResponse(wire), id), /invalid|mismatch|inconsistent/);
});

test("interrupted streams retain received text and never synthesize completion", async () => {
  const updates = [];
  await assert.rejects(readCanonicalStream(streamResponse(frame(chunk("keep me"))), id, value => updates.push(value)), /before a terminal/);
  assert.equal(updates.at(-1).text, "keep me"); assert.equal(updates.at(-1).complete, false);
  await assert.rejects(readCanonicalStream(streamResponse(frame(terminal(1)).trimEnd()), id), /before a terminal/);
});

test("display event and session bounds stop uncontrolled streams", async () => {
  const value = await readCanonicalStream(streamResponse(frame(chunk("x".repeat(MAX_DISPLAY_CHARACTERS - 1) + "🐈")) + frame(chunk("overflow", 2)) + frame(terminal(3))), id);
  assert.equal(value.text.length, MAX_DISPLAY_CHARACTERS - 1); assert.equal(value.truncated, true);
  await assert.rejects(readCanonicalStream(streamResponse("data: " + "x".repeat(1024 * 1024)), id), /1 MiB/);
  let count = 0;
  const bytes = new TextEncoder().encode(": comment\n\n".repeat(10000));
  const oversized = new Response(new ReadableStream({ pull(c) { count++; c.enqueue(bytes); }, cancel() { count = -count; } }), { headers: { "content-type": "text/event-stream" } });
  await assert.rejects(readCanonicalStream(oversized, id), /16 MiB/); assert.ok(count < 0);
});

test("request uses captured authority exact endpoint redirects forbidden and one POST", async () => {
  const requests = [];
  const envelope = { workload_id: id, payload: { input: "selection" }, stream: false };
  await invokeStream({ endpoint: new URL("https://cluster.example/base/v1/workloads:stream"), token: "token", subjectRef: "subject", envelope, timeoutMs: 1000,
    fetchImpl: async (url, init) => { requests.push({ url: url.toString(), init }); return streamResponse(frame(terminal(1))); } });
  assert.equal(requests.length, 1); assert.equal(requests[0].init.redirect, "error");
  assert.equal(requests[0].init.headers["X-LunaNexa-Subject"], "subject");
  assert.equal(JSON.parse(requests[0].init.body).stream, true); assert.equal(envelope.stream, false);
});

test("timeout and public rejection are bounded without retry or raw transport disclosure", async () => {
  let calls = 0;
  const args = { endpoint: new URL("https://cluster.example/v1/workloads:stream"), token: "token", subjectRef: "subject", envelope: { workload_id: id }, timeoutMs: 5 };
  await assert.rejects(invokeStream({ ...args, fetchImpl: async (_url, init) => { calls++; return new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("secret transport details")), { once: true })); } }), /local deadline/);
  assert.equal(calls, 1);
  await assert.rejects(invokeStream({ ...args, fetchImpl: async () => Response.json({ error: { code: "Denied", message: "No lease" } }, { status: 403 }) }), /Denied: No lease/);
  await assert.rejects(invokeStream({ ...args, fetchImpl: async () => Response.json({ token: "not a stream" }) }), /did not return/);
});


test("Completed is the stream event kind and canonical terminal state stays authoritative", async () => {
  // Source contract: WorkloadState in contracts/types.mbt; live and replay
  // construction in api/server.mbt. Completed is never a WorkloadState.
  for (const state of ["Succeeded", "Failed", "Cancelled", "Rejected"]) {
    const event = terminal(1); event.response.state = state;
    const value = await readCanonicalStream(streamResponse(frame(event)), id);
    assert.equal(value.state, state); assert.equal(value.complete, true);
  }
  for (const state of ["Completed", "Submitted", "Admitted", "Queued", "Running", "Streaming", "Unknown"]) {
    const event = terminal(1); event.response.state = state;
    await assert.rejects(readCanonicalStream(streamResponse(frame(event)), id), /inconsistent/);
  }
  for (const kind of ["Failed", "Cancelled"]) {
    const event = terminal(1, id, kind); event.response.state = "Succeeded";
    await assert.rejects(readCanonicalStream(streamResponse(frame(event)), id), /inconsistent/);
  }
});
