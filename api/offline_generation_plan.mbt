///|
priv struct OfflineGenerationPlanRequest {
  request : @offline.ArtifactGenerationRequest
  markers : Array[String]
} derive(FromJson)

///|
fn offline_generation_packet(
  packets : Array[@contractdoc.ContractPacket],
  order : @offline.CommercialOrder,
  template : @offline.DocumentTemplate,
) -> @contractdoc.ContractPacket? {
  let manifest = @contractdoc.manifest_for_template_id(template.template_id)
  guard manifest.template_id == template.template_id &&
    manifest.template_version == template.version &&
    manifest.fillable_sha256 == template.sha256 else {
    return None
  }
  let candidates = packets.filter(packet => {
    packet.tenant_ref == order.tenant_ref &&
    packet.organization_id == order.organization_id &&
    packet.subject_ref == order.purchaser_subject_ref &&
    packet.order_ref == order.order_id &&
    packet.template_id == template.template_id &&
    packet.template_version == template.version &&
    packet.template_sha256 == manifest.sha256 &&
    packet.state == @contractdoc.GenerationRequested &&
    order.agreement_ref.map_or(true, id => id == packet.packet_id)
  })
  // An explicit old binding is never replaced; an unbound order must have
  // exactly one fully scoped generation-requested packet, not "latest wins".
  if candidates.length() == 1 {
    Some(candidates[0])
  } else {
    None
  }
}

