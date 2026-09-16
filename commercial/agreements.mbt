///|
pub fn CommercialStore::register_agreement_template(
  self : CommercialStore,
  template : AgreementTemplate,
) -> Unit raise CommercialError {
  if !safe_identifier(template.template_id) ||
    !safe_identifier(template.agreement_type) ||
    !safe_identifier(template.version) ||
    template.locale.length() == 0 ||
    template.locale.length() > 32 ||
    !valid_sha256(template.rendered_document_hash) ||
    template.document_uri.map_or(false, uri => {
      uri.length() == 0 ||
      uri.length() > 2048 ||
      uri.any(character => character.is_whitespace()) ||
      uri.contains("#") ||
      uri.contains("?") ||
      (!uri.has_prefix("https://") && !uri.has_prefix("/docs/"))
    }) ||
    template.effective_unix_ms <= 0L ||
    template.created_unix_ms <= 0L {
    raise InvalidInput("invalid agreement template")
  }
  let key = template_key(template.template_id, template.version)
  match self.templates.get(key) {
    Some(existing) =>
      if existing == template {
        ()
      } else {
        raise IdempotencyConflict("agreement template version is immutable")
      }
    None => self.templates[key] = template
  }
}

///|
pub fn CommercialStore::set_template_state(
  self : CommercialStore,
  template_id : String,
  version : String,
  next : AgreementTemplateState,
) -> AgreementTemplate raise CommercialError {
  let key = template_key(template_id, version)
  let template = match self.templates.get(key) {
    Some(value) => value
    None => raise NotFound("agreement template")
  }
  let allowed = match (template.state, next) {
    (DraftTemplate, ReadyTemplate) => true
    (ReadyTemplate, SupersededTemplate) => true
    _ => false
  }
  if !allowed {
    raise InvalidTransition("agreement template state")
  }
  if next == ReadyTemplate && template.document_uri is None {
    raise InvalidInput("ready agreement template requires readable terms")
  }
  let updated = { ..template, state: next }
  self.templates[key] = updated
  updated
}

///|
fn CommercialStore::require_ready_template(
  self : CommercialStore,
  template_id : String,
  version : String,
  document_hash : String,
) -> AgreementTemplate raise CommercialError {
  match self.templates.get(template_key(template_id, version)) {
    Some(template) => {
      if template.state != ReadyTemplate ||
        template.rendered_document_hash != document_hash {
        raise InvalidInput("agreement template is not ready or hash mismatched")
      }
      template
    }
    None => raise NotFound("agreement template")
  }
}

///|
pub fn CommercialStore::accept_clickwrap(
  self : CommercialStore,
  acceptance : ClickwrapAcceptance,
) -> IdempotencyResult raise CommercialError {
  ignore(self.require_organization(acceptance.organization_id))
  ignore(
    self.require_ready_template(
      acceptance.template_id,
      acceptance.template_version,
      acceptance.rendered_document_hash,
    ),
  )
  if !safe_identifier(acceptance.acceptance_id) ||
    !safe_identifier(acceptance.idempotency_key) ||
    !safe_identifier(acceptance.user_id) ||
    !safe_display_name(acceptance.intent) ||
    acceptance.presentation_context_hash.length() == 0 ||
    acceptance.network_context_hash.length() == 0 ||
    acceptance.accepted_unix_ms <= 0L {
    raise InvalidInput("invalid clickwrap evidence")
  }
  if !self.grants
    .values()
    .any(grant => {
      grant.organization_id == acceptance.organization_id &&
      grant.user_id == acceptance.user_id &&
      (
        grant.expires_unix_ms is None ||
        grant.expires_unix_ms.unwrap_or(0L) > acceptance.accepted_unix_ms
      )
    }) {
    raise PermissionDenied("active organization membership required")
  }
  let scoped_key = "\{acceptance.organization_id}:\{acceptance.idempotency_key}"
  match self.acceptance_keys.get(scoped_key) {
    Some(existing_id) =>
      match self.acceptances.get(existing_id) {
        Some(existing) =>
          if existing == acceptance {
            Replayed
          } else {
            raise IdempotencyConflict("clickwrap evidence changed")
          }
        None => raise InvalidInput("acceptance index is corrupt")
      }
    None => {
      if self.acceptances.contains(acceptance.acceptance_id) {
        raise AlreadyExists("clickwrap acceptance")
      }
      self.acceptances[acceptance.acceptance_id] = acceptance
      self.acceptance_keys[scoped_key] = acceptance.acceptance_id
      Created
    }
  }
}

///|
pub fn CommercialStore::create_agreement(
  self : CommercialStore,
  agreement : Agreement,
) -> Unit raise CommercialError {
  ignore(self.require_organization(agreement.organization_id))
  ignore(
    self.require_ready_template(
      agreement.template_id,
      agreement.template_version,
      agreement.rendered_document_hash,
    ),
  )
  if !safe_identifier(agreement.agreement_id) ||
    !safe_identifier(agreement.signer_user_id) ||
    !safe_identifier(agreement.signer_authority_ref) ||
    agreement.state != DraftAgreement ||
    agreement.created_unix_ms <= 0L ||
    agreement.updated_unix_ms != agreement.created_unix_ms {
    raise InvalidInput("invalid agreement")
  }
  if self.agreements.contains(agreement.agreement_id) {
    raise AlreadyExists("agreement")
  }
  self.agreements[agreement.agreement_id] = agreement
}

