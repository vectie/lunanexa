///|
fn machine_view(
  state : @nodelease.ExclusiveLeaseState,
  handoff : @nodelease.CustomerCredentialHandoffState,
) -> @nodelease.CustomerExclusiveMachineView {
  {
    version: @nodelease.contract_version,
    lease_ref: "lease-visible-1",
    machine_ref: "assigned-machine:lease-visible-1",
    state,
    generation: 4L,
    username: "alice",
    starts_unix_ms: 1000L,
    expires_unix_ms: 10000L,
    updated_unix_ms: 4000L,
    reachability: Online,
    last_seen_unix_ms: Some(4900L),
    credential_handoff: {
      state: handoff,
      handoff_ref: if handoff == Available {
        Some("lease-handoff:lease-visible-1:4")
      } else {
        None
      },
      credential_kind: "short-lived-ssh-certificate",
      valid_until_unix_ms: 10000L,
      raw_secret_included: false,
    },
    can_terminate: state == Active,
    termination_confirmation: if state == Active {
      Some("TERMINATE lease-visible-1")
    } else {
      None
    },
  }
}

///|
test "machine access view explains safe handoff and live lifecycle" {
  let state = {
    ..@machine_access.default_state(English),
    machines: [machine_view(Active, Available)],
  }
  let html = @machine_access.render(state)
  assert_true(html.contains("My machine access"))
  assert_true(html.contains("Online"))
  assert_true(html.contains("Ready to redeem"))
  assert_true(html.contains("lease-handoff:lease-visible-1:4"))
  assert_true(html.contains("No password or private key is displayed"))
  assert_false(html.contains("node_id"))
  assert_false(html.contains("access_credential_ref"))
}

///|
test "machine access confirmation is explicit and bilingual" {
  let base = {
    ..@machine_access.default_state(ChineseSimplified),
    machines: [machine_view(Active, Available)],
  }
  let confirming = base
    .update(BeginTermination("lease-visible-1"))
    .update(ConfirmationChanged("TERMINATE lease-visible-1"))
  let html = @machine_access.render(confirming)
  assert_true(html.contains("我的机器访问"))
  assert_true(html.contains("这将立即中断会话"))
  assert_true(html.contains("TERMINATE lease-visible-1"))
  assert_true(html.contains("终止访问"))
  assert_false(html.contains("class=\"danger-button\" disabled"))
}

///|
test "closing machine blocks repeat termination and handoff" {
  let state = {
    ..@machine_access.default_state(English),
    machines: [machine_view(Expiring, Closed)],
  }
  let html = @machine_access.render(state)
  assert_true(html.contains("Access is closing or closed"))
  assert_false(html.contains("End access early"))
  assert_false(html.contains("lease-handoff:"))
}

///|
test "empty machine access state is understandable" {
  let english = @machine_access.render(@machine_access.default_state(English))
  assert_true(english.contains("No exclusive machine access"))
  let chinese = @machine_access.render(
    @machine_access.default_state(ChineseSimplified),
  )
  assert_true(chinese.contains("尚未获分配独占机器访问权限"))
}
