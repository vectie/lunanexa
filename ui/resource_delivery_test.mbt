///|
test "whole node reservation requires selection and explicit idle review" {
  let empty = @ui.default_resource_delivery_panel()
  assert_false(@ui.resource_reservation_available(empty))
  let panel = {
    ..empty,
    leases: [
      {
        key: "lease-a:org-a",
        label: "User A",
        tenant_ref: "tenant-a",
        organization_id: "org-a",
        authority_ref: "grant-a",
        lease_id: "lease-a",
        expires_unix_ms: 99999L,
      },
    ],
    selected_lease: "lease-a:org-a",
    selected_nodes: ["spark-a", "spark-b"],
  }
  assert_false(@ui.resource_reservation_available(panel))
  let reviewed = panel.update(ConfirmResourceIdle)
  assert_true(@ui.resource_reservation_available(reviewed))
  assert_false(
    @ui.resource_reservation_available(
      reviewed.update(ToggleResourceNode("spark-b")),
    ),
  )
  assert_false(
    @ui.resource_reservation_available(reviewed.update(ReserveResources)),
  )
}

///|
test "undertaking allocation only enables exact quoted node count after review" {
  let empty = @ui.default_resource_delivery_panel()
  let order : @ui.UndertakingAllocationRow = {
    order_id: "order-a",
    organization_id: "org-a",
    purchaser_subject_ref: "subject-a",
    node_count: 2L,
    expires_unix_ms: Some(99999L),
    status: "ReadyForAllocation",
    node_ids: [],
  }
  let panel = {
    ..empty,
    undertaking_orders: [order],
    selected_undertaking_order: "order-a",
    undertaking_selected_nodes: ["spark-a", "spark-b"],
  }
  assert_false(@ui.undertaking_allocation_available(panel))
  let reviewed = panel.update(ConfirmUndertakingIdle)
  assert_true(@ui.undertaking_allocation_available(reviewed))
  assert_false(
    @ui.undertaking_allocation_available(
      reviewed.update(ToggleUndertakingNode("spark-b")),
    ),
  )
  assert_false(
    @ui.undertaking_allocation_available({
      ..reviewed,
      undertaking_orders: [{ ..order, status: "AwaitingApprovalOrEvidence", }],
    }),
  )
  assert_false(
    @ui.undertaking_allocation_available({
      ..reviewed,
      undertaking_orders: [{ ..order, status: "AuthorityEnded", }],
    }),
  )
  assert_false(
    @ui.undertaking_allocation_available(reviewed.update(AllocateUndertaking)),
  )
}

///|
test "undertaking and generic reservation choices never bleed across workflows" {
  let empty = @ui.default_resource_delivery_panel()
  let selected = empty.update(ToggleUndertakingNode("spark-a"))
  assert_eq(selected.undertaking_selected_nodes, ["spark-a"])
  assert_eq(selected.selected_nodes, [])
  let reviewed = selected.update(ConfirmUndertakingIdle)
  assert_true(reviewed.undertaking_confirmed_idle)
  assert_false(reviewed.confirmed_idle)
  let generic = reviewed.update(ToggleResourceNode("spark-b"))
  assert_eq(generic.undertaking_selected_nodes, ["spark-a"])
  assert_eq(generic.selected_nodes, ["spark-b"])
  assert_true(generic.undertaking_confirmed_idle)
  assert_false(generic.confirmed_idle)
  let switched = generic.update(SelectUndertakingOrder("order-b"))
  assert_eq(switched.undertaking_selected_nodes, [])
  assert_false(switched.undertaking_confirmed_idle)
  assert_eq(switched.selected_nodes, ["spark-b"])
}
