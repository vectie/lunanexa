///|
/// Selects administrator-granted private-cloud workspace access. Commercial
/// machine ordering is deliberately unaffected. Defaults to false.
pub fn ApiService::with_private_cloud_workspace_access(
  self : ApiService,
  enabled : Bool,
) -> ApiService {
  { ..self, private_cloud_workspace_access: enabled }
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
