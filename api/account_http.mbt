///|
fn account_path(path : String) -> Bool {
  path == "/v1/auth/session:exchange" ||
  path == "/v1/auth/self" ||
  path == "/v1/auth/sessions" ||
  path == "/v1/auth/sessions:revoke-all" ||
  path == "/v1/auth/logout" ||
  path.has_prefix("/v1/auth/sessions/") ||
  path == "/v1/accounts" ||
  path.has_prefix("/v1/accounts/")
}

///|
priv struct SessionExchangeIntent {
  lifetime_ms : Int64
} derive(FromJson)

///|
priv struct AccountCreateIntent {
  account_id : String
  subject_ref : String
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[@account.AccountRole]
  state : @account.AccountState
} derive(FromJson)

///|
priv struct AccountRolesIntent {
  roles : Array[@account.AccountRole]
} derive(FromJson)

///|
fn decode_session_exchange(body : String) -> SessionExchangeIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_account_create(body : String) -> AccountCreateIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_account_roles(body : String) -> AccountRolesIntent? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn valid_account_roles(roles : Array[@account.AccountRole]) -> Bool {
  roles.length() > 0 &&
  roles.length() <= 3 &&
  roles.all(role => roles.count(role) == 1)
}

///|
fn safe_identity_value(value : String, maximum : Int) -> Bool {
  value.trim() != "" &&
  value.length() <= maximum &&
  value.all(character => {
    character.is_printable() && character != '\n' && character != '\r'
  })
}

