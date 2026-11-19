/* Original classroom artwork; references and design rationale are recorded in docs. */
(() => {
  "use strict";
  const palette = { ink: "#172945", muted: "#64748b", line: "#cbd5e1", paper: "#fff", model: "#7965c7", data: "#dda846", compute: "#338ea7", output: "#26947e", red: "#c86b67", dark: "#18263f" };
  const probabilities = (temperature = 1) => { const values = [.6, .3, .1].map(p => Math.pow(p, 1 / temperature)); const sum = values.reduce((a, b) => a + b, 0); return values.map(p => p / sum); };
  const choose = (values, random) => { let total = 0; for (let i = 0; i < values.length; i++) { total += values[i]; if (random < total) return i; } return values.length - 1; };
  const trainingStep = (weight, rate = .05) => { const xs = [1, 2, 3]; const loss = xs.reduce((sum, x) => sum + (weight * x - 2 * x) ** 2, 0) / 3; const gradient = xs.reduce((sum, x) => sum + 2 * (weight * x - 2 * x) * x, 0) / 3; return { weight, loss, next: weight - rate * gradient }; };
  const sortExample = () => ({ input: [20, 100, 3], ordinary: [20, 100, 3].sort(), numeric: [20, 100, 3].sort((a, b) => a - b) });
  // A deliberately small decode-only scheduler: two slots, all requests ready.
  function scheduling(mode) {
    const waiting = [2, 4, 1, 3].map((length, i) => ({ id: "ABCD"[i], length, count: 0 }));
    const slots = [null, null], rounds = [];
    while (waiting.length || slots.some(Boolean)) {
      if (mode === "continuous" || slots.every(s => !s || s.count === s.length)) {
        for (let i = 0; i < 2; i++) if (!slots[i] || slots[i].count === slots[i].length) slots[i] = waiting.shift() || null;
      }
      const cells = slots.map(s => s && s.count < s.length ? { id: s.id, token: ++s.count, length: s.length } : null);
      if (!cells.some(Boolean)) break;
      rounds.push(cells);
      if (mode === "continuous") for (let i = 0; i < 2; i++) if (slots[i]?.count === slots[i]?.length) slots[i] = null;
    }
    return rounds;
  }
  const weekendChoice = rain => rain ? { place: "museum", tool: "museum_hours", result: "09:00–17:00" } : { place: "park", tool: "park_route", result: "2 km" };
  const weightedMix=(weights,values)=>values[0].map((_,j)=>values.reduce((sum,v,i)=>sum+weights[i]*v[j],0));

  function render(root, visual, locale, h) {
    const { svg, svgText, stage, arrow, pick } = h;
    const en = locale === "en", c = palette, scene = visual.scene;
    const say = (zh, english) => en ? english : zh;
    const diagramLabels={"INPUT → OUTPUT":"输入 → 输出","MODEL INPUT":"送给模型的输入","CONTEXT / HARNESS":"上下文 / 外围程序","RESULT":"返回结果","TOOL CALL":"工具调用请求","TOOL RESULT":"工具返回结果","NEXT TOOL":"下一项工具","TOOL":"工具","HARNESS":"外围程序（Harness）","PRETRAIN":"预训练","POST-TRAIN":"后训练","INFERENCE":"推理","MODEL v1":"模型版本 1","MODEL v2":"模型版本 2","MODEL":"模型","ENGINES / TOOLS":"引擎 / 开发工具","DOMAIN WORK":"具体工作","APPLICATION":"应用","WEIGHTS + GPU":"参数 + GPU","Engine + weights":"引擎 + 参数","Model API":"模型 API"};
    const value = v => pick(v, locale);
    const rect = (p, x, y, w, ht, fill = "#fff", stroke = "none", radius = 7, extra = {}) => { const r = svg("rect", { x, y, width: w, height: ht, rx: radius, fill, stroke, ...extra }); p.append(r); return r; };
    const path = (p, d, stroke = c.line, width = 2, fill = "none", extra = {}) => { const n = svg("path", { d, stroke, "stroke-width": width, fill, ...extra }); p.append(n); return n; };
    const text = (p, x, y, content, size = 23, fill = c.ink, anchor = "start", weight = 400) => { const t = svgText(p, x, y, en?content:(diagramLabels[content]||content), size, anchor); t.setAttribute("fill", fill); t.setAttribute("font-weight", weight); return t; };
    const circle = (p, x, y, r, fill, stroke = "none") => { const n = svg("circle", { cx: x, cy: y, r, fill, stroke }); p.append(n); return n; };
    const head = (p, x, y, num, content, color = c.model) => { text(p, x, y, String(num).padStart(2, "0"), 16, color, "start", 700); text(p, x + 35, y, content, 24, c.ink, "start", 650); };
    function chip(p, x, y, w = 210, ht = 160) {
      rect(p, x, y, w, ht, "#234961", "#4f7b8e", 9);
      for (let i = 0; i < 12; i++) { rect(p, x + 15 + i * (w - 30) / 12, y - 8, 5, 10, "#88a4b4", "none", 1); rect(p, x + 15 + i * (w - 30) / 12, y + ht - 2, 5, 10, "#88a4b4", "none", 1); }
      const die = Math.min(w * .43, ht * .6), dx = x + (w - die) / 2, dy = y + (ht - die) / 2;
      rect(p, dx - 6, dy - 6, die + 12, die + 12, "#101f35", "#8cd0d4", 4);
      for (let r = 0; r < 6; r++) for (let k = 0; k < 6; k++) rect(p, dx + k * die / 6 + 1, dy + r * die / 6 + 1, die / 6 - 3, die / 6 - 3, (k + r) % 3 ? "#559aa9" : "#a4ded1", "none", 1);
      for (let i = 0; i < 4; i++) { const mx = i < 2 ? x + 12 : x + w - 39, my = y + 22 + (i % 2) * (ht - 70); rect(p, mx, my, 27, 43, "#7290a3", "#a4bbc6", 3); }
    }
    function model(p, x, y, w = 205, ht = 135, name = say("语言模型", "LLM")) {
      for (let i = 5; i >= 0; i--) { const off = i * 9; path(p, `M${x + off} ${y - off} h${w} l18 15 v${ht} h-${w} l-18 -15 Z`, i ? "#a497d0" : "#7260b0", 1, i ? "#e9e5f5" : "#d9d1ef"); }
      rect(p, x + 15, y + 15, w - 12, ht - 14, "#493d77", "none", 3);
      for (let i = 0; i < 7; i++) for (let j = 0; j < 3; j++) rect(p, x + 28 + i * (w - 40) / 7, y + 31 + j * 21, 12, 12, (i + j) % 3 ? "#8477b6" : "#b8acd9", "none", 1);
      text(p, x + w / 2 + 10, y + ht - 10, name, 21, "#fff", "middle", 650);
    }
    function rack(p, x, y, w = 150, ht = 235, label = "GPU NODE") {
      path(p, `M${x} ${y} l15 -12 h${w} v${ht} l-15 12 Z`, "#4b5e76", 1, "#26374d"); rect(p, x, y, w, ht, "#17253b", "#6e829a", 5);
      for (let i = 0; i < Math.min(6,Math.max(2,Math.floor((ht-15)/34))); i++) { rect(p, x + 10, y + 14 + i * 34, w - 20, 27, "#3c5069", "#708399", 3); for (let k = 0; k < 4; k++) rect(p, x + 19 + k * 19, y + 22 + i * 34, 12, 11, k % 2 ? "#728999" : "#746799", "none", 1); circle(p, x + w - 22, y + 27 + i * 34, 3, "#8dd1b4"); }
      text(p, x + w / 2, y + ht + 27, label, 16, c.muted, "middle", 600);
    }
    function browser(p, x, y, w, ht, title, dark = false) {
      rect(p, x, y, w, ht, dark ? c.dark : "#fff", "#c5d1dd", 9); rect(p, x, y, w, 34, dark ? "#2a3b56" : "#edf1f6", "none", 9); rect(p, x, y + 23, w, 11, dark ? "#2a3b56" : "#edf1f6", "none", 0);
      ["#d78680", "#dfbd74", "#83b7a0"].forEach((col, i) => circle(p, x + 16 + i * 14, y + 16, 4, col)); text(p, x + 66, y + 23, title, 15, dark ? "#d6e2f1" : c.muted);
    }
    function doc(p, x, y, w, ht, title, lines = [], highlight = -1) {
      path(p, `M${x} ${y} h${w - 22} l22 22 v${ht - 22} h-${w} Z`, "#c7d2df", 1.3, "#fff"); path(p, `M${x + w - 22} ${y} v22 h22`, "#c7d2df", 1.3, "#edf2f8");
      text(p, x + 18, y + 36, title, 19, c.ink, "start", 650);
      lines.forEach((line, i) => { if (i === highlight) rect(p, x + 10, y + 52 + i * 32, w - 20, 29, "#fff1cc", "none", 3); text(p, x + 18, y + 74 + i * 32, line, 17, i === highlight ? "#8a6115" : c.muted); });
    }
    function waveform(p, x, y, width, height, color = c.compute) { for (let i = 0; i < 66; i++) { const amp = (Math.sin(i * 1.7) ** 2 * .65 + Math.cos(i * .31) ** 2 * .35) * height; rect(p, x + i * width / 66, y - amp / 2, 3, amp, color, "none", 1); } }
    function cafe(p,x,y,w,ht) {
      const view=svg("svg",{x,y,width:w,height:ht,viewBox:"0 0 240 210"});p.append(view);rect(view,0,0,240,210,"#d7e8ed");circle(view,188,37,21,"#efd099");path(view,"M0 175 L240 169 V210 H0 Z","none",0,"#c7d8cb");
      rect(view,43,57,151,127,"#e9d6b7","none",1);path(view,"M34 60 L118 24 L203 60 Z","#8c7767",1,"#9a7160");rect(view,60,94,53,65,"#537b80","#b0997f",3);rect(view,131,94,45,90,"#486e71","#ae9479",3);path(view,"M86 95 V158 M61 125 H112 M152 95 V182", "#d7d9bc",2);rect(view,40,74,157,24,"#578778","none",1);for(let i=0;i<8;i++)rect(view,44+i*19,74,9,24,"#d2d9bf","none",0);text(view,116,69,"CAFÉ",12,"#4c6054","middle",650);rect(view,41,184,156,10,"#bdb497","none",1);
      rect(view,17,146,10,43,"#8b7562","none",1);circle(view,23,126,26,"#82a98d");circle(view,11,140,20,"#779d80");circle(view,37,141,20,"#93b39a");rect(view,206,164,13,23,"#ad8267","none",2);path(view,"M211 165 Q188 141 205 135 Q221 142 211 165 M212 165 Q227 140 232 146 Q235 161 212 165", "none",0,"#709c83");return view;
    }
    function table(p, x, y, width, rows) {
      rect(p, x, y, width, 36 + rows.length * 42, "#fff", c.line, 5); rect(p, x, y, width, 36, "#e9eef6", "none", 4);
      const widths = [.45, .27, .28]; const heads = say(["事项", "负责人", "日期"], ["Task", "Owner", "Date"]); let dx = x;
      heads.forEach((label, i) => { text(p, dx + 12, y + 25, label, 16, c.muted, "start", 650); dx += width * widths[i]; });
      rows.forEach((row, i) => { path(p, `M${x} ${y + 36 + i * 42} h${width}`, "#e3e9f0", 1); let dx = x; row.forEach((cell, j) => { text(p, dx + 12, y + 65 + i * 42, cell, 18, j === 1 ? c.model : c.ink); dx += width * widths[j]; }); });
    }
    const cardLabel = (p, x, y, heading, detail) => { text(p, x, y, heading, 24, c.ink, "middle", 650); if (detail) text(p, x, y + 31, detail, 18, c.muted, "middle"); };
    const is = (...ids) => ids.includes(scene);
    root.classList.add("studio-svg");

    if(is("pre-post-test-time")){
      [["PRETRAIN",say("前文 → 真实下一 Token","PREFIX → ACTUAL NEXT TOKEN"),"MODEL v1",say("比较目标概率 → 更新参数","Target probability → update")],["POST-TRAIN",say("任务 → 好回答的示范","TASK → DEMONSTRATION"),"MODEL v2",say("从已有参数继续调整","Continue from learned parameters")],["INFERENCE",say("这一次的任务与上下文","This task and its context"),say("生成 / 搜索 / 比较","Generate / search / compare"),say("本次使用的计算","Computation for this task")]].forEach((row,i)=>{const g=stage(root,i+1),x=20+i*365;head(g,x,28,i+1,row[0]);doc(g,x+10,66,310,125,row[1],i===0?["The sky is → blue",say("目标 blue 的概率：20% → 60%","Target blue probability: 20% → 60%")]:i===1?[say("提取待办 → 事项表","Extract tasks → a task table"),say("比较两个回答 → 偏好反馈","Compare answers → preferences")]:[say("问题 + 资料 → 本次回答","Question + material → response")]);arrow(g,x+160,203,x+160,244);rect(g,x+10,260,310,75,i<2?"#e5ddf3":"#d9eced","none",4);text(g,x+165,307,row[2],25,i<2?c.model:c.compute,"middle",650);text(g,x+165,389,row[3],19,c.muted,"middle");});return true;
    }
    if(is("prompt-before-after")){
      [[say("整理这份记录。","Organize these notes."),say("可以是摘要、改写或待办清单。","Could mean a summary, rewrite or task list.")],[say("提取事项、负责人、日期。","Extract task, owner and date."),say("用表格；没提及的信息留空。","Use a table; keep missing fields absent.")]].forEach((row,i)=>{const g=stage(root,i+1),x=25+i*555;browser(g,x,38,500,315,say(i?"明确的任务说明":"宽泛的任务说明",i?"SPECIFIC TASK":"BROAD TASK"));text(g,x+23,122,row[0],27,c.ink,"start",650);text(g,x+23,173,row[1],21,c.muted);if(i){table(g,x+23,211,452,[[say("初稿","Draft"),say("小李","Li"),say("周四","Thu")]]);}else{[say("摘要","Summary"),say("改写","Rewrite"),say("待办","Tasks")].forEach((v,k)=>{rect(g,x+25+k*155,238,135,60,"#edf1f7","none",3);text(g,x+92+k*155,277,v,23,c.muted,"middle");});}text(g,x+250,404,say(i?"输出结构成为生成条件。":"任务中仍有许多未确定的选择。",i?"Output structure becomes a condition.":"The task leaves many choices open."),23,i?c.output:c.muted,"middle");});return true;
    }
    if(is("different-ai-tasks")){
      const a=stage(root,1);head(a,20,28,1,say("分类","Classification"));rect(a,35,72,285,180,"#f1e9da","none",5);path(a,"M104 136 L106 93 L144 117 Q175 103 204 120 L238 91 L234 142 Q259 217 170 231 Q78 217 104 136","#a0805a",2,"#d5b78d");circle(a,144,164,6,c.ink);circle(a,203,164,6,c.ink);path(a,"M165 188 L180 188 L173 197 Z",c.ink,1,c.ink);text(a,40,304,say("图像 → 类别：猫","Image → category: cat"),25,c.ink);text(a,40,370,say("输出一个类别。","Output a category."),22,c.muted);
      const b=stage(root,2);head(b,390,28,2,say("数值预测","Value prediction"));path(b,"M420 72 V252 H690",c.line,2);path(b,"M430 221 L480 196 L530 207 L580 155 L630 132",c.compute,4);path(b,"M630 132 L680 106",c.model,4,"none",{"stroke-dasharray":"7 5"});circle(b,680,106,7,c.model);text(b,420,63,say("需求量","Demand"),17,c.muted);text(b,660,280,say("时间","Time"),17,c.muted);text(b,410,319,say("历史需求 → 下周估计","History → demand estimate"),24,c.ink);text(b,410,370,say("输出数值或分布。","Output a value or distribution."),22,c.muted);
      const d=stage(root,3);head(d,760,28,3,say("规划与行动","Planning and action"));for(let i=0;i<5;i++)for(let j=0;j<4;j++)rect(d,785+i*55,78+j*43,51,39,(i===2&&j<3)?"#62768b":"#edf1f6","#d5dfeb",2);path(d,"M812 98 V229 H1032 V98",c.output,5);circle(d,812,98,9,c.data);circle(d,1032,98,9,c.output);text(d,812,65,say("起点","Start"),17,c.data,"middle");text(d,1032,65,say("终点","Goal"),17,c.output,"middle");text(d,778,304,say("位置与障碍 → 路线","Position + obstacles → route"),23,c.ink);text(d,778,370,say("输出动作顺序。","Output an action sequence."),22,c.muted);return true;
    }
    if(is("cluster-engine-path")){
      const a=stage(root,1);text(a,20,30,say("Kubernetes：安排运行位置","Kubernetes: service placement"),23,c.compute,"start",650);doc(a,20,70,175,170,say("服务资源要求","SERVICE REQUEST"),[say("1 块 GPU","One GPU"),say("需要设备与显存","Device + memory")]);[0,1].forEach(i=>{rect(a,245,78+i*153,185,125,"#e8eef6","#9eb0c4",5);text(a,337,115+i*153,say(`节点 ${i+1}`,`NODE ${i+1}`),21,c.compute,"middle",650);text(a,337,162+i*153,say(i?"已有工作":"可用设备",i?"Occupied":"Available"),19,c.muted,"middle");});
      const b=stage(root,2);arrow(b,200,150,237,140);rect(b,258,130,159,56,"#d7eade","#8dbda4",4);text(b,337,165,say("模型服务实例","SERVICE INSTANCE"),18,c.output,"middle",650);text(b,215,406,say("放置一份服务，不是每个 Token 都重新放置。","Place a service, not each individual token."),19,c.ink,"middle");
      const d=stage(root,3);path(d,"M462 38 V401",c.line,1);text(d,498,30,say("节点内：推理引擎","ON THE NODE: INFERENCE ENGINE"),23,c.model,"start",650);browser(d,498,63,570,110,"WEIGHTS + GPU",true);text(d,520,135,say("加载参数，执行模型计算。","Load weights; execute model computation."),25,"#c8d8ec");
      const out=stage(root,4);const initial=text(out,500,215,say("先处理输入 Prefill：A B C → D","Prefill input: A B C → D"),23,c.compute);const next=text(out,500,308,say("再生成：读 A/B/C 缓存 + D → E","Decode: read A/B/C cache + D → E"),22,c.output);const cache=[];for(let r=0;r<2;r++){text(out,500,255+r*92,say("记录","Cache"),17,c.muted);for(let i=0;i<4;i++){const box=rect(out,560+i*99,230+r*92,85,38,i===3?"#b5dcc7":"#d9d1ed","none",3);const t=text(out,602+i*99,256+r*92,"ABCD"[i],20,c.ink,"middle");cache.push({box,t,r,i});}}text(out,795,397,say("读旧记录，算新位置；省重复计算，不丢前文。","Read old states, compute the new position; keep the context."),20,c.output,"middle");
      root.studio={progress(step,p){if(step!==4)return;initial.setAttribute("opacity",p<.12?.15:1);next.setAttribute("opacity",p<.5?.15:1);cache.forEach(({box,t,r,i})=>{const active=r===0?i<3&&p>.12:(i<3&&p>.5)||(i===3&&p>.8);box.setAttribute("opacity",active?1:.05);t.setAttribute("opacity",active?1:.05);});}};root.studio.progress(4,1);return true;
    }

    if (is("agent-loop")) {
      const a=stage(root,1);doc(a,20,64,245,258,say("周六半日安排","SATURDAY PLAN"),[say("地点：杭州","City: Hangzhou"),say("先查天气","Check the weather"),say("再决定去哪里","Choose where to go")]);
      const harness=stage(root,2);rect(harness,310,17,760,363,"#f3f0f9","#c5b8df",5);text(harness,330,49,"HARNESS",16,c.model,"start",700);text(harness,1045,49,say("准备上下文 · 执行工具 · 保留结果","Context · tools · results"),17,c.muted,"end");
      browser(harness,340,75,320,110,say("天气返回 → 放入输入","Weather result → input"),true);const weather=text(harness,360,148,say("工具返回：下雨","Tool result: rain"),25,"#f3d28e");arrow(harness,275,185,323,132);
      const b=stage(root,3);model(b,768,100,175,113);const decision=text(b,860,264,say("选择室内活动","Choose an indoor activity"),23,c.model,"middle",650);arrow(b,678,132,746,160);
      const d=stage(root,4);browser(d,340,225,320,124,"NEXT TOOL",true);const call=text(d,359,292,say("查询场馆开放时间","museum_hours()"),24,"#b9e1d3");const result=text(d,359,326,'→ 09:00–17:00',21,"#afc5d9");path(d,"M857 284 V336 H678",c.output,2);arrow(d,735,336,678,336);
      const foot=text(d,695,410,say("结果重新进入上下文，再继续安排。","Return the result to context; continue planning."),23,c.output,"middle");
      root.studio={kind:"weather",set(rain){const choice=weekendChoice(rain);weather.textContent=say(`工具返回：${rain?"下雨":"晴天"}`,`Tool result: ${rain?"rain":"clear"}`);decision.textContent=say(rain?"选择室内活动":"选择公园散步",rain?"Choose an indoor activity":"Choose a park walk");call.textContent=say(rain?"查询场馆开放时间":"查询公园步行路线",choice.tool+'()');result.textContent='→ '+choice.result;foot.setAttribute('data-choice',choice.place);},reset(){this.set(true);}};return true;
    }
    if (is("workflow-vs-agent")) {
      const a=stage(root,1);head(a,25,30,1,say("会议处理：程序排好顺序","Meeting: a fixed sequence"));
      [say("音频","Audio"),say("转录","Transcript"),say("摘要","Summary")].forEach((label,i)=>{browser(a,30+i*172,112,147,130,label);text(a,103+i*172,193,["wave →","Aa →","• • •"][i],28,c.compute,"middle");if(i<2)arrow(a,181+i*172,177,195+i*172,177);});text(a,266,320,say("程序预先排好路径，也可以写分支。","Code predefines paths, including branches."),22,c.ink,"middle");
      const b=stage(root,2);path(b,"M550 15 V395",c.line,1);head(b,585,30,2,say("研究任务：读结果再选路","Research: choose after reading"));rect(b,740,80,200,60,"#eee7f8","#c5b5de",4);text(b,840,119,say("还缺什么？","What is missing?"),24,c.model,"middle");
      [[625,say("缺来源","Need a source"),say("搜索资料","Search")],[860,say("缺数值","Need a value"),say("运行计算","Compute")]].forEach(([x,label,tool],i)=>{arrow(b,840,150,x+90,226);text(b,i?1010:665,188,label,19,c.muted,"middle");browser(b,x,240,180,83,"TOOL");text(b,x+90,301,tool,22,c.compute,"middle");});text(b,835,377,say("模型提出下一步，程序负责执行。","Model proposes; software executes."),22,c.ink,"middle");return true;
    }
    if (is("three-improvement-loops")) {
      const columns=[{title:say("改这次结果","Revise this result"),file:"sort-prices.js",old:"prices.sort()",next:"sort((a,b)=>a-b)",detail:say("同一个模型，代码候选变了。","Same model, different code.")},{title:say("改助手的工作方式","Improve the assistant"),file:"harness",old:"read_file()",next:"read_file() + run()",detail:say("以后每次都能读到运行结果。","Later calls can see run results.")},{title:say("改模型参数","Train the model"),file:"weights",old:"w = 0.50",next:"w = 1.20",detail:say("训练算法更新参数。","Training updates parameters.")}];
      columns.forEach((col,i)=>{const g=stage(root,i+1),x=18+i*368;head(g,x,30,i+1,col.title);browser(g,x,72,330,261,col.file,true);text(g,x+18,150,col.old,i===0?23:25,"#d9bc85");arrow(g,x+165,174,x+165,225);rect(g,x+13,244,303,55,"#28524d","none",4);text(g,x+24,279,col.next,i===0?23:25,"#b7e2cd");text(g,x+165,385,col.detail,20,c.muted,"middle");});return true;
    }
    if (is("rsi-feedback")) {
      const rows=[{v:"v1",x:30,top:say("研究助手提出改法","Assistant proposes a change"),body:say("给搜索工具增加批量查询","Add batch search to its tools")},{v:"v2",x:395,top:say("改进后的助手","The improved assistant"),body:say("并行收集资料，提出下一次改法","Collect sources for the next change")},{v:"v3",x:760,top:say("继续改进方法","Improve the method again"),body:say("新方法再次用于改进过程","Use the new method to improve again")}];
      rows.forEach((row,i)=>{const g=stage(root,i+1);browser(g,row.x,70,310,220,say(`助手版本 ${row.v}`,`ASSISTANT VERSION ${row.v}`),true);text(g,row.x+155,156,row.v,52,"#c8b9eb","middle",700);text(g,row.x+155,218,row.top,20,"#d9e4ef","middle");text(g,row.x+155,331,row.body,19,c.muted,"middle");if(i)arrow(g,row.x-45,180,row.x-8,180);});
      const d=stage(root,4);path(d,"M1060 345 V390 H185 V345",c.output,3);text(d,625,383,say("反馈改变了“怎样做下一轮改进”。","Feedback changes how the next improvement is produced."),23,c.output,"middle");return true;
    }
    if (is("coding-agent-workflow")) {
      const xs=[155,550,960],names=say(["项目与要求","模型调用","编辑器 / 终端"],["Project / request","Model call","Editor / terminal"]);xs.forEach((x,i)=>{text(root,x,28,names[i],23,[c.data,c.model,c.compute][i],"middle",650);path(root,`M${x} 48 V402`,c.line,1);});
      const messages=[{step:1,y:87,a:0,b:1,line:say("需求 + sort-prices.js","Request + sort-prices.js")},{step:2,y:146,a:1,b:2,line:"edit → prices.sort()"},{step:3,y:205,a:2,b:1,line:"run → [100,20,3]"},{step:4,y:264,a:1,b:2,line:"edit → sort((a,b)=>a-b)"},{step:4,y:323,a:2,b:1,line:"run → [3,20,100]"}];
      messages.forEach(m=>{const g=stage(root,m.step),left=Math.min(xs[m.a],xs[m.b]),right=Math.max(xs[m.a],xs[m.b]),start=xs[m.a]+(m.a<m.b?10:-10),end=xs[m.b]+(m.a<m.b?-10:10);text(g,(left+right)/2,m.y-13,m.line,21,m.a===2?c.output:c.ink,"middle");arrow(g,start,m.y,end,m.y);path(g,`M${start} ${m.y} H${end}`,m.a===2?c.output:c.model,5,"none",{class:"lv-signal",pathLength:100});});const d=stage(root,4);rect(d,325,358,460,43,"#e4f2eb","none",4);text(d,555,387,say("返回结果，进入下一次模型调用。","Return results into the next model call."),22,c.output,"middle");return true;
    }
    if (is("multi-agent-handoffs")) {
      const a=stage(root,1);doc(a,15,95,225,235,say("对比三款产品","COMPARE 3 PRODUCTS"),[say("相同问题","Same questions"),say("容量、价格、续航","Capacity, price, battery")]);text(a,125,377,say("协调者分配任务","Coordinator assigns work"),20,c.model,"middle");
      const b=stage(root,2);const entries=[["A","128 GB","¥2,000","10 h"],["B","256 GB","¥2,500","8 h"],["C","256 GB","¥2,200","9 h"]];entries.forEach((row,i)=>{const y=14+i*136;browser(b,330,y,380,114,say(`工作者 ${row[0]} · 独立上下文`,`WORKER ${row[0]} · OWN CONTEXT`));text(b,347,y+66,say(`只看产品 ${row[0]} 的资料`,`Only product ${row[0]} sources`),19,c.muted);text(b,347,y+99,row.slice(1).join(" · "),23,c.compute);arrow(b,253,210,313,y+59);});
      const d=stage(root,3);browser(d,800,72,282,280,say("比较表","COMPARISON"));entries.forEach((row,i)=>{text(d,820,145+i*61,row[0],25,c.model,"start",700);text(d,855,145+i*61,row[1]+' · '+row[3],19);text(d,855,169+i*61,row[2],18,c.muted);});[0,1,2].forEach(i=>arrow(d,725,73+i*136,787,210));text(d,940,393,say("交换摘要，再整合。","Exchange summaries, then combine."),20,c.output,"middle");return true;
    }
    if (is("aggregate-throughput-batching")) {
      const a=stage(root,1);text(a,20,27,say("相同输入：A 2、B 4、C 1、D 3 个输出 Token；同时到达；2 个槽位。","Same work: A 2, B 4, C 1, D 3 output tokens; all ready; two slots."),23,c.ink,"start",600);
      const chart=stage(root,2),cells=[],cursors=[],counters=[];const schedules=[scheduling("fixed"),scheduling("continuous")];const colors={A:"#d2c4ec",B:"#badce7",C:"#f2d799",D:"#add8c4"};
      schedules.forEach((rounds,lane)=>{const y=75+lane*160;text(chart,20,y+30,say(lane?"连续批处理":"固定批次",lane?"Continuous":"Fixed batches"),24,c.ink,"start",650);text(chart,20,y+63,say(lane?"空位立即补入":"等整批结束",lane?"Refill free slots":"Wait for the whole batch"),18,c.muted);for(let i=0;i<7;i++){text(chart,245+i*88,y-9,String(i+1),17,c.muted,"middle");for(let slot=0;slot<2;slot++){const cell=rounds[i]?.[slot],x=209+i*88,cy=y+slot*48;const g=svg("g");chart.append(g);rect(g,x,cy,77,39,cell?colors[cell.id]:"#eef1f5",cell?"none":"#d7dfe8",3);text(g,x+38,cy+26,cell?`${cell.id}${cell.token}`:"—",23,cell?c.ink:"#b6c2d0","middle",600);cells.push({g,tick:i+1});}}cursors.push(rect(chart,204,y-4,87,91,"none",c.model,3,{"stroke-width":3,opacity:0}));counters.push(text(chart,898,y+38,"0 / 10",32,c.output,"start",650));text(chart,898,y+72,say("累计 Token","tokens so far"),18,c.muted);});
      const d=stage(root,3);text(d,20,414,say("同样 10 个 Token：固定批次 7 轮；连续批处理 6 轮。","Same ten tokens: fixed batches take seven rounds; continuous takes six."),24,c.output,"start",600);
      let tick=0;const paint=()=>{cells.forEach(({g,tick:t})=>g.setAttribute("opacity",t<=tick?1:.13));schedules.forEach((rounds,i)=>{cursors[i].setAttribute("x",204+(Math.max(1,Math.min(tick,rounds.length))-1)*88);cursors[i].setAttribute("opacity",tick?1:0);const count=rounds.slice(0,tick).flat().filter(Boolean).length;counters[i].textContent=`${count} / 10`;});root.studio?.onRound?.(tick);};
      root.studio={kind:"batching",next(){tick=Math.min(7,tick+1);paint();return tick;},stage(current){if(current===3)tick=7;paint();},progress(step,p){if(step===2){tick=Math.floor(7*p);paint();}},reset(){tick=0;paint();}};return true;
    }
    if (is("scientific-search-loop")) {
      const a=stage(root,1);text(a,20,28,say("候选材料：成分比例 × 预测性质","Candidate materials: composition × predicted property"),24,c.ink,"start",650);path(a,"M70 65 V330 H475",c.line,2);text(a,260,376,say("成分比例","Composition fraction"),22,c.muted,"middle");text(a,64,357,"0",17,c.muted);text(a,463,357,"1",17,c.muted);const points=[[.08,.25],[.15,.37],[.25,.32],[.35,.62],[.47,.54],[.56,.79],[.65,.71],[.74,.61],[.85,.36],[.94,.23]];points.forEach(([x,y],i)=>{circle(a,80+x*370,320-y*260,7,c.compute);text(a,80+x*370,301-y*260,String.fromCharCode(65+i),16,c.muted,"middle");});
      const b=stage(root,2);[5,6].forEach(i=>circle(b,80+points[i][0]*370,320-points[i][1]*260,17,"none",c.data));text(b,265,407,say("先研究 F、G","Investigate F and G first"),22,"#aa7f2a","middle");arrow(b,490,190,587,190);
      const d=stage(root,3);browser(d,610,80,455,226,say("计算 / 实验记录","COMPUTATION / EXPERIMENT"));[say("候选","Candidate"),say("预测","Predicted"),say("观察","Observed")].forEach((label,i)=>text(d,[631,785,945][i],155,label,20,[c.muted,c.compute,c.output][i]));[["F","0.79","0.58"],["G","0.71","0.76"]].forEach((row,j)=>row.forEach((cell,i)=>text(d,[631,785,945][i],210+j*52,cell,24,i===2?c.output:c.ink)));
      [0,.5,1].forEach(v=>text(a,58,326-v*260,String(v),16,c.muted,"end"));text(a,92,62,say("预测","Predicted"),17,c.compute);const out=stage(root,4);[.58,.76].forEach((observed,j)=>{const i=j+5,x=80+points[i][0]*370;path(out,`M${x} ${320-points[i][1]*260} V${320-observed*260}`,c.output,2);circle(out,x,320-observed*260,8,c.output);});text(out,310,62,say("观察","Observed"),17,c.output);path(out,"M830 322 V360 H510",c.output,3);text(out,800,405,say("新观察，改变下一轮选点。","New observations guide the next selection."),22,c.output,"middle");return true;
    }

    if (is("text-in-text-out")) {
      const examples = [
        { title: say("翻译", "Translate"), input: "会议改到周三。", output: "The meeting is moved\nto Wednesday." },
        { title: say("总结", "Summarize"), input: say("小李周四交稿，\n小王周五补图。", "Li: draft Thursday.\nWang: figures Friday."), output: say("初稿：小李 · 周四\n补图：小王 · 周五", "Draft: Li · Thursday\nFigures: Wang · Friday") },
        { title: say("编程", "Code"), input: say("价格从小到大\n[20, 100, 3]", "Sort prices\n[20, 100, 3]"), output: say("生成程序 → 运行\n[3, 20, 100]","Generate code → run\n[3, 20, 100]") },
      ];
      examples.forEach((example, i) => { const g = stage(root, i + 1), x = 20 + i * 365; head(g, x + 4, 28, i + 1, example.title); browser(g, x, 58, 340, 300, "INPUT → OUTPUT"); rect(g, x + 18, 112, 304, 92, "#fff4d9", "none", 5); text(g, x + 33, 143, example.input, 23); arrow(g, x + 170, 210, x + 170, 239); rect(g, x + 18, 248, 304, 88, "#e8f4ef", "none", 5); text(g, x + 33, 280, example.output, 21, c.output); }); return true;
    }
    if (is("complete-request-map")) {
      const a=stage(root,1);doc(a,15,30,215,175,say("任务","TASK"),[say("总结、编程、创作","Summarize, code, create")]);
      const b=stage(root,2);browser(b,325,32,330,175,"CONTEXT / HARNESS");text(b,345,107,say("资料 + 工具 + 循环","Material + tools + loop"),22);path(b,"M345 135 H604 M345 159 H575",c.line,4);arrow(b,245,115,309,115);
      const d=stage(root,3);model(d,820,55,195,120);arrow(d,670,115,799,115);
      const hw=stage(root,4);chip(hw,815,262,210,135);path(hw,"M929 207 V245",c.compute,2,"none",{"stroke-dasharray":"5 5"});text(hw,775,285,say("引擎与硬件","Engine / hardware"),18,c.compute,"end");text(hw,775,320,say("执行上方的计算","Execute the model above"),18,c.muted,"end");
      const out=stage(root,5);browser(out,28,265,570,130,"RESULT");text(out,50,340,say("初稿｜小李｜周四；补图｜小王｜周五","Draft | Li | Thu; figures | Wang | Fri"),25,c.output);arrow(out,799,175,670,175);text(out,733,211,say("返回表格","Return table"),18,c.output,"middle");arrow(out,490,218,490,250);return true;
    }
    if (is("model-application-compute", "request-through-factory", "platform-location")) {
      const early=is("model-application-compute");const a = stage(root, 1); browser(a, 35, 105, 270, 195, say("应用工作区", "APPLICATION")); rect(a, 55, 158, 230, 43, "#fff1d2"); text(a, 67, 185, say("任务与资料", "Task and material"), 21); text(a, 59, 235, say(early?"收集要求 · 显示结果":"编辑器 · 文档 · 工具", early?"Gather input · display output":"Editor · documents · tools"), 19, c.muted); path(a, "M58 252 h190 M58 269 h145", "#cbd5e1", 4); cardLabel(a, 170, 354, say(early?"你操作的应用":"应用 / Harness", early?"The app you use":"Application / harness"));
      if (is("platform-location")) {
        const b = stage(root, 2); rect(b, 400, 115, 300, 190, "#e3f2eb", "#62aa8e", 6); text(b, 550, 168, "LunaNexa", 36, c.output, "middle", 750); text(b, 550, 218, say("模型访问 · 服务路由", "Model access · routing"), 21, c.ink, "middle"); text(b, 550, 250, say("计算资源管理", "Compute resources"), 21, c.ink, "middle"); arrow(b, 320, 200, 382, 200);
        const d = stage(root, 3); rack(d, 830, 84, 135, 220, "GPU / KUBERNETES"); arrow(d, 718, 200, 807, 200); return true;
      }
      const b = stage(root, 2); model(b, 430, 124, 205, 140); cardLabel(b, 550, 354, say("模型", "Model"), say(early?"收到文字，生成后续":"参数 + 本次上下文",early?"Receive text, generate continuation":"Parameters + context")); arrow(b, 322, 200, 415, 200);
      const d = stage(root, 3); rack(d, 845, 78, 145, 238, say(early?"运行模型的机器":"推理引擎 / GPU",early?"Machine running the model":"ENGINE / GPU")); arrow(d, 704, 200, 823, 200); cardLabel(d, 920, 385, say("执行数字运算", "Execute arithmetic"));
      if (is("request-through-factory")) { const out = stage(root,4);path(out,"M920 326 V400 H170 V335",c.output,2);arrow(out,170,335,170,310); }
      return true;
    }
    if (is("token-pieces")) {
      const a = stage(root, 1); text(a, 50, 46, say("原始文字", "SOURCE TEXT"), 16, c.muted, "start", 650); text(a, 50, 118, "raincoat", 62, c.ink, "start", 600); path(a, "M52 142 H358", c.line, 2);
      ["rain", "coat"].forEach((part, i) => { const g = stage(root, i + 2), x = 460 + i * 285; rect(g, x, 68, 220, 80, i ? "#ece5f7" : "#fff0ce", "none", 6); text(g, x + 110, 120, part, 39, i ? c.model : "#996a15", "middle", 600); text(g, x + 110, 193, say("编号 ","ID ")+(i?"B":"A"), 22, c.muted, "middle"); });
      const d = stage(root, 4); [[-.2,.5,.1,-.4],[.7,-.1,.3,.2]].forEach((values,row) => { const x = 460 + row * 285;arrow(d,x+110,210,x+110,257);values.forEach((v,k)=>{rect(d,x+k*55,279,49,62,v<0?"#e5d2df":"#c8dde8","none",2);text(d,x+k*55+24,317,v.toFixed(1),18,c.ink,"middle");});});text(d, 720, 391, say("一串数值（向量）参与模型运算。", "A list of numbers (a vector) enters computation."), 23, c.model, "middle"); return true;
    }
    if (is("next-token-probabilities")) {
      const a = stage(root, 1); text(a, 34, 53, say("当前序列", "CURRENT SEQUENCE"), 16, c.muted, "start", 650); text(a, 34, 120, "The sky is", 44, c.ink, "start", 600); model(a, 80, 230, 200, 115); arrow(a, 190, 140, 190, 197);
      const b = stage(root, 2); head(b, 450, 45, 2, say("下一 Token 的分布", "Next-token distribution")); const bars=[], labels=[];
      ["blue", "gray", "dark"].forEach((name, i) => { const y = 85 + i * 77; text(b, 450, y + 29, say(name+["（蓝）","（灰）","（暗）"][i],name),23); rect(b, 585, y, 400, 42, "#edf0f7", "none", 3); bars.push(rect(b, 585, y, [.6, .3, .1][i] * 400, 42, [c.compute, c.model, c.data][i], "none", 3, { class: "lv-bar" })); labels.push(text(b, 1008, y + 29, ["60%", "30%", "10%"][i], 24)); }); arrow(b, 330, 260, 429, 187);
      const d = stage(root, 3); rect(d, 455, 331, 580, 65, "#e6f4ed", "none", 5); const selected=text(d, 478, 374, say("本次追加：blue", "Append this time: blue"), 28, c.output, "start", 650); let values=probabilities(1),sampled=null;
      root.studio={kind:"sampling", temperature(t){values=probabilities(t);sampled=null;bars.forEach((bar,i)=>bar.setAttribute("width",String(values[i]*400)));labels.forEach((label,i)=>{label.textContent=(values[i]*100).toFixed(1)+"%";});selected.textContent=say("待抽样：按当前概率选择","Ready: sample from current probabilities");}, sample(){const result=["blue","gray","dark"][choose(values,Math.random())];sampled=result;selected.textContent=say("本次追加：","Append this time: ")+result;return result;},stage(step){if(step===3&&!sampled)this.sample();},explain(step){if(step===2)return say(`当前候选被选中的比例：blue ${(values[0]*100).toFixed(1)}%、gray ${(values[1]*100).toFixed(1)}%、dark ${(values[2]*100).toFixed(1)}%；合计 100%（显示值经过四舍五入）。`,`Current selection probabilities: blue ${(values[0]*100).toFixed(1)}%, gray ${(values[1]*100).toFixed(1)}%, dark ${(values[2]*100).toFixed(1)}%; total 100% before rounding.`);if(step===3&&sampled)return say(`这次抽到 ${sampled}。抽样按当前概率进行；再抽一次可能不同。温度越低越集中，越高越分散。`,`This draw selected ${sampled}. Sampling uses the current probabilities; another draw can differ. Lower temperature concentrates them, higher temperature flattens them.`);return null;}}; return true;
    }
    if (is("autoregressive-feedback")) {
      const a=stage(root,1);text(a,50,48,say("已经生成的序列","SEQUENCE SO FAR"),16,c.muted,"start",650);["The","sky","is"].forEach((word,i)=>{rect(a,50+i*135,83,120,65,"#edf1f6");text(a,110+i*135,126,word,29,c.ink,"middle");});
      const b=stage(root,2);model(b,470,212,190,120);arrow(b,245,165,453,255);text(b,550,380,say("计算下一步","Compute the next step"),21,c.model,"middle");
      const d=stage(root,3);rect(d,850,230,160,70,"#e6f3ed");text(d,930,277,"blue",37,c.output,"middle",650);arrow(d,735,267,828,267);
      const e=stage(root,4);rect(e,455,83,150,65,"#dceee8");text(e,530,126,"blue",29,c.output,"middle");path(e,"M930 217 V45 H530 V72",c.output,3);path(e,"M930 217 V45 H530 V72",c.output,5,"none",{pathLength:100,class:"lv-signal"});text(e,785,28,say("追加，再算下一步","Append, then compute again"),21,c.output,"middle");return true;
    }
    if (is("attention-context")) {
      const a=stage(root,1);text(a,20,28,say("前文：我买了自行车。周末下雨，想骑它。","Context: I bought a bicycle. It may rain; I want to ride it."),23,c.ink,"start",600);text(a,20,64,say("模型把位置的信息写成数值列表；下面只取两组示意。","Positions have numerical representations; two toy value lists are shown."),20,c.muted);
      [[say("自行车的信息","Bicycle value"),"[1, 0]"],[say("天气的信息","Weather value"),"[0, 1]"]].forEach((row,i)=>{doc(a,25,100+i*150,280,123,row[0],[row[1]]);});
      const b=stage(root,2),weights=[.8,.2],weightLabels=[],bars=[];weights.forEach((w,i)=>{arrow(b,318,165+i*150,478,165+i*150);weightLabels.push(text(b,405,131+i*150,`${w*100}%`,32,c.model,"middle",700));rect(b,350,197+i*150,115,13,"#ede7f5","none",2);bars.push(rect(b,350,197+i*150,115*w,13,c.model,"none",2));});
      const d=stage(root,3);browser(d,505,100,570,270,say("先分别乘，再逐项相加","MULTIPLY EACH, THEN ADD ENTRIES"));const products=[text(d,525,176,"",25,c.model),text(d,525,228,"",25,c.compute)];path(d,"M525 249 H1053",c.line,1);const result=text(d,525,291,"",31,c.output,"start",650);text(d,525,337,say("加权后的信息 → 继续计算下一 Token","Combined values → next-token computation"),21,c.muted);
      const paint=p=>{const v=weightedMix(weights,[[1,0],[0,1]]);products[0].textContent=`${weights[0].toFixed(1)} × [1, 0] = [${weights[0].toFixed(1)}, 0]`;products[1].textContent=`${weights[1].toFixed(1)} × [0, 1] = [0, ${weights[1].toFixed(1)}]`;products[0].setAttribute("opacity",p<.12?.15:1);products[1].setAttribute("opacity",p<.4?.15:1);result.textContent=`[${v[0].toFixed(2)}, ${v[1].toFixed(2)}]`;result.setAttribute("opacity",p<.75?.15:1);weightLabels.forEach((t,i)=>{t.textContent=`${Math.round(weights[i]*100)}%`;bars[i].setAttribute("width",115*weights[i]);});};
      root.studio={kind:"attention",toggle(){weights.reverse();paint(1);},progress(step,p){if(step===3)paint(p);},reset(){weights[0]=.8;weights[1]=.2;paint(1);}};paint(1);return true;
    }
    if (is("training-update")) {
      const a=stage(root,1), left=72, top=60, width=530, height=285;path(a,`M${left} ${top} V${top+height} H${left+width}`,c.line,2);[1,2,3].forEach(x=>{text(a,left+x*145,top+height+31,String(x),18,c.muted,"middle");circle(a,left+x*145,top+height-2*x*40,7,c.data);text(a,left+x*145+12,top+height-2*x*40-12,`${x*2}`,20,c.data);});[0,2,4,6].forEach(y=>text(a,58,top+height-y*40+5,String(y),17,c.muted,"end"));text(a,72,29,say("总价 y（元）；黄点 = 已知目标","Total y; gold points = known targets"),21);text(a,450,409,say("件数 x","Quantity x"),22,c.muted);const fitted=path(a,"",c.model,5,"none",{class:"st-fit-line",pathLength:100});
      const b=stage(root,2);const residuals=[1,2,3].map(x=>path(b,`M${left+x*145} ${top+height-.5*x*40} V${top+height-2*x*40}`,c.red,2,"none",{"stroke-dasharray":"5 5","data-draw":"true"}));text(b,675,213,say("红线 = 预测与目标的差距","Red lines = prediction errors"),22,c.red);text(b,675,249,say("误差平方后取平均","Average the squared errors"),22,c.ink);const errorFormula=text(b,675,284,"(1.5² + 3² + 4.5²) ÷ 3",22,c.muted);const loss=text(b,675,324,say("平均平方误差 = ","MSE = ")+"10.50",26,c.ink);
      const weight=text(a,675,79,say("单价 w = ","Unit price w = ")+"0.50",35,c.model,"start",700);text(a,675,123,say("总价 = 件数 × 单价","Total = quantity × unit price"),24,c.muted);const predictions=text(a,675,165,"",22,c.model);let w=.5;
      const updateGroup=stage(root,3),updateText=text(updateGroup,675,382,"",24,c.model);let from=.5,updates=0;const paint=current=>{weight.textContent=say("单价 w = ","Unit price w = ")+current.toFixed(2);loss.textContent=say("平均平方误差 = ","MSE = ")+trainingStep(current).loss.toFixed(2);errorFormula.textContent="("+[1,2,3].map(x=>(2*x-current*x).toFixed(2)+"²").join(" + ")+") ÷ 3";predictions.textContent=say("预测：","Predictions: ")+[1,2,3].map(x=>(current*x).toFixed(2)).join(" / ");updateText.textContent=`${from.toFixed(2)} + ${(current-from).toFixed(2)} = ${current.toFixed(2)}`;fitted.setAttribute("d",`M${left} ${top+height} L${left+435} ${top+height-current*3*40}`);residuals.forEach((r,i)=>r.setAttribute("d",`M${left+(i+1)*145} ${top+height-current*(i+1)*40} V${top+height-2*(i+1)*40}`));};
      root.studio={kind:"training",train(){from=w;w=trainingStep(w).next;updates++;paint(w);},reset(){from=.5;w=.5;updates=0;paint(w);},stage(step){if(step===3&&w===.5)this.train();},progress(step,p){if(step===3)paint(from+(w-from)*p);},explain(step){return step===3&&updates>1?say(`继续调整单价：w = ${w.toFixed(2)}，平均平方误差约 ${trainingStep(w).loss.toFixed(2)}。`,`Continue adjusting unit price: w = ${w.toFixed(2)}, mean squared error ≈ ${trainingStep(w).loss.toFixed(2)}.`):null;}};root.studio.reset();return true;
    }
    if (is("training-vs-inference")) {
      [0,1].forEach(i=>{const g=stage(root,i+1),x=35+i*555;head(g,x,25,i+1,say(i?"推理：用学到的参数":"训练：参数会变化",i?"Inference: use learned weights":"Training: change weights"));doc(g,x+5,87,130,170,say("数据","DATA"),[say(i?"当前问题":"许多例子",i?"New input":"Examples")]);model(g,x+210,122,170,120);arrow(g,x+145,172,x+196,172);if(!i){path(g,`M${x+390} 260 V335 H${x+280} V282`,c.model,3);text(g,x+260,375,say("比较后回传，更新参数","Compare, feed back, update"),21,c.model,"middle");}else{arrow(g,x+414,180,x+470,180);text(g,x+465,245,say("结果","Output"),24,c.output,"middle");text(g,x+260,375,say("输入变，参数保持这一版本","New input, same model version"),21,c.output,"middle");}});return true;
    }
    if(is("meeting-workflow")){
      const a=stage(root,1);browser(a,20,72,245,237,say("会议录音","MEETING AUDIO"));waveform(a,40,185,205,80);text(a,40,275,"00:00 — 01:24",18,c.muted);
      const b=stage(root,2);doc(b,340,72,280,237,say("转录文字","TRANSCRIPT"),[say("小李周四交初稿。","Li: draft Thursday."),say("小王周五补图。","Wang: figures Friday."),say("下周一评审。","Review on Monday.")]);arrow(b,280,190,323,190);text(b,300,350,say("语音识别","Speech recognition"),20,c.compute,"middle");
      const d=stage(root,3);table(d,700,90,380,[[say("初稿","Draft"),say("小李","Li"),say("周四","Thu")],[say("补图","Figures"),say("小王","Wang"),say("周五","Fri")],[say("评审","Review"),say("未提及","Absent"),say("下周一","Mon")]]);arrow(d,635,190,683,190);text(d,852,291,say("语言模型提取字段","Language model extracts fields"),20,c.model,"middle");
      const out=stage(root,4);rect(out,700,331,380,58,"#e0efe8","none",4);text(out,890,367,say("日历 / 任务系统","Calendar / task system"),24,c.output,"middle",600);arrow(out,890,301,890,323);return true;
    }
    if (is("prompt-worked-output")) {
      const a=stage(root,1);if(is("meeting-workflow")){browser(a,25,86,290,220,say("会议录音","MEETING AUDIO"));waveform(a,45,195,250,88);text(a,45,276,"00:00 — 01:24",17,c.muted);}else doc(a,25,68,335,270,say("原始会议记录","MEETING NOTES"),[say("小李周四交初稿。","Li: draft Thursday."),say("小王周五补图。","Wang: figures Friday."),say("下周一评审。","Review on Monday.")],0);
      const b=stage(root,2);arrow(b,380,199,565,199);text(b,470,158,say(is("meeting-workflow")?"转录与整理":"提取字段",is("meeting-workflow")?"Transcribe + organize":"Extract fields"),21,c.model,"middle");table(b,590,93,480,[[say("初稿","Draft"),say("小李","Li"),say("周四","Thu")],[say("补图","Figures"),say("小王","Wang"),say("周五","Fri")],[say("评审","Review"),say("未提及","Unspecified"),say("下周一","Mon")]]);
      if(is("meeting-workflow")){const d=stage(root,3);text(d,618,328,say("决定与待办","Decisions and tasks"),25,c.output);const e=stage(root,4);rect(e,600,352,420,45,"#e6f3ed");text(e,620,382,say("日历 / 任务系统","Calendar / task system"),21,c.output);}return true;
    }
    if (is("context-tokens")) {
      const a=stage(root,1);head(a,25,30,1,say("输入 Token","Input tokens"));doc(a,25,78,225,235,say("应用指令","INSTRUCTIONS"),[say("总结这份材料","Summarize the text")]);doc(a,280,78,275,235,say("对话与附带文章","CONVERSATION + TEXT"),[say("之前的消息","Earlier messages"),say("附带的整篇文章","The attached article"),say("工具找到的段落","Retrieved passages")],1);
      const b=stage(root,2);head(b,765,30,2,say("输出 Token","Output tokens"));doc(b,765,78,300,235,say("生成的摘要","GENERATED SUMMARY"),[say("模型逐步写出","Generated step by step"),say("摘要、代码或回答","Summary, code or reply")]);arrow(b,579,191,742,191);text(b,545,381,say("当前输入 + 后续生成，使用上下文空间","Current input and generated continuation use context space"),25,c.ink,"middle");return true;
    }
    if (is("context-packet")) {
      const labels=[[say("任务说明","INSTRUCTIONS"),say("提取决定和待办","Extract decisions and tasks")],[say("相关对话","CONVERSATION"),say("使用姓名与明确日期","Use names and dates")],[say("文件与工具结果","FILES + TOOL RESULTS"),say("会议记录、术语表","Transcript and glossary")]];
      labels.forEach((row,i)=>{const g=stage(root,i+1);doc(g,25,15+i*133,400,115,row[0],[row[1]]);});
      const d=stage(root,4);[0,1,2].forEach(i=>arrow(d,444,72+i*133,625,205));browser(d,650,70,420,290,"MODEL INPUT");["#f8e7ba","#d5c9ed","#c8e1e7"].forEach((color,i)=>{rect(d,672,123+i*66,372,49,color,"none",4);text(d,690,155+i*66,labels[i][1],21);});text(d,860,390,say("为这一次调用组装","Assembled for this call"),25,c.model,"middle");return true;
    }
    if (is("rag-retrieval")) {
      const a=stage(root,1);doc(a,27,72,250,275,say("问题","QUESTION"),[say("报销最晚什么时候交？","Expense deadline?"),say("相关对话","Conversation")]);
      const b=stage(root,2);[2,1,0].forEach(i=>doc(b,368+i*9,64+i*9,270,270,say(is("rag-retrieval")?"公司文档":"相关资料",is("rag-retrieval")?"DOCUMENTS":"MATERIAL"),[say("报销制度 · 示例","Example expense policy"),say("次月 5 日前提交。","Submit by the 5th."),say("附带票据与说明。","Attach receipts." )],1));arrow(b,291,205,353,205);
      const d=stage(root,is("context-tokens")?2:3);rect(d,762,82,300,220,"#f0ecf9","#c2b4e2",6);text(d,780,120,say("本次上下文","CURRENT CONTEXT"),20,c.model,"start",650);text(d,780,164,say("任务说明","Instructions"),22);text(d,780,207,say("问题 + 相关片段","Question + passages"),22);text(d,780,250,say("送入模型","Sent to the model"),22,c.model);arrow(d,665,205,744,205);
      if(!is("context-tokens")){const out=stage(root,4);rect(out,365,365,690,43,"#e6f3ed");text(out,382,394,say("根据制度：请在次月 5 日前提交。","From the policy: submit by the fifth of next month."),22,c.output);}return true;
    }
    if (is("task-revision-loop","coding-example")) {
      browser(root,25,30,625,355,"sort-prices.js",true);const a=stage(root,1);text(a,47,109,"const prices = [20, 100, 3];",25,"#e2d6f4");text(a,47,164,"prices.sort();",25,"#f2d18b");text(a,47,203,say("// 默认按字符串顺序","// default: string order"),19,"#9cb0c8");
      const b=stage(root,2);rect(b,40,245,590,87,"#264b48","none",4);text(b,56,280,"prices.sort((a, b) => a - b);",24,"#a6e1c6");text(b,56,312,say("// 数值升序","// ascending numeric order"),18,"#9bc2b3");
      const result=sortExample();head(a,715,60,1,say("默认输出","Default result"));const ordinary=text(a,715,125,JSON.stringify(result.ordinary),31,c.red,"start",650);head(b,715,245,2,say("数值输出","Numeric result"));const numeric=text(b,715,310,JSON.stringify(result.numeric),31,c.output,"start",650);arrow(b,658,278,697,278);
      root.studio={kind:"code",run(){const r=sortExample();ordinary.textContent=JSON.stringify(r.ordinary);numeric.textContent=JSON.stringify(r.numeric);}};return true;
    }
    if (is("tool-roundtrip")) {
      const a=stage(root,1);text(a,25,29,say("应用提供的工具说明","APP-SUPPLIED TOOL DESCRIPTION"),19,c.muted);text(a,25,67,"weather(city, day)",22,c.model);arrow(a,145,78,145,98);model(a,30,145,200,130);cardLabel(a,150,353,say("模型","Model"));
      const b=stage(root,2);browser(b,350,38,385,160,"TOOL CALL",true);text(b,368,106,'weather({',24,"#d7c9f3");text(b,393,141,'city: "Hangzhou", day: "Sat"',20,"#f2d18f");text(b,368,175,'})',24,"#d7c9f3");arrow(b,250,200,335,130);
      const d=stage(root,3);rect(d,855,127,195,130,"#e9f2f7","#8db9c9",5);circle(d,918,178,22,"#bed7e0");circle(d,943,165,30,"#bed7e0");circle(d,969,180,21,"#bed7e0");path(d,"M915 216 l-7 14 M943 216 l-7 14 M971 216 l-7 14",c.compute,3);text(d,950,297,say("天气工具","Weather tool"),24,c.compute,"middle");arrow(d,751,131,839,185);
      const out=stage(root,4);browser(out,350,252,385,135,"TOOL RESULT",true);text(out,371,323,'{ "condition": "rain" }',23,"#a3dbc6");path(out,"M850 270 L755 313",c.output,2);arrow(out,333,315,250,256);return true;
    }
    if (is("gpu-compute-data")) {
      chip(root,360,95,380,245);const a=stage(root,1);text(a,55,75,say("显存：存放数字","DEVICE MEMORY"),22,c.compute,"start",650);path(a,"M210 85 H310 V145 H365",c.compute,2);text(a,55,120,say("模型权重与工作数据","Weights and working data"),20,c.muted);text(a,55,170,say("参数：[5, 4]","Weights: [5, 4]"),23,c.model);text(a,55,214,say("输入1：[2, 3]","Input 1: [2, 3]"),23,c.data);text(a,55,254,say("输入2：[1, 4]","Input 2: [1, 4]"),23,c.data);
      const b=stage(root,2);path(b,"M410 155 H485 M410 255 H485 M615 155 H690 M615 255 H690",c.data,5,"none",{class:"st-data-bus"});text(b,55,335,say("带宽：数据搬运速度","Bandwidth: moving data"),23,"#a8781c");path(b,"M280 327 H330 V255 H405",c.data,2);
      const d=stage(root,3);rect(d,492,169,116,99,"none","#c9f4e4",3,{"stroke-width":3});text(d,810,104,say("计算单元","COMPUTE UNITS"),22,c.model,"start",650);path(d,"M800 114 H770 V219 H620",c.model,2);text(d,810,149,say("大量相似运算同时进行","Many similar operations at once"),20,c.muted);const rowA=text(d,810,233,"2×5 + 3×4 = 22",23,c.model);const rowB=text(d,810,285,"1×5 + 4×4 = 21",23,c.compute);text(d,810,335,say("两行互不依赖，可以同时算。","Independent rows can run together."),17,c.muted);text(d,550,402,say("CPU：程序控制　GPU / TPU：加速大量计算","CPU: program control; GPU / TPU: accelerate many computations"),22,c.ink,"middle",650);root.studio={progress(step,p){if(step!==3)return;rowA.textContent="2×5 + 3×4 = "+(p>.65?String(2*5+3*4):"?");rowB.textContent="1×5 + 4×4 = "+(p>.65?String(1*5+4*4):"?");}};return true;
    }
    if (is("weight-memory-arithmetic")) {
      const a=stage(root,1);head(a,30,36,1,say("FP16：每个数 16 bit = 2 字节","FP16: 16 bits = 2 bytes per value"));text(a,30,112,"16",76,c.model,"start",750);text(a,135,110,"GB",30,c.muted);rect(a,30,145,650,65,c.model,"none",4,{class:"st-quantity"});text(a,35,249,say("80 亿个数 × 2 字节 = 160 亿字节","8 billion values × 2 bytes = 16 billion bytes"),24);
      const b=stage(root,2);head(b,30,300,2,"4 bit");rect(b,30,324,162.5,50,c.compute,"none",4,{class:"st-quantity"});text(b,220,362,"4 GB",40,c.compute,"start",700);
      const d=stage(root,3);path(d,"M745 30 V384",c.line,1);text(d,790,76,say("运行时还会使用","ALSO AT RUNTIME"),22,c.muted,"start",650);[say("KV 缓存","KV cache"),say("临时计算数据","Intermediate data"),say("运行时工作区","Runtime workspace")].forEach((label,i)=>{rect(d,790,120+i*77,248,50,["#e6eef7","#eee8f8","#e6f3ec"][i],"none",4);text(d,810,153+i*77,label,23);});return true;
    }
    if (is("factory-input-output")) {
      const a=stage(root,1);text(a,40,40,say(is("cluster-engine-path")?"Kubernetes：安排运行位置":"电力、散热、网络",is("cluster-engine-path")?"Kubernetes: place service instances":"Power, cooling, networking"),26,c.ink,"start",650);path(a,"M70 66 H1020",c.line,2);
      const b=stage(root,2);[0,1,2,3].forEach(i=>{rack(b,70+i*250,120,140,215,`NODE ${i+1}`);path(b,`M${140+i*250} 71 V105`,c.compute,2);});
      const d=stage(root,3);[0,1,2,3].forEach(i=>{rect(d,89+i*250,135,102,31,"#9584c9","none",2);text(d,140+i*250,157,is("factory-input-output")?"MODEL":"ENGINE",15,"#fff","middle",650);});
      const out=stage(root,4);path(out,"M140 367 V396 H890 V367",c.output,3);text(out,515,390,say("请求与生成结果，在服务之间流动","Requests and generated results flow through services"),23,c.output,"middle");return true;
    }
    if (is("parallel-vs-replicas")) {
      [0,1].forEach(i=>{const g=stage(root,i+1),x=35+i*555;head(g,x,28,i+1,say(i?"多副本":"模型并行",i?"Replicas":"Model parallelism"));chip(g,x+15,155,185,145);chip(g,x+300,155,185,145);if(!i){rect(g,x+45,113,125,35,"#b8a7dc");text(g,x+108,137,say("半份模型","½ MODEL"),17,c.model,"middle",650);rect(g,x+330,113,125,35,"#8f7dbb");text(g,x+393,137,say("半份模型","½ MODEL"),17,"#fff","middle",650);arrow(g,x+213,227,x+285,227);text(g,x+250,367,say("一个模型，设备间交换数据","One model, devices exchange data"),22,c.ink,"middle");}else{[0,1].forEach(k=>{text(g,x+105+k*285,71,say(`请求 ${"AB"[k]}`,`Request ${"AB"[k]}`),21,c.compute,"middle");arrow(g,x+105+k*285,80,x+105+k*285,101);rect(g,x+35+k*285,108,140,40,"#b7a7d9");text(g,x+105+k*285,136,say("完整模型","FULL MODEL"),19,c.model,"middle",650);});text(g,x+250,367,say("两份实例，各接一个请求","Two instances, separate requests"),22,c.ink,"middle");}});return true;
    }
    if (is("token-interval-arithmetic")) {
      const a=stage(root,1);text(a,28,28,say("先数 3 个 Token：只有 2 个间隔","First count three tokens: only two gaps"),24,c.ink,"start",650);[0,1,2].forEach(i=>{circle(a,90+i*220,81,17,i?c.compute:c.data);text(a,90+i*220,123,String(i+1),20,c.ink,"middle");if(i<2){path(a,`M${116+i*220} 81 h168`,c.line,2);text(a,200+i*220,65,"20 ms",21,c.muted,"middle");}});text(a,680,85,"20 ms = 0.020 s",28,c.model);
      for(let i=0;i<101;i++){rect(a,35+i*9.8,164,4,35,i?"#7faec0":c.data,"none",1);if(i<100)path(a,`M${40+i*9.8} 209 h4.8`,c.line,1);}text(a,40,252,say("101 个 Token → 100 个间隔","101 tokens → 100 gaps"),31,c.ink,"start",650);text(a,620,252,"100 × 0.020 s = 2 s",28,c.model);
      const b=stage(root,2);path(b,"M40 281 H1060",c.line,1);text(b,40,321,say("只算首个之后","After the first token only"),22,c.compute);text(b,40,377,"100 ÷ 2 = 50 Token/s",34,c.compute,"start",700);text(b,570,321,say("全程包括首个之前的 0.8 秒","Whole request, including 0.8 s initial wait"),21,c.output);text(b,570,377,"101 ÷ 2.8 ≈ 36 Token/s",32,c.output,"start",650);return true;
    }
    if (is("diffusion-steps")) {
      const a=stage(root,1);text(a,20,27,say("文字条件：街边咖啡店，绿色遮阳篷。","Text condition: a street-side café with a green awning."),23,c.model,"start",600);
      rect(a,20,90,210,210,"#dfe7eb","#c5d1df",4);for(let r=0;r<6;r++)for(let k=0;k<6;k++){const v=r===2&&k===2?153:((r*73+k*137+19)*41)%251;rect(a,23+k*34,93+r*34,32,32,`rgb(${v},${v},${v})`,r===2&&k===2?c.data:"none",1,{"stroke-width":3});}text(a,125,335,say("当前噪声状态","Current noisy state"),22,c.ink,"middle",600);
      text(a,125,365,say("黄框一格：0.60","Gold-outlined cell: 0.60"),19,c.muted,"middle");const b=stage(root,2);rect(b,350,117,210,151,"#e6dff3","#b9a8d9",5);text(b,455,153,say("训练好的模型","Trained model"),24,c.model,"middle",650);text(b,455,195,say("预测当前更新","Predict an update"),22,c.ink,"middle");text(b,455,238,say("示例：调整 −0.20","Toy update: −0.20"),20,c.model,"middle");text(b,455,306,say("训练：图像加噪 → 学更新","Train: add noise → learn updates"),18,c.muted,"middle");arrow(b,245,190,335,190);path(b,"M455 44 V100",c.model,2);text(b,585,75,say("当前第几步","Current step"),20,c.muted,"middle");path(b,"M585 82 L535 110",c.line,2);
      const d=stage(root,3);rect(d,650,106,170,170,"#dfe7eb","#c5d1df",4);let tracked;for(let r=0;r<6;r++)for(let k=0;k<6;k++){const square=rect(d,656+k*27,112+r*27,24,24,["#b2c9cf","#94b4bf","#dac7a8","#9ebdaa"][(r*3+k*5)%4],r===2&&k===2?c.data:"none",1,{"stroke-width":3});if(r===2&&k===2)tracked=square;}arrow(d,575,190,635,190);text(d,735,310,say("更新后的数值状态","Updated numerical state"),21,c.ink,"middle",600);const cell=text(d,735,345,"0.60 − 0.20 = 0.40",22,c.output,"middle");path(d,"M735 358 V397 H125 V378",c.output,2);text(d,420,389,say("新状态送回同一个模型，再做一步。","Feed the new state into the same model again."),21,c.output,"middle");
      const out=stage(root,4);arrow(out,835,190,895,190);text(out,865,140,say("解码","Decode"),20,c.compute,"middle");cafe(out,910,106,170,170);text(out,995,310,say("可显示的像素图像","Visible pixel image"),20,c.ink,"middle",600);text(out,995,345,say("多轮后再转换","Convert after iterations"),18,c.muted,"middle");root.studio={progress(step,p){if(step===3){cell.textContent=`0.60 − ${(p*.2).toFixed(2)} = ${(.6-p*.2).toFixed(2)}`;const v=Math.round((.6-p*.2)*255);tracked.setAttribute("fill",`rgb(${v},${v},${v})`);}}};root.studio.progress(3,1);return true;
    }
    if (is("creative-workflow")) {
      const a=stage(root,1);doc(a,20,65,220,270,say("15 秒文稿","15-SECOND SCRIPT"),[say("街边的咖啡店","A street-side café"),say("镜头慢慢推进","A slow camera move"),say("一句简短旁白","A short narration")]);
      const b=stage(root,2);[0,1,2].forEach(i=>{const x=290+i*200,picture=cafe(b,x,68,180,166);picture.setAttribute("viewBox",`${i*9} ${i*6} ${240-i*18} ${210-i*16}`);text(b,x+90,251,`00:${String(i*5).padStart(2,"0")}`,18,c.muted,"middle");});
      const d=stage(root,3);waveform(d,300,314,570,50,c.model);text(d,910,324,say("旁白","Narration"),22,c.model);
      const out=stage(root,4);rect(out,290,365,705,30,"#cadce6");path(out,"M305 355 V405 M620 355 V405 M985 355 V405",c.ink,2);text(out,1020,391,say("导出","Export"),21,c.output);return true;
    }
    if (is("industry-value-map")) {
      const a=stage(root,1);head(a,20,30,1,say("硬件与设施","Hardware / facilities"));chip(a,45,95,200,145);rack(a,62,282,135,95,"COMPUTE");
      const b=stage(root,2);head(b,420,30,2,say("模型与服务","Models / services"));model(b,455,90,200,120);arrow(b,260,165,428,165);
      const d=stage(root,3);browser(d,420,282,315,103,"ENGINES / TOOLS",true);text(d,440,351,"engine · API · harness",22,"#cbbde5");
      const out=stage(root,4);head(out,855,30,4,say("应用","Applications"));browser(out,825,128,255,194,"DOMAIN WORK");text(out,847,201,say("代码 · 内容 · 科研","Code · content · science"),18);text(out,847,250,say("连接到实际工作","Connect to real work"),20,c.output);arrow(out,738,169,810,169);arrow(out,752,330,812,291);return true;
    }
    if (is("api-vs-selfhosting")) {
      [0,1].forEach(i=>{const g=stage(root,i+1),y=35+i*200;head(g,25,y+22,i+1,say(i?"自行运行":"调用模型 API",i?"Operate the model":"Call a model API"));browser(g,30,y+48,210,115,"APPLICATION");text(g,46,y+119,say("发送请求","Send request"),22);arrow(g,256,y+105,403,y+105);if(i){rect(g,425,y+53,300,103,"#e5edf6","#9aafc4",4);text(g,448,y+93,"Engine + weights",25,c.compute);text(g,448,y+127,say("自己的服务","Your model service"),20,c.muted);}else{rect(g,425,y+53,300,103,"#ece6f7","#bdafdc",4);text(g,448,y+93,"Model API",27,c.model);text(g,448,y+127,say("服务方运行模型","Provider operates the model"),20,c.muted);}arrow(g,742,y+105,864,y+105);chip(g,890,y+48,170,115);});return true;
    }
    if (is("protein-structure")) {
      const a=stage(root,1);text(a,25,50,say("氨基酸序列","AMINO-ACID SEQUENCE"),18,c.muted,"start",650);["M","A","K","L","V","F"].forEach((letter,i)=>{rect(a,25+i*61,94,49,62,["#e5d9f5","#f4e4be","#d7e9e5"][i%3],"none",5);text(a,49+i*61,136,letter,29,c.ink,"middle",650);});
      const b=stage(root,2);text(b,210,266,"AlphaFold",35,c.model,"middle",650);arrow(b,400,215,523,215);
      const d=stage(root,3),points=[];for(let i=0;i<180;i++){const t=i/179*Math.PI*5;const x=785+Math.cos(t)*(132-45*Math.sin(t*.4))+Math.sin(t*.5)*45;const y=202+Math.sin(t)*96+Math.cos(t*.5)*38;points.push(`${i?'L':'M'}${x.toFixed(1)} ${y.toFixed(1)}`);}path(d,points.join(' '),c.model,8,"none",{class:"st-protein",pathLength:100});text(d,790,358,say("同一条链，在空间中排列","The same chain, arranged in space"),24,c.ink,"middle",600);text(d,790,396,say("曲线示意形状；不是折叠过程动画。","A shape illustration, not a folding simulation."),20,c.muted,"middle");return true;
    }
    // The remaining comparison, interval and flow diagrams use the shared renderer.
    root.classList.remove("studio-svg"); return false;
  }

  function controls(diagram, locale, advance, before=()=>{}) {
    const study=diagram.studio;if(!study?.kind)return null;const en=locale==="en",root=document.createElement("span");root.className="studio-controls";
    const button=(label,run)=>{const b=document.createElement("button");b.type="button";b.textContent=label;b.addEventListener("click",()=>{before();run();});root.append(b);};
    if(study.kind==="sampling"){
      const label=document.createElement("label");label.textContent=en?"Temperature ":"温度 ";const input=document.createElement("input");input.type="range";input.min="0.5";input.max="2";input.step="0.1";input.value="1";input.setAttribute("aria-label",en?"Temperature":"温度");const number=document.createElement("output");number.textContent="1.0";input.addEventListener("input",()=>{before();number.textContent=Number(input.value).toFixed(1);study.temperature(Number(input.value));advance(2);});label.append(input,number);root.append(label);button(en?"Sample a token":"抽样一个 Token",()=>{study.sample();advance(3);});root.reset=()=>{input.value="1";number.textContent="1.0";study.temperature(1);};
    }else if(study.kind==="training"){button(en?"Train one more step":"再训练一步",()=>{study.train();advance(3);});root.reset=()=>study.reset();}
    else if(study.kind==="code"){button(en?"Run the example":"运行这段示例",()=>{study.run();advance(2);});}
    else if(study.kind==="attention"){button(en?"Swap the weights":"交换权重",()=>{study.toggle();advance(3);});root.reset=()=>study.reset();}
    else if(study.kind==="weather"){
      const label=document.createElement("label");label.textContent=en?"Tool result ":"工具结果 ";const select=document.createElement("select");select.setAttribute("aria-label",en?"Weather result":"天气结果");[["rain",en?"Rain":"下雨"],["clear",en?"Clear":"晴天"]].forEach(([v,t])=>{const o=document.createElement("option");o.value=v;o.textContent=t;select.append(o);});select.addEventListener("change",()=>{before();study.set(select.value==="rain");advance(4);});label.append(select);root.append(label);root.reset=()=>{select.value="rain";study.reset();};
    }else if(study.kind==="batching"){
      const count=document.createElement("output");count.setAttribute("aria-live","polite");study.onRound=tick=>{count.textContent=en?`Round ${tick} / 7`:`第 ${tick} / 7 轮`;};study.onRound(0);button(en?"Compute one round":"计算一轮",()=>{const tick=study.next();advance(tick>=7?3:2);});root.append(count);root.reset=()=>study.reset();
    }
    return root;
  }
  const api={render,controls,probabilities,choose,trainingStep,sortExample,scheduling,weekendChoice,weightedMix};if(typeof module!=="undefined"&&module.exports)module.exports=api;else window.LunaStudio=api;
})();
