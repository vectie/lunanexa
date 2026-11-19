/* Worked board examples. Animation changes the actual quantities shown. */
(() => {
  "use strict";
  const neuron = (x = 2) => { const sum = x * .5 + .2; return { sum, output: Math.max(0, sum) }; };
  const probabilityLoss = p => -Math.log(p);
  const advantages = rewards => { const baseline = rewards.reduce((a,b)=>a+b,0)/rewards.length; return { baseline, values: rewards.map(r=>r-baseline) }; };
  const allocation = n => { const d = 16/n; return { n,d,loss:n**-.5+d**-.5 }; };
  const route = scores => { const selected = scores.map((s,i)=>({s,i})).sort((a,b)=>b.s-a.s).slice(0,2); const sum=selected.reduce((a,b)=>a+b.s,0); const weights=scores.map((s,i)=>selected.some(v=>v.i===i)?s/sum:0); return { selected:selected.map(v=>v.i),weights,output:weights.reduce((s,w,i)=>s+w*[2,9,4,7][i],0) }; };
  const quantize = (values,step) => values.map(value=>{const raw=Math.round(value/step),code=Math.max(-8,Math.min(7,raw)),restored=code*step;return {value,raw,code,restored,error:Math.abs(restored-value),clipped:raw!==code};});
  function render(root, visual, locale, h) {
    if(visual.type!=="board")return false;
    const {svg,svgText,stage,arrow,pick}=h,en=locale==="en",say=(zh,english)=>en?english:zh;
    const c={ink:"#172945",muted:"#64748b",line:"#cbd5e1",purple:"#7965c7",teal:"#26947e",blue:"#338ea7",red:"#c86b67"};
    const text=(p,x,y,s,size=24,fill=c.ink,anchor="start")=>{const node=svgText(p,x,y,s,size,anchor);node.setAttribute("fill",fill);return node;};
    const rect=(p,x,y,w,height,fill="#fff",stroke=c.line)=>{const node=svg("rect",{x,y,width:w,height,rx:8,fill,stroke});p.append(node);return node;};
    const line=(p,x1,y1,x2,y2,color=c.line,width=2)=>{const node=svg("line",{x1,y1,x2,y2,stroke:color,"stroke-width":width});p.append(node);return node;};
    const card=(p,x,y,w,title,detail,color=c.blue)=>{rect(p,x,y,w,112,"#fff",color);text(p,x+18,y+38,title,25,color);text(p,x+18,y+80,detail,23);};
    let current=1,progress=1,input=2,n=4,token="A",step=.25;
    const layers=[stage(root,1),stage(root,2),stage(root,3),stage(root,4)];
    const clear=()=>layers.forEach(g=>g.replaceChildren());
    const fmt=(v,d=3)=>Number(v.toFixed(d)).toString();
    function draw(){
      clear();const [a,b,d,e]=layers,key=visual.diagram;
      if(key==="neuron"){
        card(a,30,50,235,say("输入 x₁","Input x₁"),`${input} × 0.5`,c.purple);card(a,30,235,235,say("输入 x₂","Input x₂"),"1 × 0.2",c.purple);
        arrow(b,275,108,420,190);arrow(b,275,290,420,230);
        const v=neuron(input),p=current===2?progress:1;
        card(b,435,150,265,say("加权和 + 偏置","Sum + bias"),`${fmt(v.sum*p)} + 0`,c.blue);
        arrow(d,710,205,790,205);card(d,800,150,265,"ReLU",`max(0, ${fmt(v.sum)})`,c.teal);
        text(d,820,330,`${say("输出","Output")} = ${fmt(v.output)}`,30,c.teal);
      }else if(key==="probability"){
        text(a,35,48,say("前文：离离 → 真实后续：原","Prefix: 离离 → observed next: 原"),28);
        const p=current===3?progress:0,values=[.6-.4*p,.1,.2+.4*p,.1];
        ["草","上","原","木"].forEach((s,i)=>{const y=95+i*65;text(b,50,y+28,s,28);rect(b,120,y,580*values[i],35,i===2?c.teal:c.purple,"none");text(b,735,y+27,`${fmt(values[i]*100,0)}%`,24);text(b,885,y+27,`target = ${i===2?1:0}`,23,i===2?c.teal:c.muted);});
        text(d,55,395,`−ln(${fmt(values[2])}) = ${probabilityLoss(values[2]).toFixed(3)}`,30,c.teal);text(d,570,395,say("目标概率 ↑，损失 ↓","Target probability ↑, loss ↓"),24);
      }else if(key==="reward"){
        text(a,35,42,say("要求：保留“周四交初稿”","Requirement: retain “draft due Thursday”"),27);
        card(a,35,85,485,say("回答 A：周四交初稿","A: Draft due Thursday"),say("包含日期","Date included"),c.teal);card(a,575,85,485,say("回答 B：交初稿","B: Submit a draft"),say("遗漏日期","Date omitted"),c.red);
        text(b,65,250,"reward = 1",29,c.teal);text(b,605,250,"reward = 0",29,c.red);
        const v=advantages([1,0]),p=current===3?progress:1;
        text(d,65,305,`1 − ${fmt(v.baseline*p)} = +${fmt(1-v.baseline*p)}`,28,c.teal);text(d,605,305,`0 − ${fmt(v.baseline*p)} = −${fmt(v.baseline*p)}`,28,c.red);
        text(e,65,377,say("正优势：鼓励该行为","Positive advantage: favor behavior"),23,c.teal);text(e,605,377,say("负优势：反向学习信号","Negative: opposite learning signal"),23,c.red);
      }else if(key==="scaling"){
        text(a,35,45,say("同一个示意预算：N × D = 16","Same illustrative budget: N × D = 16"),28);
        const v=allocation(n);card(b,35,85,280,`N = ${n}`,say("相对模型规模","Relative model size"),c.purple);card(b,35,235,280,`D = ${fmt(v.d)}`,say("相对数据量","Relative data size"),c.blue);
        line(d,420,330,1040,330);line(d,420,330,420,85);text(d,430,78,say("玩具损失（越低越好）","Toy loss (lower is better)"),23);
        const ns=[1,2,4,8,16],x=i=>465+i*135,y=value=>330-(value-.9)*400;
        ns.forEach((value,i)=>{const l=allocation(value).loss; if(i)line(d,x(i-1),y(allocation(ns[i-1]).loss),x(i),y(l),c.line,3);rect(d,x(i)-6,y(l)-6,12,12,value===n?c.teal:c.purple,"none");text(d,x(i),365,String(value),22,c.ink,"middle");});
        text(d,600,405,`N = ${n}  ·  loss = ${v.loss.toFixed(3)}`,25,c.teal);
      }else if(key==="interconnect"){
        [0,1,2,3].forEach(i=>{card(a,20+i*275,55,245,`GPU ${i+1}`,`${say("权重分片","Weight shard")} ${i+1}`,c.purple);text(a,35+i*275,195,"4 GB",24,c.muted);if(i<3)line(b,135+i*275,232,410+i*275,232,c.blue,4);line(b,135+i*275,170,135+i*275,232,c.blue,3);});
        text(b,35,295,say("互联传递中间状态；显存仍分属各张卡","Links move states; memory remains distributed"),25);
        arrow(d,960,235,960,340);text(d,805,385,say("模型输出","Model output"),28,c.teal);
      }else if(key==="moe"){
        const scores=token==="A"?[.5,.2,.25,.05]:[.05,.45,.1,.4],r=route(scores),p=current===3?progress:1;
        text(a,30,42,`Token ${token}`,29,c.purple);text(a,340,42,say("同一个模型内的四个专家","Four experts within one model"),25);
        [0,1,2,3].forEach(i=>{const selected=r.selected.includes(i),x=25+i*275;card(a,x,150,240,`${say("专家","Expert")} ${i+1}`,say("参数保留在模型中","Parameters retained"),c.purple);text(b,x+12,115,`score ${scores[i]}`,24);if(selected){rect(d,x,145,240,123,"none",c.teal);text(d,x+10,310,`${fmt(r.weights[i]*p)} × ${[2,9,4,7][i]}`,27,c.teal);}});
        text(d,40,388,`${say("加权结果","Weighted output")} = ${fmt(r.output*p)}`,29,c.teal);text(e,700,388,say("下一片段 → 重新路由","Next token → route again"),23,c.blue);
      }else if(key==="quantization"){
        const values=quantize([1.23,-.78,.41],step),columns=[40,290,565,855];
        [say("原值","Original"),say("除步长、取整","Divide, round"),say("4 位码 −8…7","4-bit code −8…7"),say("重建 / 误差","Restored / error")].forEach((s,i)=>text(i===0?a:i===3?d:b,columns[i],60,s,23));
        values.forEach((v,i)=>{const y=135+i*85;text(a,columns[0],y,String(v.value),31);text(b,columns[1],y,`${fmt(v.value/step)} → ${v.raw}`,25);text(b,columns[2],y,`${v.code}${v.clipped?say("（截断）"," (clip)"):""}`,25,v.clipped?c.red:c.purple);const p=current===3?progress:1;const restored=v.value+(v.restored-v.value)*p;text(d,columns[3],y,`${fmt(restored)} / ${fmt(Math.abs(restored-v.value))}`,25,c.teal);});
        text(a,40,405,`${say("步长","Step")} = ${step}`,25,c.blue);text(d,420,405,say("重建 = 整数码 × 步长","Restored = code × step"),25);
      }else if(key==="evaluation"){
        const rows=[[say("抽取日期","Extract date"),say("与原文日期相同","Matches source date"),"✓"],[say("修复排序","Fix sorting"),say("通过数字排序用例","Passes numeric sort cases"),"×"],[say("检索制度","Retrieve policy"),say("引用对应段落","Cites matching passage"),"✓"]];
        rows.forEach((row,i)=>{const y=45+i*103;text(a,30,y+35,row[0],26);text(a,255,y+35,row[1],23);arrow(b,640,y+26,785,y+26);text(b,800,y+35,say("运行","Run"),24);text(d,1000,y+35,row[2],36,i===1?c.red:c.teal);});
        text(d,45,395,say("合成样例：2 / 3 完成；保留失败项、时间与用量","Synthetic: 2 / 3 complete; keep failures, time and usage"),25,c.teal);
      }else if(key==="pairing"){
        text(a,40,45,say("固定任务与评分条件，逐个改变因素","Keep task and scoring fixed; vary one factor"),26);
        const cells=[[40,105,"A + X",1],[590,105,"A + Y",2],[40,270,"B + X",3]];
        cells.forEach(([x,y,label,number])=>{const parent=layers[number-1];card(parent,x,y,450,label,say("框架 + 模型","Harness + model"),number===1?c.purple:c.blue);});
        arrow(b,500,160,580,160);text(b,600,250,say("只换模型 X → Y","Change only model X → Y"),23,c.blue);
        text(d,590,340,say("只换框架 A → B","Change only harness A → B"),25,c.blue);
      }
    }
    function explain(value){
      if(visual.diagram==="neuron"&&value>=2){const v=neuron(input);return say(`${input}×0.5 + 1×0.2 = ${fmt(v.sum)}；ReLU 取 max(0, ${fmt(v.sum)}) = ${fmt(v.output)}。`,`${input}×0.5 + 1×0.2 = ${fmt(v.sum)}; ReLU gives max(0, ${fmt(v.sum)}) = ${fmt(v.output)}.`);}
      if(visual.diagram==="scaling"&&value===3){const v=allocation(n);return say(`当前 N=${n}、D=${fmt(v.d)}，预算 N×D=16，玩具损失=${v.loss.toFixed(3)}。比较不同分配；这不是实际模型测量。`,`N=${n}, D=${fmt(v.d)}, N×D=16, toy loss=${v.loss.toFixed(3)}. Compare allocations; these are not model measurements.`);}
      if(visual.diagram==="moe"&&value>=3){const r=route(token==="A"?[.5,.2,.25,.05]:[.05,.45,.1,.4]);return say(`Token ${token} 选择专家 ${r.selected.map(i=>i+1).join('、')}；归一化权重组合后得到 ${fmt(r.output)}。切换 Token，比较路线与结果。`,`Token ${token} selects experts ${r.selected.map(i=>i+1).join(', ')}; normalized mixing gives ${fmt(r.output)}. Switch tokens to compare routes.`);}
      if(visual.diagram==="quantization"&&value===3){const v=quantize([1.23,-.78,.41],step);return say(`步长 ${step}：重建 [${v.map(x=>fmt(x.restored)).join(', ')}]，绝对误差 [${v.map(x=>fmt(x.error)).join(', ')}]。${v.some(x=>x.clipped)?'注意超过 4 位范围的数发生截断。':'本次没有超出 4 位编码范围。'}`,`Step ${step}: restored [${v.map(x=>fmt(x.restored)).join(', ')}], absolute errors [${v.map(x=>fmt(x.error)).join(', ')}]. ${v.some(x=>x.clipped)?'Out-of-range values clip.':'No codes clip in this case.'}`);}
      return pick(visual.beats[value-1],locale);
    }
    root.studio={kind:`board-${visual.diagram}`,stage(value){current=value;progress=1;draw();},progress(value,p){current=value;progress=p;draw();},explain,set(key,value){if(key==="input")input=Number(value);if(key==="n")n=Number(value);if(key==="token")token=value;if(key==="step")step=Number(value);draw();},reset(){input=2;n=4;token="A";step=.25;draw();}};
    draw();return true;
  }
  function controls(diagram,locale,onChange,onBeforeChange){
    if(!diagram.studio?.kind?.startsWith("board-"))return null;
    const key=diagram.studio.kind.slice(6),en=locale==="en",configs={neuron:["input",en?"First input":"第一个输入",[-2,-1,0,1,2],2,3],scaling:["n",en?"Model size N":"模型规模 N",[1,2,4,8,16],4,3],moe:["token","Token",["A","B"],"A",4],quantization:["step",en?"Step":"步长",[.125,.25,.5],.25,3]};
    const config=configs[key];if(!config)return null;
    const [name,title,values,initial,stage]=config,label=document.createElement("label"),select=document.createElement("select");label.className="board-control";label.append(document.createTextNode(title+" "));select.setAttribute("aria-label",title);
    values.forEach(value=>{const option=document.createElement("option");option.value=String(value);option.textContent=String(value);select.append(option);});select.value=String(initial);label.append(select);
    select.addEventListener("change",()=>{onBeforeChange();diagram.studio.set(name,select.value);onChange(stage);});label.reset=()=>{select.value=String(initial);diagram.studio.reset();};return label;
  }
  const api={render,controls,neuron,probabilityLoss,advantages,allocation,route,quantize};
  if(typeof window!=="undefined")window.LunaWhiteboard=api;
  if(typeof module!=="undefined")module.exports=api;
})();
