import assert from "node:assert/strict";
import test from "node:test";
import { createWorkloadCancellation, workloadOperationEndpoint } from "./cancellation-client.mjs";
import { createExtension } from "./extension-host.mjs";
import { makeHost, leaseResponse, result, frame, chunk, terminal } from "./test-host.mjs";
const id = "vscode-test-1";
const receipt = () => Response.json({ workload_id: id, accepted: true, receipt: "cancel-receipt" }, { status: 202 });
const defaults = { base: "https://cluster.example/control", workloadId: id, token: "captured-token", subjectRef: "captured-subject", timeoutMs: 1000 };
const tick = () => new Promise(resolve => setImmediate(resolve));

test("cancellation uses the exact captured authority and one single-flight POST", async () => {
  const calls = [], states = [];
  let resolve;
  const base = new URL(defaults.base);
  const cancel = createWorkloadCancellation({ ...defaults, base, onStatus: value => states.push(value), fetchImpl: async (url, init) => { calls.push({ url: url.toString(), init }); return new Promise(done => { resolve = done; }); } });
  base.hostname = "other.example";
  const first = cancel.request(), second = cancel.request(); assert.equal(first, second);
  await tick(); assert.equal(calls.length, 1);
  assert.equal(calls[0].url, "https://cluster.example/control/v1/workloads/vscode-test-1/cancel");
  assert.equal(calls[0].init.headers.Authorization, "Bearer captured-token"); assert.equal(calls[0].init.headers["X-LunaNexa-Subject"], "captured-subject");
  assert.equal(calls[0].init.redirect, "error"); assert.equal(calls[0].init.body, "");
  resolve(receipt()); assert.equal((await first).state, "accepted");
  assert.equal(states.at(-1).receipt, "cancel-receipt"); assert.match(states.at(-1).message, /Waiting/);
  await cancel.request(); assert.equal(calls.length, 1); cancel.finish();
});

test("endpoint validation rejects traversal and credential destinations", () => {
  for (const value of ["../other", "x/y", "", "x?secret", "x#fragment"]) assert.throws(() => workloadOperationEndpoint(defaults.base, value), /invalid/);
  for (const base of ["http://remote.example", "https://token@remote.example", "https://remote.example/?token=x"]) assert.throws(() => workloadOperationEndpoint(base, id));
});

test("unbound malformed denied and missing cancellation receipts remain unconfirmed", async () => {
  const replies = [
    () => Response.json({ workload_id: "other", accepted: true, receipt: "x" }, { status: 202 }),
    () => Response.json({ workload_id: id, accepted: false, receipt: "x" }, { status: 202 }),
    () => Response.json({ workload_id: id, accepted: true }, { status: 202 }),
    () => Response.json({ workload_id: id, accepted: true, receipt: "x\nforged" }, { status: 202 }),
    () => new Response("not JSON", { status: 202 }),
    ...[200, 401, 403, 404, 500].map(status => () => Response.json({ error: { code: "NotConfirmed", message: "bounded public detail" } }, { status })),
  ];
  for (const reply of replies) {
    let calls = 0;
    const cancel = createWorkloadCancellation({ ...defaults, fetchImpl: async () => { calls++; return reply(); } });
    const value = await cancel.request(); assert.equal(value.state, "unconfirmed"); assert.equal(calls, 1); cancel.finish();
  }
});

test("transport failure and timeout do not expose raw details or imply cancellation", async () => {
  const failed = createWorkloadCancellation({ ...defaults, fetchImpl: async () => { throw new Error("token=secret"); } });
  const value = await failed.request(); assert.equal(value.state, "unconfirmed"); assert.doesNotMatch(value.message, /secret/);
  const timed = createWorkloadCancellation({ ...defaults, timeoutMs: 5, fetchImpl: (_url, init) => new Promise((_r, reject) => init.signal.addEventListener("abort", () => reject(new Error("secret")), { once: true })) });
  assert.match((await timed.request()).message, /local deadline/);
});

