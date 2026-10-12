/* Local output for the existing authenticated diagnostics page. No transport. */
(() => {
  "use strict";
  const sections = Object.freeze(["health", "alerts", "fleet", "knowledge", "skills"]);
  const healthStates = new Set(["healthy", "degraded", "unavailable", "stale", "disabled"]);
  function fail() { throw new Error("The selected diagnostic evidence cannot be exported."); }
  function object(value) { if (!value || typeof value !== "object" || Array.isArray(value)) fail(); return value; }
  function string(value, max = 128) { if (typeof value !== "string" || !value || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) fail(); return value; }
  function code(value) { if (!/^[A-Za-z0-9][A-Za-z0-9._:@/-]{0,127}$/.test(string(value))) fail(); return value; }
  function count(value) { if (!Number.isSafeInteger(value) || value < 0) fail(); return value; }
  function flag(value) { if (typeof value !== "boolean") fail(); return value; }
  function list(value, project, max = 128) { if (!Array.isArray(value) || value.length > max) fail(); return value.map(project); }
  function health(value) { if (!healthStates.has(value)) fail(); return value; }
  const runbook = value => ({ runbook_page_id: code(value.runbook_page_id) });
  function stateCounts(value) {
    object(value);
    return { total: count(value.total), truncated: flag(value.truncated), by_state: list(value.by_state, row => ({ code: code(row.code), count: count(row.count) })) };
  }
  function build(payload, selected, createdAt = Date.now()) {
    if (payload?.ok !== true || payload.category !== "overview") fail();
    const value = object(payload.diagnostics);
    if (value.contract_version !== "lunanexa.guide-diagnostics.v1") fail();
    if (!Array.isArray(selected) || !selected.length || selected.some(item => !sections.includes(item)) || new Set(selected).size !== selected.length) fail();
    const chosen = sections.filter(section => selected.includes(section));
    const missing = list(value.missing_evidence, code);
    const observation = count(value.generated_unix_ms);
    const result = {
      contract_version: "lunanexa.guide-support-report.v1",
      observed_unix_ms: observation,
      report_created_unix_ms: count(createdAt),
      correlation_receipt: code(payload.correlation_receipt),
      selected_sections: chosen,
      missing_evidence: missing,
      limitations: [
        "Selected aggregate diagnostics from one saved response; not a live or complete cluster report.",
        "Missing evidence is unknown, not zero. Available counts may be bounded or partial.",
        "Observation time is the server projection time, not a simultaneous controller snapshot or export time.",
        "Receipts and knowledge revisions are references, not independently authenticated proof.",
        "Review operational details before sharing; this download does not send a support request.",
        "No production, physical-cluster, model-response, payment or customer-access qualification is established.",
      ],
      sections: {},
    };
    for (const section of chosen) {
      if (section === "health") {
        result.sections.health = {
          adapter_health: health(object(value.adapter).health),
          components: list(value.components, item => ({ code: code(item.code), health: health(item.health), ...runbook(item) })),
          reconciliation: missing.includes("reconciliation-plan") ? { evidence: "missing" } : {
            evidence: "available", pending_actions: count(object(value.reconciliation).pending_actions), ...runbook(value.reconciliation),
          },
        };
      } else if (section === "alerts") {
        const alerts = object(value.active_alerts);
        result.sections.alerts = missing.includes("operator-alerts") ? { evidence: "missing" } : {
          evidence: "available", total: count(alerts.total), critical: count(alerts.critical),
          by_code: list(alerts.by_code, item => ({ code: code(item.code), count: count(item.count), ...runbook(item) })),
        };
      } else if (section === "fleet") {
        result.sections.fleet = {
          nodes: missing.includes("node-summary") ? { evidence: "missing" } : { evidence: "available", ...stateCounts(value.nodes) },
          exclusive_leases: missing.includes("lease-summary") ? { evidence: "missing" } : { evidence: "available", ...stateCounts(value.exclusive_leases) },
        };
      } else if (section === "knowledge") {
        const knowledge = object(value.knowledge);
        result.sections.knowledge = {
          revision: code(knowledge.revision),
          last_successful_index_build: knowledge.last_successful_index_build === null ? null : string(knowledge.last_successful_index_build, 80),
          age_ms: knowledge.age_ms === null ? null : count(knowledge.age_ms),
          maximum_age_ms: count(knowledge.maximum_age_ms), stale: flag(knowledge.stale),
        };
      } else if (section === "skills") {
        result.sections.skills = list(value.skills, item => ({
          id: code(item.id), name: string(item.name, 120), version: string(item.version, 64),
          enabled: flag(item.enabled), health: health(item.health),
          required_evidence: list(item.required_evidence, code, 32), missing_evidence: list(item.missing_evidence, code, 32),
          ...runbook(item),
        }), 32);
      }
    }
    const content = JSON.stringify(result, null, 2) + "\n";
    if (new TextEncoder().encode(content).byteLength > 131072) fail();
    return Object.freeze({ content, filename: `lunanexa-guide-support-${observation}.json` });
  }
  globalThis.LunaNexaDiagnosticReport = Object.freeze({ build, sections });
})();
