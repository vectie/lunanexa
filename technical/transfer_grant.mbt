///|
pub(all) enum TransferScope {
  ModelRead
  RuntimeImageRead
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TransferGrant {
  grant_id : String
  nonce : String
  node_id : String
  deployment_id : String
  model_digest : String
  scope : TransferScope
  issued_unix_ms : Int64
  expires_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct TransferGrantUse {
  node_id : String
  deployment_id : String
  model_digest : String
  scope : TransferScope
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum GrantAuthenticity {
  Verified
  Unverified
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum TransferGrantRejection {
  AuthenticityRequired
  InvalidGrant
  GrantNotYetValid
  GrantExpired
  GrantLifetimeExceeded
  UnsafeLifetimePolicy
  NonceReplayed
  NodeMismatch
  DeploymentMismatch
  ModelMismatch
  ScopeMismatch
} derive(Debug, Eq, ToJson, FromJson)

///|
pub let transfer_grant_absolute_max_lifetime_ms : Int64 = 900000L

///|
pub(all) enum TransferGrantDecision {
  Accepted(consumed_nonce~ : String)
  Rejected(TransferGrantRejection)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn validate_transfer_grant(
  grant : TransferGrant,
  requested : TransferGrantUse,
  authenticity : GrantAuthenticity,
  consumed_nonces : Array[String],
  now_unix_ms : Int64,
  maximum_lifetime_ms : Int64,
) -> TransferGrantDecision {
  if authenticity != Verified {
    return Rejected(AuthenticityRequired)
  }
  if grant.grant_id.is_empty() ||
    grant.grant_id.length() > 128 ||
    grant.nonce.is_empty() ||
    grant.nonce.length() < 16 ||
    grant.nonce.length() > 128 ||
    grant.node_id.is_empty() ||
    grant.node_id.length() > 128 ||
    grant.deployment_id.is_empty() ||
    grant.deployment_id.length() > 128 ||
    !valid_digest(grant.model_digest) ||
    grant.issued_unix_ms < 0L ||
    grant.expires_unix_ms <= grant.issued_unix_ms {
    return Rejected(InvalidGrant)
  }
  if maximum_lifetime_ms <= 0L ||
    maximum_lifetime_ms > transfer_grant_absolute_max_lifetime_ms {
    return Rejected(UnsafeLifetimePolicy)
  }
  if now_unix_ms < grant.issued_unix_ms {
    return Rejected(GrantNotYetValid)
  }
  if now_unix_ms >= grant.expires_unix_ms {
    return Rejected(GrantExpired)
  }
  if grant.expires_unix_ms - grant.issued_unix_ms > maximum_lifetime_ms {
    return Rejected(GrantLifetimeExceeded)
  }
  if consumed_nonces.contains(grant.nonce) {
    return Rejected(NonceReplayed)
  }
  if requested.node_id != grant.node_id {
    return Rejected(NodeMismatch)
  }
  if requested.deployment_id != grant.deployment_id {
    return Rejected(DeploymentMismatch)
  }
  if requested.model_digest != grant.model_digest {
    return Rejected(ModelMismatch)
  }
  if requested.scope != grant.scope {
    return Rejected(ScopeMismatch)
  }
  Accepted(consumed_nonce=grant.nonce)
}
