///|
/// Carry an order across screens without selecting another company's packet.
/// Reapplying this after a read also resolves packets that were not loaded yet.
pub fn ContractDocumentsState::open_order(
  self : ContractDocumentsState,
  order_ref : String,
  tenant_ref : String,
  template_id : String,
) -> ContractDocumentsState {
  let packets = self.packets.filter(packet => {
    packet.order_ref == order_ref && packet.tenant_ref == tenant_ref
  })
  let retained = packets
    .iter()
    .find_first(packet => Some(packet.packet_id) == self.selected_packet_id)
  let selected = match retained {
    Some(_) => retained
    None =>
      packets
      .iter()
      .find_first(packet => packet.state != Superseded && packet.state != Closed)
  }
  let selected = match selected {
    Some(_) => selected
    None => packets.get(0)
  }
  let same = selected.map_or(false, packet => {
    Some(packet.packet_id) == self.selected_packet_id
  })
  {
    ..self,
    order_context: Some(order_ref),
    creation_order_ref: order_ref,
    creation_template_id: selected.map_or(template_id, packet => {
      packet.template_id
    }),
    selected_tenant_ref: Some(tenant_ref),
    search_query: "",
    selected_packet_id: selected.map(packet => packet.packet_id),
    selected_form: selected.bind(packet => self.form_for_packet(packet)),
    draft_values: if same {
      self.draft_values
    } else {
      selected.map_or([], packet => packet.values.copy())
    },
    preview: if same {
      self.preview
    } else {
      None
    },
    confirmation: if same {
      self.confirmation
    } else {
      None
    },
  }
}

///|
pub fn ContractDocumentsState::current_order(
  self : ContractDocumentsState,
) -> String? {
  match self.order_context {
    Some(_) => self.order_context
    None => self.selected_packet().map(packet => packet.order_ref)
  }
}

///|
pub fn ContractDocumentsState::restore_order_context(
  self : ContractDocumentsState,
) -> ContractDocumentsState {
  match self.order_context {
    Some(order) =>
      self.open_order(
        order,
        self.selected_tenant_ref.unwrap_or(""),
        self.creation_template_id,
      )
    None => self
  }
}

///|
/// The focused view keeps all data in state for navigation, but renders only
/// the requested order. An empty result must never fall back to another order.
fn ContractDocumentsState::order_view(
  self : ContractDocumentsState,
) -> ContractDocumentsState {
  match self.order_context {
    Some(order) =>
      {
        ..self,
        packets: self.packets.filter(packet => {
          packet.order_ref == order &&
          Some(packet.tenant_ref) == self.selected_tenant_ref
        }),
        available_orders: self.available_orders.filter(item => item.0 == order),
        obligations: self.obligations.filter(item => {
          self.packets.any(packet => {
            packet.packet_id == item.packet_id && packet.order_ref == order
          })
        }),
        closure_proposals: self.closure_proposals.filter(item => {
          self.packets.any(packet => {
            packet.packet_id == item.packet_id && packet.order_ref == order
          })
        }),
        governance_dashboard: None,
      }
    None => self
  }
}

///|
fn rental_order_link(
  state : ContractDocumentsState,
  emit : @rabbita.Emit[ContractDocumentsMessage]?,
  order : String,
  _packet : @contractdoc.ContractPacket?,
) -> @rabbita.Html {
  @html.div(class="contract-form-navigation", [
    @html.button(
      type_="button",
      class="quiet-button",
      on_click=command(emit, OpenOrder(order)),
      copy(state.locale, "Back to rental order", "返回租赁订单"),
    ),
    @html.small(order),
    if state.order_context is Some(_) {
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, ClearOrderContext),
        copy(state.locale, "All contracts", "全部合同"),
      )
    } else {
      @html.nothing
    },
  ])
}
