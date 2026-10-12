import assert from "node:assert/strict";
import test from "node:test";
import fs from "node:fs";
import { collectActivityReport, activityReportJson, activityReportCsv } from "./activity-report.mjs";
import { createRequestHistory, REQUEST_HISTORY_KEY } from "./recovery-client.mjs";
import { createExtension } from "./extension-host.mjs";
import { makeHost, result } from "./test-host.mjs";

const base = "https://cluster.example/control", subjectRef = "subject-1";
const entry = (id = "vscode-one", overrides = {}) => ({ baseUrl: base, subjectRef, workloadId: id, createdAt: 1000, mode: "unary", ...overrides });
const tick = () => new Promise(resolve => setImmediate(resolve));
const args = entries => ({ entries, base, subjectRef, token: "secret-token", now: () => 2000 });
const shown = fixture => fixture.events.filter(event => event.shown).map(event => event.shown.content);
function selectReport(fixture, format = "JSON", select = choices => choices) {
  fixture.host.window.showQuickPick = async (choices, options) => options.canPickMany ? select(choices) : choices.find(choice => choice.label === format);
}
async function seed(fixture, entries) {
  const history = createRequestHistory(fixture.context.globalState);
  for (const value of entries) await history.record(value);
}

test("report reads each chosen attempt once, preserves exact usage and counts missing evidence", async () => {
  const entries = [entry("vscode-done"), entry("vscode-running", { mode: "stream" }), entry("vscode-missing"), entry("vscode-unavailable")];
  const calls = [];
  const report = await collectActivityReport({ ...args(entries), fetchImpl: async (url, init) => {
    calls.push({ url: url.toString(), init });
    const id = url.pathname.split("/").at(-1);
    if (id === "vscode-missing") return new Response("private missing body", { status: 404 });
    if (id === "vscode-unavailable") return Response.json({ error: { code: "Denied", message: "private service error" } }, { status: 403 });
    return Response.json({ ...result(id, id === "vscode-done" ? "Succeeded" : "Running"),
      usage: { input_units: "9223372036854775807", output_units: 0, accelerator_ms: "12" }, output: { text: "private generated text" }, token: "private token" });
  } });
  assert.equal(calls.length, 4);
  assert.ok(calls.every(call => call.init.method === "GET" && call.init.redirect === "error" && call.init.body === undefined));
  assert.ok(calls.every(call => call.init.headers["X-LunaNexa-Subject"] === subjectRef));
  assert.deepEqual(report.requests.map(row => row.evidence), ["observed", "observed", "not_found", "check_failed"]);
  assert.deepEqual(report.summary.states, { Running: 1, Succeeded: 1, Unknown: 2 });
  assert.equal(report.summary.terminal, 1); assert.equal(report.summary.nonterminal, 1);
  assert.deepEqual(report.summary.usage_coverage.input_units, { reported: 2, missing: 2 });
  assert.deepEqual(report.summary.usage_coverage.queue_ms, { reported: 0, missing: 4 });
  assert.equal(report.requests[0].usage.input_units, "9223372036854775807");
  assert.equal(report.requests[0].usage.output_units, "0");
  assert.equal(report.requests[2].usage.output_units, null); assert.equal(report.requests[2].terminal, null);
  assert.equal(report.requests[0].checked_unix_ms, 2000);
  const encoded = activityReportJson(report);
  assert.equal(JSON.parse(encoded).format, "lunanexa.client-activity-report.v1");
  assert.doesNotMatch(encoded, /private|secret-token/);
  assert.match(encoded, /not an account-wide usage ledger or an invoice/);
});

