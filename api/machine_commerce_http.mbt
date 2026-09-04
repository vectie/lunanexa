///|
fn machine_commerce_path(path : String) -> Bool {
  path == "/v1/portal/self/machine-offerings" ||
  path == "/v1/portal/self/machine-terms" ||
  path == "/v1/portal/self/machine-terms/accept" ||
  path == "/v1/portal/self/machine-quotes" ||
  path == "/v1/portal/self/machine-orders" ||
  path.has_prefix("/v1/portal/self/machine-orders/") ||
  path == "/v1/machine-commerce/operator/snapshot" ||
  path == "/v1/machine-commerce/operator/offerings"
}

///|
priv struct SelfMachineQuoteRequest {
  quote_id : String
  idempotency_key : String
  project_id : String
  offering_id : String
  quantity : Int64
  duration_seconds : Int64
  unix_username : String?
  requested_model_selector : String?
  model_template_ref : String?
} derive(FromJson)

///|
priv struct SelfMachineOrderRequest {
  order_id : String
  idempotency_key : String
  quote_id : String
} derive(FromJson)

///|
/// The order, organization, project, model, endpoint and expiry are all
/// server-derived. Only presentation metadata and a bounded quota are input.
priv struct SelfDedicatedAccessKeyRequest {
  key_id : String
  display_name : String
  maximum_requests : Int64
} derive(FromJson)

///|
priv struct SelfMachineOrderAccessView {
  order_id : String
  offering_kind : @machinecommerce.MachineOfferingKind
  state : @machinecommerce.MachineOrderState
  canonical_path : String?
  model_selector : String?
  expires_unix_ms : Int64?
  machine_access_path : String?
} derive(ToJson)

///| The browser supplies only immutable presentation evidence. Organization,

///|
/// subject, acceptance identity, intent, and timestamp are server-derived.
priv struct SelfMachineTermsAcceptanceRequest {
  idempotency_key : String
  template_version : String
  rendered_document_hash : String
  document_uri : String
  presentation_context_hash : String
  network_context_hash : String
} derive(FromJson)

///|
fn decode_self_machine_quote(body : String) -> SelfMachineQuoteRequest? {
  try {
    let value = @json.parse(body)
    if machine_customer_forbidden_field(value) {
      None
    } else {
      Some(@json.from_json(value))
    }
  } catch {
    _ => None
  }
}

///|
fn decode_self_machine_order(body : String) -> SelfMachineOrderRequest? {
  try {
    let value = @json.parse(body)
    if machine_customer_forbidden_field(value) {
      None
    } else {
      Some(@json.from_json(value))
    }
  } catch {
    _ => None
  }
}

///|
fn decode_self_dedicated_access_key(
  body : String,
) -> SelfDedicatedAccessKeyRequest? {
  try {
    let value = @json.parse(body)
    guard value is Object(fields) &&
      fields.length() == 3 &&
      fields
      .keys()
      .all(key => {
        key == "key_id" || key == "display_name" || key == "maximum_requests"
      }) else {
      return None
    }
    Some(@json.from_json(value))
  } catch {
    _ => None
  }
}

///| Physical placement and controller target fields are never customer input,

///|
/// even if a permissive JSON decoder would otherwise ignore them.
fn machine_customer_forbidden_field(value : Json) -> Bool {
  match value {
    Object(fields) => {
      for key, child in fields {
        let normalized = key.to_lower()
        if normalized == "node_id" ||
          normalized == "device_id" ||
          normalized == "target_lease_ref" ||
          normalized == "target_deployment_ref" ||
          normalized == "assigned_node_id" ||
          machine_customer_forbidden_field(child) {
          return true
        }
      }
      false
    }
    Array(values) => values.any(machine_customer_forbidden_field)
    _ => false
  }
}

