///|
test "rental setup preserves intent and same-company verification preserves purchase" {
  let base = demo_state()
  let organization = base.organizations[0]
  let pending = {
    ..base,
    organizations: [
      {
        ..organization,
        organization: {
          ..organization.organization,
          state: PendingVerification,
        },
      },
    ],
  }
  let setup = pending.update(Navigate(OfflineCommerce))
  assert_eq(setup.route, SelfService)
  assert_eq(setup.self_service.step, Organization)
  assert_true(setup.self_service.return_to_rental)
  let verified = { ..setup, organizations: [organization], }
  let refreshed = verified.update(
    SelfService(SelectOrganization(organization.organization.organization_id)),
  )
  assert_eq(refreshed.self_service.order, base.self_service.order)
  assert_eq(refreshed.offline_commerce.orders, base.offline_commerce.orders)
  assert_eq(
    refreshed.update(SelfService(ContinueWithOrganization)).route,
    OfflineCommerce,
  )
}

///|
test "enterprise rental carries the order through documents payment and company machines" {
  let base = demo_state()
  let packet = base.contract_documents.packets[2]
  let order = {
    ..base.offline_commerce.orders[0],
    order_id: packet.order_ref,
    tenant_ref: packet.tenant_ref,
    organization_id: packet.organization_id,
    requested_undertaking_term: Some("day"),
    state: PendingEvidenceUpload,
  }
  let ordered = {
    ..base,
    route: OfflineCommerce,
    offline_commerce: {
      ..base.offline_commerce,
      orders: [order],
      selected_order_id: Some(order.order_id),
    },
  }
  assert_true(render(ordered).contains("Open rental document"))
  let documents = ordered.update(
    OfflineCommerce(OpenContractDocuments(order.order_id)),
  )
  assert_eq(documents.route, ContractDocuments)
  assert_eq(
    documents.contract_documents.selected_packet_id,
    Some(packet.packet_id),
  )
  assert_eq(documents.contract_documents.order_context, Some(order.order_id))
  assert_true(render(documents).contains("Upload payment receipt"))
  let returned = documents.update(ContractDocuments(OpenOrder(order.order_id)))
  assert_eq(returned.offline_commerce.selected_order_id, Some(order.order_id))
  assert_eq(returned.route, OfflineCommerce)
  let approved = {
    ..returned,
    contract_documents: {
      ..returned.contract_documents,
      packets: [{ ..packet, state: Effective, }],
    },
  }
  assert_false(render(approved).contains("Open company machines"))
  assert_true(
    render(approved).contains("Machine access opens after allocation"),
  )
  let approved_document = approved.update(
    OfflineCommerce(OpenContractDocuments(order.order_id)),
  )
  assert_false(render(approved_document).contains("Open company machines"))
  assert_true(render(approved_document).contains("Upload payment receipt"))
  let allocated = {
    ..approved,
    offline_commerce: {
      ..approved.offline_commerce,
      orders: [{ ..order, state: Fulfilled, }],
    },
  }
  assert_true(render(allocated).contains("Open company machines"))
  assert_eq(
    approved.update(OfflineCommerce(OpenMachineAccess(order.order_id))).route,
    MachineAccess,
  )
}
