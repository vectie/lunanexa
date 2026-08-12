(() => {
  "use strict";

  const expectedContract = "moonbook.repository-coursebook.v1";
  const expectedEvidenceContract = "moonbook.repository-coursebook-evidence.v1";
  const state = {
    book: null,
    evidence: null,
    page: null,
    pageById: new Map(),
    groupById: new Map(),
    sourceById: new Map(),
    petPending: false,
  };

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const clear = (node) => { while (node.firstChild) node.firstChild.remove(); };
  const text = (value) => String(value ?? "");
  const array = (value) => Array.isArray(value) ? value : [];
  const element = (tag, options = {}) => {
    const node = document.createElement(tag);
    if (options.className) node.className = options.className;
    if (options.text !== undefined) node.textContent = text(options.text);
    if (options.attrs) {
      for (const [name, value] of Object.entries(options.attrs)) {
        if (value !== undefined && value !== null) node.setAttribute(name, text(value));
      }
    }
    return node;
  };

  function slug(value) {
    const normalized = text(value).normalize("NFKC").toLowerCase()
      .replace(/[^\p{L}\p{N}]+/gu, "-").replace(/^-+|-+$/g, "");
    return normalized || "section";
  }

  function boundedId(value) {
    return /^[a-z0-9][a-z0-9-]{0,79}$/.test(text(value));
  }

  function assertBook(book) {
    if (!book || book.contract_version !== expectedContract) throw new Error("Unsupported coursebook contract.");
    if (!book.project || !text(book.project.name).trim()) throw new Error("Project metadata is incomplete.");
    if (!array(book.navigation).length || !array(book.pages).length) throw new Error("The coursebook has no navigation or pages.");
    const pageIds = new Set();
    for (const page of book.pages) {
      if (!boundedId(page.id) || pageIds.has(page.id)) throw new Error("Page ids must be unique lowercase slugs.");
      if (!text(page.title).trim() || !array(page.blocks)) throw new Error(`Page ${page.id} is incomplete.`);
      pageIds.add(page.id);
    }
    const navIds = [];
    const groupIds = new Set();
    for (const group of book.navigation) {
      if (!boundedId(group.id) || groupIds.has(group.id)) throw new Error("Navigation group ids must be unique lowercase slugs.");
      groupIds.add(group.id);
      for (const id of array(group.page_ids)) {
        if (!pageIds.has(id)) throw new Error(`Navigation references missing page ${id}.`);
        navIds.push(id);
      }
    }
    if (navIds.length !== pageIds.size || new Set(navIds).size !== pageIds.size) {
      throw new Error("Every page must appear exactly once in navigation.");
    }
  }

  async function loadJson(path, required) {
    const response = await fetch(path, { headers: { Accept: "application/json" }, cache: "no-store" });
    if (!response.ok) {
      if (!required && response.status === 404) return null;
      throw new Error(`Unable to load ${path}.`);
    }
    return response.json();
  }

  async function loadCoursebook() {
    const [book, evidence] = await Promise.all([
      loadJson("./coursebook.json", true),
      loadJson("./coursebook-evidence.json", false),
    ]);
    assertBook(book);
    if (evidence && evidence.contract_version !== expectedEvidenceContract) {
      throw new Error("Unsupported coursebook evidence contract.");
    }
    state.book = book;
    state.evidence = evidence;
    state.pageById = new Map(book.pages.map((page) => [page.id, page]));
    state.groupById = new Map(book.navigation.map((group) => [group.id, group]));
    state.sourceById = new Map(array(evidence?.sources).map((source) => [source.id, source]));
  }

  function pageHref(pageId, sectionId = "") {
    const url = new URL(window.location.href);
    url.searchParams.set("page", pageId);
    url.hash = sectionId ? `#${encodeURIComponent(sectionId)}` : "";
    return `${url.pathname}${url.search}${url.hash}`;
  }

  function requestedPageId() {
    const candidate = new URL(window.location.href).searchParams.get("page");
    return state.pageById.has(candidate) ? candidate : state.book.pages[0].id;
  }

  function currentGroup(page) {
    return state.groupById.get(page.group_id) || state.book.navigation.find((group) => array(group.page_ids).includes(page.id));
  }

  function makePageLink(pageId, label, className = "") {
    const link = element("a", { className, text: label, attrs: { href: pageHref(pageId) } });
    link.addEventListener("click", (event) => {
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      navigate(pageId);
    });
    return link;
  }

  function renderChrome() {
    const project = state.book.project;
    document.documentElement.lang = text(project.language || "en");
    document.title = `${project.name} · Coursebook`;
    $("[data-project-mark]").textContent = text(project.short_name || project.name.slice(0, 2)).slice(0, 3).toUpperCase();
    $("[data-project-name]").textContent = project.name;
    $("[data-pet-name]").textContent = `${project.name} guide`;
    const freshness = $("[data-freshness]");
    freshness.textContent = text(project.freshness || "draft");
    freshness.dataset.tone = text(project.freshness || "draft");
    $("[data-revision]").textContent = project.revision ? `Revision ${project.revision}` : "Revision unavailable";

    const productNav = $("[data-product-nav]");
    const sidebar = $("[data-sidebar-nav]");
    clear(productNav);
    clear(sidebar);
    for (const group of state.book.navigation) {
      const firstId = array(group.page_ids)[0];
      const topLink = makePageLink(firstId, group.label);
      topLink.dataset.groupId = group.id;
      productNav.append(topLink);

      const section = element("section", { className: "sidebar-group" });
      section.append(element("h2", { text: group.label }));
      for (const pageId of array(group.page_ids)) {
        const page = state.pageById.get(pageId);
        const link = makePageLink(pageId, page.title);
        link.dataset.pageId = pageId;
        section.append(link);
      }
      sidebar.append(section);
    }
    renderPetSuggestions();
  }

  function appendList(parent, items) {
    const list = element("ul");
    for (const item of array(items)) list.append(element("li", { text: item }));
    parent.append(list);
  }

  function renderBlock(block, usedHeadingIds) {
    const kind = text(block?.kind);
    if (kind === "heading") {
      const level = Number(block.level) === 3 ? 3 : 2;
      const node = element(`h${level}`, { text: block.text });
      let id = boundedId(block.id) ? block.id : slug(block.text);
      let suffix = 2;
      const base = id;
      while (usedHeadingIds.has(id)) id = `${base}-${suffix++}`;
      usedHeadingIds.add(id);
      node.id = id;
      return node;
    }
    if (kind === "paragraph") return element("p", { text: block.text });
    if (kind === "bullets") {
      const list = element("ul");
      for (const item of array(block.items)) list.append(element("li", { text: item }));
      return list;
    }
    if (kind === "steps") {
      const list = element("ol", { className: "step-list" });
      for (const item of array(block.items)) {
        const body = element("div");
        body.append(element("strong", { text: item.title }), element("p", { text: item.text }));
        const row = element("li");
        row.append(body);
        list.append(row);
      }
      return list;
    }
    if (kind === "callout") {
      const node = element("aside", { className: "callout", attrs: { "data-tone": block.tone || "info" } });
      node.append(element("strong", { text: block.title }), element("p", { text: block.text }));
      return node;
    }
    if (kind === "code") {
      const node = element("section", { className: "code-block" });
      const header = element("header");
      header.append(element("span", { text: block.label || block.language || "Code" }));
      const copy = element("button", { text: "Copy", attrs: { type: "button" } });
      copy.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(text(block.code));
          copy.textContent = "Copied";
          showToast("Copied to clipboard");
          window.setTimeout(() => { copy.textContent = "Copy"; }, 1400);
        } catch {
          showToast("Copy is unavailable in this browser");
        }
      });
      header.append(copy);
      const pre = element("pre");
      pre.append(element("code", { text: block.code, attrs: { "data-language": block.language || "text" } }));
      node.append(header, pre);
      return node;
    }
    if (kind === "table") {
      const wrap = element("div", { className: "table-wrap", attrs: { tabindex: "0", role: "region", "aria-label": block.label || "Data table" } });
      const table = element("table");
      const head = element("thead");
      const headRow = element("tr");
      for (const column of array(block.columns)) headRow.append(element("th", { text: column, attrs: { scope: "col" } }));
      head.append(headRow);
      const body = element("tbody");
      for (const values of array(block.rows)) {
        const row = element("tr");
        for (const value of array(values)) row.append(element("td", { text: value }));
        body.append(row);
      }
      table.append(head, body);
      wrap.append(table);
      return wrap;
    }
    if (kind === "flow") {
      const node = element("section", { className: "flow-block" });
      if (block.title) node.append(element("strong", { text: block.title }));
      const track = element("div", { className: "flow-track" });
      for (const step of array(block.steps)) {
        const card = element("div", { className: "flow-step", attrs: { "data-tone": step.tone || "default" } });
        card.append(element("strong", { text: step.title }), element("p", { text: step.text }));
        track.append(card);
      }
      node.append(track);
      return node;
    }
    if (kind === "cards") {
      const grid = element("div", { className: "card-grid" });
      for (const item of array(block.items)) {
        let card;
        if (state.pageById.has(item.href)) {
          card = makePageLink(item.href, "", "content-card");
        } else if (/^https:\/\//.test(text(item.href))) {
          card = element("a", { className: "content-card", attrs: { href: item.href, target: "_blank", rel: "noreferrer" } });
        } else {
          card = element("article", { className: "content-card" });
        }
        card.append(element("strong", { text: item.title }), element("p", { text: item.text }));
        grid.append(card);
      }
      return grid;
    }
    if (kind === "troubleshooting") {
      const node = element("section", { className: "troubleshooting" });
      const header = element("header");
      header.append(element("small", { text: "Symptom" }), element("strong", { text: block.symptom }));
      const grid = element("div", { className: "troubleshooting-grid" });
      const sections = [
        ["Likely causes", block.likely_causes],
        ["Safe checks", block.checks],
        ["Resolution", block.resolution],
        ["Escalate when", block.escalate_when || ["The documented checks do not isolate the failure."]],
      ];
      for (const [title, items] of sections) {
        const section = element("section");
        section.append(element("h3", { text: title }));
        appendList(section, items);
        grid.append(section);
      }
      node.append(header, grid);
      return node;
    }
    if (kind === "checkpoint") {
      const node = element("aside", { className: "checkpoint" });
      node.append(element("strong", { text: block.question }));
      const details = element("details");
      details.append(element("summary", { text: "Reveal answer" }), element("p", { text: block.answer }));
      node.append(details);
      if (Number(block.revisit_after_days) > 0) node.append(element("small", { text: `Revisit after ${Number(block.revisit_after_days)} days.` }));
      return node;
    }
    return null;
  }

  function renderToc(headings) {
    const toc = $("[data-toc]");
    clear(toc);
    for (const heading of headings) {
      const link = element("a", { text: heading.textContent, attrs: { href: `#${encodeURIComponent(heading.id)}`, "data-level": heading.tagName === "H3" ? "3" : "2" } });
      link.addEventListener("click", (event) => {
        event.preventDefault();
        history.replaceState({ page: state.page.id }, "", pageHref(state.page.id, heading.id));
        heading.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
      });
      toc.append(link);
    }
  }

  function renderSources(page) {
    const container = $("[data-source-list]");
    clear(container);
    const list = element("ul", { className: "source-list" });
    for (const sourceId of array(page.source_ids)) {
      const source = state.sourceById.get(sourceId);
      const label = source ? `${source.id} · ${source.path || source.kind || "source"}` : `${sourceId} · evidence record unavailable`;
      list.append(element("li", { text: label }));
    }
    if (!list.childElementCount) list.append(element("li", { text: "No source references were published for this page." }));
    const repo = state.evidence?.repository;
    if (repo) list.append(element("li", { text: `Inspected ${repo.revision || "unknown revision"} · working tree ${repo.working_tree || "unknown"} · ${repo.inspected_at || "time unavailable"}` }));
    container.append(list);
  }

  function flatPageOrder() {
    return state.book.navigation.flatMap((group) => array(group.page_ids));
  }

  function renderPagination(page) {
    const node = $("[data-pagination]");
    clear(node);
    const ids = flatPageOrder();
    const index = ids.indexOf(page.id);
    const links = [
      index > 0 ? [ids[index - 1], "Previous"] : null,
      index < ids.length - 1 ? [ids[index + 1], "Next"] : null,
    ];
    for (const item of links) {
      if (!item) { node.append(element("span")); continue; }
      const target = state.pageById.get(item[0]);
      const link = makePageLink(target.id, "");
      link.append(element("small", { text: item[1] }), element("strong", { text: target.title }));
      node.append(link);
    }
  }

  function renderPage(pageId, focusMain = false) {
    const page = state.pageById.get(pageId) || state.book.pages[0];
    state.page = page;
    const group = currentGroup(page);
    document.title = `${page.title} · ${state.book.project.name}`;
    $("[data-page-status]").textContent = text(page.status || "documented");
    $("[data-page-status]").dataset.status = text(page.status || "documented");
    $("[data-page-effort]").textContent = Number(page.estimated_minutes) > 0 ? `${Number(page.estimated_minutes)} min` : "";
    $("[data-page-title]").textContent = page.title;
    $("[data-page-summary]").textContent = page.summary;
    $("[data-page-audience]").textContent = page.audience ? `For ${page.audience}` : "";
    const breadcrumbs = $("[data-breadcrumbs]");
    clear(breadcrumbs);
    breadcrumbs.append(makePageLink(state.book.pages[0].id, state.book.project.name));
    breadcrumbs.append(element("span", { text: "›" }), element("span", { text: group?.label || "Coursebook" }));

    const body = $("[data-page-body]");
    clear(body);
    const usedHeadingIds = new Set();
    for (const block of array(page.blocks)) {
      const rendered = renderBlock(block, usedHeadingIds);
      if (rendered) body.append(rendered);
    }
    const headings = $$(`h2[id], h3[id]`, body);
    renderToc(headings);
    renderSources(page);
    renderPagination(page);

    $$('[data-page-id]').forEach((link) => link.setAttribute("aria-current", link.dataset.pageId === page.id ? "page" : "false"));
    $$('[data-group-id]').forEach((link) => link.setAttribute("aria-current", link.dataset.groupId === group?.id ? "true" : "false"));
    $("[data-loading]").hidden = true;
    $("[data-error]").hidden = true;
    $("[data-article]").hidden = false;
    closeMobileNav();
    if (focusMain) $("#coursebook-main").focus({ preventScroll: true });

    const section = decodeURIComponent(window.location.hash.replace(/^#/, ""));
    if (section) window.requestAnimationFrame(() => document.getElementById(section)?.scrollIntoView());
    else window.scrollTo({ top: 0, behavior: "auto" });
  }

  function navigate(pageId, options = {}) {
    if (!state.pageById.has(pageId)) return;
    if (options.replace) history.replaceState({ page: pageId }, "", pageHref(pageId, options.sectionId || ""));
    else history.pushState({ page: pageId }, "", pageHref(pageId, options.sectionId || ""));
    renderPage(pageId, true);
    if (options.sectionId) window.requestAnimationFrame(() => document.getElementById(options.sectionId)?.scrollIntoView());
  }

  function pageSearchText(page) {
    const collect = (value) => {
      if (typeof value === "string") return value;
      if (Array.isArray(value)) return value.map(collect).join(" ");
      if (value && typeof value === "object") return Object.values(value).map(collect).join(" ");
      return "";
    };
    return collect([page.title, page.summary, page.tags, page.blocks]).toLocaleLowerCase();
  }

  function renderSearch(query) {
    const results = $("[data-search-results]");
    clear(results);
    const words = text(query).trim().toLocaleLowerCase().split(/\s+/u).filter(Boolean);
    const ranked = state.book.pages.map((page) => {
      const haystack = pageSearchText(page);
      const score = words.reduce((total, word) => total + (haystack.includes(word) ? 1 : 0), 0);
      return { page, score };
    }).filter((item) => !words.length || item.score > 0).sort((a, b) => b.score - a.score).slice(0, 20);
    if (!ranked.length) {
      results.append(element("div", { className: "search-empty", text: "No matching page. Try a component name, command, error code, or shorter phrase." }));
      return;
    }
    for (const { page } of ranked) {
      const button = element("button", { className: "search-result", attrs: { type: "button", role: "option" } });
      button.append(element("strong", { text: page.title }), element("small", { text: page.summary }));
      button.addEventListener("click", () => {
        $("[data-search-dialog]").close();
        navigate(page.id);
      });
      results.append(button);
    }
  }

  function openSearch() {
    const dialog = $("[data-search-dialog]");
    if (!dialog.open) dialog.showModal();
    const input = $("[data-search-input]");
    input.value = "";
    renderSearch("");
    window.setTimeout(() => input.focus(), 0);
  }

  function openMobileNav() {
    document.body.classList.add("nav-open");
    $("[data-toggle-nav]").setAttribute("aria-expanded", "true");
    $("[data-scrim]").hidden = false;
  }

  function closeMobileNav() {
    document.body.classList.remove("nav-open");
    $("[data-toggle-nav]").setAttribute("aria-expanded", "false");
    if ($("[data-pet-panel]").hidden) $("[data-scrim]").hidden = true;
  }

  function petSessionId() {
    const key = "moonbook.coursebook.pet.session.v1";
    try {
      const current = sessionStorage.getItem(key);
      if (/^[A-Za-z0-9_-]{1,80}$/.test(current || "")) return current;
      const generated = `browser-${crypto.randomUUID().replaceAll("-", "")}`.slice(0, 80);
      sessionStorage.setItem(key, generated);
      return generated;
    } catch {
      return "browser";
    }
  }

  function addPetMessage(role, value, citations = [], confidence = "") {
    const node = element("div", { className: "pet-message", text: value, attrs: { "data-role": role } });
    if (role === "assistant" && confidence) node.append(element("small", { text: `Evidence: ${confidence}` }));
    if (role === "assistant" && citations.length) {
      const list = element("div", { className: "pet-citations" });
      for (const citation of citations) {
        const page = state.pageById.get(citation.page_id);
        if (!page) continue;
        const button = element("button", { text: page.title, attrs: { type: "button" } });
        button.addEventListener("click", () => {
          closePet();
          navigate(page.id, { sectionId: citation.section_id || "" });
        });
        list.append(button);
      }
      if (list.childElementCount) node.append(list);
    }
    const thread = $("[data-pet-thread]");
    thread.append(node);
    thread.scrollTop = thread.scrollHeight;
  }

  function renderPetSuggestions() {
    const node = $("[data-pet-suggestions]");
    clear(node);
    for (const question of array(state.book.suggested_questions).slice(0, 6)) {
      const button = element("button", { text: question, attrs: { type: "button" } });
      button.addEventListener("click", () => askPet(question));
      node.append(button);
    }
  }

  function openPet() {
    const panel = $("[data-pet-panel]");
    panel.hidden = false;
    $("[data-open-pet]").setAttribute("aria-expanded", "true");
    $("[data-scrim]").hidden = false;
    if (!$("[data-pet-thread]").childElementCount) {
      addPetMessage("assistant", `Ask me about ${state.book.project.name}. I answer only from this published coursebook and never run commands.`);
    }
    $("[data-pet-input]").focus();
  }

  function closePet() {
    $("[data-pet-panel]").hidden = true;
    $("[data-open-pet]").setAttribute("aria-expanded", "false");
    if (!document.body.classList.contains("nav-open")) $("[data-scrim]").hidden = true;
  }

  async function askPet(question) {
    const value = text(question).trim();
    if (!value || state.petPending) return;
    state.petPending = true;
    $("[data-pet-input]").value = "";
    $("[data-pet-submit]").disabled = true;
    addPetMessage("user", value);
    const pending = element("div", { className: "pet-message", text: "Reading the published coursebook…", attrs: { "data-role": "assistant", "data-pending": "true" } });
    $("[data-pet-thread]").append(pending);
    try {
      const response = await fetch("./api/coursebook/ask", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ question: value, page_id: state.page?.id || "", session_id: petSessionId() }),
      });
      const payload = await response.json().catch(() => ({}));
      pending.remove();
      if (!response.ok || payload.ok !== true) throw new Error(text(payload.error || "The guide is unavailable."));
      addPetMessage("assistant", payload.answer, array(payload.citations), payload.confidence);
      if (payload.next_step) addPetMessage("assistant", payload.next_step);
    } catch {
      pending.remove();
      addPetMessage("assistant", "The guide is offline right now. The coursebook remains fully available through search and navigation.", [], "unavailable");
    } finally {
      state.petPending = false;
      $("[data-pet-submit]").disabled = false;
    }
  }

  function showToast(message) {
    const toast = $("[data-toast]");
    toast.textContent = message;
    toast.hidden = false;
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => { toast.hidden = true; }, 1800);
  }

  function wireEvents() {
    $("[data-open-search]").addEventListener("click", openSearch);
    $("[data-search-input]").addEventListener("input", (event) => renderSearch(event.target.value));
    $("[data-open-pet]").addEventListener("click", openPet);
    $("[data-close-pet]").addEventListener("click", closePet);
    $("[data-toggle-nav]").addEventListener("click", () => document.body.classList.contains("nav-open") ? closeMobileNav() : openMobileNav());
    $("[data-scrim]").addEventListener("click", () => { closePet(); closeMobileNav(); });
    $("[data-pet-form]").addEventListener("submit", (event) => { event.preventDefault(); askPet($("[data-pet-input]").value); });
    $("[data-pet-input]").addEventListener("keydown", (event) => {
      if (event.key === "Enter" && !event.shiftKey) { event.preventDefault(); $("[data-pet-form]").requestSubmit(); }
    });
    window.addEventListener("popstate", () => renderPage(requestedPageId()));
    window.addEventListener("keydown", (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); openSearch(); }
      else if (event.key === "/" && !["INPUT", "TEXTAREA"].includes(document.activeElement?.tagName)) { event.preventDefault(); openSearch(); }
      else if (event.key === "Escape") { closePet(); closeMobileNav(); }
    });
  }

  async function start() {
    try {
      await loadCoursebook();
      renderChrome();
      wireEvents();
      const pageId = requestedPageId();
      history.replaceState({ page: pageId }, "", pageHref(pageId, window.location.hash.replace(/^#/, "")));
      renderPage(pageId);
    } catch (error) {
      $("[data-loading]").hidden = true;
      $("[data-error]").hidden = false;
      $("[data-error-message]").textContent = error instanceof Error ? error.message : "Unknown coursebook error.";
    }
  }

  start();
})();
