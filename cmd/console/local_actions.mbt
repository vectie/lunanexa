///|
extern "js" fn copy_public_identifier_promise(value : String) -> @js.Promise =
  #| async value => {
  #|   if (!navigator.clipboard?.writeText) throw new Error("clipboard unavailable");
  #|   await navigator.clipboard.writeText(value);
  #| }
