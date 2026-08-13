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
      handoff_ref: None,
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
  assert_true(html.contains("Redeem SSH access"))
  assert_false(html.contains("lease-handoff:lease-visible-1:4"))
  assert_false(html.contains("node_id"))
  assert_false(html.contains("access_credential_ref"))
}

///|
test "redeemed access shows safe connection metadata without raw secret" {
  let state = {
    ..@machine_access.default_state(English),
    now_unix_ms: 5000L,
    machines: [machine_view(Active, Available)],
    redeemed_credentials: [
      {
        version: @credential.contract_version,
        handoff_ref: "lnxh_safe",
        lease_ref: "lease-visible-1",
        generation: 4L,
        issuer_redirect_url: "https://ssh-ca.example/redeem/safe",
        host_alias: "machine.example",
        ssh_port: 2222,
        host_key_fingerprint: "SHA256:safehostkey",
        connection_command: "ssh -p 2222 alice@machine.example",
        valid_until_unix_ms: 10000L,
        redemption_receipt: "lnxr_safe",
        one_time: true,
        raw_secret_included: false,
      },
    ],
  }
  let html = @machine_access.render(state)
  assert_true(html.contains("machine.example"))
  assert_true(html.contains("SHA256:safehostkey"))
  assert_true(html.contains("ssh -p 2222 alice@machine.example"))
  assert_true(html.contains("href=\"https://ssh-ca.example/redeem/safe\""))
  assert_true(html.contains("Continue to credential issuer"))
  assert_false(html.contains("node_id"))
  assert_false(html.contains("private_key"))
}

///|
test "recoverable access offers the same post-reload retrieval action" {
  let state = {
    ..@machine_access.default_state(English),
    now_unix_ms: 5000L,
    machines: [machine_view(Active, Recoverable)],
  }
  let html = @machine_access.render(state)
  assert_true(html.contains("Access details recoverable"))
  assert_true(html.contains("Recover access details"))
  assert_true(html.contains("does not issue another credential"))
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
