///|
/// A deployment-owned, organization-scoped description of shared trial
/// capacity. It does not reserve a node. Text offerings authorize unlimited
/// organization-scoped keys only while the exact trial model binding remains.
pub(all) struct SharedTrialOffering {
  organization_id : String
  tenant_ref : String
  node_id : String
  node_label : String
  model_alias : String
  model_name : String
  kind : String
  health_url : String
  public_url : String
} derive(FromJson)

///|
pub extend SharedTrialOffering with FromJson::{from_json}

///|
fn shared_trial_offering_visible(
  offering : SharedTrialOffering,
  organization_id : String,
  tenant_ref : String,
) -> Bool {
  offering.organization_id == organization_id &&
  offering.tenant_ref == tenant_ref
}

///|
fn ApiService::shared_trial_text_offering(
  self : ApiService,
  organization_id : String,
  tenant_ref : String,
  model_alias : String,
) -> SharedTrialOffering? {
  self.shared_trial_offerings
  .iter()
  .find_first(offering => {
    shared_trial_offering_visible(offering, organization_id, tenant_ref) &&
    offering.kind == "Text" &&
    offering.model_alias == model_alias
  })
}

///|
fn ApiService::shared_trial_text_key_scope(
  self : ApiService,
  organization_id : String,
  tenant_ref : String,
  models : Array[String],
) -> Bool {
  models.length() > 0 &&
  models.all(model => {
    self.shared_trial_text_offering(organization_id, tenant_ref, model)
    is Some(_)
  })
}

///|
fn shared_trial_node_matches(
  offering : SharedTrialOffering?,
  node_id : String,
) -> Bool {
  offering.map_or(true, value => value.node_id == node_id)
}

///|
async fn ApiService::shared_trial_authorized_key(
  self : ApiService,
  authority : @access.ApiAuthorization,
  model_alias : String,
) -> SharedTrialOffering? {
  let access_key = match self.access_store {
    Some(access) =>
      access
      .views_for_subject(authority.tenant_ref, authority.subject_ref)
      .iter()
      .find_first(key => key.key_id == authority.key_id)
      .map_or(false, key => {
        key.maximum_requests == 0L &&
        self.shared_trial_text_key_scope(
          authority.organization_id,
          authority.tenant_ref,
          key.allowed_models,
        )
      })
    None => false
  }
  let handoff_key = match self.client_handoff_store {
    Some(handoffs) =>
      handoffs.snapshot().credentials.any(key => {
        key.key_id == authority.key_id &&
        key.tenant_ref == authority.tenant_ref &&
        key.subject_ref == authority.subject_ref &&
        key.organization_id == Some(authority.organization_id) &&
        key.maximum_requests == 0L &&
        self.shared_trial_text_key_scope(
          authority.organization_id,
          authority.tenant_ref,
          key.allowed_models,
        )
      })
    None => false
  }
  if !access_key && !handoff_key {
    return None
  }
  self.shared_trial_text_offering(
    authority.organization_id,
    authority.tenant_ref,
    model_alias,
  )
}

///|
async fn ApiService::shared_trial_node_online(
  self : ApiService,
  node_id : String,
  now : Int64,
) -> Bool {
  self.store
  .heartbeats()
  .any(heartbeat => {
    heartbeat.node_id == node_id &&
    heartbeat.state == Active &&
    heartbeat.timestamp_unix_ms <= now &&
    now - heartbeat.timestamp_unix_ms <=
    self.global_settings.control_timing.heartbeat_timeout_ms &&
    heartbeat.inventory.labels.get(machine_usage_pool_label) == Some("trial")
  })
}

///|
pub fn ApiService::with_shared_trial_offerings(
  self : ApiService,
  offerings : Array[SharedTrialOffering],
) -> ApiService raise {
  let seen : Map[String, Unit] = Map([])
  let text_models : Map[String, Unit] = Map([])
  for offering in offerings {
    let identity = "\{offering.organization_id}|\{offering.node_id}"
    let text_identity = "\{offering.organization_id}|\{offering.tenant_ref}|\{offering.model_alias}"
    if offering.organization_id == "" ||
      offering.tenant_ref == "" ||
      offering.node_id == "" ||
      offering.node_label == "" ||
      offering.model_alias == "" ||
      offering.model_name == "" ||
      !["Video", "Text"].contains(offering.kind) ||
      (
        offering.kind == "Text" &&
        !@contracts.valid_identifier(offering.model_alias)
      ) ||
      !offering.health_url.has_prefix("http://") ||
      !offering.public_url.has_prefix("https://") ||
      seen.contains(identity) ||
      (offering.kind == "Text" && text_models.contains(text_identity)) {
      raise Failure::Failure("invalid shared trial offering configuration")
    }
    seen[identity] = ()
    if offering.kind == "Text" {
      text_models[text_identity] = ()
    }
  }
  { ..self, shared_trial_offerings: offerings, }
}

///|
async fn ApiService::shared_trial_offering_view(
  self : ApiService,
  offering : SharedTrialOffering,
  now : Int64,
) -> Json {
  let node_online = self.shared_trial_node_online(offering.node_id, now)
  let service_responding = if node_online {
    try
      @async.with_timeout(2000, () => {
        let (response, _) = @http.get(offering.health_url)
        response.code == 200
      })
    catch {
      _ => false
    } noraise {
      value => value
    }
  } else {
    false
  }
  {
    "node_id": offering.node_id,
    "node_label": offering.node_label,
    "model_alias": offering.model_alias,
    "model_name": offering.model_name,
    "kind": offering.kind,
    "node_online": node_online,
    "service_responding": service_responding,
    "public_url": offering.public_url,
    "shared": true,
    "request_limit": "none",
  }
}
