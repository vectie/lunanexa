///|
priv struct ProviderPaymentCheckoutIntent {
  idempotency_key : String
  period_id : String
} derive(FromJson)

///|
fn commercial_provider_adapter_path(path : String) -> Bool {
  path == "/internal/v1/commercial-provider/requests" ||
  path == "/internal/v1/commercial-provider/dispatch-receipts"
}

///|
fn valid_provider_action_origin(origin : String) -> Bool {
  if !origin.has_prefix("https://") ||
    origin.length() <= "https://".length() ||
    origin.length() > 512 ||
    origin.has_suffix("/") ||
    origin.contains("?") ||
    origin.contains("#") ||
    origin.contains("\\") ||
    origin.any(character => character.is_whitespace()) {
    return false
  }
  let authority = origin["https://".length():]
  !authority.contains("/") &&
  !authority.contains("@") &&
  authority != "localhost" &&
  !authority.has_prefix("127.") &&
  authority != "[::1]"
}

///|
pub fn ApiService::with_commercial_provider_adapter(
  self : ApiService,
  token : String,
  provider : String,
  environment : String,
  action_origin : String,
) -> ApiService raise Failure {
  if token.length() < 32 ||
    token.length() > 4096 ||
    !valid_callback_identity(provider) ||
    !valid_callback_identity(environment) ||
    !valid_provider_action_origin(action_origin) {
    raise Failure("commercial provider adapter configuration is invalid")
  }
  {
    ..self,
    commercial_provider_adapter_token: Some(token),
    commercial_provider_name: Some(provider),
    commercial_provider_environment: Some(environment),
    commercial_provider_action_origin: Some(action_origin),
  }
}

///|
fn ApiService::commercial_provider_adapter_ready(self : ApiService) -> Bool {
  guard self.commercial_provider_adapter_token is Some(_) &&
    self.commercial_provider_name is Some(provider) &&
    self.commercial_provider_environment is Some(environment) &&
    self.commercial_provider_action_origin is Some(_) else {
    return false
  }
  self.provider_callback_secrets.get("\{provider}|\{environment}") is Some(_)
}

///|
fn provider_request_digest(organization_id : String, key : String) -> String {
  @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode("\{organization_id}\n\{key}")),
  )
}

///|
/// Persist the authority record before a machine adapter can claim it.
async fn ApiService::queue_provider_record(
  self : ApiService,
  record : @commercial_integrations.ExternalRecord,
  commercial_lock_held? : Bool = false,
) -> @commercial_integrations.ExternalRecordView {
  if !commercial_lock_held {
    self.commercial_mutex.acquire()
  }
  defer (if !commercial_lock_held { self.commercial_mutex.release() })
  let before = self.commercial_integrations.durable_snapshot()
  match self.commercial_integrations.record_by_id(record.record_id) {
    Some(existing) if existing.state == Submitted =>
      ignore(
        self.commercial_integrations.renew_expired_dispatch(
          record.record_id,
          @async.now(),
        ),
      ) catch {
        // A still-live Submitted request is the idempotent current session.
        InvalidTransition(_) => ()
        _ => {
          ignore(
            self.commercial_integrations.replace_from_durable_snapshot(before),
          ) catch {
            _ => ()
          }
          raise Failure("commercial provider renewal conflicts")
        }
      }
    _ => ()
  }
  ignore(self.commercial_integrations.register(record)) catch {
    _ => {
      ignore(self.commercial_integrations.replace_from_durable_snapshot(before)) catch {
        _ => ()
      }
      raise Failure("commercial provider request conflicts")
    }
  }
  self.persist_commercial_state() catch {
    _ => {
      ignore(self.commercial_integrations.replace_from_durable_snapshot(before)) catch {
        _ => ()
      }
      raise Failure("commercial provider request persistence failed")
    }
  }
  self.commercial_integrations.snapshot(record.organization_id).records
  .iter()
  .find_first(value => value.record_id == record.record_id)
  .unwrap()
}

