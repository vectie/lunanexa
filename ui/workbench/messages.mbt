///|
priv enum MessageText {
  LocalDraftWarning
  ExportDraftsLabel
  CopyReceipt
  SelectAuthorizedModel
  AdvancedModel
}

///|
fn message_text(locale : @i18n.Locale, key : MessageText) -> String {
  match key {
    LocalDraftWarning =>
      @i18n.copy(
        locale, "Drafts exist only in this page. Export before closing or switching browsers. The file contains your draft text; keep it private.",
        "草稿仅保存在当前页面中。关闭或更换浏览器前请导出。文件包含草稿原文，请妥善保管。",
      )
    ExportDraftsLabel => @i18n.copy(locale, "Export drafts", "导出草稿")
    CopyReceipt => @i18n.copy(locale, "Copy receipt", "复制回执")
    SelectAuthorizedModel =>
      @i18n.copy(locale, "Select an authorized model", "选择已授权模型")
    AdvancedModel =>
      @i18n.copy(
        locale, "Advanced: manual model alias", "高级：手动输入模型别名",
      )
  }
}

///|
/// Export only user-authored drafts, not authentication, output, or lease state.
pub fn export_drafts(state : WorkbenchState) -> String {
  let files : Array[Json] = [
    for file in state.files => {
      { "path": file.path, "language": file.language, "content": file.content }
    }
  ]
  let result : Json = { "format": "lunanexa.browser-drafts.v1", "files": files }
  result.stringify(indent=2)
}

///|
fn lease_remaining_message(
  locale : @i18n.Locale,
  lease_id : String,
  minutes : Int64,
) -> String {
  @i18n.copy(
    locale,
    "Lease \{lease_id} · \{minutes}m remaining",
    "租约 \{lease_id} · 剩余 \{minutes} 分钟",
  )
}

///|
fn local_drafts_message(locale : @i18n.Locale, count : Int) -> String {
  @i18n.copy(locale, "\{count} LOCAL", "\{count} 个本地草稿")
}

///|
fn handoff_requested_message(
  locale : @i18n.Locale,
  client_label : String,
) -> String {
  @i18n.copy(
    locale,
    "\{client_label} handoff requested. Only opaque, expiring client metadata may leave this browser; no node access was created.",
    "已请求 \{client_label} 交接。只有不透明且有时效的客户端元数据可离开此浏览器；未创建任何节点访问权限。",
  )
}
