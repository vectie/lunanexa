///|
fn valid_id(value : String) -> Bool {
  @contracts.valid_identifier(value, maximum_length=256)
}

///|
fn valid_label(value : String, maximum_length : Int) -> Bool {
  value.trim() != "" &&
  value.length() <= maximum_length &&
  value.all(character => {
    character.is_printable() &&
    character != '<' &&
    character != '>' &&
    character != '\n' &&
    character != '\r'
  })
}

///|
fn valid_money(value : @commercial.FixedMoney) -> Bool {
  value.minor_units >= 0L &&
  value.currency.length() == 3 &&
  value.currency.all(character => character >= 'A' && character <= 'Z') &&
  value.scale >= 0 &&
  value.scale <= 6
}

///|
fn valid_digest(value : String) -> Bool {
  value.length() == 71 &&
  value.has_prefix("sha256:") &&
  value[7:].all(character => character.is_ascii_hexdigit())
}

///|
fn valid_unix_username(value : String) -> Bool {
  value.length() > 0 &&
  value.length() <= 32 &&
  value != "root" &&
  value != "daemon" &&
  value != "lunanexa" &&
  value[0] >= 'a' &&
  value[0] <= 'z' &&
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= '0' && character <= '9') ||
    character == '_' ||
    character == '-'
  })
}

///|
fn valid_signature(value : String) -> Bool {
  value.length() == 64 &&
  value.all(character => {
    character.is_ascii_digit() || (character >= 'a' && character <= 'f')
  })
}

///|
pub fn validate_offering(
  offering : MachineOffering,
) -> Unit raise MachineCommerceError {
  if !valid_id(offering.offering_id) ||
    !valid_id(offering.sku) ||
    !valid_label(offering.display_name, 160) ||
    !valid_id(offering.region) ||
    !valid_id(offering.accelerator_class) ||
    !valid_id(offering.meter) ||
    !valid_money(offering.unit_price) ||
    (offering.state == OfferingActive && offering.unit_price.minor_units <= 0L) ||
    offering.accelerator_count <= 0L ||
    offering.accelerator_count > 128L ||
    offering.memory_mib <= 0L ||
    offering.cpu_count <= 0L ||
    offering.billing_quantum_seconds <= 0L ||
    offering.minimum_duration_seconds <= 0L ||
    offering.maximum_duration_seconds < offering.minimum_duration_seconds ||
    offering.maximum_duration_seconds > 31536000L ||
    offering.capacity_total < 0L ||
    offering.generation <= 0L ||
    offering.created_unix_ms <= 0L ||
    offering.updated_unix_ms < offering.created_unix_ms ||
    offering.allowed_model_template_refs.length() > 256 {
    raise InvalidInput("invalid machine offering")
  }
  for template_ref in offering.allowed_model_template_refs {
    if !valid_id(template_ref) {
      raise InvalidInput("invalid model template reference")
    }
  }
  match offering.kind {
    BareMachine =>
      if offering.allowed_model_template_refs.length() != 0 {
        raise InvalidInput(
          "bare-machine offering cannot constrain model templates",
        )
      }
    DedicatedEndpoint =>
      if offering.allowed_model_template_refs.length() == 0 {
        raise InvalidInput("dedicated endpoint requires model templates")
      }
  }
}

///|
pub fn validate_quote_intent(
  intent : MachineQuoteIntent,
) -> Unit raise MachineCommerceError {
  if !valid_id(intent.quote_id) ||
    !valid_id(intent.idempotency_key) ||
    !valid_id(intent.tenant_ref) ||
    !valid_id(intent.organization_id) ||
    !valid_id(intent.project_id) ||
    !valid_id(intent.purchaser_subject_ref) ||
    !valid_id(intent.offering_id) ||
    intent.quantity <= 0L ||
    intent.quantity > 128L ||
    intent.duration_seconds <= 0L ||
    intent.valid_for_ms <= 0L ||
    intent.valid_for_ms > 3600000L ||
    intent.requested_model_selector.map_or(false, value => !valid_id(value)) ||
    intent.model_template_ref.map_or(false, value => !valid_id(value)) ||
    intent.unix_username.map_or(false, value => !valid_unix_username(value)) {
    raise InvalidInput("invalid machine quote intent")
  }
}