///|
pub fn agreement_transition_allowed(
  from : AgreementState,
  to : AgreementState,
) -> Bool {
  match (from, to) {
    (DraftAgreement, InternalReview | Voided) => true
    (InternalReview, ReadyForSignature | Voided) => true
    (ReadyForSignature, AwaitingSigner | Voided | SupersededAgreement) => true
    (
      AwaitingSigner,
      PartiallySigned
      | AwaitingCountersignature
      | Executed
      | Declined
      | ExpiredAgreement
      | Voided,
    ) => true
    (
      PartiallySigned,
      AwaitingCountersignature
      | Executed
      | Declined
      | ExpiredAgreement
      | Voided,
    ) => true
    (AwaitingCountersignature, Executed | Declined | ExpiredAgreement | Voided) =>
      true
    (Executed, SupersededAgreement | Voided) => true
    _ => false
  }
}

///|
pub fn CommercialStore::transition_agreement(
  self : CommercialStore,
  organization_id : String,
  agreement_id : String,
  actor_user_id : String,
  next : AgreementState,
  updated_unix_ms : Int64,
) -> Agreement raise CommercialError {
  let agreement = match self.agreements.get(agreement_id) {
    Some(value) => value
    None => raise NotFound("agreement")
  }
  if agreement.organization_id != organization_id {
    raise TenantMismatch
  }
  if !self.has_permission(
      organization_id,
      actor_user_id,
      SignAgreement,
      updated_unix_ms,
    ) {
    raise PermissionDenied("legal signer permission required")
  }
  if actor_user_id != agreement.signer_user_id ||
    updated_unix_ms < agreement.updated_unix_ms ||
    !agreement_transition_allowed(agreement.state, next) {
    raise InvalidTransition("agreement state")
  }
  let updated = { ..agreement, state: next, updated_unix_ms }
  self.agreements[agreement_id] = updated
  updated
}

///|
pub fn CommercialStore::reconcile_signature_callback(
  self : CommercialStore,
  callback : SignatureCallback,
) -> (Agreement, IdempotencyResult) raise CommercialError {
  if !safe_identifier(callback.callback_id) ||
    !safe_identifier(callback.agreement_id) ||
    !safe_identifier(callback.organization_id) ||
    !safe_identifier(callback.external_envelope_ref) ||
    !safe_identifier(callback.signer_user_id) ||
    !valid_sha256(callback.rendered_document_hash) ||
    callback.received_unix_ms <= 0L ||
    callback.executed_artifact_ref
    .map(value => !safe_identifier(value))
    .unwrap_or(false) ||
    callback.executed_artifact_hash
    .map(value => !valid_sha256(value))
    .unwrap_or(false) {
    raise InvalidInput("invalid signature callback evidence")
  }
  if !callback.verified {
    raise PermissionDenied("signature callback is not verified")
  }
  match self.signature_callbacks.get(callback.callback_id) {
    Some(existing) =>
      if existing == callback {
        let agreement = self.agreements.get(callback.agreement_id).unwrap()
        (agreement, Replayed)
      } else {
        raise IdempotencyConflict("signature callback changed")
      }
    None => {
      let agreement = match self.agreements.get(callback.agreement_id) {
        Some(value) => value
        None => raise NotFound("agreement")
      }
      if agreement.organization_id != callback.organization_id {
        raise TenantMismatch
      }
      if agreement.rendered_document_hash != callback.rendered_document_hash ||
        agreement.signer_user_id != callback.signer_user_id ||
        agreement.external_envelope_ref != Some(callback.external_envelope_ref) ||
        agreement.state != callback.expected_previous_state ||
        !agreement_transition_allowed(agreement.state, callback.next_state) ||
        callback.received_unix_ms < agreement.updated_unix_ms {
        raise InvalidTransition("signature callback evidence mismatch")
      }
      if !self.has_permission(
          callback.organization_id,
          callback.signer_user_id,
          SignAgreement,
          callback.received_unix_ms,
        ) {
        raise PermissionDenied("signer authority is no longer active")
      }
      if callback.next_state == Executed &&
        (
          callback.executed_artifact_ref is None ||
          callback.executed_artifact_hash is None
        ) {
        raise InvalidInput("executed agreement requires artifact evidence")
      }
      let updated = {
        ..agreement,
        state: callback.next_state,
        executed_artifact_ref: callback.executed_artifact_ref,
        executed_artifact_hash: callback.executed_artifact_hash,
        updated_unix_ms: callback.received_unix_ms,
      }
      self.agreements[agreement.agreement_id] = updated
      self.signature_callbacks[callback.callback_id] = callback
      (updated, Created)
    }
  }
}

///|
fn CommercialStore::agreement_type_satisfied(
  self : CommercialStore,
  organization_id : String,
  agreement_type : String,
) -> Bool {
  let clickwrap = self.acceptances
    .values()
    .any(acceptance => {
      if acceptance.organization_id != organization_id {
        false
      } else {
        self.templates
        .get(template_key(acceptance.template_id, acceptance.template_version))
        .map(template => {
          template.agreement_type == agreement_type &&
          template.rendered_document_hash == acceptance.rendered_document_hash &&
          template.state == ReadyTemplate
        })
        .unwrap_or(false)
      }
    })
  clickwrap ||
  self.agreements
  .values()
  .any(agreement => {
    if agreement.organization_id != organization_id ||
      agreement.state != Executed {
      false
    } else {
      self.templates
      .get(template_key(agreement.template_id, agreement.template_version))
      .map(template => template.agreement_type == agreement_type)
      .unwrap_or(false)
    }
  })
}
