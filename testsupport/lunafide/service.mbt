///|
struct IdempotencyEntry {
  fingerprint : String
  result_ref : String
}

///|
pub struct LunaFide {
  test_secret : String
  verifications : Map[String, VerificationRecord]
  envelopes : Map[String, EnvelopeRecord]
  payments : Map[String, PaymentRecord]
  invoices : Map[String, InvoiceRecord]
  idempotency : Map[String, IdempotencyEntry]
  aggregate_sequences : Map[String, Int64]
  events : Array[WebhookEvent]
}

///|
pub fn LunaFide::new(test_secret : String) -> LunaFide raise LunaFideError {
  if test_secret == "" {
    raise LunaFideError::InvalidRequest("test webhook secret must not be empty")
  }
  {
    test_secret,
    verifications: Map([]),
    envelopes: Map([]),
    payments: Map([]),
    invoices: Map([]),
    idempotency: Map([]),
    aggregate_sequences: Map([]),
    events: [],
  }
}

///|
pub fn LunaFide::health(self : LunaFide, now_unix_ms : Int64) -> HealthPayload {
  ignore(self)
  {
    identity: service_identity(),
    status: "ok",
    state_backend: "ephemeral-in-memory",
    observed_unix_ms: now_unix_ms,
  }
}

///|
fn valid_ref(value : String) -> Bool {
  value != "" &&
  value.length() <= 256 &&
  !value.contains("\n") &&
  !value.contains("\r")
}

///|
fn valid_sha256(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for char in value[7:] {
    if !(char >= '0' && char <= '9') && !(char >= 'a' && char <= 'f') {
      return false
    }
  }
  true
}

///|
fn validate_common(
  request_version : String,
  idempotency_key : String,
  tenant_ref : String,
) -> Unit raise LunaFideError {
  if request_version != protocol_version {
    raise LunaFideError::InvalidRequest("unsupported protocol version")
  }
  if !valid_ref(idempotency_key) || !valid_ref(tenant_ref) {
    raise LunaFideError::InvalidRequest(
      "invalid idempotency or tenant reference",
    )
  }
}

///|
fn LunaFide::idempotent_ref(
  self : LunaFide,
  scope : String,
  fingerprint : String,
) -> String? raise LunaFideError {
  match self.idempotency.get(scope) {
    None => None
    Some(entry) if entry.fingerprint == fingerprint => Some(entry.result_ref)
    Some(_) => raise LunaFideError::IdempotencyConflict(scope)
  }
}

///|
fn LunaFide::remember(
  self : LunaFide,
  scope : String,
  fingerprint : String,
  result_ref : String,
) -> Unit {
  self.idempotency[scope] = { fingerprint, result_ref }
}

///|
fn LunaFide::next_sequence(self : LunaFide, aggregate_ref : String) -> Int64 {
  let next = self.aggregate_sequences.get(aggregate_ref).unwrap_or(0L) + 1L
  self.aggregate_sequences[aggregate_ref] = next
  next
}

///|
fn LunaFide::emit(
  self : LunaFide,
  kind : WebhookKind,
  tenant_ref : String,
  aggregate_ref : String,
  idempotency_key : String,
  occurred_unix_ms : Int64,
  payload : Json,
) -> Unit {
  let sequence = self.next_sequence(aggregate_ref)
  let unsigned : WebhookEvent = {
    protocol_version,
    provider: "LunaFide",
    environment: "test-only",
    event_id: stable_ref(
      "lfevt",
      "\{aggregate_ref}|\{sequence}|\{idempotency_key}",
    ),
    kind,
    tenant_ref,
    aggregate_ref,
    sequence,
    occurred_unix_ms,
    idempotency_key,
    payload,
    key_id: "lunafide-ephemeral-v1",
    auth_scheme: "HMAC-SHA256-TEST-ONLY",
    signature: "",
  }
  self.events.push({
    ..unsigned,
    signature: sign_webhook(unsigned, self.test_secret),
  })
}

///|
pub fn LunaFide::events(self : LunaFide) -> Array[WebhookEvent] {
  self.events.copy()
}

