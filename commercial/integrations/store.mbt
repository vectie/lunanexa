///|
pub struct IntegrationStore {
  records : Map[String, ExternalRecord]
  external_index : Map[String, String]
  callbacks : Map[String, ExternalCallback]
  reconciliation_exception_counts : Map[String, Int]
}

///|
pub fn IntegrationStore::new() -> IntegrationStore {
  {
    records: Map([]),
    external_index: Map([]),
    callbacks: Map([]),
    reconciliation_exception_counts: Map([]),
  }
}

///|
fn IntegrationStore::record_exception(
  self : IntegrationStore,
  organization_id : String,
) -> Unit {
  self.reconciliation_exception_counts.update_or_default(organization_id, 0, count => {
    count + 1
  })
}

///|
fn safe_identifier(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 256 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == ':' ||
    character == '.' ||
    character == '@' ||
    character == '/'
  })
}

///|
fn valid_currency(value : String) -> Bool {
  value.length() == 3 &&
  value.all(character => character >= 'A' && character <= 'Z')
}

///|
fn external_key(record : ExternalRecord) -> String {
  "\{record.organization_id}:\{record.provider}:\{record.environment}:\{record.external_ref}"
}

///|
fn validate_record(record : ExternalRecord) -> Unit raise IntegrationError {
  if !safe_identifier(record.record_id) ||
    !safe_identifier(record.organization_id) ||
    !safe_identifier(record.provider) ||
    !safe_identifier(record.environment) ||
    !safe_identifier(record.external_ref) ||
    record.created_unix_ms <= 0L ||
    record.updated_unix_ms != record.created_unix_ms ||
    record.state != Pending {
    raise InvalidInput("invalid external integration record")
  }
  match record.kind {
    Payment | TaxInvoice =>
      if record.expected_amount_minor.map(amount => amount < 0L).unwrap_or(true) ||
        record.currency.map(valid_currency).unwrap_or(false) == false ||
        record.money_scale.map(scale => scale < 0 || scale > 9).unwrap_or(true) {
        raise InvalidInput(
          "money integration requires amount, currency, and scale",
        )
      }
    IdentityVerification =>
      if record.expected_amount_minor is Some(_) ||
        record.currency is Some(_) ||
        record.money_scale is Some(_) {
        raise InvalidInput("identity integration cannot carry money")
      }
    QualifiedSignature =>
      if record.expected_document_hash is None {
        raise InvalidInput("signature integration requires a document hash")
      }
  }
}

///|
fn same_registration(left : ExternalRecord, right : ExternalRecord) -> Bool {
  left.record_id == right.record_id &&
  left.organization_id == right.organization_id &&
  left.kind == right.kind &&
  left.provider == right.provider &&
  left.environment == right.environment &&
  left.external_ref == right.external_ref &&
  right.state == Pending &&
  left.expected_amount_minor == right.expected_amount_minor &&
  left.currency == right.currency &&
  left.money_scale == right.money_scale &&
  left.expected_document_hash == right.expected_document_hash &&
  left.entitlement_transaction_ref == right.entitlement_transaction_ref &&
  left.created_unix_ms == right.created_unix_ms &&
  right.updated_unix_ms == right.created_unix_ms
}

///|
pub fn IntegrationStore::register(
  self : IntegrationStore,
  record : ExternalRecord,
) -> ReconciliationResult raise IntegrationError {
  validate_record(record)
  match self.records.get(record.record_id) {
    Some(existing) =>
      if same_registration(existing, record) {
        Replayed
      } else {
        raise IdempotencyConflict("record id payload changed")
      }
    None => {
      let key = external_key(record)
      match self.external_index.get(key) {
        Some(_) => raise AlreadyExists("external provider reference")
        None => ()
      }
      self.records[record.record_id] = record
      self.external_index[key] = record.record_id
      Applied
    }
  }
}

///|
pub fn external_transition_allowed(
  kind : ExternalRecordKind,
  from : ExternalRecordState,
  to : ExternalRecordState,
) -> Bool {
  match (kind, from, to) {
    (IdentityVerification, Pending, Submitted | Verified | Failed) => true
    (IdentityVerification, Submitted, Verified | Failed | Expired) => true
    (IdentityVerification, Verified, Expired) => true
    (Payment, Pending, Submitted | Authorized | Settled | Failed) => true
    (Payment, Submitted, Authorized | Settled | Failed) => true
    (Payment, Authorized, Settled | Failed | Voided) => true
    (Payment, Settled, Refunded) => true
    (TaxInvoice, Pending, Submitted | Issued | Failed) => true
    (TaxInvoice, Submitted, Issued | Failed | Voided) => true
    (TaxInvoice, Issued, Credited | Voided) => true
    (TaxInvoice, Credited, Issued | Voided) => true
    (QualifiedSignature, Pending, Submitted | Verified | Failed) => true
    (QualifiedSignature, Submitted, Verified | Failed | Expired | Voided) =>
      true
    (QualifiedSignature, Verified, Voided | Expired) => true
    _ => false
  }
}

