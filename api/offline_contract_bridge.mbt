///|
priv struct OfflineContractBinding {
  packet : @contractdoc.ContractPacket
} derive(FromJson)

///|
async fn ApiService::offline_contract_generation_gate(
  self : ApiService,
  packet : @contractdoc.ContractPacket,
  now : Int64,
) -> HttpReply? {
  guard self.offline_commerce_store is Some(commerce) else {
    return Some(
      api_error(
        503, "OfflineCommerceUnavailable", "commercial document authority unavailable",
        true,
      ),
    )
  }
  let manifest = @contractdoc.manifest_for_template_id(packet.template_id)
  // Scope precedes new-order validation: preserved legacy packets remain
  // readable, but an unapproved legacy font/template cannot be re-rendered.
  if self.offline_template_approvals is Some(approvals) &&
    !approvals.any(a => {
      a.template_id == packet.template_id &&
      a.version == packet.template_version &&
      a.locale == manifest.locale &&
      a.sha256 == manifest.fillable_sha256
    }) {
    return Some(
      api_error(
        503, "TemplateApprovalScopeMissing", "the exact template version locale and digest require deployment approval",
        false,
      ),
    )
  }
  let snapshot = commerce.snapshot()
  let template = snapshot.templates
    .iter()
    .find_first(t => {
      t.template_id == packet.template_id &&
      t.version == packet.template_version &&
      t.locale == manifest.locale &&
      t.sha256 == manifest.fillable_sha256
    })
  guard template is Some(template) &&
    packet.template_sha256 == manifest.sha256 &&
    snapshot.orders.any(order => {
      order.order_id == packet.order_ref &&
      order.tenant_ref == packet.tenant_ref &&
      order.organization_id == packet.organization_id &&
      order.purchaser_subject_ref == packet.subject_ref &&
      order.quote is Some(_) &&
      order.expires_unix_ms > now &&
      (
        order.state == PendingInternalApproval ||
        order.state == PendingOfflineExecution
      )
    }) else {
    return Some(
      api_error(
        409, "ContractGenerationOrderBindingMissing", "a live matching order and registered immutable template are required",
        false,
      ),
    )
  }
  if self.offline_template_scope_gate(Some(template)) is Some(denied) {
    return Some(denied)
  }
  self.offline_readiness_gate(
    [ApprovedLegalTemplates, OoxmlWorker, PdfRenderer, CjkFonts],
    now,
  )
}

///|
async fn ApiService::enqueue_offline_contract_packet(
  self : ApiService,
  packet : @contractdoc.ContractPacket,
) -> Unit {
  guard packet.state == @contractdoc.GenerationRequested &&
    packet.values_sha256 is Some(_) &&
    self.offline_commerce_store is Some(commerce) else {
    fail("contract generation binding is incomplete")
  }
  let order = commerce.order_for_operator(packet.order_ref)
  guard order.quote is Some(quote) else { fail("contract quote missing") }
  let manifest = @contractdoc.manifest_for_template_id(packet.template_id)
  let binding : Json = { "packet": packet.to_json() }
  for kind in [@offline.EditableContractDocx, @offline.PrintReadyContractPdf] {
    let artifact_id = @offline_store.contract_archive_artifact_id(
      packet.packet_id,
      packet.revision,
      kind,
    )
    ignore(
      commerce.request_generation(
        {
          request_id: "generate-" + artifact_id,
          artifact_id,
          order_id: order.order_id,
          organization_id: packet.organization_id,
          kind,
          template_id: packet.template_id,
          template_version: packet.template_version,
          locale: manifest.locale,
          expected_object_ref: @offline_store.contract_archive_object_ref(
            packet.organization_id,
            packet.order_ref,
            packet.packet_id,
            packet.revision,
            kind,
          ),
          input_snapshot_sha256: quote.terms_digest,
          requested_by: packet.subject_ref,
          requested_unix_ms: packet.updated_unix_ms,
        },
        contract_binding=binding,
      ),
    )
  }
}

