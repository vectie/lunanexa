///|
fn technical_acceptance_panel(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  order : @offline.CommercialOrder,
) -> @html.Html {
  if order.technical_acceptance_waiver is Some(w) {
    return @html.section(class="offline-panel", [
      @html.h3(
        copy(
          state.locale,
          "Non-commercial technical acceptance",
          "非商业技术验收",
        ),
      ),
      @html.p(
        copy(
          state.locale,
          "Unsigned · Unpaid · Invoice waived. This is not a completed commercial contract.",
          "未签署 · 未付款 · 发票已豁免，不代表商业合同已履约。",
        ),
      ),
      @html.p(
        copy(state.locale, "Bound resource", "绑定资源") +
        ": " +
        w.authority_target_ref,
      ),
      @html.p(
        copy(state.locale, "Test access expires", "测试权限截止") +
        ": " +
        order_expiry_label(state.locale, w.expires_unix_ms),
      ),
      @html.p(
        copy(state.locale, "Authorization record", "授权记录") +
        ": " +
        w.user_authorization_ref,
      ),
    ])
  }
  guard state.audience == OperatorCommerce &&
    state.technical_authorization is Some(scope) &&
    scope.order_id == order.order_id &&
    scope.purchaser_subject_ref == order.purchaser_subject_ref &&
    scope.order_binding.map_or(true, b => b.matches_order(order)) &&
    (order.state == Quoted || order.state == PendingInternalApproval) else {
    return @html.nothing
  }
  @html.section(class="offline-panel", [
    @html.h3(
      copy(
        state.locale,
        "Limited technical acceptance",
        "限时技术验收（仅本订单）",
      ),
    ),
    if scope.order_binding is Some({ entitlement_kind: WorkspaceLease, .. }) &&
      state.technical_target_ref.is_empty() {
      @html.button(
        type_="button",
        class="primary-action",
        disabled=state.loading,
        on_click=command(
          emit,
          BeginConfirmation(
            PrepareTechnicalWorkspace(order.order_id, order.generation),
          ),
        ),
        copy(
          state.locale,
          "Prepare limited workspace (up to 45 minutes)",
          "准备限时工作区（最多 45 分钟）",
        ),
      )
    } else {
      @html.nothing
    },
    @html.p(
      copy(
        state.locale,
        "Requires a real operator session and an existing administrator-approved target. Does not sign or pay this order.",
        "需要真实管理员会话及已经授权的资源；不会签署或支付本订单。",
      ),
    ),
    @html.p(
      copy(state.locale, "Authorization deadline", "授权截止时间") +
      ": " +
      order_expiry_label(state.locale, scope.expires_unix_ms),
    ),
    @html.label(
      for_="technical-target",
      copy(state.locale, "Approved resource reference", "已批准资源引用"),
    ),
    @html.input(
      id="technical-target",
      attrs=@html.Attrs::build().disabled(
        scope.order_binding is Some({ entitlement_kind: WorkspaceLease, .. }),
      ),
      value=state.technical_target_ref,
      maxlength=160,
      on_input=text_command(emit, value => TechnicalTargetChanged(value)),
    ),
    @html.label(
      for_="technical-grant",
      copy(
        state.locale,
        "Administrator grant reference",
        "管理员授权引用",
      ),
    ),
    @html.input(
      id="technical-grant",
      attrs=@html.Attrs::build().disabled(
        scope.order_binding is Some({ entitlement_kind: WorkspaceLease, .. }),
      ),
      value=state.technical_grant_id,
      maxlength=160,
      on_input=text_command(emit, value => TechnicalGrantChanged(value)),
    ),
    @html.button(
      type_="button",
      class="primary-action",
      disabled=state.loading ||
        state.technical_target_ref.trim() == "" ||
        state.technical_grant_id.trim() == "",
      on_click=command(
        emit,
        BeginConfirmation(
          AuthorizeTechnicalOrder(
            order.order_id,
            order.generation,
            state.technical_target_ref.trim().to_owned(),
            state.technical_grant_id.trim().to_owned(),
            scope.user_authorization_ref,
            0L,
          ),
        ),
      ),
      copy(state.locale, "Review test waiver", "审阅本订单测试豁免"),
    ),
  ])
}

///|
fn technical_order_status(
  locale : @i18n.Locale,
  order : @offline.CommercialOrder,
) -> String {
  if order.technical_acceptance_waiver is Some(_) {
    match order.state {
      Fulfilled =>
        return copy(locale, "Test access provisioned", "测试资源已开通")
      FulfillmentPending =>
        return copy(locale, "Test access provisioning", "测试资源开通中")
      _ => ()
    }
  }
  order_state_label(locale, order.state)
}

///|
fn technical_policy_items(locale : @i18n.Locale) -> Array[@rabbita.Html] {
  [
    copy(
      locale, "Signature waived — unsigned", "签署已豁免 — 未签署",
    ),
    copy(locale, "Payment waived — unpaid", "付款已豁免 — 未付款"),
    copy(
      locale, "Invoice waived — no issued invoice asserted", "发票已豁免 — 不代表已开票",
    ),
    copy(
      locale, "Actual account authentication remains required; not commercial KYC",
      "仍须真实账户认证，不代表商业 KYC",
    ),
    copy(
      locale, "Commercial review waived; administrator resource authorization remains required",
      "商业审核已豁免，仍须管理员资源授权",
    ),
  ].map(label => @html.li([@html.span(label)]))
}