///|
async fn ApiService::handle_commercial_provider_adapter(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
) -> HttpReply {
  guard self.commercial_provider_adapter_token is Some(token) &&
    bearer_authorized(headers, token) &&
    self.commercial_provider_name is Some(provider) &&
    self.commercial_provider_environment is Some(environment) else {
    return api_error(
      401, "Unauthenticated", "valid provider adapter authority is required", false,
    )
  }
  match (verb, path) {
    (Get, "/internal/v1/commercial-provider/requests") => {
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let intents = try
        self.commercial_integrations.pending_provider_intents(
          provider, environment,
        )
      catch {
        _ =>
          return api_error(
            503, "ProviderOutboxUnavailable", "provider request outbox is unavailable",
            true,
          )
      } noraise {
        value => value
      }
      json_reply(200, intents.to_json())
    }
    (Post, "/internal/v1/commercial-provider/dispatch-receipts") => {
      let receipt : @commercial_integrations.ExternalDispatchReceipt? = try
        @json.from_json(@json.parse(body))
      catch {
        _ => None
      } noraise {
        value => Some(value)
      }
      guard receipt is Some(value) &&
        value.provider == provider &&
        value.environment == environment &&
        self.commercial_provider_action_origin is Some(action_origin) &&
        value.action_url.has_prefix("\{action_origin}/") else {
        return api_error(
          400, "ProviderReceiptRejected", "dispatch receipt is invalid or misrouted",
          false,
        )
      }
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      let before = self.commercial_integrations.durable_snapshot()
      let (record, result) = try
        self.commercial_integrations.record_dispatch(value)
      catch {
        _ =>
          return api_error(
            409, "ProviderReceiptRejected", "dispatch receipt did not match a pending request",
            false,
          )
      } noraise {
        accepted => accepted
      }
      self.persist_commercial_state() catch {
        _ => {
          ignore(
            self.commercial_integrations.replace_from_durable_snapshot(before),
          )
          return api_error(
            503, "CommercialPersistenceFailed", "dispatch receipt was rolled back",
            true,
          )
        }
      }
      self.operator_audit(
        "provider.dispatch.accept",
        record.record_id,
        "provider-dispatch:\{value.accepted_unix_ms}",
      )
      json_reply(200, { "record": record.to_json(), "result": result.to_json() })
    }
    _ =>
      api_error(404, "NotFound", "provider adapter route was not found", false)
  }
}

///|
async fn ApiService::create_payment_checkout(
  self : ApiService,
  subject_ref : String,
  headers : Map[String, String],
  intent : ProviderPaymentCheckoutIntent,
) -> HttpReply {
  guard self.portal_store is Some(portal) else {
    return api_error(
      503, "PortalUnavailable", "enterprise portal is unavailable", true,
    )
  }
  let view = try portal_view_for_request(portal, subject_ref, headers) catch {
    error => return portal_error_reply(error)
  } noraise {
    value => value
  }
  if !@portal.role_allows(view.membership.roles, BillingViewer) &&
    !@portal.role_allows(view.membership.roles, OrganizationAdministrator) {
    return api_error(
      403, "PortalAccessDenied", "billing role is required", false,
    )
  }
  if !self.commercial_provider_adapter_ready() {
    return api_error(
      503, "CommercialProviderUnavailable", "payment provider adapter is not ready",
      true,
    )
  }
  if !@contracts.valid_identifier(intent.idempotency_key) ||
    !@contracts.valid_identifier(intent.period_id) {
    return api_error(
      400, "InvalidRequest", "invalid payment checkout intent", false,
    )
  }
  let commercial = try
    self.commercial_store.snapshot(view.membership.organization_id)
  catch {
    _ =>
      return api_error(
        404, "BillingPeriodNotFound", "finalized billing period was not found", false,
      )
  } noraise {
    value => value
  }
  guard commercial.finalized_periods
    .iter()
    .find_first(period => {
      period.period_id == intent.period_id &&
      period.organization_id == view.membership.organization_id
    })
    is Some(period) &&
    period.total.minor_units > 0L else {
    return api_error(
      404, "BillingPeriodNotFound", "positive finalized billing period was not found",
      false,
    )
  }
  // A finalized period has one logical checkout regardless of browser retry
  // keys. This prevents parallel sessions for the same payable entitlement.
  let digest = provider_request_digest(
    view.membership.organization_id,
    "billing-period:\{period.period_id}",
  )
  let now = @async.now()
  let record_id = "payment-\{digest}"
  let created_unix_ms = self.commercial_integrations
    .record_by_id(record_id)
    .map(value => value.created_unix_ms)
    .unwrap_or(now)
  let queued = try
    self.queue_provider_record({
      record_id,
      organization_id: view.membership.organization_id,
      kind: Payment,
      provider: self.commercial_provider_name.unwrap_or(""),
      environment: self.commercial_provider_environment.unwrap_or(""),
      external_ref: "checkout-\{digest}",
      state: Pending,
      expected_amount_minor: Some(period.total.minor_units),
      currency: Some(period.total.currency),
      money_scale: Some(period.total.scale),
      expected_document_hash: None,
      entitlement_transaction_ref: Some("billing-period:\{period.period_id}"),
      created_unix_ms,
      updated_unix_ms: created_unix_ms,
    })
  catch {
    _ =>
      return api_error(
        409, "PaymentRequestRejected", "payment checkout request conflicted", false,
      )
  } noraise {
    value => value
  }
  let status = if queued.state == Pending { 202 } else { 200 }
  json_reply(status, queued.to_json())
}