///|
/// The dispatcher first discovers immutable template metadata. After fetching
/// and digest-verifying that template, it submits its exact physical markers.
/// Values come only from the order-linked, tenant-bound document packet.
async fn ApiService::offline_generation_plan(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard verb == Post &&
    self.artifact_worker_callback_token is Some(token) &&
    bearer_authorized(headers, token) else {
    return api_error(
      401, "Unauthenticated", "artifact dispatcher authority required", false,
    )
  }
  let detailed : OfflineGenerationPlanRequest? = decode_offline(body)
  let decoded : @offline.ArtifactGenerationRequest? = match detailed {
    Some(value) => Some(value.request)
    None => decode_offline(body)
  }
  guard decoded is Some(request) && self.offline_commerce_store is Some(store) else {
    return api_error(
      400, "InvalidRequest", "invalid generation plan request", false,
    )
  }
  let snapshot = store.snapshot()
  guard snapshot.generation_requests.any(value => value == request) else {
    return api_error(
      409, "GenerationRequestMismatch", "only persisted generation work can be executed",
      false,
    )
  }
  guard snapshot.orders
    .iter()
    .find_first(order => order.order_id == request.order_id)
    is Some(order) &&
    snapshot.templates
    .iter()
    .find_first(template => {
      template.template_id == request.template_id &&
      template.version == request.template_version
    })
    is Some(template) &&
    snapshot.work_claims.any(claim => {
      claim.work_id == "artifact:\{request.request_id}" &&
      claim.attempt > 0 &&
      claim.completed_unix_ms is None &&
      claim.expected_order_generation == order.generation
    }) else {
    return api_error(
      409, "GenerationClaimRequired", "a current matching dispatcher claim is required",
      true,
    )
  }
  guard order.organization_id == request.organization_id &&
    order.quote is Some(quote) &&
    quote.terms_digest == request.input_snapshot_sha256 &&
    template.locale == request.locale else {
    return api_error(
      409, "GenerationBindingMismatch", "order quote and template bindings must match",
      false,
    )
  }
  if self.offline_template_scope_gate(Some(template)) is Some(denied) {
    return denied
  }
  let retained = store.generation_plan(request.request_id)
  let binding : OfflineContractBinding? = match retained {
    Some({ "contract_binding": raw, .. }) => Some(@json.from_json(raw))
    _ => None
  }
  if binding is Some(binding) {
    guard self.contract_document_store is Some(documents) &&
      documents.packet(binding.packet.packet_id) == Some(binding.packet) &&
      offline_generation_packet([binding.packet], order, template) is Some(_) else {
      return api_error(
        409, "ContractGenerationRevisionChanged", "the frozen contract revision is no longer current",
        false,
      )
    }
  }
  if retained is Some(frozen) && frozen is { "job": _, .. } {
    return json_reply(200, frozen)
  }
  let docx_replacements : Array[Json] = []
  let xlsx_replacements : Array[Json] = []
  if request.kind == @offline.QuoteScheduleXlsx {
    guard template.template_id == "offline-quote-v1" && template.version == "1" else {
      return api_error(
        409, "UnsupportedQuoteTemplate", "quote template has no approved cell binding",
        false,
      )
    }
    if quote.subtotal.minor_units < 0L ||
      quote.tax.minor_units < 0L ||
      quote.total.minor_units < 0L ||
      quote.total.minor_units > 9007199254740991L ||
      quote.subtotal.minor_units > 9007199254740991L ||
      quote.tax.minor_units > 9007199254740991L ||
      quote.subtotal.minor_units + quote.tax.minor_units !=
      quote.total.minor_units ||
      quote.subtotal.scale != quote.total.scale ||
      quote.tax.scale != quote.total.scale {
      return api_error(
        409, "QuoteSpreadsheetPrecision", "quote cannot be represented exactly by the spreadsheet profile",
        false,
      )
    }
    for
      (row, value) in [
        (2, order.order_id),
        (3, order.organization_id),
        (4, quote.quote_id),
        (5, quote.currency),
        (6, quote.subtotal.minor_units.to_string()),
        (7, quote.tax.minor_units.to_string()),
        (9, quote.total.scale.to_string()),
      ] {
      xlsx_replacements.push({
        "sheet_name": "Quote",
        "row": row,
        "column": 2,
        "value": value,
      })
    }
  }
  if request.kind != @offline.QuoteScheduleXlsx && detailed is Some(input) {
    guard input.markers.length() > 0 &&
      input.markers.length() <= 512 &&
      self.contract_document_store is Some(documents) &&
      offline_generation_packet(
        match binding {
          Some(binding) => [binding.packet]
          None => documents.packets_for_subject(order.purchaser_subject_ref)
        },
        order,
        template,
      )
      is Some(packet) else {
      return api_error(
        409, "GenerationInputsMissing", "link a matching completed document packet to this order",
        false,
      )
    }
    let replacements = try packet.marker_replacements(input.markers) catch {
      _ =>
        return api_error(
          409, "GenerationInputsIncomplete", "document fields do not resolve all template markers",
          false,
        )
    } noraise {
      value => value
    }
    for replacement in replacements {
      docx_replacements.push({
        "placeholder": replacement.field_id,
        "value": replacement.value,
      })
    }
  }
  let xlsx = request.kind == @offline.QuoteScheduleXlsx
  let source_suffix = if xlsx { "xlsx" } else { "docx" }
  let output_suffix = if request.kind == @offline.PrintReadyContractPdf {
    "pdf"
  } else {
    source_suffix
  }
  let base_plan : Json = {
    "template_object_ref": template.object_ref,
    "template_sha256": template.sha256,
    "job": {
      "schema_version": 1,
      "request": request.to_json(),
      "template_filename": "template.\{source_suffix}",
      "prepared_filename": "prepared.\{source_suffix}",
      "output_filename": "output.\{output_suffix}",
      "result_filename": "result.json",
      "render_manifest_filename": "render.json",
      "docx_replacements": docx_replacements.to_json(),
      "xlsx_replacements": xlsx_replacements.to_json(),
    },
  }
  let plan = match (base_plan, retained) {
    (Object(fields), Some({ "contract_binding": raw, .. })) => {
      fields["contract_binding"] = raw
      fields.to_json()
    }
    _ => base_plan
  }
  if detailed is Some(_) || xlsx {
    let frozen = try store.retain_generation_plan(request, plan) catch {
      error => return offline_error_reply(error)
    } noraise {
      value => value
    }
    json_reply(200, frozen)
  } else {
    json_reply(200, plan)
  }
}
