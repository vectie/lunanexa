import assert from "node:assert/strict";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import test from "node:test";

// Opt-in browser integration checks against the actual docs server. No account
// or shared browser profile is used. Start server.mjs before enabling the test.
test("speaker manuscripts follow the complete class and drive its real diagrams",{
  skip:process.env.LUNANEXA_BROWSER_TEST!=="1",timeout:180000
},async()=>{
  const require=createRequire(import.meta.url);
  const {chromium}=require(process.env.LUNANEXA_PLAYWRIGHT||"playwright");
  const browser=await chromium.launch({headless:true,executablePath:process.env.LUNANEXA_CHROME||undefined});
  const origin=process.env.COURSEBOOK_PREVIEW_ORIGIN||"http://127.0.0.1:4396";
  const output=new URL("../output/ai-course-speaker-20261116/",import.meta.url);
  await mkdir(output,{recursive:true});
  const data=JSON.parse(await readFile(new URL("./ai-lecture.json",import.meta.url),"utf8"));
  const scripts=Object.values(data.speaking_pages).sort((a,b)=>a.number-b.number);
  const errors=[],walk=[];
  try{
    const context=await browser.newContext({viewport:{width:1440,height:1000},locale:"zh-CN"});
    const page=await context.newPage();page.on("pageerror",error=>errors.push(error.message));
    await page.setViewportSize({width:390,height:844});
    await page.goto(`${origin}/?page=ai-course-map`);
    await page.locator('[data-course-manuscript]').waitFor();
    assert.ok(await page.getByRole("link",{name:"逐页讲稿",exact:true}).isVisible());
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:new URL("preview-book-entry-mobile.png",output).pathname});
    await page.setViewportSize({width:1440,height:1000});
    await page.goto(`${origin}/?view=lecture&slide=${scripts[0].id}&page=${scripts[0].page_id}`);
    await page.locator(".lecture-shell").waitFor();
    await page.getByRole("button",{name:"讲稿",exact:true}).click();
    for(const script of scripts){
      const shell=page.locator(".lecture-shell");
      assert.equal(await shell.getAttribute("data-slide-id"),script.id);
      const manuscript=shell.locator(".speaker-verbatim");
      assert.ok((await manuscript.innerText()).includes(script.opening),script.id);
      assert.ok((await manuscript.innerText()).includes(script.closing),script.id);
      assert.equal(await manuscript.locator(".speaker-demo").count(),script.steps.length);
      assert.equal(await shell.locator(".speaker-preparation").getAttribute("open"),null);
      const bounds=await manuscript.evaluate(el=>({width:el.clientWidth,scroll:el.scrollWidth}));
      assert.ok(bounds.scroll<=bounds.width+1,`${script.id} text overflow`);
      for(const item of script.steps){
        await manuscript.locator(".speaker-demo").nth(item.step-1).evaluate(el=>el.click());
        assert.equal(await shell.locator(".teaching-figure").getAttribute("data-step"),String(item.step),script.id);
        assert.equal(await manuscript.locator(".note-current").getAttribute("data-note-step"),String(item.step));
      }
      if(script.id==="expert-routing"){
        const select=shell.locator('.board-control select');
        await select.selectOption("B");
        await manuscript.locator(".speaker-demo").nth(1).click();
        assert.equal(await select.inputValue(),"A");
      }
      if(script.id==="attention-context")await page.screenshot({path:new URL("preview-speaker-panel.png",output).pathname});
      walk.push({id:script.id,page:script.number,steps:script.steps.length,opening:true,closing:true});
      if(script.number<48)await shell.getByRole("button",{name:"下一页 →",exact:true}).click();
    }
    await page.getByRole("button",{name:"English",exact:true}).click();
    assert.equal(await page.locator(".speaker-verbatim").count(),0);
    assert.ok(await page.getByRole("link",{name:"Complete Chinese script",exact:true}).isVisible());
    assert.notEqual(await page.locator(".speaker-preparation").getAttribute("open"),null);
    await page.goto(`${origin}/ai-speaker-script.html`);
    assert.equal(await page.locator("nav li").count(),48);
    assert.equal(await page.locator(".script-page").count(),48);
    await page.locator('nav a[href="#target-and-loss"]').click();
    assert.equal(new URL(page.url()).hash,"#target-and-loss");
    await page.screenshot({path:new URL("preview-print-manuscript.png",output).pathname});
    await page.evaluate(()=>{window.print=()=>{window.__printCalled=true;};});
    await page.getByRole("button",{name:"打印讲稿",exact:true}).click();
    assert.equal(await page.evaluate(()=>window.__printCalled),true);
    const download=await Promise.all([page.waitForEvent("download"),page.getByRole("link",{name:"下载 Markdown",exact:true}).click()]);
    assert.equal(download[0].suggestedFilename(),"ai-speaker-script.md");
    const source=await readFile(new URL("./ai-speaker-script.md",import.meta.url),"utf8");
    assert.equal(await readFile(await download[0].path(),"utf8"),source);
    await page.setViewportSize({width:390,height:844});
    await page.goto(`${origin}/ai-speaker-script.html#target-and-loss`);
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.screenshot({path:new URL("preview-manuscript-mobile.png",output).pathname});
    await page.emulateMedia({media:"print"});
    assert.equal(await page.locator("nav").isVisible(),false);
    assert.equal(await page.locator(".script-toolbar").isVisible(),false);
    assert.ok(await page.locator("#target-and-loss").isVisible());
    assert.deepEqual(errors,[]);
    await writeFile(new URL("browser-walk.json",output),JSON.stringify({origin,pages:walk,steps:walk.reduce((n,p)=>n+p.steps,0),errors,printControls:true,downloadBytesMatch:true,mobileOverflow:false},null,2)+"\n");
  }finally{await browser.close();}
});