///|
fn constant_time_identity_equal(left : String, right : String) -> Bool {
  if left.length() != right.length() {
    return false
  }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn parse_identity_time(value : String) -> Int64? {
  Some(@string.parse_int64(value)) catch {
    _ => None
  }
}

///|
priv struct TrustedIdentityAssertion {
  issuer : String
  subject : String
  replay_key : String
}

///|
/// Verifies the exact assertion emitted by the external identity gateway.
/// Roles and tenant scope are intentionally absent: both come only from
/// LunaNexa's durable account/portal/workspace stores.
fn ApiService::trusted_identity_assertion(
  self : ApiService,
  headers : Map[String, String],
  now_unix_ms : Int64,
) -> TrustedIdentityAssertion? {
  if self.identity_assertion_secret.length() < 32 {
    return None
  }
  guard header(headers, "X-LunaNexa-Identity-Issuer") is Some(issuer) &&
    header(headers, "X-LunaNexa-Identity-Subject") is Some(subject) &&
    header(headers, "X-LunaNexa-Identity-Nonce") is Some(nonce) &&
    header(headers, "X-LunaNexa-Identity-Issued-At") is Some(issued_raw) &&
    header(headers, "X-LunaNexa-Identity-Expires-At") is Some(expires_raw) &&
    header(headers, "X-LunaNexa-Identity-Signature") is Some(signature) &&
    parse_identity_time(issued_raw) is Some(issued_unix_ms) &&
    parse_identity_time(expires_raw) is Some(expires_unix_ms) else {
    return None
  }
  if !safe_identity_value(issuer, 512) ||
    !safe_identity_value(subject, 1024) ||
    !@contracts.valid_identifier(nonce) ||
    issued_unix_ms > now_unix_ms + 5000L ||
    issued_unix_ms < now_unix_ms - 30000L ||
    expires_unix_ms <= now_unix_ms ||
    expires_unix_ms <= issued_unix_ms ||
    expires_unix_ms - issued_unix_ms > 30000L {
    return None
  }
  let canonical = "lunanexa.identity.assertion.v1\n\{issuer}\n\{subject}\n\{issued_raw}\n\{expires_raw}\n\{nonce}"
  let signature_hex = @crypto.bytes_to_hex_string(
    @crypto.hmac(
      @crypto.SHA256::new(),
      @utf8.encode(self.identity_assertion_secret).view(),
      @utf8.encode(canonical).view(),
    ),
  )
  let expected = "sha256:\{signature_hex}"
  if !constant_time_identity_equal(signature, expected) {
    return None
  }
  Some({
    issuer,
    subject,
    replay_key: "lunanexa.identity.nonce.v1\n\{issuer}\n\{nonce}",
  })
}

///|
fn account_error(error : Error) -> HttpReply {
  match error {
    @account.AccountError::AlreadyExists(_) =>
      api_error(409, "AlreadyExists", "account identity already exists", false)
    @account.AccountError::NotFound(_) =>
      api_error(404, "NotFound", "account record was not found", false)
    @account.AccountError::InvalidTransition(_) =>
      api_error(
        409, "InvalidTransition", "account transition was rejected", false,
      )
    @account.AccountError::AssertionReplayed =>
      api_error(
        409, "AssertionReplayed", "identity assertion was already consumed", false,
      )
    @account.AccountError::Unauthorized =>
      api_error(
        401, "Unauthenticated", "account session is not authorized", false,
      )
    _ =>
      api_error(400, "AccountRejected", "account request was rejected", false)
  }
}

///|
async fn ApiService::current_account_session(
  self : ApiService,
  headers : Map[String, String],
) -> @account.AccountAuthorization? {
  guard self.account_store is Some(accounts) &&
    bearer_secret(headers) is Some(secret) &&
    secret.has_prefix("lnxs_") else {
    return None
  }
  Some(accounts.authorize(secret, @async.now())) catch {
    _ => None
  }
}

///|
fn path_identifier(path : String, prefix : String, suffix : String) -> String? {
  if !path.has_prefix(prefix) ||
    !path.has_suffix(suffix) ||
    path.length() <= prefix.length() + suffix.length() {
    return None
  }
  let value = path[prefix.length():path.length() - suffix.length()].to_owned()
  if @contracts.valid_identifier(value) {
    Some(value)
  } else {
    None
  }
}

///|
async fn ApiService::handle_accounts(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.account_store is Some(accounts) else {
    return api_error(
      503, "AccountStoreUnavailable", "durable human-account authority is unavailable",
      true,
    )
  }
  if verb == Post && path == "/v1/auth/session:exchange" {
    guard allow_asserted_subject &&
      decode_session_exchange(body) is Some(intent) &&
      self.trusted_identity_assertion(headers, @async.now()) is Some(assertion) else {
      return api_error(
        401, "IdentityAssertionRejected", "a fresh signed identity assertion is required",
        false,
      )
    }
    let issued = try
      accounts.issue_session(
        assertion.issuer,
        assertion.subject,
        assertion.replay_key,
        intent.lifetime_ms,
        @async.now(),
      )
    catch {
      error => return account_error(error)
    } noraise {
      value => value
    }
    return json_reply(201, issued.to_json())
  }
  if path.has_prefix("/v1/auth/") {
    guard self.current_account_session(headers) is Some(authorization) else {
      return api_error(
        401, "Unauthenticated", "a valid account session is required", false,
      )
    }
    match (verb, path) {
      (Get, "/v1/auth/self") =>
        return json_reply(200, authorization.account.to_json())
      (Get, "/v1/auth/sessions") =>
        return json_reply(
          200,
          accounts
          .sessions_for_account(authorization.account.account_id)
          .to_json(),
        )
      (Post, "/v1/auth/logout") => {
        let revoked = accounts.revoke_session(
          authorization.session_id,
          authorization.account.account_id,
          @async.now(),
        )
        return json_reply(200, revoked.to_json())
      }
      (Post, "/v1/auth/sessions:revoke-all") => {
        let count = accounts.revoke_all_sessions(
          authorization.account.account_id,
          @async.now(),
        )
        return json_reply(200, { "revoked_sessions": count })
      }
      (Post, _) => {
        guard path_identifier(path, "/v1/auth/sessions/", ":revoke")
          is Some(session_id) else {
          return api_error(404, "NotFound", "route was not found", false)
        }
        let revoked = try
          accounts.revoke_session(
            session_id,
            authorization.account.account_id,
            @async.now(),
          )
        catch {
          error => return account_error(error)
        } noraise {
          value => value
        }
        return json_reply(200, revoked.to_json())
      }
      _ => return api_error(404, "NotFound", "route was not found", false)
    }
  }
  guard self.operator_identity(headers) is Some(operator_id) else {
    return api_error(
      401, "Unauthenticated", "valid operator authority is required", false,
    )
  }
  match (verb, path) {
    (Get, "/v1/accounts") => json_reply(200, accounts.views().to_json())
    (Post, "/v1/accounts") => {
      guard decode_account_create(body) is Some(intent) else {
        return api_error(400, "InvalidRequest", "invalid account intent", false)
      }
      let now = @async.now()
      let created = try
        accounts.create({
          version: @account.contract_version,
          account_id: intent.account_id,
          subject_ref: intent.subject_ref,
          identity_issuer: intent.identity_issuer,
          identity_subject_sha256: @account.identity_subject_digest(
            intent.identity_issuer,
            intent.identity_subject,
          ),
          display_name: intent.display_name,
          email: intent.email,
          identity_receipt: intent.identity_receipt,
          roles: intent.roles,
          state: intent.state,
          created_unix_ms: now,
          updated_unix_ms: now,
        })
      catch {
        error => return account_error(error)
      } noraise {
        value => value
      }
      self.operator_audit_as(
        operator_id,
        "account.create",
        created.account_id,
        "account-created:\{created.account_id}",
      )
      json_reply(201, created.to_json())
    }
    (Post, _) => {
      let transition : (@account.AccountState, String)? = if path.has_suffix(
          ":activate",
        ) {
        Some((Active, ":activate"))
      } else if path.has_suffix(":suspend") {
        Some((Suspended, ":suspend"))
      } else if path.has_suffix(":revoke") {
        Some((Revoked, ":revoke"))
      } else {
        None
      }
      match transition {
        Some((state, suffix)) => {
          guard path_identifier(path, "/v1/accounts/", suffix)
            is Some(account_id) else {
            return api_error(404, "NotFound", "route was not found", false)
          }
          let now = @async.now()
          guard accounts
            .views()
            .iter()
            .find_first(account => account.account_id == account_id)
            is Some(current_account) else {
            return account_error(@account.AccountError::NotFound(account_id))
          }
          if state == Suspended || state == Revoked {
            match self.access_store {
              Some(access) =>
                ignore(access.revoke_subject(current_account.subject_ref, now)) catch {
                  _ =>
                    return api_error(
                      500, "AccountCredentialRevocationFailed", "account state was not changed because credential revocation failed",
                      true,
                    )
                }
              None => ()
            }
          }
          let updated = try accounts.set_state(account_id, state, now) catch {
            error => return account_error(error)
          } noraise {
            value => value
          }
          self.operator_audit_as(
            operator_id,
            "account.state.change",
            account_id,
            "account-state:\{account_id}:\{Repr(state)}",
          )
          json_reply(200, updated.to_json())
        }
        None => {
          guard path_identifier(path, "/v1/accounts/", ":set-roles")
            is Some(account_id) else {
            return api_error(404, "NotFound", "route was not found", false)
          }
          guard decode_account_roles(body) is Some(intent) &&
            valid_account_roles(intent.roles) else {
            return api_error(
              400, "InvalidRequest", "invalid account role intent", false,
            )
          }
          let now = @async.now()
          guard accounts
            .views()
            .iter()
            .find_first(account => account.account_id == account_id)
            is Some(current_account) else {
            return account_error(@account.AccountError::NotFound(account_id))
          }
          if @account.role_allows(current_account.roles, EnterpriseUser) &&
            !@account.role_allows(intent.roles, EnterpriseUser) {
            match self.access_store {
              Some(access) =>
                ignore(access.revoke_subject(current_account.subject_ref, now)) catch {
                  _ =>
                    return api_error(
                      500, "AccountCredentialRevocationFailed", "account roles were not changed because credential revocation failed",
                      true,
                    )
                }
              None => ()
            }
          }
          let updated = try
            accounts.set_roles(account_id, intent.roles, now)
          catch {
            error => return account_error(error)
          } noraise {
            value => value
          }
          self.operator_audit_as(
            operator_id,
            "account.roles.change",
            account_id,
            "account-roles:\{account_id}",
          )
          json_reply(200, updated.to_json())
        }
      }
    }
    _ => api_error(404, "NotFound", "route was not found", false)
  }
}