///|
fn evidence_matches(
  record : ExternalRecord,
  callback : ExternalCallback,
) -> Bool {
  let money_matches = match record.kind {
    Payment | TaxInvoice =>
      callback.amount_minor == record.expected_amount_minor &&
      callback.currency == record.currency
    IdentityVerification | QualifiedSignature =>
      callback.amount_minor is None && callback.currency is None
  }
  let document_matches = match record.kind {
    QualifiedSignature =>
      callback.document_hash == record.expected_document_hash
    TaxInvoice =>
      record.expected_document_hash is None ||
      callback.document_hash == record.expected_document_hash
    IdentityVerification | Payment => true
  }
  money_matches && document_matches
}

///|
pub fn IntegrationStore::reconcile_callback(
  self : IntegrationStore,
  callback : ExternalCallback,
) -> (ExternalRecord, ReconciliationResult) raise IntegrationError {
  if !safe_identifier(callback.callback_id) ||
    !safe_identifier(callback.record_id) ||
    !safe_identifier(callback.organization_id) ||
    !safe_identifier(callback.provider) ||
    !safe_identifier(callback.environment) ||
    !safe_identifier(callback.external_ref) ||
    callback.provider_event_unix_ms <= 0L ||
    callback.received_unix_ms < callback.provider_event_unix_ms {
    self.record_exception(callback.organization_id)
    raise InvalidInput("invalid external callback")
  }
  match self.callbacks.get(callback.callback_id) {
    Some(existing) =>
      if existing == callback {
        let record = self.records.get(callback.record_id).unwrap()
        (record, Replayed)
      } else {
        let owner = self.records
          .get(callback.record_id)
          .map(record => record.organization_id)
          .unwrap_or(callback.organization_id)
        self.record_exception(owner)
        raise IdempotencyConflict("callback id payload changed")
      }
    None => {
      let record = match self.records.get(callback.record_id) {
        Some(value) => value
        None => {
          self.record_exception(callback.organization_id)
          raise NotFound("external record")
        }
      }
      if !callback.signature_verified {
        self.record_exception(record.organization_id)
        raise UnverifiedCallback
      }
      if record.organization_id != callback.organization_id {
        self.record_exception(record.organization_id)
        raise TenantMismatch
      }
      if record.provider != callback.provider ||
        record.environment != callback.environment ||
        record.external_ref != callback.external_ref ||
        !evidence_matches(record, callback) {
        self.record_exception(record.organization_id)
        raise EvidenceMismatch(
          "provider, environment, amount, currency, or document mismatch",
        )
      }
      if callback.expected_previous_state != record.state ||
        !external_transition_allowed(
          record.kind,
          record.state,
          callback.next_state,
        ) ||
        callback.received_unix_ms < record.updated_unix_ms {
        self.record_exception(record.organization_id)
        raise InvalidTransition("stale or out-of-order callback")
      }
      let updated = {
        ..record,
        state: callback.next_state,
        updated_unix_ms: callback.received_unix_ms,
      }
      self.records[record.record_id] = updated
      self.callbacks[callback.callback_id] = callback
      (updated, Applied)
    }
  }
}

///|
fn hash_reference(value : String) -> String {
  let digest = @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
  "sha256:\{digest}"
}

///|
pub fn IntegrationStore::snapshot(
  self : IntegrationStore,
  organization_id : String,
) -> IntegrationSnapshot {
  let records = self.records
    .values()
    .filter(record => record.organization_id == organization_id)
    .map(record => {
      record_id: record.record_id,
      organization_id: record.organization_id,
      kind: record.kind,
      provider: record.provider,
      environment: record.environment,
      external_ref_sha256: hash_reference(record.external_ref),
      state: record.state,
      expected_amount_minor: record.expected_amount_minor,
      currency: record.currency,
      money_scale: record.money_scale,
      expected_document_hash: record.expected_document_hash,
      entitlement_transaction_ref_sha256: record.entitlement_transaction_ref.map(
        hash_reference,
      ),
      updated_unix_ms: record.updated_unix_ms,
    })
    .to_array()
  records.sort_by_key(record => record.record_id)
  {
    schema_version: integration_schema_version,
    organization_id,
    records,
    reconciliation_exception_count: self.reconciliation_exception_counts
    .get(organization_id)
    .unwrap_or(0),
  }
}
