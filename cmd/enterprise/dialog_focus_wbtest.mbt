///|
extern "js" fn exercise_dialog_dismissal(install : () -> Unit) -> String =
  #| (install) => {
  #|   const saved = [globalThis.document, globalThis.MutationObserver, globalThis.__lunanexaEnterpriseDialogFocus];
  #|   const handlers = {}, results = [];
  #|   let observe, shown = true, closed = 0, restored = 0;
  #|   const trigger = {isConnected:true, focus(){ restored++; }};
  #|   const backdrop = {};
  #|   const cancel = {disabled:false, tabIndex:0, getClientRects:()=>[{}], focus(){}, click(){ closed++; shown=false; observe(); }};
  #|   const inside = {};
  #|   const dialog = {querySelector:selector=>selector.includes('#api-key-connection-dismiss')?cancel:null, querySelectorAll:()=>[cancel], closest:()=>backdrop, contains:e=>e===inside || e===cancel};
  #|   try {
  #|     globalThis.__lunanexaEnterpriseDialogFocus = false;
  #|     globalThis.document = {documentElement:{}, activeElement:trigger, querySelectorAll:()=>shown?[dialog]:[], addEventListener:(name,fn)=>{handlers[name]=fn;}};
  #|     globalThis.MutationObserver = class {constructor(fn){observe=fn;} observe(){}};
  #|     install();
  #|     handlers.click({target:inside}); results.push(closed===0);
  #|     handlers.click({target:backdrop}); results.push(closed===1 && restored===1);
  #|     shown=true; observe();
  #|     let prevented=false; handlers.keydown({key:'Escape',preventDefault(){prevented=true;}});
  #|     results.push(closed===2 && prevented && restored===2);
  #|     shown=true; observe(); cancel.disabled=true;
  #|     handlers.click({target:backdrop}); handlers.keydown({key:'Escape',preventDefault(){}});
  #|     results.push(closed===2);
  #|     return JSON.stringify(results);
  #|   } finally {
  #|     [globalThis.document, globalThis.MutationObserver, globalThis.__lunanexaEnterpriseDialogFocus] = saved;
  #|   }
  #| }

///|
test "outside click and Escape dismiss the dialog, retain inside clicks, and respect pending operations" {
  assert_eq(
    exercise_dialog_dismissal(install_dialog_focus),
    "[true,true,true,true]",
  )
}
