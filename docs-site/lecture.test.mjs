import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import test from "node:test";
const require = createRequire(import.meta.url);
const { flatten, pick, pointAlong, indexItems } = require("./lecture.js");
const { probabilities, choose, trainingStep, sortExample, scheduling, weekendChoice, weightedMix } = require("./lecture-studio.js");
const data = JSON.parse(await readFile(new URL("./ai-lecture.json", import.meta.url), "utf8"));
const book = JSON.parse(await readFile(new URL("./coursebook.json", import.meta.url), "utf8"));
const board = require("./whiteboard-studio.js");

test("board worked examples preserve their mathematics and reveal clipping",()=>{
  assert.deepEqual(board.neuron(2),{sum:1.2,output:1.2});assert.equal(board.neuron(-2).output,0);
  assert.ok(Math.abs(board.probabilityLoss(.2)-1.609437912)<1e-8);assert.ok(board.probabilityLoss(.6)<board.probabilityLoss(.2));
  assert.deepEqual(board.advantages([1,0]),{baseline:.5,values:[.5,-.5]});
  assert.equal(board.allocation(4).loss,1);assert.ok(board.allocation(16).loss>board.allocation(4).loss);assert.equal(board.allocation(8).d,2);
  const a=board.route([.5,.2,.25,.05]),b=board.route([.05,.45,.1,.4]);assert.deepEqual(a.selected,[0,2]);assert.deepEqual(b.selected,[1,3]);assert.ok(Math.abs(a.output-8/3)<1e-9);assert.ok(Math.abs(a.weights.reduce((x,y)=>x+y)-1)<1e-9);
  assert.deepEqual(board.quantize([1.23,-.78,.41],.25).map(v=>v.code),[5,-3,2]);const clipped=board.quantize([1.23],.125)[0];assert.equal(clipped.code,7);assert.equal(clipped.clipped,true);assert.equal(clipped.restored,.875);
});

test("all source points are primary content in normal chapters and the main presentation",async()=>{
  const coverage=JSON.parse(await readFile(new URL("../docs/ai-whiteboard-coverage.json",import.meta.url),"utf8")),zh=JSON.parse(await readFile(new URL("./coursebook.zh-CN.json",import.meta.url),"utf8"));
  const groups=book.pages.find(p=>p.id==="ai-course-map").blocks[0].groups,items=indexItems(groups),frames=flatten(data).filter(f=>f.visual);
  assert.equal(items.length,60);assert.equal(coverage.mapped_points,186);assert.equal(coverage.sections,47);assert.equal(coverage.integration,"primary-curriculum");assert.deepEqual(coverage.images.map(i=>i.download_rank),[7,6,5,4,3,2,1]);
  assert.ok(!book.pages.some(page=>page.id.startsWith("ai-board-")));assert.ok(!book.navigation.some(group=>group.id==="ai-board-notes"));
  assert.equal(data.curriculum.primary_minutes,78);assert.equal(data.curriculum.support_minutes,27);
  for(const point of coverage.points){const page=book.pages.find(p=>p.id===point.page_id),localized=zh.pages[point.page_id];for(const projection of [page,localized])assert.ok(projection.blocks.some(block=>block.kind==="heading"&&block.id===point.anchor),point.id);assert.ok(items.some(item=>item.id===point.section_id&&item.slide_id===point.slide_id));const frame=frames.find(frame=>frame.id===point.slide_id);assert.ok(frame?.source_sections.includes(point.section_id),point.id);assert.ok(frame.primary_notes.zh.length>0);}
  for(const lesson of data.lessons)for(const section of lesson.sections.filter(s=>s.primary)){const frame=lesson.slides.find(f=>f.id===section.slide_id);for(const paragraph of section.paragraphs){assert.ok(frame.primary_notes.zh.includes(paragraph[0]),section.id);assert.ok(frame.primary_notes.en.includes(paragraph[1]),section.id);}}
  for(const term of ["MoE","量化","Advantage","FP16","NPC","Mid-training","NVLink"]){assert.ok(indexItems(groups,term).length>0,term);}
  for(const reading of coverage.uncertain_readings)assert.ok(items.some(item=>item.id===reading.concept_id),reading.id);
  assert.equal(new Set(items.map(i=>i.id)).size,items.length);
});

