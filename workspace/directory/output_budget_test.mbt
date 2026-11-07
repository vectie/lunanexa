///|
async test "output synchronization preserves active reservations counts expiry and foreign leases" {
  let temporary = @fs.tmpdir(prefix="workspace-output-test-")
  let path = temporary + "/workspace.json"
  let directory = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1000L,
  )
  ignore(directory.create_user(workspace_user("output-user", "output-subject")))
  ignore(
    directory.issue_access_grant(
      access_grant("output-grant", "output-user", Developer, 10000L),
      1000L,
    ),
  )
  let lease = workspace_lease(
    "output-lease",
    "output-subject",
    Developer,
    500L,
    10000L,
    Active,
  )
  ignore(directory.issue_lease(lease, 1000L))
  ignore(
    directory.issue_lease(
      { ..lease, lease_id: "other-lease", policy_receipt: "other-policy", },
      1000L,
    ),
  )
  assert_eq(
    directory.sync_policy_output_budget(
      lease.tenant_ref,
      lease.policy_receipt,
      16384,
      1100L,
      input_bytes=65536,
    ),
    1,
  )
  assert_eq(
    directory.sync_policy_output_budget(
      lease.tenant_ref,
      lease.policy_receipt,
      16384,
      1100L,
      input_bytes=65536,
    ),
    0,
  )
  let reopened = @directory.FileWorkspaceDirectory::open(
    path,
    now_unix_ms=1200L,
  )
  let snapshot = reopened.snapshot(1200L)
  let updated = snapshot.leases
    .iter()
    .find_first(l => l.lease_id == lease.lease_id)
    .unwrap()
  assert_eq(updated, {
    ..lease,
    limits: {
      ..lease.limits,
      capabilities: [
        {
          ..lease.limits.capabilities[0],
          max_output_units_per_request: 16384,
          max_input_units_per_request: 65536,
        },
      ],
    },
  })
  assert_eq(
    snapshot.leases.iter().find_first(l => l.lease_id == "other-lease").unwrap().limits,
    lease.limits,
  )
  assert_eq(
    reopened.sync_policy_output_budget(
      lease.tenant_ref,
      lease.policy_receipt,
      32768,
      10000L,
    ),
    0,
  )
  @fs.rmdir(temporary, recursive=true)
}
