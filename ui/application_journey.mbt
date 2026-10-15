///|
/// These links select existing authority. They never create a grant, reserve a
/// node or start an application as a side effect of navigation.
pub fn ConsoleState::open_access_step(
  self : ConsoleState,
  account_id : String,
  organization_id : String,
  route : OperatorRoute,
) -> ConsoleState {
  guard !self.loading &&
    (
      route == Users ||
      route == Leases ||
      route == Catalog ||
      route == ContractDocuments
    ) else {
    return self
  }
  guard self.access_packages
    .iter()
    .find_first(item => {
      item.account_id == account_id && item.organization_id == organization_id
    })
    is Some(item) else {
    return self
  }
  if route == Leases && item.lease_id is None {
    return self
  }
  let resources = if route == Leases {
    {
      ..self.resource_delivery,
      selected_lease: item.lease_id.unwrap_or("") + ":" + item.organization_id,
      selected_nodes: [],
      confirmed_idle: false,
      reservation_id: "",
      selected_undertaking_order: "",
    }
  } else {
    self.resource_delivery
  }
  let documents = if route == ContractDocuments {
    {
      ..self.contract_documents.update(SelectTenant(item.tenant_ref)),
      order_context: None,
      search_query: "",
    }
  } else {
    self.contract_documents
  }
  {
    ..self,
    route,
    access_package_context: Some((account_id, organization_id)),
    resource_delivery: resources,
    contract_documents: documents,
  }
}

///|
fn access_context_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  guard state.access_package_context is Some((account_id, organization_id)) &&
    (
      state.route == Users ||
      state.route == Leases ||
      state.route == Catalog ||
      state.route == ContractDocuments
    ) else {
    return @html.nothing
  }
  let item = state.access_packages
    .iter()
    .find_first(item => {
      item.account_id == account_id && item.organization_id == organization_id
    })
  @html.section(class="operation-panel", [
    @html.div(class="section-heading", [
      @html.strong(
        item.map_or(
          localized(
            state.locale,
            "Access package unavailable",
            "访问权限记录不可用",
          ),
          item => "\{item.display_name} · \{item.organization_id}",
        ),
      ),
      if state.route != Users && item is Some(_) {
        @html.button(
          type_="button",
          class="quiet-button",
          disabled=state.loading,
          on_click=command(
            emit,
            OpenAccessStep(account_id, organization_id, Users),
          ),
          localized(state.locale, "Back to user access", "返回用户权限"),
        )
      } else {
        @html.nothing
      },
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, ClearAccessContext),
        if state.route == Users {
          localized(state.locale, "All users", "全部用户")
        } else if state.route == Leases {
          localized(state.locale, "All resources", "全部资源")
        } else {
          localized(state.locale, "Clear user focus", "取消用户筛选")
        },
      ),
    ]),
    if state.route == Users {
      item.map_or(@html.nothing, item => access_package_card(state, item, emit))
    } else {
      @html.nothing
    },
  ])
}
