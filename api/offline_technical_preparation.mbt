///|
/// Reuse the durable onboarding saga with the already authenticated purchaser.
/// This prepares a requested workspace; it does not activate it or sign a contract.
async fn ApiService::prepare_technical_workspace(
  self : ApiService,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.account_session_authorization(headers, PlatformOperator)
    is Some(operator) else {
    return api_error(
      403, "OperatorSessionRequired", "a real active operator browser session is required",
      false,
    )
  }
  guard self.offline_commerce_store is Some(commerce) &&
    self.access_onboarding_store is Some(journal) &&
    self.account_store is Some(accounts) &&
    self.technical_acceptance_authorization is Some(scope) &&
    (decode_offline(body) : OfflineOrderAction?) is Some(action) else {
    return api_error(
      409, "TechnicalAcceptanceNotAuthorized", "explicit order authorization and onboarding authorities are required",
      false,
    )
  }
  let now = @async.now()
  let order = commerce.order_for_operator(action.order_id)
  guard self.technical_scope_allows(
      order,
      scope.user_authorization_ref,
      now + 1L,
      now,
    ) &&
    scope.order_binding is Some(binding) &&
    binding.entitlement_kind == WorkspaceLease &&
    order.generation == action.expected_generation &&
    (order.state == Quoted || order.state == PendingInternalApproval) &&
    order.technical_acceptance_waiver is None &&
    self.technical_identity(order.purchaser_subject_ref, now) is Some(purchaser) else {
    return api_error(
      409, "TechnicalAcceptanceNotAuthorized", "current order, purchaser login and workspace authorization are required",
      false,
    )
  }
  guard accounts.snapshot().accounts
    .iter()
    .find_first(a => a.account_id == purchaser.account_id)
    is Some(account) else {
    return api_error(
      409, "TechnicalIdentityRequired", "the existing purchaser identity is required",
      false,
    )
  }
  let operation_id = "technical-access-" + order.order_id
  let record = match journal.record(operation_id) {
    Some(existing) => existing
    None => {
      let expires = if now + 2700000L < scope.expires_unix_ms {
        now + 2700000L
      } else {
        scope.expires_unix_ms
      }
      guard expires - now >= 300000L else {
        return api_error(
          409, "TechnicalAuthorizationExpiring", "less than five minutes remain in the approved test window",
          false,
        )
      }
      let fingerprint = @crypto.bytes_to_hex_string(
        @crypto.sha256(@utf8.encode(order.order_id)),
      )
      journal.begin(
        {
          operation_id,
          fingerprint,
          requested_by: operator.account.subject_ref,
          account_id: account.account_id,
          subject_ref: account.subject_ref,
          identity_issuer: account.identity_issuer,
          identity_subject_sha256: account.identity_subject_sha256,
          display_name: account.display_name,
          email: account.email,
          organization_id: order.organization_id,
          tenant_ref: order.tenant_ref,
          membership_id: "technical-member-" + fingerprint,
          user_id: "technical-user-" + fingerprint,
          grant_id: "technical-grant-" + fingerprint,
          lease_id: "technical-lease-" + fingerprint,
          identity_receipt: account.identity_receipt,
          expires_unix_ms: expires,
          enterprise_gpu_capabilities: None,
        },
        now,
      )
    }
  }
  guard record.intent.subject_ref == order.purchaser_subject_ref &&
    record.intent.organization_id == order.organization_id &&
    record.intent.tenant_ref == order.tenant_ref &&
    record.intent.expires_unix_ms > now &&
    record.intent.expires_unix_ms <= scope.expires_unix_ms &&
    record.intent.expires_unix_ms - record.created_unix_ms <= 3600000L else {
    return api_error(
      409, "TechnicalTargetMismatch", "the prior preparation cannot be rebound or extended",
      false,
    )
  }
  if record.status == Conflicted {
    return api_error(
      409, "AccessPackageConflict", "the prior preparation requires explicit recovery",
      false,
    )
  }
  if record.status == RecoverableFailure {
    ignore(journal.retry(operation_id, now))
  }
  self.execute_webide_access_package(record.intent, now)
}

///|
async fn ApiService::technical_authorization_view(self : ApiService) -> Json {
  let targets : Array[Json] = []
  if self.technical_acceptance_authorization is Some(scope) &&
    self.access_onboarding_store is Some(journal) &&
    journal.record("technical-access-" + scope.order_id) is Some(record) &&
    (record.step == Prepared || record.step == Enabled) {
    targets.push({
      "order_id": scope.order_id,
      "authority_target_ref": record.intent.lease_id,
      "grant_id": record.intent.grant_id,
      "expires_unix_ms": record.intent.expires_unix_ms,
    })
  }
  {
    "authorizations": self.technical_acceptance_authorization
    .map_or([], s => [s])
    .to_json(),
    "prepared_targets": targets.to_json(),
  }
}
