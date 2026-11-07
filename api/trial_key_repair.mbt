///|
/// Recover legacy personal keys issued through the private-workspace branch.
/// Bind only an unambiguous existing, same-owner, same-project trial key. The
/// durable stores make this safe to retry after a partial write or restart.
pub async fn ApiService::reconcile_trial_api_keys(
  self : ApiService,
  now : Int64,
) -> (Int32, Int32, Int32) {
  guard self.account_store is Some(accounts) &&
    self.access_store is Some(access) else {
    return (0, 0, 0)
  }
  let mut bound = 0
  let mut capped = 0
  let mut unresolved = 0
  for account in accounts.views() {
    guard accounts.active_trial_for_subject(account.subject_ref, now)
      is Some(trial) else {
      continue
    }
    let candidates = access
      .views_for_subject(trial.tenant_ref, account.subject_ref)
      .filter(key => {
        key.organization_id == Some(trial.organization_id) &&
        key.project_id == Some(trial.project_id) &&
        key.revoked_unix_ms is None &&
        key.expires_unix_ms > now &&
        key.issued_unix_ms >= trial.starts_unix_ms &&
        key.allowed_models.length() > 0 &&
        key.allowed_models.all(model => trial.allowed_models.contains(model)) &&
        key.scopes.length() > 0 &&
        key.scopes.all(scope => scope is (ModelList | Inference)) &&
        trial.api_key_id.map_or(true, id => key.key_id == id)
      })
    match candidates {
      [key] => {
        if access.cap_expiry_for_subject(
            key.key_id,
            trial.tenant_ref,
            account.subject_ref,
            trial.expires_unix_ms,
            now,
          ) {
          capped += 1
        }
        if trial.api_key_id is None {
          ignore(accounts.bind_trial_api_key(trial.trial_id, key.key_id, now))
          bound += 1
        }
      }
      [] => ()
      _ => unresolved += 1
    }
  }
  (bound, capped, unresolved)
}
