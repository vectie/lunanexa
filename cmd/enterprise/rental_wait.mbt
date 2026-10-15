///|
priv enum RentalWaitResult {
  Company(Array[@enterprise_ui.SelfServiceOrganizationView])
  Scans(Array[@offline_commerce.OfflineArtifactSummary])
}

///|
fn rental_wait_active(
  model : AppModel,
  generation : Int64,
  organization : String,
) -> Bool {
  !model.demo_mode &&
  !model.token.is_empty() &&
  model.contract_poll_generation == generation &&
  model.portal.selected_organization_id == Some(organization) &&
  (
    (
      model.portal.route == SelfService &&
      model.portal.self_service.step == Organization
    ) ||
    (
      model.portal.route == ContractDocuments &&
      model.portal.contract_documents.confirmation
      is Some(SubmitUndertaking(_, _, _, _))
    )
  )
}

///|
fn rental_wait_timer(
  model : AppModel,
  remaining : Int,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  let generation = model.contract_poll_generation
  let organization = model.portal.selected_organization_id.unwrap_or("")
  @rabbita.perform(message => emit(message), async fn() noraise {
    ignore(contract_preview_delay_promise(3000).wait()) catch {
      _ => ()
    }
    RentalWaitDue(generation, organization, remaining)
  })
}

///|
fn start_rental_wait(
  model : AppModel,
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  let pending_company = model.portal.organizations.any(value => {
    Some(value.organization.organization_id) ==
    model.portal.selected_organization_id &&
    value.organization.state == PendingVerification
  })
  let scan = model.portal.route == ContractDocuments &&
    model.portal.contract_documents.confirmation
    is Some(SubmitUndertaking(_, _, _, _))
  if !pending_company && !scan {
    return (model, @rabbita.none)
  }
  let next = {
    ..model,
    contract_poll_generation: model.contract_poll_generation + 1L,
  }
  if rental_wait_active(
      next,
      next.contract_poll_generation,
      next.portal.selected_organization_id.unwrap_or(""),
    ) {
    (next, rental_wait_timer(next, 100, emit))
  } else {
    (next, @rabbita.none)
  }
}

///|
fn rental_wait_request(
  model : AppModel,
  generation : Int64,
  organization : String,
  remaining : Int,
  emit : @rabbita.Emit[AppMessage],
) -> @rabbita.Cmd {
  @rabbita.perform(message => emit(message), async fn() noraise {
    let result = try {
      if model.portal.route == SelfService {
        Ok(Company(load_self_service_organizations(model)))
      } else {
        let orders : Array[@offline.CommercialOrder] = @json.from_json(
          @json.parse(
            request(
              "GET",
              model.endpoint,
              "/v1/offline-commerce/self/orders",
              model.token,
              model.subject_ref,
            ),
          ),
        )
        let packet = model.portal.contract_documents.packets
          .iter()
          .find_first(packet => {
            Some(packet.packet_id) ==
            model.portal.contract_documents.selected_packet_id
          })
        let artifacts : Array[@offline_commerce.OfflineArtifactSummary] = []
        for order in orders {
          if !packet.map_or(false, packet => packet.order_ref == order.order_id) {
            continue
          }
          for id in order.artifact_ids {
            let value : OfflineArtifactView = @json.from_json(
              @json.parse(
                request(
                  "GET",
                  model.endpoint,
                  "/v1/offline-commerce/self/artifacts/\{id}",
                  model.token,
                  model.subject_ref,
                ),
              ),
            )
            artifacts.push({
              artifact_id: value.artifact_id,
              order_id: value.order_id,
              kind: value.kind,
              revision: value.revision,
              media_type: value.media_type,
              byte_count: value.byte_count,
              sha256: value.sha256,
              scan_state: value.scan_state,
              review_state: value.review_state,
              submitted_by: "customer-evidence",
              created_unix_ms: value.created_unix_ms,
            })
          }
        }
        Ok(Scans(artifacts))
      }
    } catch {
      _ => Err("refresh_failed")
    }
    RentalWaitLoaded(generation, organization, remaining, result)
  })
}

///|
fn apply_rental_wait(
  model : AppModel,
  generation : Int64,
  organization : String,
  remaining : Int,
  result : Result[RentalWaitResult, String],
  emit : @rabbita.Emit[AppMessage],
) -> (AppModel, @rabbita.Cmd) {
  guard rental_wait_active(model, generation, organization) else {
    return (model, @rabbita.none)
  }
  let mut pending = false
  let next = match result {
    Ok(Company(organizations)) if model.portal.route == SelfService => {
      pending = organizations.any(value => {
        value.organization.organization_id == organization &&
        value.organization.state == PendingVerification
      })
      { ..model, portal: { ..model.portal, organizations, }, }
    }
    Ok(Scans(artifacts)) if model.portal.route == ContractDocuments => {
      pending = !artifacts.any(artifact => artifact.kind == ExecutedContractScan) ||
        artifacts.any(artifact => {
          artifact.kind == ExecutedContractScan &&
          artifact.scan_state == AwaitingScan
        })
      let documents = model.portal.contract_documents
      let signed = artifacts.filter(artifact => {
        artifact.kind == ExecutedContractScan &&
        artifact.scan_state == ScanPassed &&
        artifact.review_state != ReviewRejected
      })
      let documents = {
        ..documents,
        signed_artifacts: [
          ..documents.signed_artifacts.filter(item => {
            !artifacts.any(artifact => artifact.order_id == item.0)
          }),
          ..signed.map(artifact => {
            (
              artifact.order_id,
              artifact.artifact_id,
              "v\{artifact.revision}",
              artifact.created_unix_ms,
            )
          }),
        ],
        loading: false,
        success_message: if pending {
          Some(
            portal_copy(
              model.portal.locale,
              "Checking the uploaded scan…",
              "正在检查上传的扫描件…",
            ),
          )
        } else if !signed.is_empty() {
          Some(
            portal_copy(
              model.portal.locale,
              "Scan ready. Confirm the signing date to submit.",
              "扫描件已就绪，请确认签署日期并提交。",
            ),
          )
        } else {
          None
        },
        error_message: if !pending && signed.is_empty() {
          Some(
            portal_copy(
              model.portal.locale,
              "The scan was rejected. Upload a corrected file.",
              "扫描件未通过检查，请重新上传。",
            ),
          )
        } else {
          None
        },
      }
      let documents = if pending {
        documents
      } else {
        documents.select_only_signed_scan()
      }
      { ..model, portal: { ..model.portal, contract_documents: documents, }, }
    }
    _ => model
  }
  if pending && remaining > 1 {
    return (next, rental_wait_timer(next, remaining - 1, emit))
  }
  if pending || result is Err(_) {
    let notice = portal_copy(
      model.portal.locale,
      "Automatic check paused. Refresh to try again.",
      "自动检查已暂停，请刷新重试。",
    )
    return (
      {
        ..next,
        portal: {
          ..next.portal,
          contract_documents: {
            ..next.portal.contract_documents,
            error_message: Some(notice),
          },
          self_service: {
            ..next.portal.self_service,
            action_error: Some(notice),
          },
        },
      },
      @rabbita.none,
    )
  }
  if result is Ok(Company(_)) {
    (next, load_command(next, emit))
  } else {
    (next, @rabbita.none)
  }
}
