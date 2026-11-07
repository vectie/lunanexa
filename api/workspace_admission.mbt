///|
/// Selects administrator-granted private-cloud workspace access. Commercial
/// machine ordering is deliberately unaffected. Defaults to false.
pub fn ApiService::with_private_cloud_workspace_access(
  self : ApiService,
  enabled : Bool,
) -> ApiService {
  { ..self, private_cloud_workspace_access: enabled, }
}

///|
/// The registered private endpoint is tenant-bound. An empty model scope or a
/// shared/foreign alias never inherits unlimited request access.
fn ApiService::private_model_key_scope(
  self : ApiService,
  tenant_ref : String,
  models : Array[String],
) -> Bool {
  match self.external_text_route {
    Some(route) =>
      route.tenant_ref == tenant_ref &&
      models.length() > 0 &&
      models.all(model => model == route.model_alias)
    None => false
  }
}

///|
async fn ApiService::private_workspace_key_authorized(
  self : ApiService,
  key_id : String,
  tenant_ref : String,
  subject_ref : String,
  now : Int64,
) -> Bool {
  // A commercial credential never becomes a private-cloud credential when
  // an order ends or its contract is revoked.
  match self.machine_commerce_store {
    Some(machine) =>
      if machine.order_for_access_key(key_id) is Some(_) {
        return false
      }
    None => ()
  }
  self.private_workspace_authorized(tenant_ref, subject_ref, now)
}

///|
async fn ApiService::private_workspace_authorized(
  self : ApiService,
  tenant_ref : String,
  subject_ref : String,
  now : Int64,
) -> Bool {
  if !self.private_cloud_workspace_access {
    return false
  }
  // A personal trial also has a Developer workspace grant. That grant is
  // derivative of the trial, not an administrator-issued company grant.
  // Keep the distinction after expiry/revocation; a different company tenant
  // for the same person is unaffected.
  match self.account_store {
    Some(accounts) =>
      match
        accounts
        .views()
        .iter()
        .find_first(account => account.subject_ref == subject_ref) {
        Some(account) =>
          if accounts.trial_for_account(account.account_id) is Some(trial) &&
            trial.tenant_ref == tenant_ref {
            return false
          }
        None => ()
      }
    None => ()
  }
  match self.workspace_directory {
    Some(directory) =>
      try {
        ignore(
          directory.authorize_subject_for_tenant(
            subject_ref,
            tenant_ref,
            Developer,
            now,
          ),
        )
        true
      } catch {
        _ => false
      }
    None => false
  }
}
