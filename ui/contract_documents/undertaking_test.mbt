///|
fn undertaking_packet(
  state : @contractdoc.ContractPacketState,
) -> @contractdoc.ContractPacket raise {
  let manifest = @contractdoc.undertaking_manifest()
  let packet = @contractdoc.new_packet(
    manifest,
    "undertaking-ui",
    "undertaking-ui-key",
    "tenant-a",
    "org-a",
    "subject-a",
    "order-a",
    None,
    [MasterLease],
    1000L,
  )
  { ..packet, state, }
}

///|
test "OFL creation option coexists with original packets without silently upgrading them" {
  let legacy = @contractdoc.undertaking_manifest()
  let current = @contractdoc.undertaking_ofl_manifest()
  let state = {
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(current),
    available_manifests: [current, legacy],
    creation_template_id: current.template_id,
    packets: [undertaking_packet(InformationDraft)],
    selected_packet_id: Some("undertaking-ui"),
    selected_form: Some(MasterLease),
  }
  assert_eq(state.current_manifest(), Some(legacy))
  let html = @contract_documents.render(state)
  assert_true(html.contains("开源字体新版"))
  assert_true(html.contains("原版 · 历史订单"))
  assert_true(
    html.contains("value=\"youthpolicy-device-undertaking-ofl-v2\" selected"),
  )
  let selected = state.update(SelectCreationTemplate(legacy.template_id))
  assert_eq(selected.creation_template_id, legacy.template_id)
  assert_eq(selected.current_manifest(), Some(legacy))
}

///|
test "undertaking template selection reuses source editor without legacy template leakage" {
  let undertaking = @contractdoc.undertaking_manifest()
  let state = {
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(@contractdoc.youthpolicy_remote_lease_manifest()),
    available_manifests: [
      @contractdoc.youthpolicy_remote_lease_manifest(),
      undertaking,
    ],
    packets: [undertaking_packet(InformationDraft)],
    selected_packet_id: Some("undertaking-ui"),
    selected_form: Some(MasterLease),
  }
  assert_eq(state.current_manifest(), Some(undertaking))
  let html = @contract_documents.render(state)
  assert_true(html.contains("设备使用承诺函"))
  assert_true(html.contains("甲方负责确认关联订单的租期与金额"))
  assert_false(html.contains("源合同包：7 份表单 · 18 页"))
  assert_true(state.preview_request() is Some(_))
}

///|
test "missing undertaking manifest fails closed instead of displaying bilateral contract" {
  let state = {
    ..@contract_documents.default_state(English),
    manifest: Some(@contractdoc.youthpolicy_remote_lease_manifest()),
    packets: [undertaking_packet(InformationDraft)],
    selected_packet_id: Some("undertaking-ui"),
    selected_form: Some(MasterLease),
  }
  assert_eq(state.current_manifest(), None)
  assert_true(state.preview_request() is None)
  assert_true(
    @contract_documents.render(state).contains("Contract template unavailable"),
  )
}

///|
test "undertaking order selection filters tariffs and resets on path changes" {
  let manifest = @contractdoc.undertaking_manifest()
  let state = {
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(manifest),
    available_manifests: [manifest],
    creation_template_id: manifest.template_id,
    available_orders: [
      ("order-a", "符合条件的订单"),
      ("order-b", "不符合条件的订单"),
    ],
    undertaking_order_refs: ["order-a"],
  }
  let html = @contract_documents.render(state)
  assert_true(html.contains("符合条件的订单"))
  assert_false(html.contains("不符合条件的订单"))
  let changed = state
    .update(SelectCreationOrder("order-a"))
    .update(SelectCreationTemplate("other"))
  assert_eq(changed.creation_order_ref, "")
}

///|
test "undertaking separates tenant submission from operator approval and renewal" {
  let generated = undertaking_packet(Generated)
  let tenant = @contract_documents.contract_packet_capabilities(
    generated,
    CustomerMessenger,
  )
  assert_true(tenant.contains(SubmitUndertaking))
  assert_true(tenant.contains(ReviseUndertaking))
  assert_false(tenant.contains(RegisterExecution))
  let operator = @contract_documents.contract_packet_capabilities(
    generated,
    ManagerOperator,
  )
  assert_false(operator.contains(RegisterExecution))
  assert_false(operator.contains(SubmitUndertaking))
  assert_false(
    @contract_documents.contract_packet_capabilities(
      undertaking_packet(Effective),
      CustomerMessenger,
    ).contains(RequestRenewal),
  )
}