test("the complete class has one 120-minute route with the break at minute 50", () => {
  const frames = flatten(data);
  assert.equal(data.lessons.length, 24);
  assert.equal(frames.length, 48);
  assert.equal(new Set(frames.map(f => f.id)).size, frames.length);
  assert.equal(frames.reduce((sum, f) => sum + f.minutes, 0), 120);
  const breakIndex = frames.findIndex(f => f.kind === "break");
  assert.equal(frames.slice(0, breakIndex).reduce((sum, f) => sum + f.minutes, 0), 50);
  assert.equal(frames.at(-1).kind, "questions");
  assert.equal(frames.at(-1).minutes, 5);
  for (const frame of frames) {
    assert.ok(frame.minutes > 0);
    assert.ok(book.pages.some(p => p.id === frame.page_id));
    for (const locale of ["en", "zh-CN"]) {
      assert.ok(pick(frame.title, locale));
      assert.ok(pick(frame.lead, locale));
      assert.ok(frame.notes[locale === "en" ? "en" : "zh"].length > 0);
    }
  }
});

test("each content slide has an explained visual and finite, named animation stages", () => {
  const allowed = new Set(["flow", "compare", "tokens", "prediction", "graph", "timeline", "lanes", "batch", "diffusion", "protein", "code", "weights", "board"]);
  for (const frame of flatten(data).filter(f => f.visual)) {
    const visual = frame.visual;
    assert.ok(allowed.has(visual.type), frame.id);
    assert.ok(visual.steps.length >= 2 && visual.steps.length <= 8, frame.id);
    assert.ok(pick(visual.caption, "zh-CN"));
    assert.ok(pick(visual.caption, "en"));
    for (const step of visual.steps) { assert.ok(pick(step, "en")); assert.ok(pick(step, "zh-CN")); }
    if (visual.type === "graph") {
      const ids = new Set(visual.nodes.map(n => n.id));
      assert.equal(ids.size, visual.nodes.length);
      for (const edge of visual.edges) { assert.ok(ids.has(edge.from), frame.id); assert.ok(ids.has(edge.to), frame.id); }
      for (const node of visual.nodes) {
        assert.ok(node.x >= 0 && node.y >= 0 && node.x + node.w <= 1100 && node.y + node.h <= 420, frame.id);
        assert.ok(node.step <= visual.steps.length, frame.id);
      }
    }
    assert.doesNotMatch(JSON.stringify([frame.title, frame.lead, frame.key, frame.visual]), /hardening|生产就绪|风险清单|免责声明|验收|权限/i, frame.id);
  }
});

test("teaching arithmetic and runnable code examples agree with their outputs", () => {
  assert.deepEqual([20, 100, 3].sort(), [100, 20, 3]);
  assert.deepEqual([20, 100, 3].sort((a, b) => a - b), [3, 20, 100]);
  assert.equal(8e9 * 16 / 8 / 1e9, 16);
  assert.equal(8e9 * 4 / 8 / 1e9, 4);
  assert.equal((101 - 1) * 0.020, 2);
  assert.equal(20 * 100 / 10, 200);
  const parallel = flatten(data).find(f => f.id === "parallel-time").visual;
  for (const row of parallel.rows) assert.equal(row.parts.reduce((sum, p) => sum + p.value, 0), row.value);
});

test("classroom experiments compute changed results rather than swapping static labels", () => {
  const original = probabilities(1);
  original.forEach((p, i) => assert.ok(Math.abs(p - [.6, .3, .1][i]) < 1e-12));
  assert.ok(probabilities(.5)[0] > original[0]);
  assert.ok(probabilities(2)[0] < original[0]);
  for (const temperature of [.5, 1, 2]) assert.ok(Math.abs(probabilities(temperature).reduce((a,b)=>a+b,0)-1)<1e-12);
  assert.equal(choose(original, .2), 0);
  assert.equal(choose(original, .8), 1);
  assert.equal(choose(original, .99), 2);
  const first = trainingStep(.5);
  assert.equal(first.loss, 10.5);
  assert.ok(Math.abs(first.next - 1.2) < 1e-12);
  assert.ok(trainingStep(first.next).loss < first.loss);
  let w = .5; for (let i=0;i<20;i++) w=trainingStep(w).next;
  assert.ok(Math.abs(w-2)<.0001);
  assert.deepEqual(sortExample(), {input:[20,100,3],ordinary:[100,20,3],numeric:[3,20,100]});
});