///|
fn decode_self_machine_terms_acceptance(
  body : String,
) -> SelfMachineTermsAcceptanceRequest? {
  try {
    let value = @json.parse(body)
    guard value is Object(fields) &&
      fields.length() == 6 &&
      fields
      .keys()
      .all(key => {
        key == "idempotency_key" ||
        key == "template_version" ||
        key == "rendered_document_hash" ||
        key == "document_uri" ||
        key == "presentation_context_hash" ||
        key == "network_context_hash"
      }) else {
      return None
    }
    Some(@json.from_json(value))
  } catch {
    _ => None
  }
}

///|
fn decode_machine_order_action(
  body : String,
) -> @machinecommerce.MachineOrderAction? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn decode_machine_offering(body : String) -> @machinecommerce.MachineOffering? {
  try @json.from_json(@json.parse(body)) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn machine_order_action_path(path : String) -> (String, String)? {
  let prefix = "/v1/portal/self/machine-orders/"
  if !path.has_prefix(prefix) {
    return None
  }
  let remainder = path[prefix.length():].to_owned()
  for suffix in ["/cancel", "/terminate"] {
    if remainder.has_suffix(suffix) && remainder.length() > suffix.length() {
      let order_id = remainder[:remainder.length() - suffix.length()].to_owned()
      if @contracts.valid_identifier(order_id, maximum_length=256) {
        return Some((order_id, suffix[1:].to_owned()))
      }
    }
  }
  None
}

///|
fn machine_order_access_path(path : String) -> (String, String)? {
  let prefix = "/v1/portal/self/machine-orders/"
  if !path.has_prefix(prefix) {
    return None
  }
  let remainder = path[prefix.length():].to_owned()
  for suffix in ["/access", "/access-key"] {
    if remainder.has_suffix(suffix) && remainder.length() > suffix.length() {
      let order_id = remainder[:remainder.length() - suffix.length()].to_owned()
      if @contracts.valid_identifier(order_id, maximum_length=256) {
        return Some((order_id, suffix[1:].to_owned()))
      }
    }
  }
  None
}

///|
fn machine_commerce_error_reply(error : Error) -> HttpReply {
  match error {
    @machinecommerce.MachineCommerceError::Unauthorized(_) =>
      api_error(
        403, "MachineOrderAccessDenied", "machine purchasing role is required", false,
      )
    @machinecommerce.MachineCommerceError::TenantMismatch =>
      api_error(
        403, "TenantMismatch", "request crosses the organization boundary", false,
      )
    @machinecommerce.MachineCommerceError::NotFound(_) =>
      api_error(404, "NotFound", "machine commerce record was not found", false)
    @machinecommerce.MachineCommerceError::AlreadyExists(_) =>
      api_error(
        409, "AlreadyExists", "machine commerce record already exists", false,
      )
    @machinecommerce.MachineCommerceError::IdempotencyConflict(_) =>
      api_error(
        409, "IdempotencyConflict", "idempotency key identifies a different mutation",
        false,
      )
    @machinecommerce.MachineCommerceError::StaleGeneration =>
      api_error(
        409, "StaleGeneration", "machine order changed; refresh before retrying",
        true,
      )
    @machinecommerce.MachineCommerceError::QuoteExpired =>
      api_error(
        409, "QuoteExpired", "machine quote expired; request a new quote", false,
      )
    @machinecommerce.MachineCommerceError::QuoteIntegrityFailed =>
      api_error(
        409, "QuoteIntegrityFailed", "machine quote integrity validation failed",
        false,
      )
    @machinecommerce.MachineCommerceError::PriceMismatch =>
      api_error(
        409, "PriceMismatch", "settled payment does not equal the signed quote",
        false,
      )
    @machinecommerce.MachineCommerceError::CapacityUnavailable =>
      api_error(
        409, "CapacityUnavailable", "machine capacity is unavailable", true,
      )
    @machinecommerce.MachineCommerceError::InvalidTransition(_) =>
      api_error(
        409, "InvalidTransition", "machine order cannot perform that transition",
        false,
      )
    @machinecommerce.MachineCommerceError::InvalidInput(_) =>
      api_error(
        400, "MachineCommerceRejected", "machine commerce request is invalid", false,
      )
    _ =>
      api_error(
        503, "MachineCommercePersistenceFailed", "durable machine commerce operation failed",
        true,
      )
  }
}

///|
fn machine_payment_transaction_ref(order_id : String) -> String {
  "machine-order:\{order_id}"
}

///| There must be one current Ready template for the self-service machine

///| agreement type. Operators supersede old versions before publishing a new

///|
/// one, so ambiguity fails closed.
fn ApiService::machine_terms_template(
  self : ApiService,
) -> @commercial.AgreementTemplate? {
  let ready = self.commercial_store.durable_snapshot().commercial.agreement_templates.filter(template => {
      template.agreement_type == "machine-self-service" &&
      template.state == ReadyTemplate &&
      template.document_uri is Some(_) &&
      template.effective_unix_ms <= @async.now()
    },
  )
  if ready.length() == 1 {
    Some(ready[0])
  } else {
    None
  }
}

///|
fn ApiService::machine_terms_satisfied(
  self : ApiService,
  organization_id : String,
) -> Bool {
  let commercial = self.commercial_store.durable_snapshot().commercial
  commercial.clickwrap_acceptances.any(acceptance => {
    acceptance.organization_id == organization_id &&
    commercial.agreement_templates.any(template => {
      template.template_id == acceptance.template_id &&
      template.version == acceptance.template_version &&
      template.rendered_document_hash == acceptance.rendered_document_hash &&
      template.agreement_type == "machine-self-service" &&
      template.state == ReadyTemplate &&
      template.document_uri is Some(_)
    })
  })
}

///| Payment callback integration point. Provider reconciliation must call this

///|
/// only after its signature, event binding, amount and terminal status checks.
pub async fn ApiService::activate_machine_order_settled_payment(
  self : ApiService,
  order_id : String,
  settlement : @machinecommerce.MachinePaymentSettlement,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder, @machinecommerce.IdempotencyResult) {
  guard self.machine_commerce_store is Some(machine_store) else {
    raise @machinecommerce.MachineCommerceError::InvalidTransition(
      "durable machine commerce store is unavailable",
    )
  }
  machine_store.activate_settled_payment(order_id, settlement, now_unix_ms)
}

///|
async fn ApiService::machine_commerce_portal_view(
  self : ApiService,
  headers : Map[String, String],
  allow_asserted_subject : Bool,
) -> (@portal.EnterpriseSelfView, String) {
  guard self.portal_store is Some(portal) else {
    raise @machinecommerce.MachineCommerceError::InvalidTransition(
      "enterprise portal is unavailable",
    )
  }
  guard self.portal_subject(headers, allow_asserted_subject)
    is Some(subject_ref) else {
    raise @machinecommerce.MachineCommerceError::Unauthorized(
      "verified enterprise identity is required",
    )
  }
  let view = portal_view_for_request(portal, subject_ref, headers) catch {
    _ =>
      raise @machinecommerce.MachineCommerceError::Unauthorized(
        "select an active organization",
      )
  }
  (view, subject_ref)
}

///|
fn ApiService::machine_commerce_project_allowed(
  self : ApiService,
  view : @portal.EnterpriseSelfView,
  project_id : String,
) -> Bool {
  self.commercial_store.project_for_organization(
    view.membership.organization_id,
    project_id,
  )
  is Some(_) &&
  self.commercial_store
  .organization(view.membership.organization_id)
  .map_or(false, organization => organization.state == Active)
}

///| Customer-visible capacity is bounded by both durable commercial

///|
/// reservations and live, region/SKU-compatible heartbeat inventory.
async fn ApiService::live_machine_availability(
  self : ApiService,
  machine_store : @machinecommerce_store.MachineCommerceStore,
  offering : @machinecommerce.MachineOffering,
  now_unix_ms : Int64,
) -> @machinecommerce.MachineAvailability {
  let logical = machine_store.availability(offering.offering_id, now_unix_ms)
  let reserved_managed_nodes = self.machine_reserved_managed_nodes()
  let live = self
    .machine_offering_nodes(offering, now_unix_ms)
    .filter(node_id => !reserved_managed_nodes.contains(node_id))
    .length()
    .to_int64()
    .min(logical.capacity_available)
  {
    ..logical,
    capacity_total: logical.capacity_reserved + live,
    capacity_available: live,
  }
}

///|
/// Resolves an API key's durable paid-order binding and fails closed when the
/// binding no longer authorizes its dedicated deployment. An unbound key is a
/// normal shared-MaaS key and returns `(None, None)`.
async fn ApiService::dedicated_order_binding(
  self : ApiService,
  authority : @access.ApiAuthorization,
  model_selector : String?,
  now_unix_ms : Int64,
) -> (@machinecommerce.MachineOrder?, HttpReply?) {
  guard self.machine_commerce_store is Some(machine_store) &&
    machine_store.order_for_access_key(authority.key_id) is Some(order) else {
    return (None, None)
  }
  let expires_unix_ms = order.active_started_unix_ms.map(started => {
    started + order.duration_seconds * 1000L
  })
  if order.offering_kind != DedicatedEndpoint ||
    order.state != Active ||
    order.organization_id != authority.organization_id ||
    order.project_id != authority.project_id ||
    order.tenant_ref != authority.tenant_ref ||
    order.purchaser_subject_ref != authority.subject_ref ||
    expires_unix_ms.map_or(true, expires => now_unix_ms >= expires) ||
    model_selector.map_or(false, selected => {
      order.requested_model_selector != Some(selected)
    }) ||
    order.target_deployment_ref is None {
    return (
      None,
      Some(
        api_error(
          403, "DedicatedOrderInactive", "the API key's paid dedicated order is not active",
          false,
        ),
      ),
    )
  }
  guard self.deployment_store is Some(deployments) &&
    order.target_deployment_ref is Some(deployment_id) &&
    deployments.deployment(deployment_id) is Some(operation) &&
    operation.state == Ready &&
    operation.endpoint is Some(_) else {
    return (
      None,
      Some(
        api_error(
          503, "DedicatedEndpointUnavailable", "the paid dedicated deployment is not ready",
          true,
        ),
      ),
    )
  }
  (Some(order), None)
}

///|
async fn ApiService::handle_machine_commerce(
  self : ApiService,
  verb : ApiMethod,
  path : String,
  headers : Map[String, String],
  body : String,
  allow_asserted_subject : Bool,
) -> HttpReply {
  guard self.machine_commerce_store is Some(machine_store) else {
    return api_error(
      503, "MachineCommerceUnavailable", "durable machine commerce authority is unavailable",
      true,
    )
  }
  if path.has_prefix("/v1/machine-commerce/operator/") {
    if !self.operator_authorized(headers) {
      return api_error(
        401, "Unauthenticated", "valid operator authority is required", false,
      )
    }
    match (verb, path) {
      (Get, "/v1/machine-commerce/operator/snapshot") =>
        return json_reply(200, machine_store.snapshot().to_json())
      (Post, "/v1/machine-commerce/operator/offerings") => {
        guard decode_machine_offering(body) is Some(offering) else {
          return api_error(
            400, "InvalidRequest", "invalid machine offering", false,
          )
        }
        let (persisted, result) = try
          machine_store.put_offering(offering)
        catch {
          error => return machine_commerce_error_reply(error)
        } noraise {
          value => value
        }
        self.operator_audit(
          "machine-commerce.offering.put",
          persisted.offering_id,
          "machine-offering:\{persisted.generation}",
        )
        return json_reply(
          if result == Created {
            201
          } else {
            200
          },
          persisted.to_json(),
        )
      }
      _ =>
        return api_error(
          404, "NotFound", "machine commerce operator route was not found", false,
        )
    }
  }
  let (view, subject_ref) = try
    self.machine_commerce_portal_view(headers, allow_asserted_subject)
  catch {
    error => return machine_commerce_error_reply(error)
  } noraise {
    value => value
  }
  match (verb, path) {
    (Get, "/v1/portal/self/machine-terms") => {
      self.commercial_mutex.acquire()
      let template = self.machine_terms_template()
      self.commercial_mutex.release()
      match template {
        Some(value) => return json_reply(200, value.to_json())
        None =>
          return api_error(
            503, "MachineTermsUnavailable", "one current machine self-service agreement template is required",
            true,
          )
      }
    }
    (Post, "/v1/portal/self/machine-terms/accept") => {
      if !@portal.role_allows(view.membership.roles, LegalSigner) {
        return api_error(
          403, "MachineTermsAccessDenied", "legal signer role is required", false,
        )
      }
      guard decode_self_machine_terms_acceptance(body) is Some(request) &&
        @contracts.valid_identifier(request.idempotency_key) &&
        @contracts.valid_identifier(request.template_version) &&
        @contracts.valid_sha256_digest(request.rendered_document_hash) &&
        @contracts.valid_sha256_digest(request.presentation_context_hash) &&
        @contracts.valid_sha256_digest(request.network_context_hash) else {
        return api_error(
          400, "InvalidRequest", "invalid machine terms acceptance evidence", false,
        )
      }
      self.commercial_mutex.acquire()
      defer self.commercial_mutex.release()
      guard self.commercial_store.organization(view.membership.organization_id)
        is Some(organization) &&
        organization.state == Active &&
        self.machine_terms_template() is Some(template) &&
        template.version == request.template_version &&
        template.rendered_document_hash == request.rendered_document_hash &&
        template.document_uri == Some(request.document_uri) else {
        return api_error(
          409, "MachineTermsUnavailable", "organization or selected terms are not ready",
          false,
        )
      }
      let before = self.commercial_store.durable_snapshot()
      let now = @async.now()
      let acceptance_id = "machine-terms-\{provider_request_digest(view.membership.organization_id, "\{subject_ref}:\{request.idempotency_key}")}"
      let acceptance : @commercial.ClickwrapAcceptance = {
        acceptance_id,
        idempotency_key: request.idempotency_key,
        organization_id: view.membership.organization_id,
        user_id: subject_ref,
        template_id: template.template_id,
        template_version: template.version,
        rendered_document_hash: template.rendered_document_hash,
        intent: "accept-machine-self-service-terms",
        presentation_context_hash: request.presentation_context_hash,
        network_context_hash: request.network_context_hash,
        accepted_unix_ms: now,
      }
      let result = try
        self.commercial_store.accept_clickwrap(acceptance)
      catch {
        _ =>
          return api_error(
            409, "MachineTermsRejected", "machine terms acceptance was rejected",
            false,
          )
      } noraise {
        value => value
      }
      self.persist_commercial_state() catch {
        _ => {
          ignore(self.commercial_store.replace_from_durable_snapshot(before))
          return api_error(
            503, "CommercialPersistenceFailed", "machine terms acceptance was rolled back",
            true,
          )
        }
      }
      return json_reply(
        if result == Created {
          201
        } else {
          200
        },
        acceptance.to_json(),
      )
    }
    (Get, "/v1/portal/self/machine-offerings") => {
      let now = @async.now()
      let response : Array[@machinecommerce.MachineOfferingView] = []
      for offering in machine_store.active_offerings() {
        let availability = try
          self.live_machine_availability(machine_store, offering, now)
        catch {
          error => return machine_commerce_error_reply(error)
        } noraise {
          value => value
        }
        response.push({ offering, availability })
      }
      return json_reply(200, response.to_json())
    }
    (Post, "/v1/portal/self/machine-quotes") => {
      if !@portal.role_allows(view.membership.roles, LeaseRequester) {
        return api_error(
          403, "MachineOrderAccessDenied", "lease requester role is required", false,
        )
      }
      guard decode_self_machine_quote(body) is Some(request) else {
        return api_error(
          400, "InvalidRequest", "invalid machine quote request", false,
        )
      }
      if !self.machine_commerce_project_allowed(view, request.project_id) {
        return api_error(
          403, "TenantMismatch", "project is not an active member of the selected organization",
          false,
        )
      }
      let now = @async.now()
      guard machine_store.snapshot().offerings
        .iter()
        .find_first(offering => offering.offering_id == request.offering_id)
        is Some(offering) else {
        return api_error(
          404, "NotFound", "machine offering was not found", false,
        )
      }
      let live_availability = try
        self.live_machine_availability(machine_store, offering, now)
      catch {
        error => return machine_commerce_error_reply(error)
      } noraise {
        value => value
      }
      if live_availability.capacity_available < 1L {
        return api_error(
          409, "CapacityUnavailable", "no live node satisfies this regional machine SKU",
          true,
        )
      }
      let (quote, result) = try
        machine_store.create_quote(
          {
            quote_id: request.quote_id,
            idempotency_key: request.idempotency_key,
            tenant_ref: view.membership.tenant_ref,
            organization_id: view.membership.organization_id,
            project_id: request.project_id,
            purchaser_subject_ref: subject_ref,
            offering_id: request.offering_id,
            quantity: request.quantity,
            duration_seconds: request.duration_seconds,
            unix_username: request.unix_username,
            requested_model_selector: request.requested_model_selector,
            model_template_ref: request.model_template_ref,
            valid_for_ms: 900000L,
          },
          now,
        )
      catch {
        error => return machine_commerce_error_reply(error)
      } noraise {
        value => value
      }
      return json_reply(
        if result == Created {
          201
        } else {
          200
        },
        quote.to_json(),
      )
    }
    (Post, "/v1/portal/self/machine-orders") => {
      if !@portal.role_allows(view.membership.roles, LeaseRequester) {
        return api_error(
          403, "MachineOrderAccessDenied", "lease requester role is required", false,
        )
      }
      guard decode_self_machine_order(body) is Some(request) &&
        machine_store.quote(request.quote_id) is Some(quote) else {
        return api_error(
          400, "InvalidRequest", "invalid machine order request", false,
        )
      }
      if quote.organization_id != view.membership.organization_id ||
        quote.tenant_ref != view.membership.tenant_ref ||
        quote.purchaser_subject_ref != subject_ref ||
        !self.machine_commerce_project_allowed(view, quote.project_id) {
        return api_error(
          403, "TenantMismatch", "quote is outside the selected organization", false,
        )
      }
      guard machine_store.snapshot().offerings
        .iter()
        .find_first(offering => offering.offering_id == quote.offering_id)
        is Some(offering) else {
        return api_error(
          404, "NotFound", "machine offering was not found", false,
        )
      }
      let checkout_availability = try
        self.live_machine_availability(machine_store, offering, @async.now())
      catch {
        error => return machine_commerce_error_reply(error)
      } noraise {
        value => value
      }
      if checkout_availability.capacity_available < 1L {
        return api_error(
          409, "CapacityUnavailable", "live machine capacity changed; request a new quote",
          true,
        )
      }
      self.commercial_mutex.acquire()
      let clickwrap_satisfied = self.machine_terms_satisfied(
        view.membership.organization_id,
      )
      self.commercial_mutex.release()
      if !clickwrap_satisfied &&
        !view.agreements.any(agreement => agreement.state == Executed) {
        return api_error(
          409, "AgreementRequired", "an executed machine agreement is required before checkout",
          false,
        )
      }
      if !self.commercial_provider_adapter_ready() {
        return api_error(
          503, "CommercialProviderUnavailable", "payment provider adapter is not ready",
          true,
        )
      }
      let (order, result) = try
        machine_store.create_order(
          {
            order_id: request.order_id,
            idempotency_key: request.idempotency_key,
            quote_id: request.quote_id,
            tenant_ref: view.membership.tenant_ref,
            organization_id: view.membership.organization_id,
            project_id: quote.project_id,
            purchaser_subject_ref: subject_ref,
          },
          @async.now(),
        )
      catch {
        error => return machine_commerce_error_reply(error)
      } noraise {
        value => value
      }
      let entitlement_ref = machine_payment_transaction_ref(order.order_id)
      let digest = provider_request_digest(
        order.organization_id,
        entitlement_ref,
      )
      let record_id = "payment-\{digest}"
      let created_unix_ms = self.commercial_integrations
        .record_by_id(record_id)
        .map(value => value.created_unix_ms)
        .unwrap_or(order.created_unix_ms)
      let checkout = try
        self.queue_provider_record({
          record_id,
          organization_id: order.organization_id,
          kind: Payment,
          provider: self.commercial_provider_name.unwrap_or(""),
          environment: self.commercial_provider_environment.unwrap_or(""),
          external_ref: "checkout-\{digest}",
          state: Pending,
          expected_amount_minor: Some(order.quoted_total.minor_units),
          currency: Some(order.quoted_total.currency),
          money_scale: Some(order.quoted_total.scale),
          expected_document_hash: None,
          entitlement_transaction_ref: Some(entitlement_ref),
          created_unix_ms,
          updated_unix_ms: created_unix_ms,
        })
      catch {
        _ =>
          return api_error(
            503, "CommercialPersistenceFailed", "machine order was retained but payment checkout could not be queued",
            true,
          )
      } noraise {
        value => value
      }
      return json_reply(if checkout.state == Pending { 202 } else { 200 }, {
        "order": order.to_json(),
        "checkout": checkout.to_json(),
        "entitlement_transaction_ref": entitlement_ref,
        "result": result.to_json(),
      })
    }
    (Get, "/v1/portal/self/machine-orders") => {
      let orders = machine_store
        .orders_for_subject(subject_ref)
        .filter(order => {
          order.organization_id == view.membership.organization_id &&
          order.tenant_ref == view.membership.tenant_ref
        })
      return json_reply(200, orders.to_json())
    }
    (Get, _) => {
      guard machine_order_access_path(path) is Some((order_id, "access")) &&
        machine_store.order(order_id) is Some(order) &&
        order.organization_id == view.membership.organization_id &&
        order.tenant_ref == view.membership.tenant_ref &&
        order.purchaser_subject_ref == subject_ref else {
        return api_error(
          404, "NotFound", "machine order access was not found", false,
        )
      }
      if order.state != Active || order.active_started_unix_ms is None {
        return api_error(
          409, "MachineOrderNotActive", "machine access is not active", true,
        )
      }
      let expires_unix_ms = order.active_started_unix_ms.map(started => {
        started + order.duration_seconds * 1000L
      })
      let access : SelfMachineOrderAccessView = match order.offering_kind {
        BareMachine =>
          {
            order_id: order.order_id,
            offering_kind: order.offering_kind,
            state: order.state,
            canonical_path: None,
            model_selector: None,
            expires_unix_ms,
            machine_access_path: Some("/v1/machine-access/self"),
          }
        DedicatedEndpoint => {
          guard self.deployment_store is Some(deployments) &&
            order.target_deployment_ref is Some(deployment_id) &&
            deployments.deployment(deployment_id) is Some(operation) &&
            operation.state == Ready &&
            operation.endpoint is Some(endpoint) &&
            order.requested_model_selector is Some(model_selector) else {
            return api_error(
              503, "DedicatedEndpointUnavailable", "the paid dedicated endpoint is not ready",
              true,
            )
          }
          {
            order_id: order.order_id,
            offering_kind: order.offering_kind,
            state: order.state,
            canonical_path: Some(endpoint.canonical_path),
            model_selector: Some(model_selector),
            expires_unix_ms,
            machine_access_path: None,
          }
        }
      }
      return json_reply(200, ToJson::to_json(access))
    }
    (Post, _) => {
      if machine_order_access_path(path) is Some((order_id, "access-key")) {
        if !@portal.role_allows(view.membership.roles, Developer) {
          return api_error(
            403, "MachineOrderAccessDenied", "developer role is required", false,
          )
        }
        guard decode_self_dedicated_access_key(body) is Some(request) &&
          @contracts.valid_identifier(request.key_id) &&
          request.display_name.trim() != "" &&
          request.display_name.length() <= 128 &&
          request.maximum_requests > 0L &&
          request.maximum_requests <= 1000000000L &&
          machine_store.order(order_id) is Some(order) &&
          order.organization_id == view.membership.organization_id &&
          order.tenant_ref == view.membership.tenant_ref &&
          order.purchaser_subject_ref == subject_ref else {
          return api_error(
            400, "InvalidRequest", "invalid dedicated access-key request", false,
          )
        }
        guard order.offering_kind == DedicatedEndpoint &&
          order.state == Active &&
          order.active_started_unix_ms is Some(active_started) &&
          order.requested_model_selector is Some(model_selector) &&
          self.deployment_store is Some(deployments) &&
          order.target_deployment_ref is Some(deployment_id) &&
          deployments.deployment(deployment_id) is Some(operation) &&
          operation.state == Ready &&
          operation.endpoint is Some(endpoint) else {
          return api_error(
            409, "DedicatedEndpointUnavailable", "the paid dedicated endpoint is not active",
            true,
          )
        }
        guard self.access_store is Some(access_store) else {
          return api_error(
            503, "AccessStoreUnavailable", "API key state is unavailable", true,
          )
        }
        if access_store.views().any(key => key.key_id == request.key_id) {
          return api_error(
            409, "ApiKeyAlreadyExists", "choose a new API key identifier", false,
          )
        }
        let now = @async.now()
        let expires_unix_ms = active_started + order.duration_seconds * 1000L
        if expires_unix_ms <= now {
          return api_error(
            409, "MachineOrderExpired", "the paid dedicated endpoint has expired",
            false,
          )
        }
        ignore(
          machine_store.bind_access_key(
            order.order_id,
            subject_ref,
            request.key_id,
            now,
          ),
        ) catch {
          _ =>
            return api_error(
              409, "ApiKeyBindingRejected", "the API key could not be bound to this order",
              true,
            )
        }
        let issued = try
          access_store.issue(
            {
              key_id: request.key_id,
              tenant_ref: order.tenant_ref,
              subject_ref,
              organization_id: order.organization_id,
              project_id: order.project_id,
              display_name: request.display_name.trim().to_owned(),
              scopes: [ModelList, Inference],
              allowed_models: [model_selector],
              expires_unix_ms,
              maximum_requests: request.maximum_requests,
            },
            now,
          )
        catch {
          _ =>
            return api_error(
              409, "ApiKeyRejected", "the order-bound API key could not be issued",
              true,
            )
        } noraise {
          value => value
        }
        return json_reply(201, {
          "access_key": issued.public_view().to_json(),
          "endpoint": endpoint.to_json(),
          "model_selector": model_selector,
          "order_id": order.order_id,
        })
      }
      guard machine_order_action_path(path) is Some((order_id, action_name)) &&
        decode_machine_order_action(body) is Some(action) else {
        return api_error(
          404, "NotFound", "machine commerce self route was not found", false,
        )
      }
      guard machine_store.order(order_id) is Some(order) &&
        order.organization_id == view.membership.organization_id &&
        order.tenant_ref == view.membership.tenant_ref else {
        return api_error(404, "NotFound", "machine order was not found", false)
      }
      let result = try {
        if action_name == "cancel" {
          machine_store.request_cancel(
            subject_ref,
            order_id,
            action,
            @async.now(),
          )
        } else {
          machine_store.request_termination(
            subject_ref,
            order_id,
            action,
            @async.now(),
          )
        }
      } catch {
        error => return machine_commerce_error_reply(error)
      } noraise {
        value => value
      }
      return json_reply(200, result.0.to_json())
    }
    _ =>
      api_error(
        404, "NotFound", "machine commerce self route was not found", false,
      )
  }
}