///|
pub fn validate_order_intent(
  intent : MachineOrderIntent,
) -> Unit raise MachineCommerceError {
  if !valid_id(intent.order_id) ||
    !valid_id(intent.idempotency_key) ||
    !valid_id(intent.quote_id) ||
    !valid_id(intent.tenant_ref) ||
    !valid_id(intent.organization_id) ||
    !valid_id(intent.project_id) ||
    !valid_id(intent.purchaser_subject_ref) {
    raise InvalidInput("invalid machine order intent")
  }
}

///|
fn validate_quote(quote : MachineQuote) -> Unit raise MachineCommerceError {
  if !valid_id(quote.quote_id) ||
    !valid_id(quote.idempotency_key) ||
    !valid_id(quote.tenant_ref) ||
    !valid_id(quote.organization_id) ||
    !valid_id(quote.project_id) ||
    !valid_id(quote.purchaser_subject_ref) ||
    !valid_id(quote.offering_id) ||
    !valid_id(quote.meter) ||
    !valid_money(quote.unit_price) ||
    !valid_money(quote.subtotal) ||
    !valid_money(quote.total) ||
    quote.quantity <= 0L ||
    quote.duration_seconds <= 0L ||
    quote.unix_username.map_or(false, value => !valid_unix_username(value)) ||
    quote.requested_model_selector.map_or(false, value => !valid_id(value)) ||
    quote.model_template_ref.map_or(false, value => !valid_id(value)) ||
    quote.created_unix_ms <= 0L ||
    quote.valid_until_unix_ms <= quote.created_unix_ms ||
    !valid_digest(quote.terms_digest) ||
    !valid_signature(quote.signature) {
    raise InvalidInput("invalid machine quote")
  }
  match quote.offering_kind {
    BareMachine =>
      if quote.unix_username is None ||
        quote.requested_model_selector is Some(_) ||
        quote.model_template_ref is Some(_) {
        raise InvalidInput("bare-machine quote requires only a unix username")
      }
    DedicatedEndpoint =>
      if quote.unix_username is Some(_) ||
        quote.requested_model_selector is None ||
        quote.model_template_ref is None {
        raise InvalidInput("dedicated endpoint quote requires a selected model")
      }
  }
}

///|
fn validate_order(order : MachineOrder) -> Unit raise MachineCommerceError {
  if !valid_id(order.order_id) ||
    !valid_id(order.idempotency_key) ||
    !valid_id(order.quote_id) ||
    !valid_id(order.tenant_ref) ||
    !valid_id(order.organization_id) ||
    !valid_id(order.project_id) ||
    !valid_id(order.purchaser_subject_ref) ||
    !valid_id(order.offering_id) ||
    order.quantity <= 0L ||
    order.duration_seconds <= 0L ||
    order.unix_username.map_or(false, value => !valid_unix_username(value)) ||
    order.requested_model_selector.map_or(false, value => !valid_id(value)) ||
    order.model_template_ref.map_or(false, value => !valid_id(value)) ||
    !valid_money(order.quoted_total) ||
    order.generation <= 0L ||
    order.created_unix_ms <= 0L ||
    order.updated_unix_ms < order.created_unix_ms {
    raise InvalidInput("invalid machine order")
  }
  if order.state == AwaitingPayment &&
    (order.payment_ref is Some(_) || order.capacity_reserved) {
    raise InvalidInput("unpaid order cannot hold capacity")
  }
  if order.state == Provisioning ||
    order.state == Active ||
    order.state == TerminationPending {
    if order.payment_ref is None || !order.capacity_reserved {
      raise InvalidInput("allocated order requires payment and lease")
    }
  }
  if order.offering_kind == BareMachine &&
    (
      order.unix_username is None ||
      order.requested_model_selector is Some(_) ||
      order.model_template_ref is Some(_) ||
      (
        (
          order.state == Provisioning ||
          order.state == Active ||
          order.state == TerminationPending
        ) &&
        (
          order.target_lease_ref is None ||
          order.target_deployment_ref is Some(_)
        )
      )
    ) {
    raise InvalidInput("bare-machine order requires only an exclusive lease")
  }
  if order.offering_kind == DedicatedEndpoint &&
    (
      order.unix_username is Some(_) ||
      order.requested_model_selector is None ||
      order.model_template_ref is None ||
      (
        (
          order.state == Provisioning ||
          order.state == Active ||
          order.state == TerminationPending
        ) &&
        (
          order.target_lease_ref is Some(_) ||
          order.target_deployment_ref is None
        )
      )
    ) {
    raise InvalidInput("dedicated endpoint requires a selected model")
  }
}
