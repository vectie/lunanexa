///|
test "enterprise lease model input is trimmed and empty entries are ignored" {
  assert_eq(
    requested_models(" text.default,embedding.default ,, image.default "),
    ["text.default", "embedding.default", "image.default"],
  )
  assert_eq(requested_models(" , , "), [])
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
