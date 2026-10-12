(() => {
  "use strict";
  const state = { locale: "en", pending: false, payload: null, report: null };
  const $ = (selector, root = document) => root.querySelector(selector);
  const clear = (node) => { while (node.firstChild) node.firstChild.remove(); };
  const text = (value) => String(value ?? "");
  const array = (value) => Array.isArray(value) ? value : [];
  const copy = {
    en: {
      language: "Language", coursebook: "Coursebook", kicker: "Administrator · Read only", title: "Guide diagnostics",
      summary: "Live, bounded health and evidence for troubleshooting the documentation guide. No commands, prompts, logs, credentials, or tenant records are available here.",
      refresh: "Refresh", refreshing: "Refreshing…", boundary: "Authenticated operator view · Aggregate evidence only · Every request is audited",
      loading: "Loading role-protected diagnostics…", unavailable: "Diagnostics are unavailable.", unavailable_detail: "The operator identity, adapter, or controller evidence could not be verified.",
      adapter_health: "Adapter health", active_alerts: "Active alerts", reconciliation: "Reconciliation backlog", knowledge_revision: "Knowledge revision",
      critical: "{count} critical", correlation: "Support receipt {value}", actions: "{count} pending actions", index_build: "Index built {value}",
      dependencies: "Dependencies", component_health: "Component health", aggregate_state: "Aggregate state", cluster_leases: "Cluster and leases",
      typed_triggers: "Typed triggers", alert_codes: "Alert codes", capabilities: "Allowlisted capabilities", skill_inventory: "Guide skill inventory",
      evidence_inputs: "Troubleshooting inputs", missing_evidence: "Missing evidence", nodes: "Machines", leases: "Exclusive leases", total: "{count} total",
      no_alerts: "No active typed alerts.", no_missing: "All required evidence is available.", runbook: "Open runbook", enabled: "Enabled", disabled: "Disabled",
      required: "Required evidence", tools: "Allowed tools", data: "Allowed data", missing: "Missing: {value}", none: "None", truncated: "Bounded at {count}+ records",
      report_title: "Local support report", report_description: "Choose aggregate sections, inspect the complete JSON, then download it. Nothing is uploaded and no support request is sent.",
      report_selection: "Report sections", report_health: "Component health and reconciliation", report_alerts: "Alert codes and counts", report_fleet: "Machine and lease state counts", report_knowledge: "Knowledge revision and freshness", report_skills: "Guide capabilities and dependencies",
      report_warning: "Observation time, support receipt and missing evidence are always included. Missing is not zero; review operational details before sharing.",
      report_review: "Review report", report_review_help: "Read the complete report. The downloaded content will exactly match this preview.", report_download: "Download reviewed JSON", report_cancel: "Cancel",
      report_choose: "Select at least one section, then review again.", report_failed: "The report could not be prepared or downloaded. Refresh diagnostics and try again.", report_cancelled: "Report discarded. Nothing was downloaded.", report_requested: "Download requested. Check your browser downloads; saving has not been verified.",
    },
    "zh-CN": {
      language: "语言", coursebook: "教程", kicker: "管理员 · 只读", title: "指南诊断",
      summary: "用于排查文档指南的实时、受限健康与证据信息。这里不提供命令、提示词、日志、凭据或租户记录。",
      refresh: "刷新", refreshing: "刷新中…", boundary: "仅限已认证管理员 · 只显示汇总证据 · 每次请求均被审计",
      loading: "正在加载受角色保护的诊断信息…", unavailable: "诊断当前不可用。", unavailable_detail: "无法验证管理员身份、诊断适配器或控制器证据。",
      adapter_health: "适配器健康", active_alerts: "活动告警", reconciliation: "协调积压", knowledge_revision: "知识版本",
      critical: "{count} 个严重告警", correlation: "支持回执 {value}", actions: "{count} 个待处理动作", index_build: "索引构建于 {value}",
      dependencies: "依赖项", component_health: "组件健康", aggregate_state: "汇总状态", cluster_leases: "集群与租约",
      typed_triggers: "类型化触发器", alert_codes: "告警代码", capabilities: "受限能力", skill_inventory: "指南技能清单",
      evidence_inputs: "排障输入", missing_evidence: "缺失证据", nodes: "机器", leases: "独占租约", total: "共 {count}",
      no_alerts: "没有活动的类型化告警。", no_missing: "所需证据均可用。", runbook: "打开运行手册", enabled: "已启用", disabled: "已禁用",
      required: "所需证据", tools: "允许工具", data: "允许数据", missing: "缺失：{value}", none: "无", truncated: "仅显示前 {count}+ 条记录的汇总",
      report_title: "本地支持报告", report_description: "选择要包含的汇总信息，查看完整 JSON，然后下载。不会上传或发送支持请求。",
      report_selection: "报告内容", report_health: "组件健康与协调", report_alerts: "告警代码与数量", report_fleet: "机器与租约状态数量", report_knowledge: "知识版本与新鲜度", report_skills: "指南能力与依赖",
      report_warning: "报告始终包含观测时间、支持回执和缺失证据。缺失不代表零；分享前请检查运行信息。",
      report_review: "查看报告", report_review_help: "请阅读完整报告。下载内容与下方预览完全一致。", report_download: "下载已审阅的 JSON", report_cancel: "取消",
      report_choose: "请至少选择一项内容，然后重新查看报告。", report_failed: "无法准备或下载报告。请刷新诊断后重试。", report_cancelled: "报告已丢弃，未下载任何内容。", report_requested: "已请求下载。请查看浏览器下载记录；尚未验证文件保存。",
    },
  };
  function t(key) { return copy[state.locale]?.[key] || copy.en[key] || key; }
  function format(key, values) { let value = t(key); for (const [name, replacement] of Object.entries(values)) value = value.replace(`{${name}}`, text(replacement)); return value; }
  function element(tag, options = {}) {
    const node = document.createElement(tag);
    if (options.className) node.className = options.className;
    if (options.text !== undefined) node.textContent = text(options.text);
    if (options.attrs) for (const [name, value] of Object.entries(options.attrs)) node.setAttribute(name, text(value));
    return node;
  }
  function statusLabel(value) {
    const labels = state.locale === "zh-CN"
      ? { healthy: "健康", degraded: "降级", unavailable: "不可用", stale: "已过期", disabled: "未启用" }
      : { healthy: "Healthy", degraded: "Degraded", unavailable: "Unavailable", stale: "Stale", disabled: "Disabled" };
    return labels[value] || text(value);
  }
  function runbookLink(pageId) {
    const advanced = pageId === "source-ledger" ? "&view=advanced" : "";
    return element("a", { text: t("runbook"), attrs: { href: `./?page=${encodeURIComponent(pageId)}${advanced}` } });
  }
  function renderChrome() {
    document.documentElement.lang = state.locale;
    document.title = `能源谷“创未来”生态街区 · ${t("title")}`;
    $("[data-language-label]").textContent = t("language");
    $("[data-coursebook-link]").textContent = t("coursebook");
    $("[data-kicker]").textContent = t("kicker"); $("[data-title]").textContent = t("title"); $("[data-summary]").textContent = t("summary");
    $("[data-refresh-label]").textContent = state.pending ? t("refreshing") : t("refresh"); $("[data-boundary]").textContent = t("boundary"); $("[data-loading]").textContent = t("loading");
    $("[data-error-title]").textContent = t("unavailable"); $("[data-error-message]").textContent = t("unavailable_detail");
    const labels = {
      "[data-overall-label]": "adapter_health", "[data-alerts-label]": "active_alerts", "[data-backlog-label]": "reconciliation", "[data-revision-label]": "knowledge_revision",
      "[data-components-kicker]": "dependencies", "[data-components-title]": "component_health", "[data-cluster-kicker]": "aggregate_state", "[data-cluster-title]": "cluster_leases",
      "[data-alert-kicker]": "typed_triggers", "[data-alert-title]": "alert_codes", "[data-skills-kicker]": "capabilities", "[data-skills-title]": "skill_inventory",
      "[data-evidence-kicker]": "evidence_inputs", "[data-evidence-title]": "missing_evidence",
      "[data-report-title]": "report_title", "[data-report-description]": "report_description", "[data-report-selection]": "report_selection",
      "[data-report-health]": "report_health", "[data-report-alerts]": "report_alerts", "[data-report-fleet]": "report_fleet", "[data-report-knowledge]": "report_knowledge", "[data-report-skills]": "report_skills",
      "[data-report-warning]": "report_warning", "[data-report-review]": "report_review", "[data-report-review-help]": "report_review_help", "[data-report-download]": "report_download", "[data-report-cancel]": "report_cancel",
    };
    for (const [selector, key] of Object.entries(labels)) $(selector).textContent = t(key);
  }
  function discardReport() {
    state.report = null;
    $("[data-report-content]").textContent = "";
    $("[data-report-preview]").hidden = true;
    $("[data-report-download]").disabled = true;
    $("[data-report-status]").textContent = "";
  }
  function reviewReport() {
    discardReport();
    if (state.pending || !state.payload) return;
    const selected = [...document.querySelectorAll("[data-report-section]")].filter(node => node.checked).map(node => node.dataset.reportSection);
    if (!selected.length) { $("[data-report-status]").textContent = t("report_choose"); return; }
    try {
      state.report = globalThis.LunaNexaDiagnosticReport.build(state.payload, selected);
      $("[data-report-content]").textContent = state.report.content;
      $("[data-report-preview]").hidden = false;
      $("[data-report-download]").disabled = false;
      $("[data-report-content]").focus();
    } catch { $("[data-report-status]").textContent = t("report_failed"); }
  }
  function downloadReport() {
    if (state.pending || !state.payload || !state.report) return;
    const reviewed = state.report;
    let url;
    let anchor;
    try {
      url = URL.createObjectURL(new Blob([reviewed.content], { type: "application/json;charset=utf-8" }));
      anchor = element("a", { attrs: { href: url, download: reviewed.filename } });
      anchor.hidden = true; document.body.append(anchor); anchor.click();
      discardReport();
      $("[data-report-status]").textContent = t("report_requested");
    } catch {
      discardReport();
      $("[data-report-status]").textContent = t("report_failed");
    } finally {
      anchor?.remove();
      if (url) setTimeout(() => URL.revokeObjectURL(url), 1000);
      $("[data-report-review]").focus();
    }
  }
  function renderStates(parent, title, summary) {
    const section = element("section", { className: "state-summary" });
    section.append(element("div", { className: "state-heading" }));
    section.firstChild.append(element("strong", { text: title }), element("span", { text: summary.truncated ? format("truncated", { count: summary.total }) : format("total", { count: summary.total }) }));
    const list = element("div", { className: "chips" });
    for (const item of array(summary.by_state)) list.append(element("span", { text: `${item.code} ${item.count}` }));
    if (!list.childElementCount) list.append(element("span", { text: t("none") }));
    section.append(list); parent.append(section);
  }
  function render(payload) {
    const value = payload.diagnostics;
    $("[data-dashboard]").hidden = false; $("[data-error]").hidden = true; $("[data-loading]").hidden = true;
    $("[data-adapter-health]").textContent = statusLabel(value.adapter.health); $("[data-adapter-health]").dataset.health = value.adapter.health;
    $("[data-correlation]").textContent = format("correlation", { value: payload.correlation_receipt });
    $("[data-alert-count]").textContent = text(value.active_alerts.total); $("[data-critical-count]").textContent = format("critical", { count: value.active_alerts.critical });
    $("[data-backlog-count]").textContent = text(value.reconciliation.pending_actions); $("[data-backlog-detail]").textContent = format("actions", { count: value.reconciliation.pending_actions });
    $("[data-revision]").textContent = value.knowledge.revision; $("[data-index-build]").textContent = format("index_build", { value: value.knowledge.last_successful_index_build || "—" });
    const components = $("[data-components]"); clear(components);
    for (const component of array(value.components)) {
      const card = element("article", { className: "component" });
      card.append(element("strong", { text: component.code }), element("span", { text: statusLabel(component.health), attrs: { "data-health": component.health } }), runbookLink(component.runbook_page_id));
      components.append(card);
    }
    const cluster = $("[data-cluster]"); clear(cluster); renderStates(cluster, t("nodes"), value.nodes); renderStates(cluster, t("leases"), value.exclusive_leases);
    const alerts = $("[data-alert-codes]"); clear(alerts);
    if (!array(value.active_alerts.by_code).length) alerts.append(element("p", { className: "empty", text: t("no_alerts") }));
    for (const alert of array(value.active_alerts.by_code)) {
      const row = element("div", { className: "alert-row" }); row.append(element("strong", { text: alert.code }), element("span", { text: text(alert.count) }), runbookLink(alert.runbook_page_id)); alerts.append(row);
    }
    const skills = $("[data-skills]"); clear(skills);
    for (const skill of array(value.skills)) {
      const card = element("article", { className: "skill-card" });
      const header = element("header"); const identity = element("div"); identity.append(element("strong", { text: skill.name }), element("small", { text: `${skill.id} · ${skill.version}` }));
      header.append(identity, element("span", { text: skill.enabled ? t("enabled") : t("disabled"), attrs: { "data-health": skill.health } })); card.append(header);
      const details = element("dl");
      for (const [label, values] of [[t("required"), skill.required_evidence], [t("tools"), skill.allowed_tools], [t("data"), skill.allowed_data]]) {
        details.append(element("dt", { text: label }), element("dd", { text: array(values).join(", ") || t("none") }));
      }
      card.append(details);
      if (array(skill.missing_evidence).length) card.append(element("p", { className: "missing", text: format("missing", { value: skill.missing_evidence.join(", ") }) }));
      card.append(runbookLink(skill.runbook_page_id)); skills.append(card);
    }
    const missing = $("[data-missing-evidence]"); clear(missing);
    if (!array(value.missing_evidence).length) missing.append(element("p", { className: "empty", text: t("no_missing") }));
    else { const list = element("ul"); for (const item of value.missing_evidence) list.append(element("li", { text: item })); missing.append(list); }
  }
  async function refresh() {
    if (state.pending) return;
    state.payload = null; discardReport(); $("[data-report-review]").disabled = true;
    state.pending = true; renderChrome(); $("[data-refresh]").disabled = true; $("[data-error]").hidden = true;
    try {
      const response = await fetch("./api/coursebook/admin/diagnostics?category=overview", { headers: { Accept: "application/json" }, cache: "no-store" });
      const payload = await response.json().catch(() => null);
      if (!response.ok || payload?.ok !== true) throw new Error("unavailable");
      render(payload);
      state.payload = payload;
      $("[data-report-review]").disabled = false;
    } catch {
      $("[data-dashboard]").hidden = true; $("[data-loading]").hidden = true; $("[data-error]").hidden = false;
    } finally {
      state.pending = false; $("[data-refresh]").disabled = false; renderChrome();
    }
  }
  function init() {
    try { state.locale = localStorage.getItem("lunanexa.locale") === "en" ? "en" : "zh-CN"; } catch { state.locale = "zh-CN"; }
    $("[data-locale]").value = state.locale;
    $("[data-locale]").addEventListener("change", (event) => { state.locale = event.target.value === "zh-CN" ? "zh-CN" : "en"; try { localStorage.setItem("lunanexa.locale", state.locale); } catch { /* optional */ } renderChrome(); refresh(); });
    $("[data-refresh]").addEventListener("click", refresh); renderChrome(); refresh();
    $("[data-report-review]").addEventListener("click", reviewReport);
    $("[data-report-download]").addEventListener("click", downloadReport);
    $("[data-report-cancel]").addEventListener("click", () => { discardReport(); $("[data-report-status]").textContent = t("report_cancelled"); $("[data-report-review]").focus(); });
    for (const input of document.querySelectorAll("[data-report-section]")) input.addEventListener("change", discardReport);
  }
  window.addEventListener("DOMContentLoaded", init);
})();
