///|
fn scoped_outcome(model : AppModel, outcome : Outcome) -> AppMessage {
  ScopedOutcome(
    model.session_generation,
    model.portal.selected_organization_id,
    outcome,
  )
}

///|
async fn load_onboarding_account(
  model : AppModel,
) -> @enterprise_ui.AccountView? {
  if !model.token.has_prefix("lnxs_") {
    return None
  }
  if model.portal.account is Some(account) {
    return Some(account)
  }
  Some(
    @json.from_json(
      @json.parse(
        request(
          "GET",
          model.endpoint,
          "/v1/auth/self",
          model.token,
          model.subject_ref,
        ),
      ),
    ),
  )
}

///|
fn onboarding_account_defaults(
  portal : @enterprise_ui.EnterpriseState,
  account : @enterprise_ui.AccountView?,
) -> @enterprise_ui.EnterpriseState {
  guard account is Some(value) else { return portal }
  let mut username = "u_"
  for character in value.account_id.to_lower() {
    if username.length() >= 30 {
      break
    }
    if (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') {
      username += character.to_string()
    }
  }
  {
    ..portal,
    account,
    unix_username: if portal.unix_username.trim() == "" && username != "u_" {
      username
    } else {
      portal.unix_username
    },
    self_service: {
      ..portal.self_service,
      billing_contact_name: if portal.self_service.billing_contact_name.trim() ==
        "" {
        value.display_name
      } else {
        portal.self_service.billing_contact_name
      },
      billing_email: if portal.self_service.billing_email.trim() == "" &&
        value.email.contains("@") {
        value.email
      } else {
        portal.self_service.billing_email
      },
    },
  }
}

///|
fn waiting_for_lease_approval(model : AppModel) -> Bool {
  model.portal.membership.map_or(false, membership => membership.active) &&
  model.portal.lease_requests.any(value => {
    Some(value.submission.organization_id) ==
    model.portal.selected_organization_id &&
    value.state == Submitted
  })
}

///|
fn waiting_for_membership(model : AppModel) -> Bool {
  model.token.has_prefix("lnxs_") &&
  model.portal.account is Some(_) &&
  model.portal.route == SelfService &&
  model.portal.self_service.step == Organization &&
  (
    (
      model.portal.membership is None &&
      model.portal.selected_organization_id is None &&
      model.portal.organizations.is_empty()
    ) ||
    model.portal.trial.map_or(false, trial => {
      model.portal.membership.map_or(false, membership => {
        membership.organization_id == trial.organization_id &&
        membership.tenant_ref == trial.tenant_ref
      })
    })
  )
}

///|
fn waiting_for_application(model : AppModel) -> Bool {
  model.token.has_prefix("lnxs_") &&
  !waiting_for_membership(model) &&
  model.portal.organizations.any(value => {
    Some(value.organization.organization_id) ==
    model.portal.selected_organization_id &&
    value.organization.state == Active
  }) &&
  model.portal.membership.map_or(false, membership => {
    membership.active && @portal.role_allows(membership.roles, Developer)
  }) &&
  !model.portal.desktop_clients.any(client => client.ready) &&
  (
    model.portal.route == DesktopIde ||
    (
      model.portal.route == SelfService &&
      model.portal.self_service.step == Organization &&
      model.portal.self_service.selected_product == Some(SharedMaaS)
    )
  )
}

///|
extern "js" fn onboarding_page_visible() -> Bool =
  #| () => typeof document === "undefined" || document.visibilityState !== "hidden"
