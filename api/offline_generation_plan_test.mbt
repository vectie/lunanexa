///|
async fn generation_plan_fixture(
  directory : String,
  spreadsheet : Bool,
) -> (
  @api.ApiService,
  @offline_store.OfflineCommerceStore,
  @offline.ArtifactGenerationRequest,
) {
  let (service, store) = offline_chain_fixture(
    directory, "http://127.0.0.1:1/v1/offline-transfers",
  )
  let now = @async.now()
  let quote = offline_test_quote("plan", now)
  ignore(
    store.register_template({
      template_id: if spreadsheet {
        "offline-quote-v1"
      } else {
        "plan-contract"
      },
      version: "1",
      kind: if spreadsheet {
        QuoteScheduleTemplate
      } else {
        ContractTemplate
      },
      locale: "zh-CN",
      media_type: if spreadsheet {
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      } else {
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      },
      object_ref: if spreadsheet {
        "s3://templates/quote.xlsx"
      } else {
        "s3://templates/contract.docx"
      },
      sha256: "sha256:" + "a".repeat(64),
      byte_count: 1000L,
      active_content_allowed: false,
      created_unix_ms: now,
      superseded_unix_ms: None,
    }),
  )
  ignore(
    store.create_order({
      order_id: "order-plan",
      idempotency_key: "idempotency-plan",
      tenant_ref: "tenant-a",
      organization_id: "org-a",
      project_id: "project-a",
      purchaser_subject_ref: "subject-a",
      selected_service_code: "exclusive-dgx",
      selected_sla_code: "standard",
      policy: {
        require_executed_agreement: true,
        require_payment: true,
        invoice_timing: InvoiceBeforeFulfillment,
        require_identity_verification: false,
        require_internal_approval: true,
      },
      quote: None,
      agreement_ref: None,
      artifact_ids: [],
      entitlement_ref: None,
      requested_undertaking_term: None,
      technical_acceptance_waiver: None,
      state: Draft,
      generation: 1L,
      created_unix_ms: now,
      updated_unix_ms: now,
      expires_unix_ms: now + 3600000L,
    }),
  )
  let quoted = store.quote_order("order-plan", quote, "operator", now)
  ignore(store.begin_offline_execution("order-plan", quoted.generation, now))
  let request = store.request_generation({
    request_id: "request-plan",
    order_id: "order-plan",
    organization_id: "org-a",
    artifact_id: "artifact-plan",
    kind: if spreadsheet {
      QuoteScheduleXlsx
    } else {
      PrintReadyContractPdf
    },
    template_id: if spreadsheet {
      "offline-quote-v1"
    } else {
      "plan-contract"
    },
    template_version: "1",
    locale: "zh-CN",
    expected_object_ref: "s3://orders/order-plan/output",
    input_snapshot_sha256: quote.terms_digest,
    requested_by: "operator",
    requested_unix_ms: now,
  })
  (service, store, request)
}

///|
async test "generation plan requires machine identity persisted exact request and live claim" {
  let directory = @fs.tmpdir(prefix="lunanexa-generation-plan-")
  defer @fs.rmdir(directory, recursive=true)
  let (service, store, request) = generation_plan_fixture(directory, false)
  let path = "/v1/offline-commerce/operator/generation-plan"
  assert_eq(
    service.handle(Post, path, chain_operator(), request.to_json().stringify()).status,
    401,
  )
  let unclaimed = service.handle(
    Post,
    path,
    chain_worker(),
    request.to_json().stringify(),
  )
  assert_eq(unclaimed.status, 409)
  assert_true(unclaimed.body.contains("GenerationClaimRequired"))
  let claims = store.claim_generation_requests(@async.now())
  assert_eq(claims.length(), 1)
  let accepted = service.handle(
    Post,
    path,
    chain_worker(),
    request.to_json().stringify(),
  )
  assert_eq(accepted.status, 200)
  let plan = @json.parse(accepted.body)
  assert_true(
    plan
    is {
      "template_object_ref": String("s3://templates/contract.docx"),
      "job": { "output_filename": String("output.pdf"), .. },
      ..
    },
  )
  for
    altered in [
      { ..request, expected_object_ref: "s3://orders/other/output", },
      { ..request, organization_id: "org-other", },
      { ..request, template_version: "2", },
      { ..request, input_snapshot_sha256: "sha256:" + "b".repeat(64), },
      { ..request, requested_by: "forged-operator", },
    ] {
    let rejected = service.handle(
      Post,
      path,
      chain_worker(),
      altered.to_json().stringify(),
    )
    assert_eq(rejected.status, 409)
    assert_true(rejected.body.contains("GenerationRequestMismatch"))
  }
  let detailed : Json = {
    "request": request.to_json(),
    "markers": ["{{company_name}}"],
  }
  let missing_packet = service.handle(
    Post,
    path,
    chain_worker(),
    detailed.stringify(),
  )
  assert_eq(missing_packet.status, 409)
  assert_true(missing_packet.body.contains("GenerationInputsMissing"))
  ignore(store.expire_orders(@async.now() + 7200000L))
  let expired = service.handle(
    Post,
    path,
    chain_worker(),
    request.to_json().stringify(),
  )
  assert_eq(expired.status, 409)
  assert_true(expired.body.contains("GenerationClaimRequired"))
}

///|
async test "quote plan binds exact monetary cells and leaves total to spreadsheet formula" {
  let directory = @fs.tmpdir(prefix="lunanexa-generation-xlsx-")
  defer @fs.rmdir(directory, recursive=true)
  let (service, store, request) = generation_plan_fixture(directory, true)
  ignore(store.claim_generation_requests(@async.now()))
  let response = service.handle(
    Post,
    "/v1/offline-commerce/operator/generation-plan",
    chain_worker(),
    request.to_json().stringify(),
  )
  assert_eq(response.status, 200)
  let body = @json.parse(response.body)
  guard body
    is {
      "job": {
        "xlsx_replacements": Array(cells),
        "docx_replacements": Array(docx),
        ..
      },
      ..
    } else {
    fail("missing typed replacement plan")
  }
  assert_eq(docx.length(), 0)
  assert_eq(cells.length(), 7)
  assert_true(
    cells.contains({
      "sheet_name": "Quote",
      "row": 2,
      "column": 2,
      "value": "order-plan",
    }),
  )
  assert_true(
    cells.contains({
      "sheet_name": "Quote",
      "row": 3,
      "column": 2,
      "value": "org-a",
    }),
  )
  assert_false(cells.any(cell => cell is { "row": Number(8, ..), .. }))
}
