///|
pub fn rental_template_id(order : @offline.CommercialOrder) -> String {
  let original = @contractdoc.undertaking_manifest()
  if order.quote.map_or(false, quote => quote.terms_digest == original.sha256) {
    original.template_id
  } else {
    @contractdoc.undertaking_ofl_manifest().template_id
  }
}

///|
pub fn rental_packet(
  state : OfflineCommerceState,
  order : @offline.CommercialOrder,
) -> @contractdoc.ContractPacket? {
  let packets = state.contract_packets.filter(packet => {
    packet.order_ref == order.order_id &&
    packet.tenant_ref == order.tenant_ref &&
    packet.organization_id == order.organization_id &&
    @contractdoc.is_undertaking_template(packet.template_id) &&
    packet.state != Superseded &&
    packet.state != Closed
  })
  if packets.length() == 1 {
    packets.get(0)
  } else {
    None
  }
}

///|
fn rental_handoff(
  state : OfflineCommerceState,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
  order : @offline.CommercialOrder,
) -> @rabbita.Html {
  if order.requested_undertaking_term is None ||
    order.state == Cancelled ||
    order.state == Rejected ||
    order.state == Expired ||
    order.state == Revoked ||
    order.state == ReversalPending ||
    order.state == ReversalManualIntervention {
    return @html.nothing
  }
  let operator = state.audience == OperatorCommerce
  let packet = rental_packet(state, order)
  let effective = packet.map_or(false, p => p.state == Effective)
  let action : (String, OfflineCommerceMessage)? = if order.state == Draft ||
    order.state == Quoted {
    None
  } else if operator && effective {
    Some(
      (
        copy(state.locale, "Check & allocate machines", "检查并下发机器"),
        OpenAllocation(order.order_id),
      ),
    )
  } else if !operator && order.state == Fulfilled {
    Some(
      (
        copy(state.locale, "Open company machines", "打开公司机器"),
        OpenMachineAccess(order.order_id),
      ),
    )
  } else if !operator && effective {
    None
  } else {
    Some(
      (
        copy(state.locale, "Open rental document", "打开租赁文件"),
        OpenContractDocuments(order.order_id),
      ),
    )
  }
  @html.section(class="offline-panel", [
    rental_quote_summary(state.locale, order),
    @html.p(
      attrs=@html.Attrs::build().role("status"),
      if order.state == Draft {
        if operator {
          copy(
            state.locale,
            "Confirm the requested tariff below.",
            "请在下方确认申请档位报价。",
          )
        } else {
          copy(
            state.locale,
            "Waiting for the operator's quote.",
            "等待运营方确认报价。",
          )
        }
      } else if order.state == Quoted {
        if operator {
          copy(
            state.locale,
            "Send the quote to start document preparation.",
            "发送报价，开始准备文件。",
          )
        } else {
          copy(
            state.locale,
            "Waiting for the operator to release the quote.",
            "等待运营方发布报价。",
          )
        }
      } else if effective {
        if operator {
          copy(
            state.locale,
            "Undertaking approved. Check payment and allocate the quoted machines.",
            "承诺函已批准。核对到账并下发报价对应机器。",
          )
        } else {
          copy(
            state.locale,
            "Undertaking approved. Machine access opens after allocation.",
            "承诺函已批准，机器下发后即可开通访问。",
          )
        }
      } else if operator && packet is None {
        copy(
          state.locale,
          "Waiting for the customer to prepare the rental document.",
          "等待客户准备租赁文件。",
        )
      } else {
        copy(
          state.locale,
          "Complete the rental document and signed-scan approval.",
          "完成租赁文件与签章审批。",
        )
      },
    ),
    match action {
      Some((label, message)) =>
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.loading,
          on_click=command(emit, message),
          label,
        )
      None => @html.nothing
    },
    if effective && state.audience == OperatorCommerce {
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, OpenContractDocuments(order.order_id)),
        copy(state.locale, "Review undertaking", "查看承诺函"),
      )
    } else {
      @html.nothing
    },
  ])
}