test("CSV preserves per-request rows, quotes receipt text and leaves missing usage blank", async () => {
  const report = await collectActivityReport({ ...args([entry()]), fetchImpl: async () => Response.json({ ...result("vscode-one"), audit_receipt: '=SUM(1,2) "你好"', usage: { input_units: 0 } }) });
  const csv = activityReportCsv(report);
  assert.equal(csv.split("\r\n").length, 3);
  assert.match(csv, /"audit_receipt","input_units","output_units","accelerator_ms","queue_ms"/);
  assert.match(csv, /"'=SUM\(1,2\) ""你好""","0",,,\r\n$/);
  assert.equal(JSON.parse(activityReportJson(report)).requests[0].audit_receipt, '=SUM(1,2) "你好"');
});

test("registered command selects a subset, exports JSON to plain text and leaves history unchanged", async () => {
  const fixture = makeHost();
  await seed(fixture, [entry("vscode-first"), entry("vscode-second"), entry("vscode-foreign", { subjectRef: "another" })]);
  const before = JSON.stringify(fixture.stored.get(REQUEST_HISTORY_KEY)); const calls = [];
  selectReport(fixture, "JSON", choices => { assert.equal(choices.length, 2); return [choices[1]]; });
  const open = fixture.host.workspace.openTextDocument;
  fixture.host.workspace.openTextDocument = async value => { assert.equal(value.language, "plaintext"); return open(value); };
  createExtension(fixture.host, { now: () => 3000, fetchImpl: async (url, init) => {
    calls.push({ url: url.toString(), method: init.method }); return Response.json(result("vscode-first"));
  } }).activate(fixture.context);
  await fixture.commands.get("lunanexa.exportActivityReport")();
  assert.deepEqual(calls, [{ url: base + "/v1/workloads/vscode-first", method: "GET" }]);
  const report = JSON.parse(shown(fixture)[0]);
  assert.equal(report.requests.length, 1); assert.equal(report.requests[0].workload_id, "vscode-first");
  assert.equal(report.scope.subject_ref, subjectRef);
  assert.equal(JSON.stringify(fixture.stored.get(REQUEST_HISTORY_KEY)), before);
  assert.ok(fixture.events.some(event => typeof event === "string" && event.includes("Save As with .json")));
  assert.equal(fixture.errors.length, 0);
  assert.ok(fixture.isCancelDisposed());
  const manifest = JSON.parse(fs.readFileSync(new URL("./package.json", import.meta.url)));
  assert.ok(manifest.activationEvents.includes("onCommand:lunanexa.exportActivityReport"));
  assert.ok(manifest.contributes.commands.some(command => command.command === "lunanexa.exportActivityReport"));
});

test("registered CSV workflow includes failed and cancelled outcomes without replay or cancellation POST", async () => {
  const fixture = makeHost(); await seed(fixture, [entry("vscode-failed"), entry("vscode-cancelled")]);
  selectReport(fixture, "CSV"); const calls = [];
  createExtension(fixture.host, { fetchImpl: async (url, init) => {
    calls.push(init.method); const id = url.pathname.split("/").at(-1);
    return Response.json(result(id, id.endsWith("failed") ? "Failed" : "Cancelled"));
  } }).activate(fixture.context);
  await fixture.commands.get("lunanexa.exportActivityReport")();
  assert.deepEqual(calls, ["GET", "GET"]);
  assert.equal(shown(fixture).length, 1); assert.match(shown(fixture)[0], /"Failed"/); assert.match(shown(fixture)[0], /"Cancelled"/);
  assert.ok(fixture.events.some(event => typeof event === "string" && event.includes("Save As with .csv")));
});

test("empty history, selection cancellation and format cancellation perform no status reads", async () => {
  for (const stage of ["empty", "selection", "format"]) {
    const fixture = makeHost(); let calls = 0;
    if (stage !== "empty") await seed(fixture, [entry()]);
    fixture.host.window.showQuickPick = async (choices, options) => stage === "format" && options.canPickMany ? choices : undefined;
    createExtension(fixture.host, { fetchImpl: async () => { calls++; } }).activate(fixture.context);
    await fixture.commands.get("lunanexa.exportActivityReport")();
    assert.equal(calls, 0); assert.equal(shown(fixture).length, 0);
  }
});

