import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import vm from "node:vm";
import test from "node:test";
import { buildGuideDiagnostics } from "./guide-diagnostics.mjs";

const read = file => readFile(new URL(file, import.meta.url), "utf8");
const [core, frontend, html, book, evidence, manifest] = await Promise.all([
  read("./admin-report.js"), read("./admin.js"), read("./admin.html"),
  read("./coursebook.json").then(JSON.parse), read("./coursebook-evidence.json").then(JSON.parse), read("./guide-skills.json").then(JSON.parse),
]);
const observedAt = Date.parse(evidence.repository.inspected_at) + 1000;
const createdAt = observedAt + 60_000;
function payload(overrides = {}) {
  return { ok: true, category: "overview", correlation_receipt: "guide-test-receipt", diagnostics: buildGuideDiagnostics({
    book, evidence, manifest, now: observedAt, snapshots: {
      health: { ok: true, value: { status: "ok" } },
      alerts: { ok: true, value: [{ lifecycle: "Unread", event: { code: "NodeUnreachable", severity: "Critical", parameters: { node_ref: "private-node" } } }] },
      nodes: { ok: true, value: [{ state: "Active", node_id: "private-node" }] },
      leases: { ok: true, value: [] },
      recovery: { ok: true, value: { actions: [{ private_assignment: "not-exported" }] } },
      ...overrides,
    },
  }) };
}
function builder() {
  const context = vm.createContext({ TextEncoder });
  vm.runInContext(core, context);
  return context.LunaNexaDiagnosticReport;
}

class Element {
  constructor(tag, host) { this.tagName = tag; this.host = host; this.children = []; this.dataset = {}; this.listeners = new Map(); this.textContent = ""; this.hidden = false; this.disabled = false; this.checked = false; this.attrs = {}; }
  get firstChild() { return this.children[0]; }
  get childElementCount() { return this.children.length; }
  append(...nodes) { for (const node of nodes) { node.parent = this; this.children.push(node); } }
  remove() { if (this.parent) this.parent.children.splice(this.parent.children.indexOf(this), 1); }
  setAttribute(key, value) { this.attrs[key] = value; }
  addEventListener(event, fn) { this.listeners.set(event, fn); }
  async trigger(event, value = {}) { if (this.disabled && event === "click") return; return this.listeners.get(event)?.({ target: this, ...value }); }
  click() { if (this.tagName === "a") { if (this.host.failClick) throw new Error("download refused"); this.host.downloads.push({ ...this.attrs, blob: this.host.urls.get(this.attrs.href) }); } else return this.trigger("click"); }
  focus() { this.host.focused = this; }
}
async function host(initial = payload(), locale = "en") {
  const state = { downloads: [], urls: new Map(), revocations: [], timers: [], calls: [], writes: [], sections: [], selectors: new Map(), responses: [initial] };
  state.body = new Element("body", state);
  for (const match of html.matchAll(/<([a-z][a-z0-9]*)\b([^>]*\bdata-[^>]*)>/gi)) {
    const node = new Element(match[1], state);
    node.disabled = /\bdisabled(?:\s|>|$)/.test(match[2]);
    node.hidden = /\bhidden(?:\s|>|$)/.test(match[2]);
    node.checked = /\bchecked(?:\s|>|$)/.test(match[2]);
    for (const attr of match[2].matchAll(/\b(data-[a-z-]+)(?:="([^"]*)")?/g)) {
      state.selectors.set(`[${attr[1]}]`, node);
      const camel = attr[1].slice(5).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
      node.dataset[camel] = attr[2] ?? "";
    }
    if (node.dataset.reportSection) state.sections.push(node);
  }
  const document = {
    body: state.body, documentElement: {},
    createElement: tag => new Element(tag, state),
    querySelector: key => { assert.ok(state.selectors.has(key), `missing HTML selector ${key}`); return state.selectors.get(key); },
    querySelectorAll: key => { assert.equal(key, "[data-report-section]"); return state.sections; },
  };
  let init;
  const context = vm.createContext({ document, TextEncoder, Blob,
    Date: class extends Date { static now() { return createdAt; } },
    window: { addEventListener: (event, fn) => { assert.equal(event, "DOMContentLoaded"); init = fn; } },
    localStorage: { getItem: () => locale, setItem: (...args) => state.writes.push(args) },
    fetch: async (...args) => { state.calls.push(args); const next = state.responses.shift(); const result = await next; if (result instanceof Error) throw result; return { ok: result?.ok === true, json: async () => result }; },
    URL: { createObjectURL: blob => { const url = `blob:local-${state.urls.size}`; state.urls.set(url, blob); return url; }, revokeObjectURL: url => state.revocations.push(url) },
    setTimeout: fn => state.timers.push(fn),
  });
  vm.runInContext(core, context);
  vm.runInContext(frontend, context);
  init();
  state.flush = async () => { await new Promise(resolve => setImmediate(resolve)); };
  state.get = key => document.querySelector(`[data-${key}]`);
  state.click = key => state.get(key).trigger("click");
  state.choose = async selected => { for (const node of state.sections) node.checked = selected.includes(node.dataset.reportSection); await state.sections[0].trigger("change"); };
  await state.flush();
  return state;
}

