import assert from "node:assert/strict";
import test from "node:test";
import { createRequestHistory, REQUEST_HISTORY_KEY, checkWorkloadOutcome, outcomePreview, requestTimeLabel } from "./recovery-client.mjs";
import { workloadOperationEndpoint } from "./cancellation-client.mjs";
import { createExtension } from "./extension-host.mjs";
import { makeHost, leaseResponse, result, frame, chunk, streamResponse } from "./test-host.mjs";
const base = "https://cluster.example/control", subjectRef = "subject-1", id = "vscode-test-1";
const entry = (workloadId = id) => ({ baseUrl: base, subjectRef, workloadId, createdAt: 1000, mode: "stream" });
const tick = () => new Promise(resolve => setImmediate(resolve));

test("serialized metadata history survives a new reader and retains only 20 projected records", async () => {
  const fixture = makeHost(); const history = createRequestHistory(fixture.context.globalState);
  await Promise.all(Array.from({ length: 25 }, (_, index) => history.record({ ...entry(`vscode-${index}`), prompt: "PRIVATE", token: "SECRET", output: "OUTPUT", path: "/private" })));
  const stored = fixture.stored.get(REQUEST_HISTORY_KEY); assert.equal(stored.length, 20);
  assert.equal(new Set(stored.map(item => item.workloadId)).size, 20);
  assert.doesNotMatch(JSON.stringify(stored), /PRIVATE|SECRET|OUTPUT|private/);
  assert.deepEqual(Object.keys(stored[0]).sort(), ["baseUrl", "createdAt", "mode", "subjectRef", "workloadId"]);
  assert.equal(createRequestHistory(fixture.context.globalState).list(base, subjectRef).length, 20);
  assert.equal(history.list("https://other.example", subjectRef).length, 0);
  assert.equal(history.list(base + "/other", subjectRef).length, 0);
  assert.equal(history.list(base, "other-subject").length, 0);
});

test("persisted identity validation rejects dot segments traversal and foreign request names", async () => {
  const fixture = makeHost(); const history = createRequestHistory(fixture.context.globalState);
  for (const workloadId of [".", "..", "../x", "vscode-../../x", "other-request", "vscode-", "vscode-a?token=secret"]) {
    await assert.rejects(history.record(entry(workloadId)), /invalid/);
  }
  for (const dot of [".", ".."]) assert.throws(() => workloadOperationEndpoint(base, dot), /invalid/);
  let calls = 0;
  for (const binding of [{ base: "https://other.example", subjectRef }, { base, subjectRef: "other" }]) {
    await assert.rejects(checkWorkloadOutcome({ entry: entry(), ...binding, token: "token", fetchImpl: async () => { calls++; } }), /different/);
  }
  assert.equal(calls, 0);
});

test("one status GET projects canonical usage and never generated output", async () => {
  for (const state of ["Queued", "Running", "Succeeded", "Failed", "Cancelled", "Rejected"]) {
    const calls = [];
    const outcome = await checkWorkloadOutcome({ entry: entry(), base, subjectRef, token: "captured-token", fetchImpl: async (url, init) => {
      calls.push({ url: url.toString(), init }); return Response.json({ ...result(id, state), output: { text: "PRIVATE OUTPUT" }, internal: "SECRET", usage: { input_units: 4, output_units: 8, accelerator_ms: "100", queue_ms: "20" } });
    } });
    assert.equal(calls.length, 1); assert.equal(calls[0].init.method, "GET"); assert.equal(calls[0].init.redirect, "error");
    assert.equal(calls[0].url, base + "/v1/workloads/" + id); assert.equal(calls[0].init.headers["X-LunaNexa-Subject"], subjectRef);
    assert.equal(outcome.state, state); assert.equal(outcome.outputUnits, "8"); assert.equal(outcome.acceleratorMs, "100");
    assert.doesNotMatch(outcomePreview(entry(), outcome), /PRIVATE|SECRET/);
  }
});

test("missing denied mismatched and timed-out status checks retain uncertainty without resubmission", async () => {
  const args = { entry: entry(), base, subjectRef, token: "token", timeoutMs: 5 };
  const missing = await checkWorkloadOutcome({ ...args, fetchImpl: async () => new Response("private unavailable body", { status: 404 }) });
  assert.equal(missing.state, "Unknown"); assert.match(outcomePreview(entry(), missing), /does not prove/);
  for (const response of [Response.json({ ...result("wrong") }), Response.json({ ...result(id, "Completed") }), Response.json({ error: { code: "Denied", message: "No access" } }, { status: 403 })]) {
    await assert.rejects(checkWorkloadOutcome({ ...args, fetchImpl: async () => response }), /mismatch|invalid|Denied/);
  }
  let calls = 0;
  await assert.rejects(checkWorkloadOutcome({ ...args, fetchImpl: (_url, init) => { calls++; return new Promise((_r, reject) => init.signal.addEventListener("abort", () => reject(new Error("secret transport")), { once: true })); } }), /outcome is still unknown/);
  assert.equal(calls, 1);
});

