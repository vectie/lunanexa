///|
test "download digest remains available without secure-context WebCrypto" {
  assert_eq(
    offline_download_digest(b"abc"),
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(
    offline_download_digest(b""),
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    download_digest_bridge(offline_download_digest),
    offline_download_digest(b"abc"),
  )
}

///|
extern "js" fn download_digest_bridge(digest : (Bytes) -> String) -> String =
  #| digest => digest(new Uint8Array([97, 98, 99]))

///|
fn polling_fixture() -> AppModel {
  let portal = @enterprise_ui.demo_state()
  let packet = {
    ..portal.contract_documents.packets[0],
    state: @contractdoc.ContractPacketState::GenerationRequested,
  }
  {
    endpoint: "",
    token: "lnxs_test",
    csrf_token: "",
    subject_ref: "test",
    connecting: false,
    bootstrap_started: true,
    demo_mode: false,
    session_generation: 0L,
    session_expires_unix_ms: None,
    machine_clock_generation: 0L,
    contract_preview_generation: 0L,
    contract_poll_generation: 1L,
    portal: {
      ..portal,
      route: ContractDocuments,
      contract_documents: {
        ..portal.contract_documents,
        packets: [packet],
        selected_packet_id: Some(packet.packet_id),
      },
    },
    login_email: "",
    login_password: "",
    register_display_name: "",
    registering: false,
  }
}

///|
test "contract generation polling converges without replacing local edits" {
  let model = polling_fixture()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let packet = model.portal.contract_documents.packets[0]
  let generated = {
    ..packet,
    state: @contractdoc.ContractPacketState::Generated,
  }
  let (next, _) = update(
    model,
    ContractPollResult(1L, packet.packet_id, 20, Ok([generated])),
    emit,
  )
  assert_eq(next.portal.contract_documents.packets[0].state, Generated)
  assert_eq(
    next.portal.contract_documents.draft_values,
    model.portal.contract_documents.draft_values,
  )
  assert_eq(
    next.portal.contract_documents.selected_form,
    model.portal.contract_documents.selected_form,
  )
  assert_true(next.portal.contract_documents.success_message is Some(_))
  let (failed, _) = update(
    model,
    ContractPollResult(
      1L,
      packet.packet_id,
      20,
      Ok([{ ..packet, state: GenerationFailed, }]),
    ),
    emit,
  )
  assert_true(failed.portal.contract_documents.error_message is Some(_))
  let (timeout, _) = update(
    model,
    ContractPollResult(1L, packet.packet_id, 1, Ok([packet])),
    emit,
  )
  assert_true(timeout.portal.contract_documents.error_message is Some(_))
}

///|
test "stale generation responses are ignored across navigation organization logout and selection" {
  let model = polling_fixture()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let packet = model.portal.contract_documents.packets[0]
  for
    stale in [
      { ..model, contract_poll_generation: 2L, },
      { ..model, token: "", },
      { ..model, portal: { ..model.portal, route: SelfService, }, },
      {
        ..model,
        portal: {
          ..model.portal,
          contract_documents: {
            ..model.portal.contract_documents,
            selected_packet_id: Some("different"),
          },
        },
      },
    ] {
    let (next, _) = update(
      stale,
      ContractPollResult(
        1L,
        packet.packet_id,
        20,
        Ok([{ ..packet, state: Generated, }]),
      ),
      emit,
    )
    assert_true(next == stale)
  }
  let (network, _) = update(
    model,
    ContractPollResult(1L, packet.packet_id, 20, Err("unavailable")),
    emit,
  )
  assert_true(network.portal.contract_documents.error_message is Some(_))
}

///|
test "navigation and organization events invalidate generation polls and duplicate requests are ignored" {
  let model = polling_fixture()
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let packet = model.portal.contract_documents.packets[0]
  let (navigated, _) = update(model, Portal(Navigate(SelfService)), emit)
  assert_true(
    navigated.contract_poll_generation > model.contract_poll_generation,
  )
  let (switched, _) = update(
    model,
    Portal(SelfService(SelectOrganization("different"))),
    emit,
  )
  assert_true(
    switched.contract_poll_generation > model.contract_poll_generation,
  )
  let (logout, _) = update(model, Logout, emit)
  assert_true(logout.contract_poll_generation > model.contract_poll_generation)
  let (duplicate, _) = update(
    model,
    Portal(
      ContractDocuments(
        ConfirmAction(
          RequestGeneration(packet.packet_id, packet.revision, "digest"),
        ),
      ),
    ),
    emit,
  )
  assert_true(duplicate == model)
}
