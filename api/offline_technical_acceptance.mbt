///|
pub fn ApiService::with_technical_acceptance_authorization(
  self : ApiService,
  authorization : @offline.TechnicalAcceptanceAuthorization,
) -> ApiService raise Failure {
  guard (
      authorization.order_id.has_prefix("technical-acceptance-") ||
      (
        authorization.order_binding is Some(_) &&
        authorization.order_id.has_prefix("offline-order-")
      )
    ) &&
    authorization.purchaser_subject_ref.has_prefix("subject-") &&
    !authorization.user_authorization_ref.is_empty() &&
    authorization.expires_unix_ms > 0L else {
    raise Failure("invalid single-order technical authorization")
  }
  { ..self, technical_acceptance_authorization: Some(authorization), }
}

///|
fn ApiService::technical_scope_allows(
  self : ApiService,
  order : @offline.CommercialOrder,
  reference : String,
  expires : Int64,
  now : Int64,
) -> Bool {
  self.technical_acceptance_authorization is Some(scope) &&
  scope.order_id == order.order_id &&
  scope.purchaser_subject_ref == order.purchaser_subject_ref &&
  scope.user_authorization_ref == reference &&
  scope.order_binding.map_or(true, binding => binding.matches_order(order)) &&
  now < scope.expires_unix_ms &&
  expires <= scope.expires_unix_ms
}

///|
priv struct TechnicalWaiverIntent {
  order_id : String
  expected_generation : Int64
  waiver_id : String
  authority_target_ref : String
  grant_id : String
  expires_unix_ms : Int64?
  user_authorization_ref : String
  reason : String
} derive(FromJson)

///|
/// Actual signed-in identity and administrator grant remain mandatory. This
/// does not assert that commercial documentary KYC has been performed.
async fn ApiService::technical_identity(
  self : ApiService,
  subject : String,
  now : Int64,
) -> @account.AccountView? {
  guard self.account_store is Some(accounts) else { return None }
  guard accounts.views().iter().find_first(a => a.subject_ref == subject)
    is Some(a) &&
    a.state == Active &&
    (
      a.email.has_prefix("technical-") ||
      (
        self.technical_acceptance_authorization
        is Some({ purchaser_subject_ref: bound, order_binding: Some(_), .. }) &&
        bound == subject
      )
    ) &&
    a.identity_issuer.has_prefix("https://") &&
    !a.identity_receipt.is_empty() &&
    accounts
    .sessions_for_account(a.account_id)
    .any(s => {
      s.revoked_unix_ms is None &&
      s.created_unix_ms <= now &&
      s.expires_unix_ms > now
    }) else {
    return None
  }
  Some(a)
}

///|
async fn ApiService::technical_workspace_bound(
  self : ApiService,
  order : @offline.CommercialOrder,
  target : String,
  grant_id : String,
  expires : Int64,
  now : Int64,
  allow_active : Bool,
  kind? : @offline.EntitlementKind = WorkspaceLease,
) -> Bool {
  guard self.workspace_directory is Some(directory) else { return false }
  let s = directory.snapshot(now)
  guard s.users
    .iter()
    .find_first(u => u.subject_ref == order.purchaser_subject_ref)
    is Some(user) &&
    user.state == UserActive &&
    s.access_grants.any(g => {
      g.grant_id == grant_id &&
      g.user_id == user.user_id &&
      g.tenant_ref == order.tenant_ref &&
      g.access == Developer &&
      g.state == GrantActive &&
      g.starts_unix_ms <= now &&
      g.expires_unix_ms >= expires
    }) else {
    return false
  }
  match kind {
    WorkspaceLease =>
      s.leases.any(l => {
        l.lease_id == target &&
        l.subject_ref == user.subject_ref &&
        l.tenant_ref == order.tenant_ref &&
        l.access == Developer &&
        (l.state == Requested || (allow_active && l.state == Active)) &&
        l.expires_unix_ms <= expires &&
        l.expires_unix_ms <= order.expires_unix_ms &&
        l.expires_unix_ms > now &&
        l.expires_unix_ms - l.starts_unix_ms <= 3600000L
      })
    ExclusiveMachineLease => {
      guard self.exclusive_lease_store is Some(leases) &&
        leases.lease(target) is Some(l) else {
        return false
      }
      l.intent.subject_ref == user.subject_ref &&
      (
        l.state == Reserved ||
        (allow_active && (l.state == Provisioning || l.state == Active))
      ) &&
      l.intent.expires_unix_ms > now &&
      l.intent.expires_unix_ms <= expires &&
      l.intent.expires_unix_ms <= order.expires_unix_ms &&
      l.intent.expires_unix_ms - l.intent.starts_unix_ms <= 3600000L
    }
    CapacityCommitment =>
      self.commercial_store.snapshot(order.organization_id).commitments.any(c => {
        c.commitment_id == target &&
        c.organization_id == order.organization_id &&
        c.approved_by is Some(_) &&
        (c.state == Approved || (allow_active && c.state == ActiveCommitment)) &&
        c.effective_until_unix_ms > now &&
        c.effective_until_unix_ms <= expires &&
        c.effective_until_unix_ms <= order.expires_unix_ms &&
        c.effective_until_unix_ms - c.effective_from_unix_ms <= 3600000L
      })
  }
}