///|
pub fn LunaFide::request_verification(
  self : LunaFide,
  request : VerificationRequest,
) -> VerificationRecord raise LunaFideError {
  validate_common(
    request.protocol_version,
    request.idempotency_key,
    request.tenant_ref,
  )
  if !valid_ref(request.subject_ref) {
    raise LunaFideError::InvalidRequest("invalid opaque subject reference")
  }
  let fingerprint = sha256_hex(request.to_json().stringify())
  let scope = "verification.request|\{request.tenant_ref}|\{request.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.verifications
      .get(result_ref)
      .unwrap_or_else(() => abort("corrupt state"))
    None => {
      let verification_ref = stable_ref("lfver", fingerprint)
      let record : VerificationRecord = {
        verification_ref,
        tenant_ref: request.tenant_ref,
        subject_ref: request.subject_ref,
        subject_type: request.subject_type,
        state: Pending,
        reason_code: "pending",
        requested_unix_ms: request.requested_unix_ms,
        resolved_unix_ms: None,
      }
      self.verifications[verification_ref] = record
      self.remember(scope, fingerprint, verification_ref)
      self.emit(
        VerificationRequested,
        request.tenant_ref,
        verification_ref,
        request.idempotency_key,
        request.requested_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::resolve_verification(
  self : LunaFide,
  resolution : VerificationResolution,
) -> VerificationRecord raise LunaFideError {
  validate_common(
    resolution.protocol_version,
    resolution.idempotency_key,
    resolution.tenant_ref,
  )
  if resolution.state != Verified &&
    resolution.state != Rejected &&
    resolution.state != Expired {
    raise LunaFideError::InvalidRequest("resolution must be terminal")
  }
  let fingerprint = sha256_hex(resolution.to_json().stringify())
  let scope = "verification.resolve|\{resolution.tenant_ref}|\{resolution.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.verifications
      .get(result_ref)
      .unwrap_or_else(() => abort("corrupt state"))
    None => {
      guard self.verifications.get(resolution.verification_ref) is Some(current) else {
        raise LunaFideError::NotFound(resolution.verification_ref)
      }
      if current.tenant_ref != resolution.tenant_ref {
        raise LunaFideError::NotFound(resolution.verification_ref)
      }
      if current.state != Pending {
        raise LunaFideError::IllegalTransition(resolution.verification_ref)
      }
      let record : VerificationRecord = {
        ..current,
        state: resolution.state,
        reason_code: resolution.reason_code,
        resolved_unix_ms: Some(resolution.resolved_unix_ms),
      }
      self.verifications[record.verification_ref] = record
      self.remember(scope, fingerprint, record.verification_ref)
      self.emit(
        VerificationResolved,
        record.tenant_ref,
        record.verification_ref,
        resolution.idempotency_key,
        resolution.resolved_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::create_envelope(
  self : LunaFide,
  request : EnvelopeRequest,
) -> EnvelopeRecord raise LunaFideError {
  validate_common(
    request.protocol_version,
    request.idempotency_key,
    request.tenant_ref,
  )
  if !valid_ref(request.template_ref) ||
    !valid_ref(request.signer_ref) ||
    !valid_sha256(request.document_sha256) ||
    request.expires_unix_ms <= request.requested_unix_ms {
    raise LunaFideError::InvalidRequest("invalid envelope request")
  }
  match request.countersigner_ref {
    Some(value) if !valid_ref(value) =>
      raise LunaFideError::InvalidRequest("invalid countersigner reference")
    _ => ()
  }
  let fingerprint = sha256_hex(request.to_json().stringify())
  let scope = "envelope.create|\{request.tenant_ref}|\{request.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.envelopes
      .get(result_ref)
      .unwrap_or_else(() => abort("corrupt state"))
    None => {
      let envelope_ref = stable_ref("lfenv", fingerprint)
      let record : EnvelopeRecord = {
        envelope_ref,
        tenant_ref: request.tenant_ref,
        template_ref: request.template_ref,
        document_sha256: request.document_sha256,
        signer_ref: request.signer_ref,
        countersigner_ref: request.countersigner_ref,
        state: AwaitingSigner,
        expires_unix_ms: request.expires_unix_ms,
        executed_unix_ms: None,
      }
      self.envelopes[envelope_ref] = record
      self.remember(scope, fingerprint, envelope_ref)
      self.emit(
        EnvelopeCreated,
        record.tenant_ref,
        envelope_ref,
        request.idempotency_key,
        request.requested_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::record_signature(
  self : LunaFide,
  action : SignatureAction,
) -> EnvelopeRecord raise LunaFideError {
  validate_common(
    action.protocol_version,
    action.idempotency_key,
    action.tenant_ref,
  )
  let fingerprint = sha256_hex(action.to_json().stringify())
  let scope = "envelope.action|\{action.tenant_ref}|\{action.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.envelopes
      .get(result_ref)
      .unwrap_or_else(() => abort("corrupt state"))
    None => {
      guard self.envelopes.get(action.envelope_ref) is Some(current) else {
        raise LunaFideError::NotFound(action.envelope_ref)
      }
      if current.tenant_ref != action.tenant_ref {
        raise LunaFideError::NotFound(action.envelope_ref)
      }
      if action.acted_unix_ms > current.expires_unix_ms {
        raise LunaFideError::ExpiredWebhook(action.envelope_ref)
      }
      let next_state = match (action.party, action.decision, current.state) {
        (Signer, SignatureDecision::Declined, AwaitingSigner) =>
          EnvelopeState::Declined
        (Signer, Signed, AwaitingSigner) =>
          if current.countersigner_ref is Some(_) {
            AwaitingCountersignature
          } else {
            Executed
          }
        (Countersigner, SignatureDecision::Declined, AwaitingCountersignature) =>
          EnvelopeState::Declined
        (Countersigner, Signed, AwaitingCountersignature) => Executed
        _ => raise LunaFideError::IllegalTransition(action.envelope_ref)
      }
      let expected_actor = match action.party {
        Signer => Some(current.signer_ref)
        Countersigner => current.countersigner_ref
      }
      if expected_actor != Some(action.actor_ref) {
        raise LunaFideError::IllegalTransition("unexpected signer")
      }
      let record : EnvelopeRecord = {
        ..current,
        state: next_state,
        executed_unix_ms: if next_state == Executed {
          Some(action.acted_unix_ms)
        } else {
          None
        },
      }
      self.envelopes[record.envelope_ref] = record
      self.remember(scope, fingerprint, record.envelope_ref)
      self.emit(
        EnvelopeUpdated,
        record.tenant_ref,
        record.envelope_ref,
        action.idempotency_key,
        action.acted_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::request_payment(
  self : LunaFide,
  request : PaymentRequest,
) -> PaymentRecord raise LunaFideError {
  validate_common(
    request.protocol_version,
    request.idempotency_key,
    request.tenant_ref,
  )
  if !valid_ref(request.order_ref) ||
    request.amount_minor <= 0L ||
    request.currency.length() != 3 ||
    request.currency != request.currency.to_upper() {
    raise LunaFideError::InvalidRequest("invalid payment request")
  }
  let fingerprint = sha256_hex(request.to_json().stringify())
  let scope = "payment.request|\{request.tenant_ref}|\{request.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.payments.get(result_ref).unwrap_or_else(() => abort("corrupt state"))
    None => {
      let payment_ref = stable_ref("lfpay", fingerprint)
      let (state, reason_code) = match request.simulated_outcome {
        Succeed => (Settled, "simulated_settlement")
        Decline => (PaymentState::Declined, "simulated_decline")
        RequireReview => (UnderReview, "simulated_review")
      }
      let record : PaymentRecord = {
        payment_ref,
        tenant_ref: request.tenant_ref,
        order_ref: request.order_ref,
        amount_minor: request.amount_minor,
        currency: request.currency,
        state,
        reason_code,
        processed_unix_ms: request.requested_unix_ms,
      }
      self.payments[payment_ref] = record
      self.remember(scope, fingerprint, payment_ref)
      self.emit(
        PaymentUpdated,
        record.tenant_ref,
        record.payment_ref,
        request.idempotency_key,
        request.requested_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::issue_invoice(
  self : LunaFide,
  request : InvoiceRequest,
) -> InvoiceRecord raise LunaFideError {
  validate_common(
    request.protocol_version,
    request.idempotency_key,
    request.tenant_ref,
  )
  validate_invoice_request(request)
  self.issue_invoice_record(request, None, InvoiceIssued)
}

///|
fn validate_invoice_request(
  request : InvoiceRequest,
) -> Unit raise LunaFideError {
  if !valid_ref(request.bill_ref) ||
    !valid_ref(request.billing_profile_ref) ||
    request.amount_minor <= 0L ||
    request.currency.length() != 3 ||
    request.currency != request.currency.to_upper() ||
    !valid_sha256(request.bill_content_sha256) {
    raise LunaFideError::InvalidRequest("invalid invoice request")
  }
}

///|
fn LunaFide::issue_invoice_record(
  self : LunaFide,
  request : InvoiceRequest,
  replaces : String?,
  kind : WebhookKind,
) -> InvoiceRecord raise LunaFideError {
  let fingerprint = sha256_hex(
    "\{request.to_json().stringify()}|\{Repr(replaces)}",
  )
  let scope = "invoice.issue|\{request.tenant_ref}|\{request.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.invoices.get(result_ref).unwrap_or_else(() => abort("corrupt state"))
    None => {
      let invoice_ref = stable_ref("lfinv", fingerprint)
      let record : InvoiceRecord = {
        invoice_ref,
        tenant_ref: request.tenant_ref,
        bill_ref: request.bill_ref,
        billing_profile_ref: request.billing_profile_ref,
        amount_minor: request.amount_minor,
        currency: request.currency,
        bill_content_sha256: request.bill_content_sha256,
        state: Issued,
        issued_unix_ms: request.requested_unix_ms,
        voided_unix_ms: None,
        replaces_invoice_ref: replaces,
      }
      self.invoices[invoice_ref] = record
      self.remember(scope, fingerprint, invoice_ref)
      self.emit(
        kind,
        record.tenant_ref,
        record.invoice_ref,
        request.idempotency_key,
        request.requested_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::void_invoice(
  self : LunaFide,
  action : InvoiceAction,
) -> InvoiceRecord raise LunaFideError {
  validate_common(
    action.protocol_version,
    action.idempotency_key,
    action.tenant_ref,
  )
  if !valid_ref(action.reason_code) {
    raise LunaFideError::InvalidRequest("void reason is required")
  }
  let fingerprint = sha256_hex(action.to_json().stringify())
  let scope = "invoice.void|\{action.tenant_ref}|\{action.idempotency_key}"
  match self.idempotent_ref(scope, fingerprint) {
    Some(result_ref) =>
      self.invoices.get(result_ref).unwrap_or_else(() => abort("corrupt state"))
    None => {
      guard self.invoices.get(action.invoice_ref) is Some(current) else {
        raise LunaFideError::NotFound(action.invoice_ref)
      }
      if current.tenant_ref != action.tenant_ref {
        raise LunaFideError::NotFound(action.invoice_ref)
      }
      if current.state != Issued {
        raise LunaFideError::IllegalTransition(action.invoice_ref)
      }
      let record : InvoiceRecord = {
        ..current,
        state: Voided,
        voided_unix_ms: Some(action.acted_unix_ms),
      }
      self.invoices[record.invoice_ref] = record
      self.remember(scope, fingerprint, record.invoice_ref)
      self.emit(
        InvoiceVoided,
        record.tenant_ref,
        record.invoice_ref,
        action.idempotency_key,
        action.acted_unix_ms,
        record.to_json(),
      )
      record
    }
  }
}

///|
pub fn LunaFide::reissue_invoice(
  self : LunaFide,
  voided_invoice_ref : String,
  request : InvoiceRequest,
) -> InvoiceRecord raise LunaFideError {
  validate_common(
    request.protocol_version,
    request.idempotency_key,
    request.tenant_ref,
  )
  validate_invoice_request(request)
  guard self.invoices.get(voided_invoice_ref) is Some(previous) else {
    raise LunaFideError::NotFound(voided_invoice_ref)
  }
  if previous.tenant_ref != request.tenant_ref || previous.state != Voided {
    raise LunaFideError::IllegalTransition(voided_invoice_ref)
  }
  if request.bill_ref != previous.bill_ref ||
    request.currency != previous.currency {
    raise LunaFideError::InvalidRequest(
      "reissue must preserve bill and currency",
    )
  }
  self.issue_invoice_record(request, Some(voided_invoice_ref), InvoiceReissued)
}
