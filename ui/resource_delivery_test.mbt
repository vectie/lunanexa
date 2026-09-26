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
    selected_nodes: ["spark-a", "spark-b"],
  }
  assert_false(@ui.undertaking_allocation_available(panel))
  let reviewed = panel.update(ConfirmResourceIdle)
  assert_true(@ui.undertaking_allocation_available(reviewed))
  assert_false(
    @ui.undertaking_allocation_available(
      reviewed.update(ToggleResourceNode("spark-b")),
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