test("the original teaching-art module loads before the lecture viewer", async () => {
  const html = await readFile(new URL("./index.html", import.meta.url), "utf8");
  assert.ok(html.indexOf('src="./lecture-studio.js') < html.indexOf('src="./lecture.js'));
  assert.ok(html.includes('href="./lecture-studio.css'));
  for (const frame of flatten(data).filter(f=>f.visual)) assert.ok(frame.visual.scene);
});

test("scheduling preserves each request and refills only available slots", () => {
  const fixed=scheduling("fixed"),continuous=scheduling("continuous");
  assert.equal(fixed.length,7);assert.equal(continuous.length,6);
  assert.equal(fixed[2][0],null);assert.deepEqual(continuous[2][0],{id:"C",token:1,length:1});
  for(const rounds of [fixed,continuous]){
    assert.equal(rounds.flat().filter(Boolean).length,10);
    for(const [id,length] of [["A",2],["B",4],["C",1],["D",3]]){
      assert.deepEqual(rounds.flat().filter(v=>v?.id===id).map(v=>v.token),Array.from({length},(_,i)=>i+1));
    }
  }
  assert.equal(weekendChoice(true).tool,"museum_hours");
  assert.equal(weekendChoice(false).tool,"park_route");
});

test("the existing book exposes its class through the same chapter IDs and diagrams", () => {
  assert.deepEqual(book.lecture.page_ids, data.lessons.map(l => l.page_id));
  for (const lesson of data.lessons) {
    const page = book.pages.find(p => p.id === lesson.page_id);
    assert.deepEqual(page.blocks.filter(b => b.kind === "diagram").map(b => b.visual), lesson.slides.map(s => s.visual));
    assert.equal(page.estimated_minutes, lesson.slides.reduce((sum, s) => sum + s.minutes, 0));
  }
});

test("every content screen has a spoken beat and a causal motion for every stage",()=>{
  for(const frame of flatten(data).filter(f=>f.visual)){
    assert.equal(frame.visual.beats.length,frame.visual.steps.length,frame.id);
    assert.equal(frame.visual.motion.length,frame.visual.steps.length,frame.id);
    assert.ok(pick(frame.transition,"en"));assert.ok(pick(frame.transition,"zh-CN"));
    for(const beat of frame.visual.beats){assert.ok(pick(beat,"en"));assert.ok(pick(beat,"zh-CN"));}
    for(const motion of frame.visual.motion){assert.ok(["flow","write","grow","draw","compute"].includes(motion.kind));if(motion.kind==="flow"){assert.ok(motion.points.length>=2);for(const [x,y]of motion.points)assert.ok(x>=0&&x<=1100&&y>=0&&y<=420);}}
  }
});

test("information is mixed numerically and motion follows distance along its path",()=>{
  assert.deepEqual(weightedMix([.8,.2],[[1,0],[0,1]]),[.8,.2]);
  assert.deepEqual(weightedMix([.2,.8],[[1,0],[0,1]]),[.2,.8]);
  assert.deepEqual(pointAlong([[0,0],[3,0],[3,4]],0),[0,0]);
  assert.deepEqual(pointAlong([[0,0],[3,0],[3,4]],3/7),[3,0]);
  assert.deepEqual(pointAlong([[0,0],[3,0],[3,4]],1),[3,4]);
});

test("course directory covers every slide once and resolves bilingual concept queries",()=>{
  const slides=flatten(data).filter(frame=>frame.visual),items=indexItems(data.outline);
  assert.equal(items.length,slides.length);
  assert.equal(new Set(items.map(item=>item.id)).size,46);
  for(const item of items){const frame=slides.find(frame=>frame.id===item.id);assert.ok(frame);assert.equal(frame.page_id,item.page_id);assert.equal(item.minutes,frame.minutes);assert.equal(item.start,flatten(data).slice(0,flatten(data).findIndex(f=>f.id===item.id)).reduce((sum,f)=>sum+f.minutes,0));}
  assert.ok(indexItems(data.outline,"KV cache").some(item=>item.id==="cluster-engine-path"));
  assert.ok(indexItems(data.outline,"缓存").some(item=>item.id==="cluster-engine-path"));
  assert.ok(indexItems(data.outline,"ＲＡＧ").some(item=>item.id==="rag-retrieval"));
  assert.deepEqual(indexItems(data.outline,"no-such-concept-12345"),[]);
  const directory=book.pages.find(page=>page.id==="ai-course-map");assert.ok(directory);assert.deepEqual(directory.blocks.find(block=>block.kind==="course-index").groups,data.concept_outline);
});

