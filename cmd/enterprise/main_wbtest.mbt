///|
test "enterprise lease model input is trimmed and empty entries are ignored" {
  assert_eq(
    requested_models(" text.default,embedding.default ,, image.default "),
    ["text.default", "embedding.default", "image.default"],
  )
  assert_eq(requested_models(" , , "), [])
}

///|
test "enterprise demo lease submission never claims an operator mutation" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    subject_ref: "",
    connecting: false,
    demo_mode: true,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: LeaseRequests },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let before = model.portal.lease_requests.length()
  let (submitted, _) = update(model, Portal(SubmitLease), emit)
  assert_eq(submitted.portal.lease_requests.length(), before)
  let message = submitted.portal.success_message.unwrap_or("")
  assert_true(message.contains("Demo preview only"))
  assert_true(message.contains("no lease request was submitted"))
}

///|
test "enterprise contract preview is reactive and generation fenced" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    subject_ref: "",
    connecting: false,
    demo_mode: true,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: ContractDocuments },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update(
    model,
    Portal(ContractDocuments(SelectForm(ReservationApplication))),
    emit,
  )
  assert_eq(selected.contract_preview_generation, 1L)
  assert_eq(
    selected.portal.contract_documents.selected_form,
    Some(ReservationApplication),
  )
  let (changed, _) = update(
    selected,
    Portal(
      ContractDocuments(
        FieldChanged("reservation.organization_name", "星海研究院"),
      ),
    ),
    emit,
  )
  assert_eq(changed.contract_preview_generation, 2L)
  guard changed.portal.contract_documents.preview_request() is Some(request) else {
    fail("expected current customer preview request")
  }
  let (after_stale, _) = update(changed, ContractPreviewDue(1L, request), emit)
  assert_eq(after_stale.contract_preview_generation, 2L)
  assert_eq(
    after_stale.portal.contract_documents.draft_values,
    changed.portal.contract_documents.draft_values,
  )
}

///|
test "demo machine termination mirrors the controller cleanup transition" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    subject_ref: "",
    connecting: false,
    demo_mode: true,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: MachineAccess },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (begun, _) = update(
    model,
    Portal(MachineAccess(BeginTermination("exclusive-lease-demo"))),
    emit,
  )
  let confirmation = "TERMINATE exclusive-lease-demo"
  let (typed, _) = update(
    begun,
    Portal(MachineAccess(ConfirmationChanged(confirmation))),
    emit,
  )
  let (terminated, _) = update(
    typed,
    Portal(
      MachineAccess(
        ConfirmTermination("exclusive-lease-demo", 5L, confirmation),
      ),
    ),
    emit,
  )
  let machine = terminated.portal.machine_access.machines[0]
  assert_eq(machine.state, Expiring)
  assert_eq(machine.generation, 6L)
  assert_eq(machine.credential_handoff.state, Closed)
  assert_false(machine.can_terminate)
  assert_eq(terminated.portal.machine_access.confirmation_lease_ref, None)
  assert_true(
    terminated.portal.success_message.unwrap_or("").contains("verified cleanup"),
  )
}

///|
test "demo credential redemption is explicit and never contains a secret" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    subject_ref: "",
    connecting: false,
    demo_mode: true,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: MachineAccess },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (redeemed, _) = update(
    model,
    Portal(MachineAccess(RedeemCredential("exclusive-lease-demo", 5L))),
    emit,
  )
  assert_eq(redeemed.portal.machine_access.redeemed_credentials.length(), 1)
  let credential = redeemed.portal.machine_access.redeemed_credentials[0]
  assert_eq(credential.lease_ref, "exclusive-lease-demo")
  assert_eq(credential.generation, 5L)
  assert_true(credential.one_time)
  assert_false(credential.raw_secret_included)
  assert_true(credential.issuer_redirect_url.contains(".invalid"))
  assert_false(redeemed.portal.machine_access.loading)
  assert_true(
    redeemed.portal.success_message
    .unwrap_or("")
    .contains("no credential was issued"),
  )
}

///|
test "enterprise demo machine countdown uses the snapshot clock" {
  let portal = @enterprise_ui.demo_state()
  let machine = portal.machine_access.machines[0]
  assert_true(portal.machine_access.now_unix_ms > 0L)
  assert_true(machine.expires_unix_ms > portal.machine_access.now_unix_ms)
  assert_true(
    machine.expires_unix_ms - portal.machine_access.now_unix_ms <= 86400000L,
  )
}

///|
test "enterprise demo renews the selected effective contract packet" {
  let model : AppModel = {
    endpoint: "http://127.0.0.1:4173",
    token: "",
    subject_ref: "",
    connecting: false,
    demo_mode: true,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    portal: { ..@enterprise_ui.demo_state(), route: ContractDocuments },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (selected, _) = update(
    model,
    Portal(ContractDocuments(SelectPacket("packet-demo-effective"))),
    emit,
  )
  let (begun, _) = update(
    selected,
    Portal(ContractDocuments(BeginRequestRenewal("packet-demo-effective"))),
    emit,
  )
  let (renewed, _) = update(
    begun,
    Portal(
      ContractDocuments(ConfirmAction(RequestRenewal("packet-demo-effective"))),
    ),
    emit,
  )
  assert_eq(renewed.portal.contract_documents.packets.length(), 3)
  let packet = renewed.portal.contract_documents.packets[2]
  assert_eq(
    renewed.portal.contract_documents.selected_packet_id,
    Some(packet.packet_id),
  )
  assert_eq(packet.state, InformationDraft)
  assert_eq(packet.preceding_packet_ref, Some("packet-demo-effective"))
  assert_true(packet.packet_id.has_prefix("contract-renewal-"))
}