test("actual diagnostic projection becomes a bounded allowlisted report with distinct original and report times", () => {
  const source = payload();
  source.private_credentials = "excluded";
  source.diagnostics.nodes.private_node = "excluded";
  source.diagnostics.components[0].raw_logs = "excluded";
  source.diagnostics.skills[0].prompt = "excluded";
  const before = JSON.stringify(source);
  const result = builder().build(source, ["skills", "fleet", "health", "knowledge", "alerts"], createdAt);
  const report = JSON.parse(result.content);
  assert.equal(report.observed_unix_ms, observedAt);
  assert.equal(report.report_created_unix_ms, createdAt);
  assert.equal(report.correlation_receipt, source.correlation_receipt);
  assert.deepEqual(report.selected_sections, ["health", "alerts", "fleet", "knowledge", "skills"]);
  assert.equal(report.sections.alerts.total, 1);
  assert.equal(report.sections.fleet.exclusive_leases.total, 0);
  assert.equal(report.sections.health.reconciliation.pending_actions, 1);
  assert.doesNotMatch(result.content, /private-node|private_assignment|private_credentials|raw_logs|excluded/);
  assert.equal(JSON.stringify(source), before);
  assert.ok(Buffer.byteLength(result.content) < 131072);
  assert.equal(result.filename, `lunanexa-guide-support-${observedAt}.json`);
});

test("missing aggregate evidence remains unknown and does not export fallback zero counts", () => {
  const missing = { ok: false, error_code: "Unavailable" };
  const source = payload({ alerts: missing, nodes: missing, leases: missing, recovery: missing });
  const report = JSON.parse(builder().build(source, ["health", "fleet", "alerts"], createdAt).content);
  assert.deepEqual(report.sections.alerts, { evidence: "missing" });
  assert.deepEqual(report.sections.fleet.nodes, { evidence: "missing" });
  assert.deepEqual(report.sections.fleet.exclusive_leases, { evidence: "missing" });
  assert.deepEqual(report.sections.health.reconciliation, { evidence: "missing" });
  assert.ok(report.missing_evidence.includes("node-summary"));
});

test("current fixed controller aggregate shape flows through production projection into report", () => {
  const source = payload({ aggregate: { ok: true, value: {
    contract_version: "lunanexa.guide-controller-aggregate.v1", generated_unix_ms: String(observedAt - 100), health: "healthy",
    alerts: { total: 2, critical: 1, by_code: [{ code: "NodeUnreachable", count: 2 }] },
    nodes: { total: 3, truncated: false, by_state: [{ code: "Active", count: 2 }, { code: "Unreachable", count: 1 }], private_node: "excluded" },
    exclusive_leases: { total: 1, truncated: false, by_state: [{ code: "Active", count: 1 }] },
    reconciliation_pending_actions: 4,
  } } });
  const report = JSON.parse(builder().build(source, ["health", "alerts", "fleet"], createdAt).content);
  assert.equal(report.sections.health.reconciliation.pending_actions, 4);
  assert.equal(report.sections.alerts.total, 2);
  assert.equal(report.sections.fleet.nodes.total, 3);
  assert.equal(report.observed_unix_ms, observedAt);
  assert.doesNotMatch(JSON.stringify(report), /private_node|excluded/);
});

