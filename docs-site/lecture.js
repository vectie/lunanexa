/* Structured teaching figures and a projection view for the existing coursebook. */
(() => {
  "use strict";
  const pick = (value, locale) => typeof value === "string" ? value : String(value?.[locale === "en" ? "en" : "zh"] ?? "");
  let markerSequence = 0;
  let measureContext;
  function textWidth(value, size, weight = 400) {
    measureContext ||= document.createElement("canvas").getContext("2d");
    if (!measureContext) return Array.from(value).length * size * .7;
    measureContext.font = `${weight} ${size}px system-ui, -apple-system, "PingFang SC", sans-serif`;
    return measureContext.measureText(value).width;
  }
  function wrapText(value, width, size) {
    return String(value).split("\n").flatMap(paragraph => {
      const parts = /\s/.test(paragraph) ? paragraph.split(/\s+/) : Array.from(paragraph);
      const joiner = /\s/.test(paragraph) ? " " : ""; const lines = []; let line = "";
      for (const part of parts) { const candidate = line ? line + joiner + part : part; if (line && textWidth(candidate, size) > width) { lines.push(line); line = part; } else line = candidate; }
      lines.push(line); return lines;
    }).join("\n");
  }
  const el = (tag, className, content) => { const node = document.createElement(tag); if (className) node.className = className; if (content !== undefined) node.textContent = content; return node; };
  const svg = (tag, attributes = {}, content) => { const node = document.createElementNS("http://www.w3.org/2000/svg", tag); for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, String(value)); if (content !== undefined) node.textContent = content; return node; };
  const svgText = (parent, x, y, value, size = 24, anchor = "middle", className = "") => {
    const node = svg("text", { x, y, "font-size": size, "text-anchor": anchor, class: className });
    String(value).split("\n").forEach((line, index) => { if (line || index) node.append(svg("tspan", { x, dy: index ? "1.4em" : 0 }, line || " ")); });
    parent.append(node); return node;
  };
  function stage(parent, number, className = "") { const node = svg("g", { "data-stage": number, class: className }); parent.append(node); return node; }
  function box(parent, x, y, w, h, title, detail = "", tone = "green") {
    parent.append(svg("rect", { x, y, width: w, height: h, rx: 14, class: `lv-box lv-${tone}` }));
    const titleSize = Math.min(27, 27 * (w - 30) / Math.max(1, textWidth(title, 27, 650)));
    svgText(parent, x + w / 2, y + (detail ? 42 : h / 2 + 8), title, titleSize, "middle", "lv-title");
    if (detail) svgText(parent, x + w / 2, y + 82, wrapText(detail, w - 28, 23), 23, "middle", "lv-detail");
  }
  function arrow(parent, x1, y1, x2, y2, label = "") {
    const d = `M ${x1} ${y1} L ${x2} ${y2}`;
    parent.append(svg("path", { d, class: "lv-edge", "marker-end": `url(#${parent.closest("svg").getAttribute("data-marker-id")})` }));
    parent.append(svg("path", { d, pathLength: 100, class: "lv-signal" }));
    if (label) svgText(parent, (x1 + x2) / 2, (y1 + y2) / 2 - 14, label, 18);
  }
  function draw(visual, locale) {
    const markerId = `lecture-arrow-${++markerSequence}`;
    const root = svg("svg", { viewBox: "0 0 1100 420", role: "img", "aria-label": pick(visual.alt || visual.caption, locale), "data-marker-id": markerId, class: `lecture-svg lv-type-${visual.type}` });
    const defs = svg("defs"); const marker = svg("marker", { id: markerId, viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" });
    marker.append(svg("path", { d: "M 0 0 L 10 5 L 0 10 z", fill: "#507c69" })); defs.append(marker); root.append(defs);
    const txt = (value) => pick(value, locale);
    if (window.LunaWhiteboard?.render(root, visual, locale, { svg, svgText, stage, arrow, pick })) return root;
    if (window.LunaStudio?.render(root, visual, locale, { svg, svgText, stage, arrow, pick })) return root;
    if (visual.type === "flow") {
      const items = visual.items; const gap = 42; const width = Math.min(290, (1020 - gap * (items.length - 1)) / items.length); const left = (1100 - width * items.length - gap * (items.length - 1)) / 2;
      items.forEach((item, i) => { const g = stage(root, i + 1); const x = left + i * (width + gap); box(g, x, 120, width, 156, txt(item.title), txt(item.detail), item.tone || "green"); if (i) arrow(g, x - gap + 7, 198, x - 8, 198); });
    } else if (visual.type === "compare") {
      const cols = visual.columns; const width = (1040 - (cols.length - 1) * 26) / cols.length;
      cols.forEach((col, i) => { const g = stage(root, i + 1); const x = 30 + i * (width + 26); const colors = ["#7965c7", "#338ea7", "#26947e"];
        g.append(svg("rect", { x, y: 35, width, height: 5, fill: colors[i % 3] }));
        svgText(g, x, 83, String(i + 1).padStart(2, "0"), 18, "start", "lv-comparison-index");
        svgText(g, x + 35, 83, txt(col.title), Math.min(27, 27 * (width - 42) / Math.max(1, textWidth(txt(col.title), 27, 650))), "start", "lv-title");
        (col.lines || []).forEach((line, j) => { svgText(g, x + 5, 157 + j * 78, wrapText(txt(line), width - 12, col.mono ? 22 : 25), col.mono ? 22 : 25, "start", col.mono ? "lv-mono" : ""); });
      });
    } else if (visual.type === "tokens") {
      const g1 = stage(root, 1); svgText(g1, 550, 62, txt(visual.sentence), 32);
      const pieces = visual.pieces; const width = Math.min(168, 990 / pieces.length); const left = (1100 - pieces.length * width) / 2;
      pieces.forEach((part, i) => { const g = stage(root, i + 2, "lv-token"); const x = left + i * width; box(g, x + 5, 132, width - 10, 98, txt(part)); svgText(g, x + width / 2, 278, String(visual.ids?.[i] ?? `ID ${i + 1}`), 22, "middle", "lv-mono"); });
      const last = stage(root, pieces.length + 2); svgText(last, 550, 365, txt(visual.result), 26);
    } else if (visual.type === "prediction") {
      const g1 = stage(root, 1); box(g1, 32, 120, 390, 150, txt(visual.context), txt(visual.contextDetail));
      visual.candidates.forEach((item, i) => { const g = stage(root, 2); const y = 80 + i * 86; svgText(g, 460, y + 29, txt(item.label), 25, "start"); g.append(svg("rect", { x: 610, y, width: 350 * item.value, height: 42, rx: 6, class: "lv-bar" })); svgText(g, 1010, y + 30, `${Math.round(item.value * 100)}%`, 25); });
      const g3 = stage(root, 3); box(g3, 320, 318, 460, 72, txt(visual.result), "", "gold");
    } else if (visual.type === "graph") {
      for (const edge of visual.edges || []) { const g = stage(root, edge.step || 1); const a = visual.nodes.find(n => n.id === edge.from); const b = visual.nodes.find(n => n.id === edge.to); if (!a || !b) continue;
        const horizontal = Math.abs(b.x - a.x) > Math.abs(b.y - a.y);
        const x1 = a.x + a.w / 2 + (horizontal ? Math.sign(b.x - a.x) * a.w / 2 : 0); const y1 = a.y + a.h / 2 + (horizontal ? 0 : Math.sign(b.y - a.y) * a.h / 2);
        const x2 = b.x + b.w / 2 - (horizontal ? Math.sign(b.x - a.x) * b.w / 2 : 0); const y2 = b.y + b.h / 2 - (horizontal ? 0 : Math.sign(b.y - a.y) * b.h / 2);
        arrow(g, x1, y1, x2, y2, txt(edge.label));
      }
      for (const node of visual.nodes) { const g = stage(root, node.step || 1); box(g, node.x, node.y, node.w, node.h, txt(node.title), txt(node.detail), node.tone || "green"); }
    } else if (visual.type === "timeline") {
      const x = 70, unit = 320;
      const g1 = stage(root, 1); arrow(g1, x, 270, 1030, 270); svgText(g1, x, 315, "0", 24); svgText(g1, 1030, 315, "t", 24);
      const g2 = stage(root, 2); g2.append(svg("rect", { x, y: 120, width: .8 * unit, height: 80, rx: 10, class: "lv-wait lv-bar" })); svgText(g2, x + .4 * unit, 164, txt(visual.wait), 24); svgText(g2, x + .8 * unit, 245, "0.8 s", 24);
      const g3 = stage(root, 3); g3.append(svg("rect", { x: x + .8 * unit, y: 120, width: 2 * unit, height: 80, rx: 10, class: "lv-bar" })); svgText(g3, x + 1.8 * unit, 164, txt(visual.decode), 24); svgText(g3, x + 2.8 * unit, 245, "2.8 s", 24);
      for (let i = 0; i < 21; i++) { const dot = stage(root, 3); dot.append(svg("circle", { cx: x + .8 * unit + i * 32, cy: 218, r: 4, class: "lv-dot" })); }
      const g4 = stage(root, 4); svgText(g4, 550, 378, txt(visual.result), 27);
    } else if (visual.type === "lanes") {
      const max = visual.max || Math.max(...visual.rows.map(r => r.value));
      visual.rows.forEach((row, i) => { const g = stage(root, i + 1); const y = 60 + i * 130; svgText(g, 30, y + 38, txt(row.label), 24, "start"); const x = 260;
        let offset = 0; const parts = row.parts || [{ value: row.value, label: row.value + " " + (visual.unit || "") }];
        parts.forEach((part, j) => { const width = part.value / max * 750; g.append(svg("rect", { x: x + offset, y, width: Math.max(width - 5, 3), height: 70, rx: 8, class: `lv-bar ${j % 2 ? "lv-wait" : ""}` })); svgText(g, x + offset + width / 2, y + 43, txt(part.label), 22); offset += width; });
      });
    } else if (visual.type === "batch") {
      svgText(root, 80, 38, txt(visual.incoming), 24, "start"); svgText(root, 550, 38, txt(visual.engine), 24); svgText(root, 930, 38, txt(visual.output), 24);
      for (let i = 0; i < 6; i++) { const g = stage(root, 1); box(g, 50, 68 + i * 51, 205, 40, `R${i + 1}`, "", "gray"); }
      const g2 = stage(root, 2); box(g2, 390, 112, 320, 186, txt(visual.batch), txt(visual.batchDetail)); arrow(g2, 270, 205, 378, 205);
      const g3 = stage(root, 3); arrow(g3, 724, 205, 820, 205); box(g3, 835, 112, 220, 186, txt(visual.result), txt(visual.resultDetail), "gold");
    } else if (visual.type === "diffusion") {
      const labels = visual.labels; for (let i = 0; i < 4; i++) { const g = stage(root, i + 1); const x = 20 + i * 275; g.append(svg("rect", { x, y: 56, width: 240, height: 240, rx: 12, fill: "#edf2eb" }));
        const picture = svg("g", { opacity: i / 3 }); picture.append(svg("circle", { cx: x + 180, cy: 108, r: 28, fill: "#e6ac54" }), svg("path", { d: `M${x + 10} 286 L${x + 85} 148 L${x + 150} 235 L${x + 193} 184 L${x + 230} 286 Z`, fill: "#548970" })); g.append(picture);
        const noise = svg("g", { class: i ? "lv-denoise" : "" }); g.append(noise);
        for (let k = 0; k < 150; k++) { const hash = ((k * 7919 + 104729) % 997); noise.append(svg("rect", { x: x + (hash % 23) * 10, y: 58 + ((hash * 31) % 23) * 10, width: 10, height: 10, opacity: (3 - i) / 3 * .8, fill: k % 2 ? "#526a64" : "#cad7cb" })); }
        svgText(g, x + 120, 342, txt(labels[i]), 24); if (i) arrow(g, x - 24, 175, x - 5, 175);
      }
    } else if (visual.type === "protein") {
      const g1 = stage(root, 1); box(g1, 20, 140, 320, 125, "M A K L V F …", txt(visual.sequence));
      const g2 = stage(root, 2); arrow(g2, 358, 205, 490, 205, "AlphaFold");
      const g3 = stage(root, 3); g3.append(svg("path", { d: "M565 260 C510 60 750 20 810 150 C855 250 600 350 690 120 C760 -20 985 140 880 285 C800 400 650 255 1000 230", class: "lv-ribbon", pathLength: 100 })); svgText(g3, 790, 365, txt(visual.structure), 26);
    } else if (visual.type === "weights") {
      const values = [["0.12", "0.40", "−0.70", "0.25", "0.10", "−0.32"], ["0.15", "0.36", "−0.67", "0.29", "0.08", "−0.30"]];
      [0, 1].forEach((version) => { const g = stage(root, version ? 3 : 1); const left = version ? 675 : 40; svgText(g, left + 180, 55, txt(version ? visual.after : visual.before), 28);
        values[version].forEach((value, i) => { const x = left + (i % 3) * 125, y = 95 + Math.floor(i / 3) * 110; g.append(svg("rect", { x, y, width: 110, height: 90, rx: 10, class: version ? "lv-box lv-gold" : "lv-box" })); svgText(g, x + 55, y + 54, value, 27, "middle", "lv-mono"); });
      });
      const feedback = stage(root, 2); arrow(feedback, 425, 185, 650, 185); svgText(feedback, 540, 125, txt(visual.feedback), 25); svgText(feedback, 540, 335, txt(visual.result), 24);
    } else if (visual.type === "code") {
      visual.panels.forEach((panel, i) => { const g = stage(root, i + 1); const x = 25 + i * 550; g.append(svg("rect", { x, y: 30, width: 520, height: 345, rx: 14, class: "lv-code-bg" })); svgText(g, x + 24, 77, txt(panel.title), 26, "start", "lv-code-title"); (panel.lines || []).forEach((line, j) => svgText(g, x + 24, 137 + j * 49, txt(line), 22, "start", "lv-code-text lv-mono")); });
    }
    return root;
  }
  function pointAlong(points, fraction) {
    const lengths=points.slice(1).map((p,i)=>Math.hypot(p[0]-points[i][0],p[1]-points[i][1]));
    let remaining=lengths.reduce((a,b)=>a+b,0)*Math.max(0,Math.min(1,fraction));
    for(let i=0;i<lengths.length;i++){if(remaining<=lengths[i]){const t=lengths[i]?remaining/lengths[i]:0;return [points[i][0]+(points[i+1][0]-points[i][0])*t,points[i][1]+(points[i+1][1]-points[i][1])*t];}remaining-=lengths[i];}
    return points.at(-1)||[0,0];
  }
  function mechanismMotion(diagram, visual, locale) {
    const labels={context:"上下文",tokens:"Token",compute:"计算",input:"输入",summary:"摘要",prefix:"前文",values:"数值",update:"更新",examples:"例子",source:"原文",instruction:"任务说明",history:"相关对话",evidence:"依据",query:"检索问题",passage:"相关片段",arguments:"调用参数",call:"调用",rain:"下雨",goal:"目标",observation:"观察",code:"代码",tools:"工具",weights:"参数",proposal:"改进方案",assignment:"任务分配",subtask:"子任务",findings:"调研结果",data:"数据",request:"请求",output:"输出",noise:"噪声",decode:"解码",sequence:"序列",prediction:"预测",candidates:"候选",investigate:"研究",observations:"新观察",audio:"音频",transcript:"转录",fields:"字段",tasks:"待办",class:"类别",value:"数值",actions:"动作",applications:"应用",task:"任务",result:"结果",route:"路线",estimate:"估计",cat:"猫","state + text":"状态与文字","1 token":"1 个 Token","next tool":"下一工具","runtime data":"运行数据","place service":"放置服务","shared work":"协同计算","request B":"请求 B","run result":"运行结果","model access":"模型访问","your service":"自建服务"};
    Object.assign(labels,{"ID → vector":"编号 → 数值",proportions:"组合比例",response:"回答","data → weights":"数据 → 参数","one task":"本次任务","Li · Thu":"小李 · 周四","5th":"次月 5 日","need data":"需要天气","audio → text":"声音 → 文字","next action":"下一动作","improve again":"继续改进",instance:"服务实例",send:"发送","same requests":"相同请求","power / network":"电力 / 网络",node:"节点","model service":"模型服务",files:"文件",edit:"修改","revise / run":"修改 / 运行",script:"文稿",time:"时间",timeline:"时间线",model:"模型",software:"软件",service:"服务"});
    let raf=null,step=0,progress=1,duration=1200,start=0,restore=[],effects=[],ignoreCompute=false;
    const layer=svg("g",{"aria-hidden":"true",class:"mechanism-carrier"});diagram.append(layer);
    const bubble=svg("rect",{rx:5,fill:"#fff8df",stroke:"#b98a31","stroke-width":1.5,height:31});const label=svg("text",{"text-anchor":"middle","font-size":17,fill:"#72531d"});layer.append(bubble,label);layer.style.display="none";
    const scope=n=>[...diagram.querySelectorAll(`[data-stage="${n}"]`)];
    function paint(p){
      const spec=visual.motion?.[step-1];if(!spec)return;diagram.dataset.motionProgress=p.toFixed(3);
      if(spec.kind==="flow") {const words=locale==="en"?spec.label:(labels[spec.label]||spec.label),[x,y]=pointAlong(spec.points,p),w=Math.min(192,Math.max(66,textWidth(words||"",17)+22));layer.style.display=p>=1?"none":"";const cx=Math.max(w/2+2,Math.min(1098-w/2,x)),cy=Math.max(34,Math.min(415,y));bubble.setAttribute("x",cx-w/2);bubble.setAttribute("y",cy-32);bubble.setAttribute("width",w);label.setAttribute("x",cx);label.setAttribute("y",cy-11);label.textContent=words||"";}
      for(const effect of effects)effect(p);
      if(spec.kind==="compute"&&!ignoreCompute)diagram.studio?.progress?.(step,p);
    }
    const cancel=()=>{if(raf!==null)cancelAnimationFrame(raf);raf=null;};
    function frame(now){progress=Math.min(1,(now-start)/duration);paint(progress);if(progress<1)raf=requestAnimationFrame(frame);else{raf=null;diagram.dispatchEvent(new Event("motionend"));}}
    function prepare(n,reason){
      cancel();restore.forEach(fn=>fn());restore=[];effects=[];layer.style.display="none";step=n;progress=0;
      const spec=visual.motion?.[n-1];duration=spec?.duration||1200;ignoreCompute=reason==="experiment"&&diagram.studio?.kind==="batching";if(!spec)return;
      const groups=scope(n);
      if(spec.kind==="write")for(const group of groups)for(const t of group.querySelectorAll("text")){
        if(!new RegExp(spec.match||".").test(t.textContent))continue;
        const spans=t.querySelectorAll("tspan").length?[...t.querySelectorAll("tspan")]:[t];const strings=spans.map(s=>s.textContent);restore.push(()=>spans.forEach((s,i)=>{s.textContent=strings[i];}));effects.push(p=>{let budget=Math.ceil(strings.join("").length*p);spans.forEach((s,i)=>{s.textContent=strings[i].slice(0,Math.max(0,budget));budget-=strings[i].length;});});
      }
      if(spec.kind==="grow")for(const group of groups)for(const bar of group.querySelectorAll(".lv-bar,.st-quantity")){const width=Number(bar.getAttribute("width"));restore.push(()=>bar.setAttribute("width",width));effects.push(p=>bar.setAttribute("width",width*p));}
      if(spec.kind==="draw")for(const group of groups)for(const path of group.querySelectorAll(".st-protein,.lv-ribbon,[data-draw]")){const old=path.getAttribute("stroke-dasharray"),offset=path.getAttribute("stroke-dashoffset");path.setAttribute("pathLength",100);path.setAttribute("stroke-dasharray",100);restore.push(()=>{if(old===null)path.removeAttribute("stroke-dasharray");else path.setAttribute("stroke-dasharray",old);if(offset===null)path.removeAttribute("stroke-dashoffset");else path.setAttribute("stroke-dashoffset",offset);});effects.push(p=>path.setAttribute("stroke-dashoffset",100*(1-p)));}
      if(reason==="experiment"&&diagram.studio?.kind==="batching")progress=1;
      if(window.matchMedia("(prefers-reduced-motion: reduce)").matches)progress=1;
      paint(progress);
    }
    return {get running(){return raf!==null;},get complete(){return progress>=1;},start(n,reason){prepare(n,reason);if(progress<1){start=performance.now();raf=requestAnimationFrame(frame);}},pause:cancel,resume(n){if(step!==n||progress>=1)this.start(n);else{start=performance.now()-progress*duration;raf=requestAnimationFrame(frame);}},discard(){cancel();progress=1;restore.forEach(fn=>fn());restore=[];layer.style.display="none";},finish(){cancel();paint(1);progress=1;restore.forEach(fn=>fn());restore=[];layer.style.display="none";},remaining(){return duration*(1-progress);}};
  }
  function figure(visual, locale = "zh-CN", { controls = true } = {}) {
    const root = el("figure", "teaching-figure"); const viewport = el("div", "teaching-viewport"); const diagram = draw(visual, locale); viewport.append(diagram); root.append(viewport);
    if(visual.scene)root.id=`concept-${visual.scene}`;
    const total = Math.max(1, visual.steps?.length || 3); let current = controls ? 1 : total; let playing = false;
    const motion=mechanismMotion(diagram,visual,locale);if(visual.motion)root.classList.add("has-mechanism-motion");
    const explanation=el("p","figure-explanation");explanation.setAttribute("aria-live","polite");
    const toolbar = el("div", "figure-controls"); const caption = el("span", "figure-step-caption"); caption.setAttribute("aria-live", "polite");
    const button = (zh, en, action) => { const b = el("button", "", locale === "en" ? en : zh); b.type = "button"; b.addEventListener("click", action); toolbar.append(b); return b; };
    const pause = () => { playing = false; motion.pause();root.classList.add("animation-paused"); if (play) play.textContent = locale === "en" ? "Play this step" : "播放这一步"; };
    function update() {
      root.querySelectorAll("[data-stage]").forEach(node => { const step = Number(node.getAttribute("data-stage")); node.classList.toggle("stage-hidden", step > current); node.classList.toggle("stage-active", step === current); });
      caption.textContent = `${current}/${total} · ${pick(visual.steps?.[current - 1] || visual.caption, locale)}`;
      root.dataset.step = String(current); if (next) next.disabled = current >= total;
      diagram.studio?.stage?.(current);
      explanation.textContent=diagram.studio?.explain?.(current)||pick(visual.beats?.[current-1]||"",locale);
      root.dispatchEvent(new CustomEvent("lecturestep",{detail:{step:current}}));
    }
    const playbackLabel=()=>{if(play)play.textContent=motion.running?(locale==="en"?"Pause":"暂停"):(locale==="en"?"Play this step":"播放这一步");};
    function advance() { motion.finish();if (current < total) current++; root.classList.remove("animation-paused"); update();motion.start(current);playbackLabel(); }
    const reset = controls ? button("重来", "Restart", () => { pause();motion.finish();current = 1; experiment?.reset?.(); root.classList.remove("animation-paused"); update(); }) : null;
    const play = controls ? button("播放这一步", "Play this step", () => {
      if (playing||motion.running) { pause(); return; }
      playing = true; root.classList.remove("animation-paused"); play.textContent = locale === "en" ? "Pause" : "暂停"; update();
      motion.resume(current);
      playing=motion.running;playbackLabel();
    }) : null;
    const next = controls ? button("下一步", "Next step", () => { pause(); advance(); }) : null;
    diagram.addEventListener("motionend",()=>{playing=false;playbackLabel();});
    const experimentFactory=diagram.studio?.kind?.startsWith("board-")?window.LunaWhiteboard:window.LunaStudio;
    const experiment = controls ? experimentFactory?.controls(diagram, locale, step => {current = Math.max(current, Math.min(total, step)); root.classList.remove("animation-paused"); update();motion.start(current,"experiment");playbackLabel();},()=>{pause();if(diagram.studio?.kind==="batching")motion.discard();else motion.finish();}) : null;
    if(visual.beats)root.append(explanation);
    if (controls) { toolbar.append(caption); root.append(toolbar); }
    if (experiment) toolbar.append(experiment);
    if (visual.caption) root.append(el("figcaption", "", pick(visual.caption, locale)));
    root.stop = pause; root.advance = () => { pause(); advance(); }; root.reset = () => reset?.click();
    root.goToStep = (step,{resetExperiment=false}={}) => {pause();motion.finish();if(resetExperiment)experiment?.reset?.();current=Math.max(1,Math.min(total,Number(step)||1));root.classList.remove("animation-paused");update();motion.start(current);playbackLabel();};
    update(); return root;
  }
  function flatten(data) {
    const frames = [];
    for (const lesson of data.lessons) {
      for (const slide of lesson.slides) frames.push({ ...slide, page_id: lesson.page_id, chapter: lesson.title });
      if (lesson.page_id === data.break_after) frames.push({ id: "class-break", page_id: lesson.page_id, minutes: data.break_minutes, title: { zh: "休息 10 分钟", en: "10-minute break" }, lead: { zh: "下半场：训练反馈、算力与选型，再看实际工作。", en: "Next: training and feedback, infrastructure, selection and actual work." }, notes: { zh: ["在 50 分钟处休息。回来从语料与参数计数接上，再解释训练信号，不重新做开场。"], en: ["Break at minute 50. Resume with corpora and parameter counts, then training signals."] }, kind: "break" });
    }
    frames.push({ id: "class-questions", page_id: data.lessons.at(-1).page_id, minutes: data.questions_minutes, title: { zh: "问题与讨论", en: "Questions and discussion" }, lead: { zh: "模型怎样生成？工具怎样接入？计算在哪里发生？", en: "How does generation work? How are tools connected? Where does computation happen?" }, notes: { zh: ["留出最后 5 分钟。沿着模型、harness、基础设施定位问题，再回到相关图。"], en: ["Reserve the final five minutes. Locate questions in the model, harness or infrastructure, then return to the relevant figure."] }, kind: "questions" });
    return frames.map((frame,index)=>({...frame,number:index+1,speaking:data.speaking_pages?.[frame.id]}));
  }
  function indexItems(groups, query="") {
    const terms=String(query).normalize("NFKC").toLocaleLowerCase().trim().split(/\s+/).filter(Boolean);
    return groups.flatMap(group=>(group.items||[]).filter(item=>{const haystack=JSON.stringify([group.title,item.title,item.takeaway,item.concepts]).normalize("NFKC").toLocaleLowerCase();return terms.every(term=>haystack.includes(term));}));
  }
  function courseIndex(groups,locale,{onRead,onPresent}={}) {
    const en=locale==="en",root=el("section","course-index"),search=el("div","course-index-search"),label=el("label","",en?"Find a concept":"查找概念"),input=el("input");
    input.type="search";input.placeholder=en?"Token, RAG, cache, latency…":"Token、RAG、缓存、延迟…";input.setAttribute("aria-label",en?"Find a concept":"查找概念");label.append(input);const count=el("span","course-index-count");count.setAttribute("role","status");search.append(label,count);root.append(search);
    const body=el("div","course-index-groups");root.append(body);
    const link=(label,href,handler,item)=>{const a=el("a","",label);a.href=href;if(handler)a.addEventListener("click",event=>{if(event.button!==0||event.metaKey||event.ctrlKey||event.shiftKey||event.altKey)return;event.preventDefault();handler(item);});return a;};
    function update(){const matches=new Set(indexItems(groups,input.value).map(item=>item.id));body.replaceChildren();count.textContent=en?`${matches.size} concepts`:`${matches.size} 个概念`;
      for(const group of groups){const items=group.items.filter(item=>matches.has(item.id));if(!items.length)continue;const section=el("section","course-index-group"),heading=el("h2","",pick(group.title,locale));heading.id=`course-${group.id}`;section.append(heading);const list=el("ul");
        for(const item of items){const reading=item.presentation===false,row=el("li",`course-index-row${reading?" is-reading":""}`),description=el("div","course-index-description");description.append(el("strong","",pick(item.title,locale)),el("p","",pick(item.takeaway,locale)));const actions=el("div","course-index-actions"),read=`?page=${encodeURIComponent(item.page_id)}#${encodeURIComponent(item.anchor||`concept-${item.id}`)}`,present=`?page=${encodeURIComponent(item.page_id)}&view=lecture&slide=${encodeURIComponent(item.slide_id||item.id)}`;
          const readLink=link(en?"Read":"阅读",read,onRead,item);readLink.setAttribute("aria-label",`${en?"Read":"阅读"}：${pick(item.title,locale)}`);actions.append(readLink);if(!reading){const presentLink=link(en?"Present":"投屏",present,onPresent,item);presentLink.setAttribute("aria-label",`${en?"Present":"投屏"}：${pick(item.title,locale)}`);actions.append(presentLink);row.append(el("span","course-index-time",`${item.start}–${item.start+item.minutes} min`));}row.append(description,actions);list.append(row);
        }section.append(list);body.append(section);
      }if(!matches.size)body.append(el("p","course-index-empty",en?"No matching concept. Try another term.":"没有匹配的概念，请换一个关键词。"));
    }input.addEventListener("input",()=>{update();root.dispatchEvent(new CustomEvent("courseindexchange"));});update();return root;
  }
  function createController({ getLocale, getPage, getIndexGroups, renderPage, changeLocale }) {
    let data, frames = [], index = 0, root, currentFigure, notesOpen = false, focusBefore;
    const language = () => getLocale() === "en" ? "en" : "zh-CN";
    function stop() { currentFigure?.stop(); }
    function close({ updateUrl = true, pageId } = {}) {
      if (!root) return; stop(); root.remove(); root = null; document.body.classList.remove("lecture-open");
      const page = pageId || frames[index]?.page_id || getPage();
      if (updateUrl) { const url = new URL(location.href); url.searchParams.delete("view"); url.searchParams.delete("slide"); url.searchParams.set("page", page); history.pushState({}, "", url); }
      renderPage(page); focusBefore?.focus();
    }
    function showIndex(){
      stop();const focusBeforeIndex=document.activeElement,locale=language(),en=locale==="en",dialog=el("dialog","lecture-index-dialog");dialog.setAttribute("aria-label",en?"Course directory":"课程目录");const header=el("header","lecture-index-header"),title=el("h2","",en?"Course directory":"课程目录"),dismiss=el("button","",en?"Back to class":"返回课堂");dismiss.type="button";dismiss.addEventListener("click",()=>dialog.close());header.append(title,dismiss);dialog.append(header);
      dialog.append(courseIndex(getIndexGroups?.()||data.outline,locale,{onPresent:item=>{dialog.close();show(frames.findIndex(frame=>frame.id===(item.slide_id||item.id)));},onRead:item=>{dialog.close();const url=new URL(location.href);url.searchParams.delete("view");url.searchParams.delete("slide");url.searchParams.set("page",item.page_id);url.hash=item.anchor||`concept-${item.id}`;history.pushState({},"",url);close({updateUrl:false,pageId:item.page_id});}}));
      dialog.addEventListener("close",()=>{dialog.remove();if(root?.contains(focusBeforeIndex))focusBeforeIndex.focus();});root.append(dialog);dialog.showModal();dialog.querySelector("input").focus();
    }
    function show(nextIndex, updateUrl = true) {
      stop(); index = Math.max(0, Math.min(frames.length - 1, nextIndex)); const frame = frames[index], locale = language(), en = locale === "en"; root.replaceChildren();
      document.title = `${pick(frame.title, locale)} · ${en ? "AI class" : "AI 课堂"}`;
      const top = el("header", "lecture-top"); const chapter = el("select", "lecture-chapters"); chapter.setAttribute("aria-label", en ? "Lesson" : "课程章节");
      data.lessons.forEach(lesson => { const option = el("option", "", pick(lesson.title, locale)); option.value = lesson.page_id; option.selected = frame.page_id === lesson.page_id; chapter.append(option); }); chapter.addEventListener("change", () => show(frames.findIndex(f => f.page_id === chapter.value)));
      top.append(chapter); const controls = el("div", "lecture-top-actions");
      const b = (zh, english, fn) => { const button = el("button", "", en ? english : zh); button.type = "button"; button.addEventListener("click", fn); controls.append(button); return button; };
      b("目录", "Contents", showIndex);
      b(en ? "中文" : "English", "中文", () => { changeLocale(en ? "zh-CN" : "en"); show(index, false); });
      const notesButton = b("讲稿", "Speaker notes", () => { notesOpen = !notesOpen; notes.hidden = !notesOpen; notesButton.setAttribute("aria-expanded", String(notesOpen)); }); notesButton.setAttribute("aria-expanded", String(notesOpen));
      b("退出投屏", "Exit presentation", () => close()); top.append(controls); root.append(top);
      const canvas = el("section", "lecture-canvas"); canvas.setAttribute("aria-label", en ? "Current slide" : "当前投屏页");
      canvas.dataset.scene = frame.id;
      const heading = el("h1", "", pick(frame.title, locale)); heading.tabIndex = -1; canvas.append(heading, el("p", "lecture-lead", pick(frame.lead, locale)));
      if (frame.visual) { currentFigure = figure(frame.visual, locale); canvas.append(currentFigure); }
      else { currentFigure = null; canvas.classList.add("lecture-pause"); const time = el("div", "lecture-break-time", frame.kind === "break" ? "10 min" : "5 min"); canvas.append(time); }
      if (frame.key) canvas.append(el("p", "lecture-key", pick(frame.key, locale)));
      root.append(canvas);
      const footer = el("footer", "lecture-footer"); const previous = el("button", "", en ? "← Previous" : "← 上一页"); previous.disabled = index === 0; previous.addEventListener("click", () => show(index - 1));
      const elapsed = frames.slice(0, index).reduce((sum, f) => sum + f.minutes, 0); footer.append(previous, el("span", "lecture-position", `${index + 1} / ${frames.length} · ${elapsed}–${elapsed + frame.minutes} min`));
      const next = el("button", "", en ? "Next →" : "下一页 →"); next.disabled = index === frames.length - 1; next.addEventListener("click", () => show(index + 1)); footer.append(next); root.append(footer);
      const notes = el("aside", "lecture-notes"); notes.hidden = !notesOpen; notes.setAttribute("aria-label", en ? "Speaker notes" : "讲稿"); notes.append(el("strong", "", `${en ? "Speaking time" : "讲授时间"} · ${frame.minutes} min`));
      const scriptLinks=el("p","speaker-script-links"),scriptLink=el("a","",en?"Complete Chinese script":"整套逐页讲稿");scriptLink.href=`./ai-speaker-script.html#${encodeURIComponent(frame.id)}`;scriptLink.target="_blank";scriptLink.rel="noopener";scriptLinks.append(scriptLink);notes.append(scriptLinks);
      if(!en&&frame.speaking){
        const script=frame.speaking,verbatim=el("section","speaker-verbatim");verbatim.setAttribute("aria-label","逐字讲解稿");verbatim.append(el("h2","",`第 ${frame.number} / ${frames.length} 页 · ${elapsed}–${elapsed+frame.minutes} 分钟`),el("p","speaker-spoken",script.opening));
        if(script.steps.length)verbatim.append(el("p","speaker-direction","演示按钮会恢复该示例的初始数值。灰色操作提示不朗读。"));
        for(const item of script.steps){const section=el("section",`speaker-segment${item.step===1?" note-current":""}`);section.dataset.noteStep=String(item.step);section.append(el("h3","",`${item.step} · ${item.label}`));const action=el("p","speaker-direction",item.action),showStep=el("button","speaker-demo","演示这一步");showStep.type="button";showStep.setAttribute("aria-label",`演示第 ${item.step} 步：${item.label}`);showStep.addEventListener("click",()=>currentFigure?.goToStep(item.step,{resetExperiment:true}));section.append(action,showStep,el("p","speaker-spoken",item.text));verbatim.append(section);}
        for(const item of script.guidance||[]){verbatim.append(el("p","speaker-direction",item.action),el("p","speaker-spoken",item.text));}
        verbatim.append(el("h3","","收束与衔接"),el("p","speaker-spoken",script.closing));notes.append(verbatim);
      }
      const preparation=el("details","speaker-preparation"),preparationTitle=el("summary","",en?"Teaching outline and reference":"备课参考：原理、节奏与学生追问");preparation.append(preparationTitle);preparation.open=en||!frame.speaking;
      const reference=el("div","speaker-reference");
      if(frame.teaching){const teaching=frame.teaching;reference.append(el("p","speaker-opening",pick(teaching.opening,locale)));if(teaching.pacing)reference.append(el("p","speaker-pacing",en?`Plan: explain ${teaching.pacing.speech_seconds}s · demonstrate ${teaching.pacing.demo_seconds}s · observe/question ${teaching.pacing.processing_seconds+teaching.pacing.question_seconds}s · transition/margin ${teaching.pacing.transition_seconds+teaching.pacing.margin_seconds}s`:`安排：讲述 ${teaching.pacing.speech_seconds} 秒 · 演示 ${teaching.pacing.demo_seconds} 秒 · 观察/追问 ${teaching.pacing.processing_seconds+teaching.pacing.question_seconds} 秒 · 转场/余量 ${teaching.pacing.transition_seconds+teaching.pacing.margin_seconds} 秒`));reference.append(el("p","speaker-action",pick(teaching.demonstration,locale)),el("p","speaker-pause",pick(teaching.pause,locale)));}
      const paragraphs=frame.notes?.[en?"en":"zh"]||[];paragraphs.forEach((paragraph,i)=>{const p=el("p",i===0?"note-current":"",paragraph);if(i<(frame.visual?.steps.length||0))p.dataset.noteStep=i+1;else p.classList.add("note-transition");reference.append(p);});
      if(frame.background_notes){const more=el("details","note-background"),summary=el("summary","",en?"Further explanation":"补充说明");more.append(summary);for(const p of frame.background_notes[en?"en":"zh"])more.append(el("p","",p));reference.append(more);}
      if(frame.primary_notes){const section=el("section","note-primary");section.append(el("h2","",en?"Teaching detail":"讲解细节"));for(const p of frame.primary_notes[en?"en":"zh"])section.append(el("p","",p));reference.append(section);}
      if(frame.teaching){const more=el("details","note-questions"),summary=el("summary","",en?"Student questions: why, how, connection":"学生追问：为什么、怎么算、怎样衔接");more.append(summary);for(const item of frame.teaching.questions)more.append(el("h3","",pick(item.question,locale)),el("p","",pick(item.answer,locale)));reference.append(more);if(frame.teaching.recovery.seconds>0){const cut=el("details","note-recovery");cut.append(el("summary","",en?`If behind: save ${frame.teaching.recovery.seconds}s`:`若落后：可缩短 ${frame.teaching.recovery.seconds} 秒`),el("p","",pick(frame.teaching.recovery.instruction,locale)));reference.append(cut);}}
      preparation.append(reference);notes.append(preparation);
      currentFigure?.addEventListener("lecturestep",event=>{notes.querySelectorAll("[data-note-step]").forEach(p=>p.classList.toggle("note-current",Number(p.dataset.noteStep)===event.detail.step));});root.append(notes);
      root.dataset.slideId = frame.id;
      root.setAttribute("aria-label", en ? "AI class" : "AI 课堂");
      if (updateUrl) { const url = new URL(location.href); url.searchParams.set("view", "lecture"); url.searchParams.set("page", frame.page_id); url.searchParams.set("slide", frame.id); history.pushState({}, "", url); }
      heading.focus({ preventScroll: true });
    }
    async function open(pageId, slideId, updateUrl = true) {
      if (!data) { const response = await fetch("./ai-lecture.json", { cache: "no-store" }); if (!response.ok) throw new Error("Unable to load class"); data = await response.json(); frames = flatten(data); }
      if (!root) { document.querySelectorAll(".teaching-figure").forEach(figure => figure.stop?.()); focusBefore = document.activeElement; root = el("section", "lecture-shell"); root.setAttribute("role", "region"); root.setAttribute("aria-label", language() === "en" ? "AI class" : "AI 课堂"); document.body.append(root); document.body.classList.add("lecture-open"); }
      const found = slideId ? frames.findIndex(f => f.id === slideId) : frames.findIndex(f => f.page_id === pageId); show(found < 0 ? 0 : found, updateUrl);
    }
    window.addEventListener("keydown", event => {
      if (!root || event.ctrlKey || event.metaKey || event.altKey || ["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)) return;
      if(root.querySelector("dialog[open]"))return;
      if (event.key === "Escape") close(); else if (["ArrowRight", "PageDown"].includes(event.key)) show(index + 1); else if (["ArrowLeft", "PageUp"].includes(event.key)) show(index - 1); else if (event.code === "Space" && event.target.tagName !== "BUTTON") currentFigure?.advance(); else return;
      event.preventDefault(); event.stopImmediatePropagation();
    }, true);
    document.addEventListener("visibilitychange", () => { if (document.hidden) stop(); });
    return { open, close, get active() { return Boolean(root); }, handleLocation() { const url = new URL(location.href); if (url.searchParams.get("view") === "lecture") { open(url.searchParams.get("page"), url.searchParams.get("slide"), false); return true; } if (root) close({ updateUrl: false }); return false; } };
  }
  const api = { pick, flatten, pointAlong, figure, courseIndex, indexItems, createController };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else {window.LunaLecture=api;document.addEventListener("visibilitychange",()=>{if(document.hidden)document.querySelectorAll(".teaching-figure").forEach(figure=>figure.stop?.());});}
})();