///|
fn rental_quote_summary(
  locale : @i18n.Locale,
  order : @offline.CommercialOrder,
) -> @rabbita.Html {
  guard @offline.undertaking_quote_term(order) is Some(days) &&
    order.quote is Some(quote) else {
    return @html.nothing
  }
  @html.p([
    @html.strong("CNY \{quote.total.minor_units / 100L}.00"),
    @html.span(
      copy(
        locale,
        " · \{quote.lines[0].quantity} machines · \{days} days",
        " · \{quote.lines[0].quantity} 台 · \{days} 天",
      ),
    ),
  ])
}

///|
/// Keep payment review beside signing approval; no second order selection.
pub fn rental_evidence_view(
  state : OfflineCommerceState,
  order_id : String,
  emit : @rabbita.Emit[OfflineCommerceMessage]?,
) -> @rabbita.Html {
  guard state.orders.iter().find_first(order => order.order_id == order_id)
    is Some(order) &&
    order.requested_undertaking_term is Some(_) else {
    return @html.nothing
  }
  let operator = state.audience == OperatorCommerce
  let artifacts = state.artifacts.filter(artifact => {
    artifact.order_id == order_id &&
    (
      artifact.kind == PaymentReceipt ||
      (operator && artifact.kind == ExecutedContractScan)
    )
  })
  @html.section(class="rental-evidence", [
    @html.style_tag(
      ".rental-evidence button{min-height:44px;padding:.65rem .9rem;border:1px solid var(--line);border-radius:.55rem;background:var(--panel);color:var(--ink);font:inherit;cursor:pointer}.rental-evidence button:focus-visible{outline:2px solid var(--mint);outline-offset:3px}.rental-evidence button:disabled{opacity:.55;cursor:not-allowed}.rental-evidence .primary-action{border-color:var(--mint);font-weight:700}",
    ),
    @html.style_tag(
      ".rental-evidence{padding:1rem;border:1px solid var(--line);border-radius:.7rem}.rental-evidence .offline-artifact-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(18rem,100%),1fr));gap:1rem}.rental-evidence .offline-artifact-card{min-width:0;padding:1rem;border:1px solid var(--line);border-radius:.6rem}.rental-evidence dd{overflow-wrap:anywhere}.rental-evidence button{margin:.3rem}.rental-evidence .offline-confirmation{padding:1rem;border:1px solid var(--mint);border-radius:.6rem}",
    ),
    @html.h3(
      copy(state.locale, "Payment & signed evidence", "付款与签章凭证"),
    ),
    rental_quote_summary(state.locale, order),
    if operator {
      if rental_packet(state, order).map_or(false, packet => {
          packet.state == Effective
        }) {
        @html.button(
          type_="button",
          class="primary-action",
          on_click=command(emit, OpenAllocation(order_id)),
          copy(
            state.locale,
            "Check & allocate machines",
            "检查并下发机器",
          ),
        )
      } else {
        @html.nothing
      }
    } else if order.state == Fulfilled {
      @html.button(
        type_="button",
        class="primary-action",
        on_click=command(emit, OpenMachineAccess(order_id)),
        copy(state.locale, "Open company machines", "打开公司机器"),
      )
    } else if order.state == PendingInternalApproval ||
      order.state == PendingEvidenceUpload ||
      order.state == NeedsCorrection {
      @html.button(
        type_="button",
        class="secondary-action",
        disabled=state.loading,
        on_click=command(emit, RequestEvidenceUpload(order_id, PaymentReceipt)),
        copy(state.locale, "Upload payment receipt", "上传付款凭证"),
      )
    } else {
      @html.nothing
    },
    @html.div(
      class="offline-artifact-grid",
      artifacts.map(artifact => artifact_card(state, emit, artifact)),
    ),
    commerce_confirmation(state, emit),
    match state.error_message {
      Some(message) =>
        @html.p(attrs=@html.Attrs::build().role("alert"), message)
      None => @html.nothing
    },
    match state.success_message {
      Some(message) =>
        @html.p(attrs=@html.Attrs::build().role("status"), message)
      None => @html.nothing
    },
  ])
}