test("operator can export only knowledge while retaining context and unavailable-evidence caveats", () => {
  const source = payload();
  const report = JSON.parse(builder().build(source, ["knowledge"], createdAt).content);
  assert.deepEqual(Object.keys(report.sections), ["knowledge"]);
  assert.equal(report.sections.knowledge.revision, source.diagnostics.knowledge.revision);
  assert.ok(report.limitations.some(item => item.includes("Missing evidence is unknown")));
  assert.ok(report.limitations.some(item => item.includes("not independently authenticated")));
});

test("reports preserve truncation, stale knowledge, Unicode names and null knowledge age", () => {
  const source = payload();
  source.diagnostics.nodes.truncated = true;
  source.diagnostics.knowledge = { ...source.diagnostics.knowledge, stale: true, age_ms: null, last_successful_index_build: null };
  source.diagnostics.skills[0].name = "中文指南 · café";
  const report = JSON.parse(builder().build(source, ["fleet", "knowledge", "skills"], createdAt).content);
  assert.equal(report.sections.fleet.nodes.truncated, true);
  assert.equal(report.sections.knowledge.age_ms, null);
  assert.equal(report.sections.knowledge.stale, true);
  assert.equal(report.sections.skills[0].name, "中文指南 · café");
});

test("no empty, duplicate or unknown section and no malformed observation can produce a report", () => {
  const api = builder();
  for (const selected of [[], ["logs"], ["health", "health"]]) assert.throws(() => api.build(payload(), selected, createdAt));
  for (const mutate of [
    p => { p.ok = false; }, p => { p.category = "alerts"; }, p => { p.diagnostics.generated_unix_ms = "123"; },
    p => { p.diagnostics.contract_version = "unknown"; }, p => { p.diagnostics.missing_evidence = null; },
    p => { p.correlation_receipt = "receipt\nextra"; }, p => { p.diagnostics.nodes.total = -1; },
  ]) { const value = payload(); mutate(value); assert.throws(() => api.build(value, ["fleet"], createdAt)); }
});

test("report size and projected collection bounds reject instead of silently truncating", () => {
  const source = payload();
  source.diagnostics.active_alerts.by_code = Array.from({ length: 129 }, () => ({ code: "Alert", count: 1, runbook_page_id: "debug-controller" }));
  assert.throws(() => builder().build(source, ["alerts"], createdAt));
  const large = payload();
  large.diagnostics.skills = Array.from({ length: 32 }, () => ({ ...large.diagnostics.skills[0], required_evidence: Array(32).fill("a".repeat(128)), missing_evidence: Array(32).fill("b".repeat(128)) }));
  assert.throws(() => builder().build(large, ["skills"], createdAt));
});

test("actual page review and explicit download produce exactly the reviewed bytes without another fetch", async () => {
  const page = await host();
  assert.equal(page.calls.length, 1);
  assert.equal(page.downloads.length, 0);
  assert.equal(page.get("report-download").disabled, true);
  await page.click("report-review");
  const preview = page.get("report-content").textContent;
  assert.equal(page.get("report-preview").hidden, false);
  assert.equal(page.downloads.length, 0);
  const report = JSON.parse(preview);
  assert.deepEqual(report.selected_sections, ["health", "alerts", "knowledge"]);
  assert.equal(page.focused, page.get("report-content"));
  await page.click("report-download");
  assert.equal(page.downloads.length, 1);
  assert.equal(await page.downloads[0].blob.text(), preview);
  assert.equal(page.downloads[0].blob.type, "application/json;charset=utf-8");
  assert.equal(page.downloads[0].download, `lunanexa-guide-support-${observedAt}.json`);
  assert.equal(page.calls.length, 1);
  assert.equal(page.writes.length, 0);
  assert.equal(page.body.children.length, 0);
  assert.equal(page.get("report-content").textContent, "");
  assert.match(page.get("report-status").textContent, /saving has not been verified/);
  assert.equal(page.focused, page.get("report-review"));
  await page.click("report-download");
  assert.equal(page.downloads.length, 1);
  page.timers.forEach(fn => fn());
  assert.deepEqual(page.revocations, [page.downloads[0].href]);
});

test("section selection invalidates a preview and new review contains only the selected subset", async () => {
  const page = await host();
  await page.click("report-review");
  await page.choose(["fleet"]);
  assert.equal(page.get("report-download").disabled, true);
  assert.equal(page.get("report-content").textContent, "");
  await page.click("report-download");
  assert.equal(page.downloads.length, 0);
  await page.click("report-review");
  assert.deepEqual(Object.keys(JSON.parse(page.get("report-content").textContent).sections), ["fleet"]);
  await page.choose([]);
  await page.click("report-review");
  assert.match(page.get("report-status").textContent, /at least one/);
});