test("actual interrupted stream records metadata and explicit reactivated status command only checks outcome", async () => {
  const fixture = makeHost(); const calls = [];
  const dependencies = { makeId: () => "test-1", now: () => 1000, fetchImpl: async (url, init) => {
    calls.push({ url: url.toString(), method: init.method });
    if (url.pathname.endsWith("/self")) return leaseResponse();
    if (init.method === "POST") return streamResponse(frame(chunk("partial")));
    return Response.json({ ...result(), output: { text: "MISSING OUTPUT MUST NOT APPEAR" }, usage: { input_units: 1, output_units: 2, accelerator_ms: "3", queue_ms: "4" } });
  } };
  createExtension(fixture.host, dependencies).activate(fixture.context);
  await fixture.commands.get("lunanexa.streamSelection")();
  assert.equal(calls.length, 2); assert.equal(fixture.stored.get(REQUEST_HISTORY_KEY).length, 1);
  createExtension(fixture.host, dependencies).activate(fixture.context);
  await fixture.commands.get("lunanexa.checkRequestOutcome")();
  assert.equal(calls.length, 3); assert.equal(calls[2].method, "GET");
  const preview = [...fixture.previews.values()].at(-1);
  assert.match(preview, /State: Succeeded/); assert.match(preview, /Generated output is not recovered/); assert.doesNotMatch(preview, /MISSING OUTPUT/);
  assert.equal(calls.filter(call => call.method === "POST").length, 1);
});

test("actual recovery picker cancellation and changed identity send nothing", async () => {
  for (const mutate of [false, true]) {
    const fixture = makeHost(); let calls = 0;
    await createRequestHistory(fixture.context.globalState).record(entry());
    fixture.host.window.showQuickPick = async choices => { if (mutate) fixture.values.subjectRef = "another-subject"; return mutate ? choices[0] : undefined; };
    createExtension(fixture.host, { fetchImpl: async () => { calls++; } }).activate(fixture.context);
    await fixture.commands.get("lunanexa.checkRequestOutcome")(); assert.equal(calls, 0);
    if (mutate) assert.match(fixture.errors[0], /changed/);
  }
});

test("failed storage or cancellation while storage is pending prevents workload dispatch", async () => {
  for (const fail of [true, false]) {
    const fixture = makeHost(); const calls = []; let release;
    fixture.context.globalState.update = async () => { if (fail) throw new Error("private storage path"); await new Promise(resolve => { release = resolve; }); };
    createExtension(fixture.host, { makeId: () => "test-1", now: () => 1000, fetchImpl: async (_url, init) => { calls.push(init.method); return leaseResponse(); } }).activate(fixture.context);
    const pending = fixture.commands.get("lunanexa.sendSelection")();
    if (!fail) { while (!release) await tick(); fixture.cancel(); release(); }
    await pending; assert.deepEqual(calls, ["GET"]); assert.match(fixture.errors[0], /No workload was submitted|No workload was sent/); assert.doesNotMatch(fixture.errors[0], /private storage/);
  }
});

test("newer explicit status check suppresses an older late result", async () => {
  const fixture = makeHost(); const pending = [];
  await createRequestHistory(fixture.context.globalState).record(entry());
  createExtension(fixture.host, { fetchImpl: async () => new Promise(resolve => pending.push(resolve)) }).activate(fixture.context);
  const first = fixture.commands.get("lunanexa.checkRequestOutcome")(); while (pending.length < 1) await tick();
  const second = fixture.commands.get("lunanexa.checkRequestOutcome")(); while (pending.length < 2) await tick();
  pending[1](Response.json(result(id, "Succeeded"))); await second;
  pending[0](Response.json(result(id, "Running"))); await first;
  assert.equal(fixture.events.filter(event => event.shown).length, 1);
  assert.match([...fixture.previews.values()].at(-1), /State: Succeeded/);
});


test("request picker uses the product display zone without shifting the stored instant", () => {
  const instant = Date.parse("2026-10-11T13:00:00Z");
  const label = requestTimeLabel(instant);
  assert.match(label, /11\/10\/2026/); assert.match(label, /21:00:00/);
  assert.match(label, /Asia\/Shanghai, UTC\+08:00/);
  assert.equal(instant, Date.parse("2026-10-11T13:00:00Z"));
});
