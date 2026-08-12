///|
fn provider_callback_path(path : String) -> Bool {
  path.has_prefix("/v1/provider-callbacks/")
}

///|
fn callback_constant_time_equal(left : String, right : String) -> Bool {
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
fn valid_callback_identity(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 256 &&
  value.all(character => {
    character.is_ascii_alphabetic() ||
    character.is_ascii_digit() ||
    character == '-' ||
    character == '_' ||
    character == ':' ||
    character == '.' ||
    character == '@' ||
    character == '/'
  })
}

///| Provider adapters sign the exact raw request body and immutable routing

///|
/// headers. The signature format is lowercase hex HMAC-SHA256.
pub fn provider_callback_signature(
  provider : String,
  environment : String,
  event_id : String,
  event_unix_ms : Int64,
  body : String,
  secret : String,
) -> String {
  let key = @utf8.encode(secret)
  let material = @utf8.encode(
    "lunanexa.provider-callback.v1|\{provider}|\{environment}|\{event_id}|\{event_unix_ms}|\{body}",
  )
  @crypto.bytes_to_hex_string(
    @crypto.hmac(@crypto.SHA256::new(), key.view(), material.view()),
  )
}

///|
async fn ApiService::handle_provider_callback(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  if verb != Post || path != "/v1/provider-callbacks/commercial" {
    return api_error(
      404, "NotFound", "provider callback route was not found", false,
    )
  }
  guard header(headers, "X-LunaNexa-Provider") is Some(provider) &&
    header(headers, "X-LunaNexa-Environment") is Some(environment) &&
    header(headers, "X-LunaNexa-Event-Id") is Some(event_id) &&
    header(headers, "X-LunaNexa-Event-Timestamp") is Some(timestamp_text) &&
    header(headers, "X-LunaNexa-Signature") is Some(signature) &&
    valid_callback_identity(provider) &&
    valid_callback_identity(environment) &&
    valid_callback_identity(event_id) else {
    return api_error(
      401, "CallbackUnauthenticated", "complete provider callback authentication is required",
      false,
    )
  }
  let event_unix_ms = try @string.parse_int64(timestamp_text) catch {
    _ =>
      return api_error(
        401, "CallbackUnauthenticated", "callback timestamp is invalid", false,
      )
  } noraise {
    value => value
  }
  let now_unix_ms = @async.now()
  if event_unix_ms <= 0L ||
    event_unix_ms > now_unix_ms + 300000L ||
    event_unix_ms < now_unix_ms - 300000L {
    return api_error(
      401, "CallbackExpired", "callback timestamp is outside the five-minute replay window",
      false,
    )
  }
  guard self.provider_callback_secrets.get("\{provider}|\{environment}")
    is Some(secret) else {
    return api_error(
      401, "CallbackUnauthenticated", "callback provider is not configured", false,
    )
  }
  let expected = provider_callback_signature(
    provider, environment, event_id, event_unix_ms, body, secret,
  )
  if signature.length() != 64 ||
    !signature.all(character => {
      character.is_ascii_digit() || (character >= 'a' && character <= 'f')
    }) ||
    !callback_constant_time_equal(signature, expected) {
    return api_error(
      401, "CallbackUnauthenticated", "callback signature is invalid", false,
    )
  }
  guard decode_external_callback(body) is Some(decoded) &&
    decoded.callback_id == event_id &&
    decoded.provider == provider &&
    decoded.environment == environment &&
    decoded.provider_event_unix_ms == event_unix_ms else {
    return api_error(
      400, "CallbackBindingMismatch", "callback body does not match its authenticated routing headers",
      false,
    )
  }
  let callback : @commercial_integrations.ExternalCallback = {
    ..decoded
    // Canonicalize replay-sensitive transport facts. The provider event time
    // is authenticated and stable; local receipt time is retained in audit.
    ,
    received_unix_ms: event_unix_ms,
    signature_verified: true,
  }
  let before_commercial = self.commercial_store.durable_snapshot()
  let before_integrations = self.commercial_integrations.durable_snapshot()
  let (record, result) = try
    self.commercial_integrations.reconcile_callback(callback)
  catch {
    _ =>
      return commercial_rejected("authenticated provider callback was rejected")
  } noraise {
    accepted => accepted
  }
  if record.kind == IdentityVerification && record.state == Verified {
    try
      self.commercial_store.record_identity_verification(
        record.organization_id,
        "provider:\{provider}:\{event_id}",
      )
    catch {
      _ => {
        ignore(
          self.commercial_store.replace_from_durable_snapshot(before_commercial),
        )
        ignore(
          self.commercial_integrations.replace_from_durable_snapshot(
            before_integrations,
          ),
        )
        return commercial_rejected(
          "identity verification could not activate the organization",
        )
      }
    } noraise {
      _ => ()
    }
  }
  if record.kind == QualifiedSignature &&
    record.state == Verified &&
    record.entitlement_transaction_ref is Some(link) &&
    link.has_prefix("portal-agreement:") {
    guard self.portal_store is Some(portal) else {
      ignore(
        self.commercial_integrations.replace_from_durable_snapshot(
          before_integrations,
        ),
      )
      return commercial_rejected(
        "qualified signature targets an unavailable enterprise portal",
      )
    }
    let agreement_id = link["portal-agreement:".length():].to_owned()
    guard portal.snapshot().agreements
      .iter()
      .find_first(agreement => {
        agreement.agreement_id == agreement_id &&
        agreement.organization_id == record.organization_id
      })
      is Some(agreement) &&
      agreement.signer_subject_ref is Some(signer_subject_ref) &&
      record.expected_document_hash is Some(document_hash) else {
      ignore(
        self.commercial_integrations.replace_from_durable_snapshot(
          before_integrations,
        ),
      )
      return commercial_rejected(
        "qualified signature does not match a portal agreement request",
      )
    }
    if agreement.state == Executed {
      if agreement.executed_artifact_hash != Some(document_hash) {
        ignore(
          self.commercial_integrations.replace_from_durable_snapshot(
            before_integrations,
          ),
        )
        return commercial_rejected(
          "executed portal agreement evidence does not match the provider callback",
        )
      }
    } else {
      try
        portal.record_execution(
          {
            agreement_id,
            expected_generation: agreement.generation,
            signer_subject_ref,
            executed_artifact_hash: document_hash,
            evidence_receipt: "provider:\{provider}:\{event_id}",
          },
          event_unix_ms,
        )
      catch {
        _ => {
          ignore(
            self.commercial_integrations.replace_from_durable_snapshot(
              before_integrations,
            ),
          )
          return commercial_rejected(
            "qualified signature could not execute the portal agreement",
          )
        }
      } noraise {
        _ => ()
      }
    }
  }
  self.persist_commercial_state() catch {
    _ => {
      ignore(
        self.commercial_store.replace_from_durable_snapshot(before_commercial),
      )
      ignore(
        self.commercial_integrations.replace_from_durable_snapshot(
          before_integrations,
        ),
      )
      return api_error(
        503, "CommercialPersistenceFailed", "provider callback was rolled back because durable commit failed",
        true,
      )
    }
  }
  self.operator_audit(
    "provider.callback.reconcile",
    record.record_id,
    "provider-event:\{event_id}",
  )
  json_reply(200, { "record": record.to_json(), "result": result.to_json() })
}
