///|
extern "js" fn export_drafts_promise(value : String) -> @js.Promise =
  #| async value => {
  #|   const blob = new Blob([value], {type: "application/json;charset=utf-8"});
  #|   const url = URL.createObjectURL(blob);
  #|   const link = document.createElement("a");
  #|   try {
  #|     link.href = url;
  #|     link.download = "lunanexa-browser-drafts.json";
  #|     link.hidden = true;
  #|     document.body.appendChild(link);
  #|     link.click();
  #|   } finally {
  #|     link.remove();
  #|     setTimeout(() => URL.revokeObjectURL(url), 1000);
  #|   }
  #| }

///|
extern "js" fn copy_diagnostic_promise(value : String) -> @js.Promise =
  #| async value => {
  #|   if (!navigator.clipboard?.writeText) throw new Error("clipboard unavailable");
  #|   await navigator.clipboard.writeText(value);
  #| }
