///|
fn valid_id(value : String) -> Bool {
  @contracts.valid_identifier(value)
}

///|
fn valid_label(value : String, maximum : Int) -> Bool {
  value.length() > 0 &&
  value.length() <= maximum &&
  value.all(character => {
    character.is_printable() && character != '<' && character != '>'
  })
}

///|
pub fn valid_sha256(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].all(character => character.is_ascii_hexdigit())
}

///|
pub fn valid_object_ref(value : String) -> Bool {
  value.length() >= 8 &&
  value.length() <= 512 &&
  (value.has_prefix("s3://") || value.has_prefix("object://")) &&
  !value.contains("..") &&
  !value.contains("\\") &&
  !value.contains_char('\n') &&
  !value.contains_char('\r')
}

///|
fn validate_money(
  value : @commercial.FixedMoney,
  currency : String,
) -> Unit raise OfflineCommerceError {
  if value.currency != currency ||
    value.scale < 0 ||
    value.scale > 6 ||
    value.minor_units < 0L {
    raise InvalidInput("invalid quote money")
  }
}

///|
pub fn validate_quote(
  quote : ImmutableQuote,
) -> Unit raise OfflineCommerceError {
  if !valid_id(quote.quote_id) ||
    !valid_id(quote.version) ||
    !valid_id(quote.service_code) ||
    !valid_id(quote.sla_code) ||
    !valid_id(quote.currency) ||
    quote.lines.length() == 0 ||
    quote.lines.length() > 1000 ||
    quote.valid_until_unix_ms <= quote.created_unix_ms ||
    quote.created_unix_ms <= 0L ||
    !valid_sha256(quote.terms_digest) {
    raise InvalidInput("invalid immutable quote")
  }
  validate_money(quote.subtotal, quote.currency)
  validate_money(quote.tax, quote.currency)
  validate_money(quote.total, quote.currency)
  let mut subtotal = 0L
  for line in quote.lines {
    if !valid_id(line.line_id) ||
      !valid_label(line.description, 500) ||
      !valid_id(line.unit) ||
      line.quantity <= 0L {
      raise InvalidInput("invalid quote line")
    }
    validate_money(line.unit_price, quote.currency)
    validate_money(line.line_total, quote.currency)
    if line.unit_price.minor_units > 0x7fffffffffffffffL / line.quantity ||
      line.unit_price.minor_units * line.quantity != line.line_total.minor_units {
      raise InvalidInput("quote line total does not reconcile")
    }
    if subtotal > 0x7fffffffffffffffL - line.line_total.minor_units {
      raise InvalidInput("quote subtotal overflow")
    }
    subtotal += line.line_total.minor_units
  }
  if subtotal != quote.subtotal.minor_units ||
    quote.subtotal.minor_units > 0x7fffffffffffffffL - quote.tax.minor_units ||
    quote.subtotal.minor_units + quote.tax.minor_units !=
    quote.total.minor_units {
    raise InvalidInput("quote totals do not reconcile")
  }
}

///|
pub fn validate_order(
  order : CommercialOrder,
) -> Unit raise OfflineCommerceError {
  if !valid_id(order.order_id) ||
    !valid_id(order.idempotency_key) ||
    !valid_id(order.tenant_ref) ||
    !valid_id(order.organization_id) ||
    !valid_id(order.project_id) ||
    !valid_id(order.purchaser_subject_ref) ||
    !valid_id(order.selected_service_code) ||
    !valid_id(order.selected_sla_code) ||
    order.generation <= 0L ||
    order.created_unix_ms <= 0L ||
    order.updated_unix_ms < order.created_unix_ms ||
    order.expires_unix_ms <= order.created_unix_ms {
    raise InvalidInput("invalid commercial order")
  }
  match order.quote {
    Some(quote) => validate_quote(quote)
    None =>
      if order.state != Draft {
        raise InvalidInput("non-draft order requires a quote")
      }
  }
  if order.artifact_ids.length() > 256 {
    raise InvalidInput("too many order artifacts")
  }
}

///|
pub fn validate_template(
  template : DocumentTemplate,
) -> Unit raise OfflineCommerceError {
  if !valid_id(template.template_id) ||
    !valid_id(template.version) ||
    !valid_id(template.locale) ||
    !valid_label(template.media_type, 120) ||
    !valid_object_ref(template.object_ref) ||
    !valid_sha256(template.sha256) ||
    template.byte_count <= 0L ||
    template.byte_count > 100000000L ||
    template.created_unix_ms <= 0L ||
    template.superseded_unix_ms.map_or(false, value => {
      value <= template.created_unix_ms
    }) ||
    template.active_content_allowed {
    raise InvalidInput("invalid or unsafe document template")
  }
  let expected = match template.kind {
    ContractTemplate =>
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    QuoteScheduleTemplate =>
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  }
  if template.media_type != expected {
    raise InvalidInput("template kind and media type disagree")
  }
}

///|
pub fn expected_media_type(kind : DocumentArtifactKind) -> Array[String] {
  match kind {
    EditableContractDocx =>
      [
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      ]
    QuoteScheduleXlsx =>
      ["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"]
    PrintReadyContractPdf => ["application/pdf"]
    ExecutedContractScan
    | PaymentReceipt
    | IssuedInvoice
    | InternalApprovalEvidence
    | IdentityVerificationEvidence =>
      ["application/pdf", "image/png", "image/jpeg"]
  }
}

///|
pub fn evidence_kind(kind : DocumentArtifactKind) -> OfflineEvidenceKind? {
  match kind {
    ExecutedContractScan => Some(ExecutedAgreementEvidence)
    PaymentReceipt => Some(PaymentEvidence)
    IssuedInvoice => Some(InvoiceEvidence)
    InternalApprovalEvidence => Some(InternalApproval)
    IdentityVerificationEvidence => Some(IdentityVerification)
    _ => None
  }
}

///|
pub fn required_evidence(
  policy : FulfillmentPolicy,
) -> Array[OfflineEvidenceKind] {
  let result = []
  if policy.require_executed_agreement {
    result.push(ExecutedAgreementEvidence)
  }
  if policy.require_payment {
    result.push(PaymentEvidence)
  }
  if policy.invoice_timing == InvoiceBeforeFulfillment {
    result.push(InvoiceEvidence)
  }
  if policy.require_internal_approval {
    result.push(InternalApproval)
  }
  if policy.require_identity_verification {
    result.push(IdentityVerification)
  }
  result
}