test("teaching checkpoints preserve the two-hour route and have answered student questions",()=>{
  assert.deepEqual(data.outline.map(group=>[group.start,group.end]),[[0,16],[16,39],[39,77],[77,104],[104,113],[113,115]]);
  for(const frame of flatten(data).filter(frame=>frame.visual)){
    const teaching=frame.teaching;assert.deepEqual(teaching.questions.map(q=>q.kind),["why","how","link"]);for(const q of teaching.questions)for(const lang of ["en","zh-CN"]){assert.ok(pick(q.question,lang));assert.ok(pick(q.answer,lang));}
    const p=teaching.pacing;assert.ok(p.margin_seconds>=0,frame.id);assert.equal(p.speech_seconds+p.demo_seconds+p.processing_seconds+p.question_seconds+p.transition_seconds+p.margin_seconds,frame.minutes*60,frame.id);
  }
});

test("every projected page has a complete manuscript aligned with its actual animation",async()=>{
  const frames=flatten(data),audit=JSON.parse(await readFile(new URL("../docs/ai-speaking-audit.json",import.meta.url),"utf8"));
  assert.equal(Object.keys(data.speaking_pages).length,48);
  let start=0,steps=0,characters=0;
  for(const [index,frame] of frames.entries()){
    const script=frame.speaking;assert.ok(script,frame.id);
    assert.equal(script.id,frame.id);assert.equal(script.number,index+1);assert.equal(script.start,start);assert.equal(script.minutes,frame.minutes);assert.equal(script.page_id,frame.page_id);assert.equal(script.language,"zh-CN");
    assert.ok(script.opening.length>5,frame.id);assert.ok(script.closing.length>5,frame.id);
    assert.deepEqual(script.steps.map(s=>s.label),(frame.visual?.steps||[]).map(s=>pick(s,"zh-CN")),frame.id);
    for(const [i,step] of script.steps.entries()){assert.equal(step.step,i+1);assert.ok(step.action.length>5);assert.ok(step.text.length>5);assert.doesNotMatch(step.text,/TODO|待补|此处展开|占位/);}
    const count=[script.opening,...script.steps.map(s=>s.text),script.closing].join("").length;
    assert.equal(script.spoken_characters,count,frame.id);
    assert.equal(script.estimated_speech_seconds,count/220*60);
    if(frame.visual){const p=frame.teaching.pacing;assert.ok(script.estimated_speech_seconds<=p.speech_seconds+p.transition_seconds,frame.id);}
    else {assert.equal(script.steps.length,0);assert.ok(script.guidance.length>0,frame.id);}
    start+=frame.minutes;steps+=script.steps.length;characters+=count;
  }
  assert.equal(start,120);assert.equal(steps,149);assert.equal(audit.animation_steps,steps);assert.equal(audit.spoken_characters,characters);assert.equal(audit.pages_detail.length,48);assert.ok(audit.pages_detail.every(p=>!p.over_budget));
});

test("the printable and editable manuscripts contain every slide and its full spoken text",async()=>{
  const html=await readFile(new URL("./ai-speaker-script.html",import.meta.url),"utf8"),md=await readFile(new URL("./ai-speaker-script.md",import.meta.url),"utf8"),local=await readFile(new URL("../docs/AI_PAGE_SPEAKER_SCRIPT_20261116.md",import.meta.url),"utf8");
  assert.equal(md,local);assert.equal((html.match(/class=script-page id=/g)||[]).length,48);assert.equal((md.match(/^## 第 \d+ 页/gm)||[]).length,48);
  for(const frame of flatten(data)){
    assert.ok(html.includes(`id="${frame.id}"`));assert.ok(html.includes(`href="#${frame.id}"`));assert.ok(html.includes(`slide=${frame.id}`));assert.ok(md.includes(frame.speaking.opening));assert.ok(md.includes(frame.speaking.closing));
    for(const step of frame.speaking.steps){assert.ok(md.includes(step.text));assert.ok(md.includes(step.action));}
  }
  assert.doesNotMatch(html,/<script(?![^>]*src=)|<style[ >]/);
  assert.match(html,/打印讲稿/);assert.match(html,/download/);
});