test("cancel discards review without download or network and permits a deliberate new review", async () => {
  const page = await host();
  await page.click("report-review");
  await page.click("report-cancel");
  assert.equal(page.get("report-content").textContent, "");
  assert.equal(page.get("report-preview").hidden, true);
  assert.equal(page.get("report-download").disabled, true);
  assert.match(page.get("report-status").textContent, /Nothing was downloaded/);
  assert.equal(page.focused, page.get("report-review"));
  await page.click("report-review");
  assert.equal(page.get("report-download").disabled, false);
  assert.equal(page.calls.length, 1);
});

test("refresh invalidates old review immediately and failed refresh cannot export stale evidence", async () => {
  const page = await host();
  await page.click("report-review");
  let finish;
  page.responses.push(new Promise(resolve => { finish = resolve; }));
  const refreshing = page.click("refresh");
  assert.equal(page.get("report-content").textContent, "");
  assert.equal(page.get("report-review").disabled, true);
  await page.click("report-download");
  finish({ ok: false });
  await refreshing;
  assert.equal(page.get("report-review").disabled, true);
  assert.equal(page.get("dashboard").hidden, true);
  assert.equal(page.downloads.length, 0);
  page.responses.push(payload());
  await page.click("refresh");
  await page.click("report-review");
  assert.equal(page.get("report-download").disabled, false);
});

test("new successful refresh and repeated reviews never substitute a different downloaded observation", async () => {
  const page = await host();
  await page.click("report-review");
  const next = payload(); next.diagnostics.generated_unix_ms += 5000; next.correlation_receipt = "guide-second-receipt";
  page.responses.push(next);
  await page.click("refresh");
  assert.equal(page.get("report-download").disabled, true);
  await page.click("report-review"); await page.click("report-review");
  const preview = page.get("report-content").textContent;
  await page.click("report-download");
  assert.equal(await page.downloads[0].blob.text(), preview);
  assert.equal(JSON.parse(preview).observed_unix_ms, observedAt + 5000);
  assert.equal(JSON.parse(preview).correlation_receipt, "guide-second-receipt");
});

test("Chinese and English report controls are live translations and language refresh clears review", async () => {
  const page = await host(payload(), "zh-CN");
  assert.equal(page.get("report-download").textContent, "下载已审阅的 JSON");
  await page.click("report-review");
  page.responses.push(payload());
  page.get("locale").value = "en";
  await page.get("locale").trigger("change"); await page.flush();
  assert.equal(page.get("report-download").textContent, "Download reviewed JSON");
  assert.equal(page.get("report-content").textContent, "");
  assert.deepEqual(page.writes, [["lunanexa.locale", "en"]]);
});

test("download failure discards the review, removes temporary link and reports no save success", async () => {
  const page = await host();
  await page.click("report-review"); page.failClick = true;
  await page.click("report-download");
  assert.match(page.get("report-status").textContent, /could not be prepared or downloaded/);
  assert.equal(page.downloads.length, 0);
  assert.equal(page.body.children.length, 0);
  assert.equal(page.get("report-download").disabled, true);
  page.timers.forEach(fn => fn());
  assert.equal(page.revocations.length, 1);
});

test("page reports projection failure without exposing partial preview or creating a file", async () => {
  const source = payload(); source.diagnostics.generated_unix_ms = "bad";
  const page = await host(source);
  await page.click("report-review");
  assert.equal(page.get("report-content").textContent, "");
  assert.equal(page.get("report-download").disabled, true);
  assert.match(page.get("report-status").textContent, /could not be prepared/);
  assert.equal(page.downloads.length, 0);
});

test("report asset is ordered before the actual page script and included in existing container packaging", async () => {
  assert.ok(html.indexOf("./admin-report.js") < html.indexOf("./admin.js"));
  assert.match(await read("./Containerfile"), /COPY --chown=node:node admin-report\.js \.\//);
  assert.doesNotMatch(core, /fetch\(|localStorage|sessionStorage|innerHTML|XMLHttpRequest/);
  assert.match(html, /data-report-content tabindex="0"/);
});
