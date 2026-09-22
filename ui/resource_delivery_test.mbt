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