test("cancel during a status read aborts that read, stops remaining reads and opens no report", async () => {
  const fixture = makeHost(); await seed(fixture, [entry("vscode-first"), entry("vscode-second")]); selectReport(fixture);
  let calls = 0, aborted = false;
  createExtension(fixture.host, { fetchImpl: async (_url, init) => {
    calls++; return new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => { aborted = true; reject(new Error("cancelled transport")); }, { once: true }));
  } }).activate(fixture.context);
  const pending = fixture.commands.get("lunanexa.exportActivityReport")();
  while (!calls) await tick(); fixture.cancel(); await pending;
  assert.equal(calls, 1); assert.equal(aborted, true); assert.equal(shown(fixture).length, 0);
  assert.equal(fixture.errors.length, 0); assert.ok(fixture.isCancelDisposed());
});

test("context change during picker or read stops export without checking another context", async () => {
  for (const stage of ["picker", "read"]) {
    const fixture = makeHost(); await seed(fixture, [entry("vscode-one"), entry("vscode-two")]); let calls = 0;
    selectReport(fixture, "JSON", choices => { if (stage === "picker") fixture.values.subjectRef = "new-subject"; return choices; });
    createExtension(fixture.host, { fetchImpl: async url => { calls++; fixture.values.apiBaseUrl = base + "/other"; return Response.json(result(url.pathname.split("/").at(-1))); } }).activate(fixture.context);
    await fixture.commands.get("lunanexa.exportActivityReport")();
    assert.equal(calls, stage === "picker" ? 0 : 1); assert.equal(shown(fixture).length, 0);
    assert.match(fixture.errors[0], /changed/);
  }
});

test("newer report supersedes a pending report and deactivation aborts pending reads", async () => {
  for (const action of ["replace", "deactivate"]) {
    const fixture = makeHost(); await seed(fixture, [entry()]); selectReport(fixture);
    let calls = 0, aborted = false;
    const extension = createExtension(fixture.host, { fetchImpl: async (_url, init) => {
      calls++;
      if (calls > 1) return Response.json(result("vscode-one"));
      return new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => { aborted = true; reject(new Error("aborted")); }, { once: true }));
    } }); extension.activate(fixture.context);
    const first = fixture.commands.get("lunanexa.exportActivityReport")(); while (!calls) await tick();
    if (action === "replace") await fixture.commands.get("lunanexa.exportActivityReport")(); else extension.deactivate();
    await first;
    assert.equal(aborted, true); assert.equal(shown(fixture).length, action === "replace" ? 1 : 0);
    assert.equal(fixture.errors.length, 0);
  }
});

test("timeout or invalid status leaves an unavailable row and still checks the next selected request", async () => {
  const calls = [];
  const report = await collectActivityReport({ ...args([entry("vscode-timeout"), entry("vscode-invalid"), entry("vscode-last")]), timeoutMs: 5,
    fetchImpl: async (url, init) => {
      const id = url.pathname.split("/").at(-1); calls.push(id);
      if (id === "vscode-timeout") return new Promise((_resolve, reject) => init.signal.addEventListener("abort", () => reject(new Error("transport")), { once: true }));
      if (id === "vscode-invalid") return Response.json(result("another-request"));
      return Response.json(result(id));
    } });
  assert.deepEqual(calls, ["vscode-timeout", "vscode-invalid", "vscode-last"]);
  assert.deepEqual(report.requests.map(row => row.evidence), ["check_failed", "check_failed", "observed"]);
});

test("duplicate, foreign and oversized selections fail before reading or inflating report counts", async () => {
  let calls = 0;
  for (const entries of [[entry(), entry()], [entry("vscode-other", { subjectRef: "other" })], Array.from({ length: 21 }, (_, i) => entry(`vscode-${i}`))]) {
    await assert.rejects(collectActivityReport({ ...args(entries), fetchImpl: async () => { calls++; } }), /unique|between/);
  }
  assert.equal(calls, 0);
});