test("finish fences queued and late cancellation callbacks without further sends", async () => {
  let calls = 0;
  const early = createWorkloadCancellation({ ...defaults, fetchImpl: async () => { calls++; return receipt(); } });
  const queued = early.request(); early.finish(); assert.equal((await queued).state, "ignored"); assert.equal(calls, 0);
  assert.equal((await early.request()).state, "ignored");
  let resolve;
  const statuses = [];
  const late = createWorkloadCancellation({ ...defaults, onStatus: value => statuses.push(value), fetchImpl: async () => new Promise(done => { resolve = done; }) });
  const pending = late.request(); await tick(); late.finish(); resolve(receipt()); await pending;
  assert.deepEqual(statuses.map(value => value.state), ["requesting"]);
});

test("actual stream command exposes cancellation accepted separately from Cancelled terminal", async () => {
  const fixture = makeHost(); const calls = []; let controller;
  createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (url, init) => {
    calls.push({ url: url.toString(), init });
    if (init.method === "GET") return leaseResponse();
    if (url.pathname.endsWith("/cancel")) return receipt();
    return new Response(new ReadableStream({ start(c) { controller = c; c.enqueue(new TextEncoder().encode(frame(chunk("received")))); } }), { headers: { "content-type": "text/event-stream" } });
  } }).activate(fixture.context);
  const running = fixture.commands.get("lunanexa.streamSelection")();
  while (!controller) await tick(); fixture.cancel(); fixture.cancel(); await tick();
  assert.match([...fixture.previews.values()].at(-1), /Server cancellation accepted/);
  assert.match([...fixture.previews.values()].at(-1), /State: Streaming/);
  controller.enqueue(new TextEncoder().encode(frame(terminal(2, id, "Cancelled")))); controller.close(); await running;
  assert.match([...fixture.previews.values()].at(-1), /State: Cancelled/);
  assert.equal(calls.filter(call => call.url.endsWith("/cancel")).length, 1);
  assert.equal(fixture.isCancelDisposed(), true); assert.equal(fixture.errors.length, 0);
});

test("completion wins a race against a late cancellation receipt in the actual command", async () => {
  const fixture = makeHost(); let controller, resolveCancellation;
  createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (url, init) => {
    if (init.method === "GET") return leaseResponse();
    if (url.pathname.endsWith("/cancel")) return new Promise(resolve => { resolveCancellation = resolve; });
    return new Response(new ReadableStream({ start(c) { controller = c; } }), { headers: { "content-type": "text/event-stream" } });
  } }).activate(fixture.context);
  const running = fixture.commands.get("lunanexa.streamSelection")(); while (!controller) await tick();
  fixture.cancel(); while (!resolveCancellation) await tick();
  controller.enqueue(new TextEncoder().encode(frame(terminal(1)))); controller.close(); await running;
  const before = [...fixture.previews.values()].at(-1); resolveCancellation(receipt()); await tick();
  assert.equal([...fixture.previews.values()].at(-1), before); assert.match(before, /State: Succeeded/); assert.equal(fixture.isCancelDisposed(), true);
});

test("actual unary command is cancellable and keeps its canonical terminal response", async () => {
  const fixture = makeHost(); let resolveWorkload; const calls = [];
  createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (url, init) => {
    calls.push(url.toString()); if (init.method === "GET") return leaseResponse();
    if (url.pathname.endsWith("/cancel")) return receipt();
    return new Promise(resolve => { resolveWorkload = resolve; });
  } }).activate(fixture.context);
  const running = fixture.commands.get("lunanexa.sendSelection")(); while (!resolveWorkload) await tick(); fixture.cancel(); await tick();
  resolveWorkload(Response.json(result(id, "Cancelled"))); await running;
  assert.equal(calls.filter(url => url.endsWith("/cancel")).length, 1);
  assert.match(fixture.events.find(value => value.shown)?.shown.content || "", /State: Cancelled/);
  assert.equal(fixture.isCancelDisposed(), true);
});

test("cancellation before submission sends neither workload nor cancel", async () => {
  for (const command of ["lunanexa.sendSelection", "lunanexa.streamSelection"]) {
    const fixture = makeHost(); fixture.cancel(); const calls = [];
    createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (_url, init) => { calls.push(init.method); return leaseResponse(); } }).activate(fixture.context);
    await fixture.commands.get(command)(); assert.deepEqual(calls, ["GET"]); assert.match(fixture.errors[0], /No workload was sent/); assert.equal(fixture.isCancelDisposed(), true);
  }
});
