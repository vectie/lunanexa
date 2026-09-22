///|
/// Deployment approval is exact-template scoped, not a legal certification.
pub(all) struct OfflineTemplateApproval {
  template_id : String
  version : String
  locale : String
  sha256 : String
  approval_ref : String
} derive(FromJson)

///|
pub extend OfflineTemplateApproval with FromJson::{from_json}

///|
/// Empty configuration denies new commercial document work. The controller
/// always installs this scope; embedded library consumers may retain their own
/// approval authority by not calling this deployment-profile method.
pub fn ApiService::with_offline_template_approvals(
  self : ApiService,
  approvals : Array[OfflineTemplateApproval],
) -> ApiService raise {
  guard approvals.length() <= 64 else { fail("too many template approvals") }
  let seen : Map[String, Unit] = Map([])
  for approval in approvals {
    let key = approval.template_id + ":" + approval.version
    guard @contracts.valid_identifier(approval.template_id) &&
      @contracts.valid_identifier(approval.version) &&
      @contracts.valid_identifier(approval.locale) &&
      approval.approval_ref.trim() != "" &&
      approval.approval_ref.length() <= 1024 &&
      approval.sha256.length() == 71 &&
      approval.sha256.has_prefix("sha256:") &&
      approval.sha256[7:].all(c => c is ('a'..='f' | '0'..='9')) &&
      !seen.contains(key) else {
      fail("invalid or duplicate template approval")
    }
    seen[key] = ()
  }
  { ..self, offline_template_approvals: Some(approvals.copy()), }
}

///|
fn ApiService::offline_template_scope_gate(
  self : ApiService,
  template : @offline.DocumentTemplate?,
) -> HttpReply? {
  guard self.offline_template_approvals is Some(approvals) else { return None }
  let approved = match template {
    None => approvals.any(a => a.template_id != "offline-quote-v1")
    Some(template) =>
      approvals.any(a => {
        a.template_id == template.template_id &&
        a.version == template.version &&
        a.locale == template.locale &&
        a.sha256 == template.sha256
      })
  }
  if approved {
    None
  } else {
    Some(
      api_error(
        503, "TemplateApprovalScopeMissing", "the exact template version locale and digest require deployment approval",
        false,
      ),
    )
  }
}
