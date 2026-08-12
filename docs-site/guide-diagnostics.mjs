import { createHash, createHmac, timingSafeEqual } from "node:crypto";

const manifestContract = "lunanexa.guide-skills.v1";
const diagnosticsContract = "lunanexa.guide-diagnostics.v1";
const maximumUpstreamBytes = 262_144;
const maximumDiagnosticBytes = 65_536;
const defaultKnowledgeMaxAgeMs = 7 * 24 * 60 * 60 * 1000;
const allowedCategories = new Set(["overview", "cluster", "alerts", "skills", "knowledge"]);
const allowedRoles = new Set(["operator", "administrator"]);

function header(headers, name) {
  if (!headers) return "";
  if (typeof headers.get === "function") return String(headers.get(name) || "");
  const key = Object.keys(headers).find((candidate) => candidate.toLowerCase() === name.toLowerCase());
  return key ? String(headers[key] || "") : "";
}

function safeInteger(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function boundedCode(value, fallback = "Unknown") {
  const normalized = String(value || "");
  return /^[A-Za-z][A-Za-z0-9._-]{0,63}$/.test(normalized) ? normalized : fallback;
}

function enumName(value, fallback = "Unknown") {
  if (typeof value === "string") return boundedCode(value, fallback);
  if (value && typeof value === "object" && !Array.isArray(value)) {
    const keys = Object.keys(value);
    if (keys.length === 1) return boundedCode(keys[0], fallback);
  }
  return fallback;
}

function countBy(values, select) {
  const counts = new Map();
  for (const value of Array.isArray(values) ? values.slice(0, 10_000) : []) {
    const key = boundedCode(select(value), "Unknown");
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return [...counts.entries()].sort(([left], [right]) => left.localeCompare(right))
    .map(([code, count]) => ({ code, count }));
}

function requiredString(value, label, pattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/) {
  const normalized = String(value || "");
  if (!pattern.test(normalized)) throw new Error(`invalid ${label}`);
  return normalized;
}

export function assertGuideSkillManifest(manifest, book) {
  if (!manifest || manifest.contract_version !== manifestContract || !Array.isArray(manifest.skills)) {
    throw new Error("unsupported guide skill manifest");
  }
  const pageIds = new Set((Array.isArray(book?.pages) ? book.pages : []).map((page) => String(page?.id || "")));
  const ids = new Set();
  for (const skill of manifest.skills) {
    const id = requiredString(skill?.id, "skill id");
    if (ids.has(id)) throw new Error("duplicate guide skill id");
    ids.add(id);
    requiredString(skill?.version, "skill version", /^[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}$/);
    if (!String(skill?.name || "").trim() || String(skill.name).length > 120) throw new Error("invalid guide skill name");
    if (!Array.isArray(skill.audience) || !skill.audience.length || skill.audience.some((item) => !["public", "operator"].includes(item))) {
      throw new Error("invalid guide skill audience");
    }
    for (const field of ["required_evidence", "allowed_tools", "allowed_data"]) {
      if (!Array.isArray(skill[field]) || skill[field].length > 32 || skill[field].some((item) => !/^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$/.test(String(item)))) {
        throw new Error(`invalid guide skill ${field}`);
      }
    }
    if (!pageIds.has(String(skill.runbook_page_id || ""))) throw new Error("guide skill runbook is missing");
  }
  for (const [code, pageId] of Object.entries(manifest.diagnostic_runbooks || {})) {
    requiredString(code, "diagnostic code");
    if (!pageIds.has(String(pageId))) throw new Error("diagnostic runbook is missing");
  }
  return manifest;
}

export function safeControllerUrl(value, allowHttps = false) {
  try {
    const url = new URL(String(value || "").trim());
    const loopback = url.protocol === "http:" && ["127.0.0.1", "localhost", "[::1]"].includes(url.hostname);
    const production = url.protocol === "https:" && allowHttps;
    return (loopback || production) && !url.username && !url.password &&
      (url.pathname === "/" || url.pathname === "") && !url.search && !url.hash;
  } catch {
    return false;
  }
}

export function adminAuthPayload({ method, pathname, actor, role, timestamp }) {
  return [String(method || "GET").toUpperCase(), String(pathname || "/"), String(actor), String(role), String(timestamp)].join("\n");
}

export function signAdminIdentity(identity, key) {
  return createHmac("sha256", key).update(adminAuthPayload(identity)).digest("hex");
}

export function verifyAdminIdentity({ headers, method, pathname, key, now = Date.now(), maximumSkewMs = 60_000 }) {
  if (typeof key !== "string" || Buffer.byteLength(key, "utf8") < 32) return null;
  const actor = header(headers, "x-lunanexa-actor");
  const role = header(headers, "x-lunanexa-role").toLowerCase();
  const timestampText = header(headers, "x-lunanexa-auth-timestamp");
  const signature = header(headers, "x-lunanexa-auth-signature").toLowerCase();
  const timestamp = Number(timestampText);
  const boundedSkew = Number.isSafeInteger(maximumSkewMs) && maximumSkewMs >= 1000 && maximumSkewMs <= 300_000 ? maximumSkewMs : 60_000;
  if (!/^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,127}$/.test(actor) || !allowedRoles.has(role) ||
      !Number.isSafeInteger(timestamp) || Math.abs(now - timestamp) > boundedSkew || !/^[a-f0-9]{64}$/.test(signature)) return null;
  const expected = signAdminIdentity({ method, pathname, actor, role, timestamp }, key);
  const left = Buffer.from(signature, "hex");
  const right = Buffer.from(expected, "hex");
  if (left.length !== right.length || !timingSafeEqual(left, right)) return null;
  return {
    actor_ref: createHash("sha256").update(actor).digest("hex").slice(0, 20),
    role,
  };
}

export function diagnosticCategory(value) {
  const category = String(value || "overview");
  return allowedCategories.has(category) ? category : null;
}

function evidenceStatus(snapshot, key) {
  return snapshot?.ok ? "available" : "missing";
}

function alertSummary(records, runbooks) {
  const active = (Array.isArray(records) ? records : []).filter((record) => enumName(record?.lifecycle) !== "Resolved").slice(0, 10_000);
  const byCode = countBy(active, (record) => record?.event?.code).map((entry) => ({
    ...entry,
    runbook_page_id: runbooks[entry.code] || runbooks.UnknownDiagnostic,
  }));
  const critical = active.filter((record) => enumName(record?.event?.severity) === "Critical").length;
  return { total: active.length, critical, by_code: byCode.slice(0, 128) };
}

function skillSummary(manifest, evidence, enabled) {
  return manifest.skills.map((skill) => {
    const missing = skill.required_evidence.filter((key) => evidence[key] !== "available");
    const isEnabled = enabled.has(skill.id);
    return {
      id: skill.id,
      name: String(skill.name).slice(0, 120),
      version: skill.version,
      audience: [...skill.audience],
      enabled: isEnabled,
      health: !isEnabled ? "disabled" : missing.length ? "degraded" : "healthy",
      required_evidence: [...skill.required_evidence],
      missing_evidence: missing,
      allowed_tools: [...skill.allowed_tools],
      allowed_data: [...skill.allowed_data],
      runbook_page_id: skill.runbook_page_id,
    };
  });
}

export function buildGuideDiagnostics({
  book,
  evidence,
  manifest,
  snapshots,
  petEnabled = false,
  adminEnabled = true,
  assistantHealthy = false,
  now = Date.now(),
  knowledgeMaxAgeMs = defaultKnowledgeMaxAgeMs,
  adapterMetrics = {},
}) {
  assertGuideSkillManifest(manifest, book);
  const inspectedAt = String(evidence?.repository?.inspected_at || "");
  const inspectedMs = Date.parse(inspectedAt);
  const ageMs = Number.isFinite(inspectedMs) ? Math.max(0, now - inspectedMs) : null;
  const boundedMaxAge = safeInteger(knowledgeMaxAgeMs, defaultKnowledgeMaxAgeMs) || defaultKnowledgeMaxAgeMs;
  const knowledgeStale = ageMs === null || ageMs > boundedMaxAge;
  const knowledgeRevision = createHash("sha256")
    .update(JSON.stringify(book || null))
    .update(JSON.stringify(evidence || null))
    .digest("hex")
    .slice(0, 20);
  const evidenceMap = {
    coursebook: book?.contract_version === "moonbook.repository-coursebook.v1" ? "available" : "missing",
    "coursebook-evidence": evidence?.contract_version === "moonbook.repository-coursebook-evidence.v1" ? "available" : "missing",
    "moonclaw-health": petEnabled && assistantHealthy ? "available" : "missing",
    "controller-health": evidenceStatus(snapshots?.health),
    "operator-alerts": evidenceStatus(snapshots?.alerts),
    "node-summary": evidenceStatus(snapshots?.nodes),
    "lease-summary": evidenceStatus(snapshots?.leases),
    "reconciliation-plan": evidenceStatus(snapshots?.recovery),
  };
  const enabled = new Set(["moonbook.repository-coursebook"]);
  if (petEnabled) enabled.add("moonbook.book-pet-query");
  if (adminEnabled) enabled.add("lunanexa.admin-guide-diagnostics");
  const enabledEvidence = new Set(manifest.skills.filter((skill) => enabled.has(skill.id)).flatMap((skill) => skill.required_evidence));
  const nodeValues = snapshots?.nodes?.ok && Array.isArray(snapshots.nodes.value) ? snapshots.nodes.value : [];
  const leaseValues = snapshots?.leases?.ok && Array.isArray(snapshots.leases.value) ? snapshots.leases.value : [];
  const recoveryActions = snapshots?.recovery?.ok && Array.isArray(snapshots.recovery.value?.actions) ? snapshots.recovery.value.actions : [];
  const alerts = alertSummary(snapshots?.alerts?.ok ? snapshots.alerts.value : [], manifest.diagnostic_runbooks);
  const missingEvidence = Object.entries(evidenceMap).filter(([key, status]) => enabledEvidence.has(key) && status !== "available").map(([key]) => key).sort();
  const adminSkill = manifest.skills.find((skill) => skill.id === "lunanexa.admin-guide-diagnostics");
  const adminMissing = adminSkill ? adminSkill.required_evidence.filter((key) => evidenceMap[key] !== "available") : ["skill-manifest"];
  const components = [
    { code: "Coursebook", health: evidenceMap.coursebook === "available" ? "healthy" : "unavailable", runbook_page_id: "source-ledger" },
    { code: "KnowledgeIndex", health: knowledgeStale ? "stale" : "healthy", runbook_page_id: manifest.diagnostic_runbooks.KnowledgeRevisionStale },
    { code: "GuideAssistant", health: !petEnabled ? "disabled" : assistantHealthy ? "healthy" : "unavailable", runbook_page_id: manifest.diagnostic_runbooks.GuideAdapterUnavailable },
    { code: "LunaNexaController", health: snapshots?.health?.ok ? "healthy" : "unavailable", runbook_page_id: manifest.diagnostic_runbooks.ControllerUnavailable },
    { code: "AdministratorDiagnostics", health: adminMissing.length ? "degraded" : "healthy", runbook_page_id: "debug-controller" },
  ];
  const result = {
    contract_version: diagnosticsContract,
    generated_unix_ms: safeInteger(now),
    knowledge: {
      revision: knowledgeRevision,
      last_successful_index_build: inspectedAt || null,
      age_ms: ageMs,
      maximum_age_ms: boundedMaxAge,
      stale: knowledgeStale,
    },
    components,
    active_alerts: alerts,
    reconciliation: {
      pending_actions: recoveryActions.length,
      runbook_page_id: recoveryActions.length ? manifest.diagnostic_runbooks.ReconciliationBacklog : "observability-recovery",
    },
    nodes: { total: Math.min(nodeValues.length, 10_000), truncated: nodeValues.length > 10_000, by_state: countBy(nodeValues, (node) => enumName(node?.state)) },
    exclusive_leases: { total: Math.min(leaseValues.length, 10_000), truncated: leaseValues.length > 10_000, by_state: countBy(leaseValues, (lease) => enumName(lease?.state)) },
    skills: skillSummary(manifest, evidenceMap, enabled),
    missing_evidence: missingEvidence,
    adapter: {
      health: missingEvidence.length ? "degraded" : "healthy",
      requests_total: safeInteger(adapterMetrics.requests_total),
      failures_total: safeInteger(adapterMetrics.failures_total),
      last_success_unix_ms: safeInteger(adapterMetrics.last_success_unix_ms) || null,
    },
  };
  if (Buffer.byteLength(JSON.stringify(result), "utf8") > maximumDiagnosticBytes) throw new Error("diagnostic projection exceeds output budget");
  return result;
}

async function fixedJsonRequest(fetcher, origin, path, token, timeoutMs) {
  let response;
  try {
    response = await fetcher(origin + path, {
      method: "GET",
      headers: token ? { Accept: "application/json", Authorization: `Bearer ${token}` } : { Accept: "application/json" },
      redirect: "error",
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch {
    return { ok: false, error_code: "Unavailable" };
  }
  if (!response?.ok) return { ok: false, error_code: response?.status === 401 || response?.status === 403 ? "Unauthorized" : "Unavailable" };
  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > maximumUpstreamBytes) return { ok: false, error_code: "ResponseTooLarge" };
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, error_code: "MalformedResponse" };
  }
}

export async function collectControllerDiagnostics({ fetcher = fetch, origin, operatorToken, timeoutMs = 2500 }) {
  const boundedTimeout = Number.isInteger(timeoutMs) && timeoutMs >= 500 && timeoutMs <= 10_000 ? timeoutMs : 2500;
  const entries = await Promise.all([
    fixedJsonRequest(fetcher, origin, "/health", "", boundedTimeout),
    fixedJsonRequest(fetcher, origin, "/v1/notifications/operator", operatorToken, boundedTimeout),
    fixedJsonRequest(fetcher, origin, "/v1/nodes", operatorToken, boundedTimeout),
    fixedJsonRequest(fetcher, origin, "/v1/exclusive-node-leases", operatorToken, boundedTimeout),
    fixedJsonRequest(fetcher, origin, "/v1/recovery/plan", operatorToken, boundedTimeout),
  ]);
  return { health: entries[0], alerts: entries[1], nodes: entries[2], leases: entries[3], recovery: entries[4] };
}

export const guideDiagnosticsLimits = Object.freeze({ maximumUpstreamBytes, maximumDiagnosticBytes });
