import assert from "node:assert/strict";
import test from "node:test";
import { createExtension } from "./extension-host.mjs";
import { makeHost, leaseResponse, frame, chunk, terminal, streamResponse } from "./test-host.mjs";

test("registered stream command sends only the selection and updates its read-only preview", async () => {
  const fixture = makeHost(); const requests = [];
  createExtension(fixture.host, { makeId: () => "test-1", now: () => 1000, fetchImpl: async (url, init) => {
    requests.push({ url: url.toString(), init });
    return init.method === "GET" ? leaseResponse() : streamResponse(frame(chunk("answer <img src=secret>")) + frame(terminal()));
  } }).activate(fixture.context);
  await fixture.commands.get("lunanexa.streamSelection")();
  assert.equal(requests.length, 2); assert.equal(requests[1].url, "https://cluster.example/control/v1/workloads:stream");
  const payload = JSON.parse(requests[1].init.body);
  assert.deepEqual(payload.payload, { input: "only selected text" }); assert.equal(payload.tenant_ref, "tenant-1");
  assert.equal(payload.deadline_unix_ms, "61000"); assert.equal(payload.data_policy.allow_training_reuse, false);
  const preview = [...fixture.previews.values()].at(-1);
  assert.match(preview, /State: Succeeded/); assert.match(preview, /answer <img src=secret>/); assert.match(preview, /audit-test/);
  assert.equal(fixture.errors.length, 0); assert.equal(fixture.events.filter(event => event.shown).length, 1);
});

test("an interrupted actual command keeps partial text and an honest incomplete state", async () => {
  const fixture = makeHost(); let posts = 0;
  createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (_url, init) => {
    if (init.method === "GET") return leaseResponse(); posts++; return streamResponse(frame(chunk("partial answer")));
  } }).activate(fixture.context);
  await fixture.commands.get("lunanexa.streamSelection")();
  const preview = [...fixture.previews.values()].at(-1);
  assert.match(preview, /State: Interrupted/); assert.match(preview, /partial answer/); assert.match(preview, /incomplete/);
  assert.equal(posts, 1); assert.equal(fixture.errors.length, 1);
});

test("closing the preview during streaming neither reopens it nor loses command isolation", async () => {
  const fixture = makeHost(); let controller;
  createExtension(fixture.host, { makeId: () => "test-1", fetchImpl: async (_url, init) => {
    if (init.method === "GET") return leaseResponse();
    return new Response(new ReadableStream({ start(c) { controller = c; } }), { headers: { "content-type": "text/event-stream" } });
  } }).activate(fixture.context);
  const pending = fixture.commands.get("lunanexa.streamSelection")();
  while (!controller) await new Promise(resolve => setImmediate(resolve));
  const uri = fixture.host.Uri.parse("lunanexa-result:/vscode-test-1.txt"); fixture.close(uri);
  controller.enqueue(new TextEncoder().encode(frame(chunk("late")) + frame(terminal()))); controller.close();
  await pending;
  assert.equal(fixture.events.filter(event => event.shown).length, 1);
  assert.equal(fixture.errors.length, 0);
});

test("empty selection never discovers authority or sends a request", async () => {
  const fixture = makeHost(); fixture.setSelection("", true); let calls = 0;
  createExtension(fixture.host, { fetchImpl: async () => { calls++; throw new Error("must not run"); } }).activate(fixture.context);
  await fixture.commands.get("lunanexa.streamSelection")(); assert.equal(calls, 0);
});
