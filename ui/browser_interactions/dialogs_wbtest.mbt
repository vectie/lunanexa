///|
extern "js" fn exercise_dialog_keyboard(install : () -> Unit) -> String =
  #| install => {
  #|   const saved = [globalThis.document,globalThis.MutationObserver,globalThis.__lunanexaDialogInteractions];
  #|   const handlers={}, results=[];
  #|   let observer, shown=true, isModal=true, cancelled=0, restored=0, prevented=0;
  #|   const trigger={isConnected:true,focus(){restored++;document.activeElement=this;}};
  #|   const backdrop={};
  #|   const first={disabled:false,tabIndex:0,getClientRects:()=>[{}],focus(){document.activeElement=this;},click(){cancelled++;shown=false;observer();}};
  #|   const last={tabIndex:0,getClientRects:()=>[{}],focus(){document.activeElement=this;}};
  #|   const dialog={getAttribute:()=>isModal?'true':null,querySelector:s=>s.includes('#contract-confirmation-dismiss')?first:null,
  #|     querySelectorAll:()=>[first,last],closest:()=>backdrop,contains:e=>e===first||e===last};
  #|   try {
  #|     globalThis.__lunanexaDialogInteractions=false;
  #|     globalThis.document={documentElement:{},activeElement:trigger,querySelectorAll:()=>shown?[dialog]:[],addEventListener:(event,fn)=>handlers[event]=fn};
  #|     globalThis.MutationObserver=class {constructor(fn){observer=fn;}observe(){}};
  #|     install(); results.push(document.activeElement===first);
  #|     handlers.keydown({key:'Tab',shiftKey:true,preventDefault(){prevented++;}});
  #|     results.push(document.activeElement===last && prevented===1);
  #|     handlers.keydown({key:'Tab',shiftKey:false,preventDefault(){prevented++;}});
  #|     results.push(document.activeElement===first && prevented===2);
  #|     document.activeElement=trigger; handlers.focusin({target:trigger});
  #|     results.push(document.activeElement===first);
  #|     handlers.click({target:last}); results.push(cancelled===0);
  #|     handlers.keydown({key:'Escape',preventDefault(){prevented++;}});
  #|     results.push(cancelled===1 && restored===1 && prevented===3);
  #|     shown=true;isModal=false;observer();document.activeElement=trigger;
  #|     handlers.focusin({target:trigger});handlers.keydown({key:'Tab',preventDefault(){prevented++;}});
  #|     results.push(document.activeElement===trigger && prevented===3);
  #|     first.disabled=true;handlers.keydown({key:'Escape',preventDefault(){prevented++;}});
  #|     results.push(cancelled===1 && prevented===3);
  #|     first.disabled=false;handlers.click({target:backdrop});results.push(cancelled===2 && restored===2);
  #|     return JSON.stringify(results);
  #|   } finally {
  #|     [globalThis.document,globalThis.MutationObserver,globalThis.__lunanexaDialogInteractions]=saved;
  #|   }
  #| }

///|
test "dialogs trap modal focus restore trigger cancel on Escape and preserve nonmodal navigation" {
  assert_eq(
    exercise_dialog_keyboard(install_dialog_interactions),
    "[true,true,true,true,true,true,true,true,true]",
  )
}
