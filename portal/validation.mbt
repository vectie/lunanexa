///|
fn safe_text(value : String, maximum_length : Int) -> Bool {
  let trimmed = value.trim()
  trimmed != "" &&
  value.length() <= maximum_length &&
  value.all(character => {
    character != '\u0000' && character != '\n' && character != '\r'
  })
}

///|
fn valid_unix_username(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 32 &&
  value != "root" &&
  value != "daemon" &&
  value != "lunanexa" &&
  value[0] >= 'a' &&
  value[0] <= 'z' &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= '0' && character <= '9') ||
    character == '_' ||
    character == '-'
  })
}

///|
pub fn validate_membership(
  membership : EnterpriseMembership,
) -> Unit raise PortalError {
  if !@contracts.valid_identifier(membership.membership_id) ||
    !@contracts.valid_identifier(membership.tenant_ref) ||
    !@contracts.valid_identifier(membership.organization_id) ||
    !@contracts.valid_identifier(membership.subject_ref) ||
    membership.roles.length() == 0 ||
    membership.created_unix_ms <= 0L {
    raise InvalidInput("invalid enterprise membership")
  }
}

///|
pub fn validate_agreement(
  agreement : PortalAgreement,
) -> Unit raise PortalError {
  if !@contracts.valid_identifier(agreement.agreement_id) ||
    !@contracts.valid_identifier(agreement.tenant_ref) ||
    !@contracts.valid_identifier(agreement.organization_id) ||
    !@contracts.valid_identifier(agreement.template_ref) ||
    !@contracts.valid_identifier(
      agreement.rendered_document_hash,
      maximum_length=512,
    ) ||
    !safe_text(agreement.title, 160) ||
    !safe_text(agreement.summary, 2000) ||
    agreement.generation <= 0L ||
    agreement.created_unix_ms <= 0L ||
    agreement.updated_unix_ms < agreement.created_unix_ms {
    raise InvalidInput("invalid portal agreement")
  }
}

///|
pub fn validate_submission(
  submission : LeaseRequestSubmission,
) -> Unit raise PortalError {
  if !@contracts.valid_identifier(submission.request_id) ||
    !@contracts.valid_identifier(submission.idempotency_key) ||
    !@contracts.valid_identifier(submission.tenant_ref) ||
    !@contracts.valid_identifier(submission.organization_id) ||
    !@contracts.valid_identifier(submission.project_id) ||
    !valid_unix_username(submission.unix_username) ||
    !safe_text(submission.justification, 1000) ||
    submission.starts_unix_ms <= 0L ||
    submission.expires_unix_ms <= submission.starts_unix_ms ||
    submission.requested_model_ids.length() == 0 ||
    submission.requested_model_ids.length() > 32 {
    raise InvalidInput("invalid enterprise lease request")
  }
  for model_id in submission.requested_model_ids {
    if !@contracts.valid_identifier(model_id, maximum_length=256) {
      raise InvalidInput("invalid requested model identity")
    }
  }
}

///|
pub fn role_allows(
  roles : Array[EnterpriseRole],
  required : EnterpriseRole,
) -> Bool {
  roles.contains(OrganizationAdministrator) || roles.contains(required)
}
