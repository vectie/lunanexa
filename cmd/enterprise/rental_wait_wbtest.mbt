///|
test "company approval updates in place and stale waits cannot cross companies" {
  let base = polling_fixture()
  let company = base.portal.organizations[0]
  let pending = {
    ..company,
    organization: { ..company.organization, state: PendingVerification, },
  }
  let model = {
    ..base,
    portal: {
      ..base.portal,
      route: SelfService,
      selected_organization_id: Some(company.organization.organization_id),
      organizations: [pending],
      self_service: { ..base.portal.self_service, step: Organization, },
    },
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (next, _) = apply_rental_wait(
    model,
    1L,
    company.organization.organization_id,
    5,
    Ok(Company([company])),
    emit,
  )
  assert_eq(next.portal.organizations[0].organization.state, Active)
  assert_eq(next.portal.self_service, model.portal.self_service)
  let (stale, _) = apply_rental_wait(
    model,
    0L,
    company.organization.organization_id,
    5,
    Ok(Company([company])),
    emit,
  )
  assert_true(stale == model)
  let (other, _) = apply_rental_wait(
    model,
    1L,
    "another-company",
    5,
    Ok(Company([company])),
    emit,
  )
  assert_true(other == model)
}

///|
test "scan wait retains submission date and drafts selects passed scan and stops on navigation" {
  let base = polling_fixture()
  let packet = {
    ..base.portal.contract_documents.packets[0],
    state: Generated,
    artifacts: [],
  }
  let organization = base.portal.organizations[0].organization.organization_id
  let model = {
    ..base,
    portal: {
      ..base.portal,
      selected_organization_id: Some(organization),
      contract_documents: {
        ..base.portal.contract_documents,
        packets: [packet],
        confirmation: Some(
          SubmitUndertaking(packet.packet_id, packet.revision, "", "2026-09-16"),
        ),
      },
    },
  }
  let artifact : @offline_commerce.OfflineArtifactSummary = {
    artifact_id: "signed",
    order_id: packet.order_ref,
    kind: ExecutedContractScan,
    revision: 1,
    media_type: "application/pdf",
    byte_count: 1000L,
    sha256: "sha256:" + "a".repeat(64),
    scan_state: ScanPassed,
    review_state: AwaitingReview,
    submitted_by: "subject",
    created_unix_ms: 1000L,
  }
  let emit : @rabbita.Emit[AppMessage] = Emit(_ => @rabbita.none)
  let (next, _) = apply_rental_wait(
    model,
    1L,
    organization,
    5,
    Ok(Scans([artifact])),
    emit,
  )
  assert_eq(
    next.portal.contract_documents.confirmation,
    Some(
      SubmitUndertaking(
        packet.packet_id,
        packet.revision,
        "signed",
        "2026-09-16",
      ),
    ),
  )
  assert_eq(
    next.portal.contract_documents.draft_values,
    model.portal.contract_documents.draft_values,
  )
  let away = { ..model, portal: { ..model.portal, route: Overview, }, }
  let (stale, _) = apply_rental_wait(
    away,
    1L,
    organization,
    5,
    Ok(Scans([artifact])),
    emit,
  )
  assert_true(stale == away)
  let (rejected, _) = apply_rental_wait(
    model,
    1L,
    organization,
    5,
    Ok(Scans([{ ..artifact, scan_state: ScanRejected, }])),
    emit,
  )
  assert_true(rejected.portal.contract_documents.error_message is Some(_))
  let (timeout, _) = apply_rental_wait(
    model,
    1L,
    organization,
    1,
    Ok(Scans([{ ..artifact, scan_state: AwaitingScan, }])),
    emit,
  )
  assert_true(timeout.portal.contract_documents.error_message is Some(_))
}