///|
async fn ApiService::complete_offline_contract_packet(
  self : ApiService,
  packet : @contractdoc.ContractPacket,
) -> Bool {
  guard packet.state == @contractdoc.GenerationRequested &&
    self.offline_commerce_store is Some(commerce) &&
    self.contract_document_store is Some(documents) else {
    return false
  }
  let snapshot = commerce.snapshot()
  let manifest = @contractdoc.manifest_for_template_id(packet.template_id)
  guard snapshot.orders.iter().find_first(o => o.order_id == packet.order_ref)
    is Some(order) &&
    order.tenant_ref == packet.tenant_ref &&
    order.organization_id == packet.organization_id &&
    order.purchaser_subject_ref == packet.subject_ref &&
    (
      order.state == PendingInternalApproval ||
      order.state == PendingOfflineExecution
    ) &&
    order.expires_unix_ms > @async.now() else {
    return false
  }
  let generated : Array[@contractdoc.ContractGeneratedArtifact] = []
  for kind in [@offline.EditableContractDocx, @offline.PrintReadyContractPdf] {
    let artifact_id = @offline_store.contract_archive_artifact_id(
      packet.packet_id,
      packet.revision,
      kind,
    )
    guard commerce.generation_plan("generate-" + artifact_id) is Some(plan) &&
      plan
      is { "contract_binding": raw_binding, "completed_result": raw_result, .. } else {
      return false
    }
    let binding : OfflineContractBinding = @json.from_json(raw_binding)
    let result : @offline.ArtifactGenerationResult = @json.from_json(raw_result)
    guard binding.packet == packet &&
      result.page_count is Some(page_count) &&
      page_count > 0 &&
      page_count <= 1000 &&
      result.verified &&
      result.render_verified &&
      !result.active_content_detected &&
      (kind != EditableContractDocx || result.moonleaf_verified) &&
      result.artifact_id == artifact_id &&
      result.request_id == "generate-" + artifact_id &&
      @offline.valid_sha256(result.visual_evidence_sha256) &&
      snapshot.artifacts.iter().find_first(a => a.artifact_id == artifact_id)
      is Some(artifact) &&
      artifact.order_id == order.order_id &&
      artifact.organization_id == packet.organization_id &&
      artifact.kind == kind &&
      artifact.template_id == Some(packet.template_id) &&
      artifact.template_version == Some(packet.template_version) &&
      artifact.locale == manifest.locale &&
      artifact.generation_state == ArtifactGenerated &&
      artifact.scan_state == ScanPassed &&
      artifact.sha256 == result.sha256 &&
      artifact.byte_count == result.byte_count &&
      artifact.object_ref == result.expected_object_ref &&
      artifact.creator_receipt == result.worker_receipt else {
      fail("contract artifact proof does not match frozen packet")
    }
    generated.push({
      artifact_id,
      media_type: result.media_type,
      sha256: result.sha256,
      byte_count: result.byte_count,
      page_count,
      render_evidence_sha256: result.visual_evidence_sha256,
      generated_unix_ms: result.completed_unix_ms,
    })
  }
  guard generated[0].page_count == generated[1].page_count else {
    fail("paired contract artifacts disagree on actual page count")
  }
  // Commerce has already durably published both exact verified objects. A
  // failure here is safely recovered by the next controller reconciliation.
  ignore(
    documents.complete_generation(
      packet.packet_id,
      packet.revision,
      generated[0],
      generated[1],
      "offline-document-dispatcher",
      @async.now(),
    ),
  )
  true
}

///|
async fn ApiService::reconcile_offline_contract_packets(
  self : ApiService,
) -> Unit {
  guard self.contract_document_store is Some(documents) else { return }
  for packet in documents.pending_generation_packets() {
    try {
      if self.complete_offline_contract_packet(packet) {
        continue
      }
      if self.offline_contract_generation_gate(packet, @async.now()) is None {
        self.enqueue_offline_contract_packet(packet)
      }
    } catch {
      _ =>
        self.alert_offline_callback_failure(
          "OfflineContractBridgePending",
          packet.packet_id,
          @async.now(),
        )
    }
  }
}
