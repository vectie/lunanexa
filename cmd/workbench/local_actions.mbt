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

///|
/// Capture the File before async work. Reset the input so the same file can be
/// retried. Only this selected File is read; its name never becomes a path/URL.
extern "js" fn read_drafts_promise() -> @js.Promise =
  #| () => {
  #|   try {
  #|     const input = document.getElementById("workbench-draft-file");
  #|     const file = input && input.files && input.files[0];
  #|     if (input) input.value = "";
  #|     if (!file) return Promise.resolve(null);
  #|     if (file.size > 16777216) return Promise.reject(new Error("draft file size limit"));
  #|     return file.arrayBuffer().then(bytes => {
  #|       if (bytes.byteLength > 16777216) throw new Error("draft file size limit");
  #|       const text = new TextDecoder("utf-8", {fatal:true}).decode(bytes);
  #|       if (text.length > 4194304) throw new Error("draft text size limit");
  #|       return text;
  #|     });
  #|   } catch (_) { return Promise.reject(new Error("draft file read failed")); }
  #| }

///|
// The pinned core exposes its parser depth limit through a deprecated label.
// Keep this narrow bound until the supported replacement API is available.
#warnings("-deprecated")
fn decode_draft_text(
  text : String,
) -> Result[Array[@workbench_ui.DraftFile], @workbench_ui.DraftImportError] {
  if text.length() > 4194304 {
    return Err(LimitExceeded)
  }
  @workbench_ui.decode_drafts(@json.parse(text, max_nesting_depth=8)) catch {
    _ => Err(InvalidPacket)
  }
}

///|
fn read_drafts_command(
  generation : Int64,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let promise = read_drafts_promise()
  @rabbita.perform(message => emit(Workbench(message)), async fn() noraise {
    let result = try {
      let value = promise.wait()
      if value.is_null() {
        Err(@workbench_ui.DraftImportError::ReadCancelled)
      } else {
        decode_draft_text(value.cast())
      }
    } catch {
      _ => Err(@workbench_ui.DraftImportError::ReadFailed)
    }
    @workbench_ui.WorkbenchMessage::DraftFileRead(generation, result)
  })
}
