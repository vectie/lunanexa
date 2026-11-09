///|
fn quote_blockers(state : OfflineCommerceState) -> Array[String] {
  state.readiness_blocker_codes.filter(code => {
    @offline.offline_blocker_applies(code, [
      ApprovedLegalTemplates,
      FinanceLegalPolicy,
    ])
  })
}

///|
fn quote_readiness_notice(state : OfflineCommerceState) -> @rabbita.Html {
  let blockers = quote_blockers(state)
  if blockers.is_empty() {
    return @html.nothing
  }
  @html.div(class="notice is-warning", [
    @html.p(
      copy(
        state.locale,
        "Commerce setup is not ready for a quote. The draft is retained.",
        "商务配置尚未就绪，暂不能报价。草稿已保留。",
      ),
    ),
    @html.details([
      @html.summary(
        copy(state.locale, "View missing setup", "查看配置缺项"),
      ),
      @html.ul([ for code in blockers => @html.li(@html.code(code)) ]),
    ]),
  ])
}