///|
async fn ApiService::technical_activation_allowed(
  self : ApiService,
  order : @offline.CommercialOrder,
  activation : @offline.EntitlementActivation,
  now : Int64,
) -> Bool {
  guard order.technical_acceptance_waiver is Some(w) else { return true }
  guard self.technical_acceptance_authorization is Some(scope) &&
    scope.order_binding == w.order_binding else {
    return false
  }
  if !self.technical_scope_allows(
      order,
      w.user_authorization_ref,
      w.expires_unix_ms,
      now,
    ) {
    return false
  }
  @offline.validate_technical_activation(order, activation, now) catch {
    _ => return false
  }
  guard self.technical_identity(order.purchaser_subject_ref, now) is Some(a) &&
    a.account_id == w.purchaser_account_id &&
    a.identity_issuer == w.identity_issuer &&
    a.identity_receipt == w.identity_receipt else {
    return false
  }
  self.technical_workspace_bound(
    order,
    w.authority_target_ref,
    w.grant_id,
    w.expires_unix_ms,
    now,
    true,
    kind=w.entitlement_kind(),
  )
}

///|
async fn ApiService::authorize_technical_waiver(
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
  guard self.offline_commerce_store is Some(store) &&
    (decode_offline(body) : TechnicalWaiverIntent?) is Some(intent) else {
    return api_error(
      400, "InvalidRequest", "invalid technical waiver request", false,
    )
  }
  let now = @async.now()
  let order = store.order_for_operator(intent.order_id)
  // UI callers bind to the existing target's expiry, not a new browser clock
  // deadline. An exact retry must retain the original waiver lifetime.
  let expires = match intent.expires_unix_ms {
    Some(value) => value
    None =>
      match order.technical_acceptance_waiver {
        Some(w) => w.expires_unix_ms
        None =>
          match
            self.technical_target_expiry(order, intent.authority_target_ref) {
            Some(value) => value
            None =>
              return api_error(
                409, "TechnicalAuthorityRequired", "an existing approved resource target is required",
                false,
              )
          }
      }
  }
  if !self.technical_scope_allows(
      order,
      intent.user_authorization_ref,
      expires,
      now,
    ) {
    return api_error(
      403, "TechnicalAcceptanceNotAuthorized", "this exact order is not enabled by the current time-bounded deployment authorization",
      false,
    )
  }
  // An exact retry returns the original server-attributed authorization; it
  // never refreshes the term or replaces the authorizing session.
  if order.technical_acceptance_waiver is Some(w) {
    if w.waiver_id == intent.waiver_id &&
      w.authority_target_ref == intent.authority_target_ref &&
      w.grant_id == intent.grant_id &&
      w.expires_unix_ms == expires &&
      w.user_authorization_ref == intent.user_authorization_ref &&
      w.reason == intent.reason &&
      w.operator_account_id == operator.account.account_id {
      return json_reply(200, order.to_json())
    }
    return api_error(
      409, "IdempotencyConflict", "technical authorization is immutable", false,
    )
  }
  guard self.technical_identity(order.purchaser_subject_ref, now)
    is Some(purchaser) &&
    order.quote is Some(quote) &&
    self.technical_workspace_bound(
      order,
      intent.authority_target_ref,
      intent.grant_id,
      expires,
      now,
      false,
      kind=self.technical_acceptance_authorization.map_or(WorkspaceLease, scope => {
        scope.order_binding.map_or(WorkspaceLease, b => b.entitlement_kind)
      }),
    ) else {
    return api_error(
      409, "TechnicalAuthorityRequired", "actual OIDC identity and exact administrator-approved requested workspace are required",
      false,
    )
  }
  let waiver : @offline.TechnicalAcceptanceWaiver = {
    waiver_id: intent.waiver_id,
    classification: "technical-acceptance-waived-not-paid",
    waived_requirements: @offline.technical_waived_requirements(),
    order_id: order.order_id,
    tenant_ref: order.tenant_ref,
    organization_id: order.organization_id,
    purchaser_subject_ref: order.purchaser_subject_ref,
    quote,
    authority_target_ref: intent.authority_target_ref,
    grant_id: intent.grant_id,
    purchaser_account_id: purchaser.account_id,
    identity_issuer: purchaser.identity_issuer,
    identity_receipt: purchaser.identity_receipt,
    identity_verification_method: "actual-oidc-not-commercial-kyc",
    operator_account_id: operator.account.account_id,
    operator_subject_ref: operator.account.subject_ref,
    operator_session_id: operator.session_id,
    user_authorization_ref: intent.user_authorization_ref,
    reason: intent.reason,
    issued_unix_ms: now,
    expires_unix_ms: expires,
    order_binding: self.technical_acceptance_authorization.map_or(None, scope => {
      scope.order_binding
    }),
  }
  json_reply(
    201,
    store
    .authorize_technical_acceptance(
      order.order_id,
      intent.expected_generation,
      waiver,
    )
    .to_json(),
  )
}
