///|
pub(all) enum OperatorList {
  Accounts
  WorkspaceProfiles
  AccessGrants
  AccessRecords
  AuditEvents
  RequestReceipts
} derive(Eq, Hash)

///|
pub extend OperatorList with Eq::{equal, not_equal}

///|
pub extend OperatorList with Hash::{hash, hash_combine}

///|
pub(all) struct ListPage {
  query : String
  page : Int32
} derive(Eq)

///|
pub extend ListPage with Eq::{equal, not_equal}

///|
fn list_page_styles() -> String {
  let css =
    #|.list-controls{display:flex;flex-wrap:wrap;align-items:end;gap:.75rem;margin:.75rem 0}.list-controls>.field-group{flex:1;min-width:min(16rem,100%)}.list-pagination{display:flex;align-items:center;gap:.65rem;flex-wrap:wrap}.list-pagination button{min-height:44px}.list-pagination [role=status]{font-variant-numeric:tabular-nums}.list-controls>.empty-state{flex-basis:100%}@media(max-width:40rem){.list-controls{display:grid;grid-template-columns:minmax(0,1fr)}.list-pagination{justify-content:space-between}}
  css
}

///|
priv struct PagedRows[T] {
  rows : Array[T]
  total : Int32
  page : Int32
  pages : Int32
}

///|
fn list_key(kind : OperatorList) -> String {
  match kind {
    Accounts => "accounts"
    WorkspaceProfiles => "workspace-profiles"
    AccessGrants => "access-grants"
    AccessRecords => "access-records"
    AuditEvents => "audit-events"
    RequestReceipts => "request-receipts"
  }
}

///|
fn list_label(locale : @i18n.Locale, kind : OperatorList) -> String {
  match kind {
    Accounts => localized(locale, "Accounts", "账户")
    WorkspaceProfiles =>
      localized(locale, "Workspace profiles", "工作区档案")
    AccessGrants => localized(locale, "Access grants", "访问授权")
    AccessRecords => localized(locale, "Company access", "企业权限")
    AuditEvents => localized(locale, "Audit events", "审计事件")
    RequestReceipts => localized(locale, "Request receipts", "请求回执")
  }
}

///|
fn[T] paged_rows(
  state : ConsoleState,
  kind : OperatorList,
  values : Array[T],
  searchable : (T) -> String,
) -> PagedRows[T] {
  let setting = state.list_pages.get(kind).unwrap_or({ query: "", page: 0, })
  let query = setting.query.trim().to_owned().to_lower()
  let filtered = if query == "" {
    values
  } else {
    values.filter(value => searchable(value).to_lower().contains(query))
  }
  let pages = ((filtered.length() + 24) / 25).max(1)
  let page = setting.page.clamp(min=0, max=pages - 1)
  let start = page * 25
  {
    rows: filtered[start:(start + 25).min(filtered.length())].to_owned(),
    total: filtered.length(),
    page,
    pages,
  }
}

///|
fn[T] list_controls(
  state : ConsoleState,
  kind : OperatorList,
  page : PagedRows[T],
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let id = "list-search-" + list_key(kind)
  let label = list_label(state.locale, kind)
  @html.div(class="list-controls", [
    @html.div(class="field-group", [
      @html.label(for_=id, localized(state.locale, "Search ", "搜索") + label),
      @html.input(
        id~,
        value=state.list_pages.get(kind).map_or("", value => value.query),
        maxlength=256,
        on_input=text_command(emit, query => ListQueryChanged(kind, query)),
      ),
    ]),
    @html.nav(
      class="list-pagination",
      attrs=@html.Attrs::build().aria_label(
        label + localized(state.locale, " pages", "分页"),
      ),
      [
        @html.button(
          type_="button",
          disabled=page.page == 0,
          on_click=command(emit, ListPageChanged(kind, page.page - 1)),
          localized(state.locale, "Previous", "上一页"),
        ),
        @html.span(
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          "\{page.page + 1} / \{page.pages} · " +
          localized(
            state.locale,
            "\{page.total} records",
            "共 \{page.total} 条",
          ),
        ),
        @html.button(
          type_="button",
          disabled=page.page + 1 >= page.pages,
          on_click=command(emit, ListPageChanged(kind, page.page + 1)),
          localized(state.locale, "Next", "下一页"),
        ),
      ],
    ),
    if page.total == 0 &&
      state.list_pages
      .get(kind)
      .map_or(false, value => value.query.trim() != "") {
      @html.p(
        class="empty-state compact",
        localized(state.locale, "No matching records", "没有匹配记录"),
      )
    } else {
      @html.nothing
    },
  ])
}
