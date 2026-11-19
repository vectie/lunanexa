import { app } from "../../scripts/app.js";
import { api } from "../../scripts/api.js";

// A compatibility extension to the pinned ComfyUI frontend. Task authority and
// output references always come from this workspace's server, never localStorage.
app.registerExtension({
  name: "LunaNexa.VideoRecovery",
  async setup() {
    const labels = { submitting: "正在提交", queued: "排队中", generating: "正在生成",
      finishing: "正在完成解码 / 编码", downloading: "正在保存成片", reconnecting: "正在重连原任务",
      completed: "已保存", failed: "生成失败", needs_attention: "等待恢复连接",
      uncertain: "提交状态待确认", cancelled: "已取消" };
    const style = document.createElement("style");
    style.textContent = `.lnx-video-toggle{position:fixed;right:20px;bottom:72px;z-index:1000;min-height:44px;padding:10px 16px;border-radius:10px;border:1px solid #8793a1;background:var(--comfy-menu-bg,#20242b);color:var(--input-text,#f5f5f5);font:600 14px system-ui;cursor:pointer}.lnx-video-panel{position:fixed;right:20px;bottom:126px;width:min(420px,calc(100vw - 40px));max-height:65vh;overflow:auto;z-index:1000;box-sizing:border-box;padding:16px;background:var(--comfy-menu-bg,#20242b);color:var(--input-text,#f5f5f5);border:1px solid #8793a1;border-radius:12px;box-shadow:0 8px 32px #0005;font:14px/1.5 system-ui}.lnx-video-panel[hidden]{display:none}.lnx-video-panel h2{font-size:18px;margin:0}.lnx-video-panel header{display:flex;align-items:center;justify-content:space-between;gap:8px}.lnx-video-panel button,.lnx-video-panel a{min-height:44px;display:inline-flex;align-items:center;justify-content:center;box-sizing:border-box;padding:8px 12px;margin:4px 8px 4px 0;border:1px solid #8793a1;border-radius:7px;color:inherit;background:transparent;font:inherit;cursor:pointer;text-decoration:none}.lnx-video-panel button:focus-visible,.lnx-video-toggle:focus-visible,.lnx-video-panel a:focus-visible{outline:3px solid #59bcff;outline-offset:2px}.lnx-video-card{padding:14px 0;border-top:1px solid #8793a155}.lnx-video-card p{margin:4px 0;overflow-wrap:anywhere}.lnx-video-card small{opacity:.8}.lnx-video-card progress{width:100%;height:12px;accent-color:#73b7e4}.lnx-video-panel video{display:block;width:100%;max-height:240px;margin-top:8px}.lnx-video-note{opacity:.85}.lnx-video-card summary{cursor:pointer;min-height:44px;line-height:44px}`;
    document.head.append(style);
    const toggle = document.createElement("button");
    toggle.className = "lnx-video-toggle";
    toggle.textContent = "视频任务";
    toggle.setAttribute("aria-expanded", "false");
    const panel = document.createElement("section");
    panel.className = "lnx-video-panel";
    panel.hidden = true;
    panel.setAttribute("aria-label", "视频任务与恢复");
    const header = document.createElement("header");
    const title = document.createElement("h2");
    title.textContent = "视频任务";
    const close = document.createElement("button");
    close.textContent = "收起";
    const note = document.createElement("p");
    note.className = "lnx-video-note";
    note.textContent = "任务和成片保存在当前工作区。切换页面不会重复生成。";
    const connection = document.createElement("p");
    connection.setAttribute("role", "status");
    const list = document.createElement("div");
    header.append(title, close);
    panel.append(header, note, connection, list);
    document.body.append(toggle, panel);
    let busy = false, previous = "", autoOpened = false;
    const cards = new Map();
    function setOpen(value) {
      panel.hidden = !value;
      toggle.setAttribute("aria-expanded", String(value));
    }
    toggle.onclick = () => { setOpen(panel.hidden); refresh(); };
    close.onclick = () => { setOpen(false); toggle.focus(); };
    panel.onkeydown = event => { if (event.key === "Escape") { setOpen(false); toggle.focus(); } };
    function render(tasks) {
      const alive = tasks.filter(task => task.active || ["submitting", "queued", "generating", "finishing", "downloading", "reconnecting"].includes(task.phase));
      toggle.textContent = alive.length ? `视频任务 · ${alive.length} 项进行中` : "视频任务";
      if (alive.length && !autoOpened) { setOpen(true); autoOpened = true; }
      if (!tasks.length) { list.textContent = "暂无视频任务；已有成片也会出现在这里。"; return; }
      const present = new Set(tasks.map(task => task.id));
      for (const [id, card] of cards) if (!present.has(id)) { card.remove(); cards.delete(id); }
      for (const [index, task] of tasks.entries()) {
        let card = cards.get(task.id);
        if (!card) {
          card = document.createElement("article"); card.className = "lnx-video-card";
          if (!cards.size) list.replaceChildren();
          cards.set(task.id, card); list.insertBefore(card, list.children[index] || null);
        }
        // Retain the video element during polling, so playback is not reset.
        const key = JSON.stringify([task.phase, task.progress, task.message, task.can_recover, task.output]);
        if (card.dataset.state === key) continue;
        card.dataset.state = key; card.replaceChildren();
        const status = document.createElement("strong");
        status.textContent = labels[task.phase] || "状态待确认";
        const time = document.createElement("p");
        time.textContent = new Date(task.created_at * 1000).toLocaleString("zh-CN", {timeZone:"Asia/Shanghai", hour12:false});
        const id = document.createElement("small"); id.textContent = `任务 ${task.id.slice(0, 10)}`;
        card.append(status, time, id);
        if (task.phase !== "completed") {
          const bar = document.createElement("progress"); bar.max = 100;
          bar.value = task.progress || 0; bar.setAttribute("aria-label", "已记录的视频进度");
          const detail = document.createElement("p");
          detail.textContent = task.phase === "generating" ? `采样进度 ${task.progress || 0}% · 以服务端报告为准` : (task.message || "任务记录已保存，页面重开后会自动同步。");
          card.append(bar, detail);
        }
        if (task.can_recover) {
          const resume = document.createElement("button"); resume.textContent = "连接原任务";
          resume.onclick = async () => {
            resume.disabled = true;
            try {
              const response = await api.fetchApi(`/lunanexa/video-tasks/${encodeURIComponent(task.id)}/recover`, {method:"POST"});
              if (!response.ok) throw new Error("连接未完成，请稍后查看任务状态");
              connection.textContent = "正在找回原任务，不会重新生成。";
            } catch { connection.textContent = "暂时未能连接。任务记录与已保存的视频仍保留，请稍后重试。"; }
            finally { resume.disabled = false; await refresh(); }
          };
          card.append(resume);
        }
        if (task.output) {
          const query = new URLSearchParams(task.output);
          const url = api.apiURL(`/view?${query}`);
          const download = document.createElement("a"); download.href = url;
          download.download = task.output.filename; download.textContent = "下载视频";
          const preview = document.createElement("details");
          const summary = document.createElement("summary"); summary.textContent = "播放预览";
          preview.append(summary);
          preview.addEventListener("toggle", () => {
            if (preview.open && !preview.querySelector("video")) {
              const video = document.createElement("video"); video.controls = true; video.preload = "metadata"; video.src = url;
              preview.append(video);
            }
          });
          card.append(download, preview);
        }
      }
    }
    async function refresh() {
      if (busy) return;
      busy = true;
      try {
        const response = await api.fetchApi("/lunanexa/video-tasks");
        if (!response.ok) throw new Error("unavailable");
        const data = await response.json();
        connection.textContent = "已与工作区同步";
        const next = JSON.stringify(data.tasks);
        if (next !== previous) { render(data.tasks); previous = next; }
      } catch {
        connection.textContent = "连接暂时中断；请勿重复生成。重新连接后自动恢复状态。";
      } finally { busy = false; }
    }
    for (const event of ["executing", "execution_success", "execution_error", "reconnected"]) api.addEventListener(event, refresh);
    document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
    window.addEventListener("pageshow", refresh);
    window.setInterval(() => { if (!document.hidden) refresh(); }, 5000);
    await refresh();
  }
});