///|
test "undertaking signed evidence is selected from same order rather than a typed digest" {
  let manifest = @contractdoc.undertaking_manifest()
  let state = {
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(manifest),
    packets: [undertaking_packet(Generated)],
    selected_packet_id: Some("undertaking-ui"),
    signed_artifacts: [
      ("order-a", "scan-a", "本订单扫描件", 1000L),
      ("other", "scan-secret", "其他组织文件", 1000L),
    ],
  }.update(BeginSubmitUndertaking("undertaking-ui", 1L))
  let html = @contract_documents.render(state)
  assert_true(html.contains("本订单扫描件"))
  assert_false(html.contains("其他组织文件"))
  assert_false(html.contains("scan-secret"))
  assert_true(html.contains("上传签章扫描件"))
  assert_false(html.contains("contract-confirm-evidence"))
  let changed = state
    .update(ConfirmationInputChanged(EvidenceDigest, "scan-a"))
    .update(ConfirmationInputChanged(SignedOn, "2026-09-16"))
  assert_eq(
    changed.confirmation,
    Some(SubmitUndertaking("undertaking-ui", 1L, "scan-a", "2026-09-16")),
  )
}

///|
test "undertaking revision makes invalidation clear before submission" {
  let state = @contract_documents.default_state(ChineseSimplified).update(
    BeginReviseUndertaking("undertaking-ui", 3L),
  )
  let html = @contract_documents.render(state)
  assert_true(html.contains("旧扫描件不能授权新版本"))
  assert_true(html.contains("role=\"alertdialog\""))
  assert_eq(state.update(DismissConfirmation).confirmation, None)
}

///|
test "undertaking evidence picker excludes scans older than current generation" {
  let packet = {
    ..undertaking_packet(Generated),
    artifacts: [
      {
        artifact_id: "generated-docx",
        media_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        sha256: "sha256:" + "a".repeat(64),
        byte_count: 100L,
        page_count: 4,
        render_evidence_sha256: "sha256:" + "b".repeat(64),
        generated_unix_ms: 2000L,
      },
    ],
  }
  let state = {
    ..@contract_documents.default_state(English),
    manifest: Some(@contractdoc.undertaking_manifest()),
    packets: [packet],
    selected_packet_id: Some(packet.packet_id),
    signed_artifacts: [
      ("order-a", "old-scan", "STALE SCAN", 1000L),
      ("order-a", "new-scan", "CURRENT SCAN", 3000L),
    ],
  }.update(BeginSubmitUndertaking(packet.packet_id, packet.revision))
  let html = @contract_documents.render(state)
  assert_false(html.contains("STALE SCAN"))
  assert_true(html.contains("CURRENT SCAN"))
  assert_true(html.contains("Download verified DOCX"))
  let operator = { ..state, actor_owner: ManagerOperator, }
  assert_true(
    @contract_documents.render(operator).contains("Download verified DOCX"),
  )
}

///|
test "both rental routes are listed and the contract route stays disabled while offline" {
  let state = {
    ..@contract_documents.default_state(ChineseSimplified),
    manifest: Some(@contractdoc.undertaking_manifest()),
    available_manifests: [
      @contractdoc.youthpolicy_remote_lease_manifest(),
      @contractdoc.undertaking_manifest(),
    ],
    selected_form: Some(MasterLease),
  }
  let html = @contract_documents.render(state)
  // The undertaking route is offered and selectable.
  assert_true(html.contains("设备使用承诺函 · 甲方审批"))
  // The contract route is still visible so the choice is discoverable, but
  // carries its unavailability and is never rendered as a selectable entry.
  assert_true(
    html.contains("传统租赁合同 · 双方签署（暂未开放）"),
  )
  assert_false(html.contains("传统租赁合同 · 双方签署</option>"))
  assert_false(@contract_documents.traditional_contract_route_available)
}

///|
test "frozen previews never replay stale role drafts" {
  let manifest = @contractdoc.undertaking_manifest()
  let states : Array[@contractdoc.ContractPacketState] = [
    GenerationRequested,
    Generated,
    GenerationFailed,
    Effective,
    Closed,
    Superseded,
  ]
  for lifecycle in states {
    let packet = undertaking_packet(lifecycle)
    let state = {
      ..@contract_documents.default_state(ChineseSimplified),
      manifest: Some(manifest),
      actor_owner: ManagerOperator,
      packets: [packet],
      selected_packet_id: Some(packet.packet_id),
      selected_form: Some(MasterLease),
      draft_values: [
        { field_id: "lease.start_date", value: "stale-unsaved-value", },
      ],
    }
    guard state.preview_request()
      is Some(RequestPreview(_, revision, _, changes)) else {
      fail("frozen packet should remain previewable")
    }
    assert_eq(revision, packet.revision)
    assert_eq(changes.length(), 0)
  }
}
