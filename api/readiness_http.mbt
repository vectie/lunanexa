///| Production-facing readiness is intentionally separate from `/health`.

///| Liveness answers whether the process can serve; this contract answers

///| whether every externally dependent management-plane capability has

///|
/// verified configuration.
pub(all) struct ManagementReadiness {
  version : String
  ready : Bool
  blocker_codes : Array[String]
  notification_delivery : @notifications.NotificationDeliveryReadiness?
  observability : @observability.ObservabilityReadiness?
  offline_commerce : @offline.OfflineCommerceReadiness
  credential_broker_configured : Bool
  machine_helper_receipt_verifier_configured : Bool
  machine_helper_adapter_verified : Bool
  machine_helper_adapter_node_scope : String?
  machine_helper_covered_node_count : Int
  eligible_enrolled_node_count : Int
  exclusive_machine_authority_configured : Bool
  artifact_signature_verifier_configured : Bool
  guide_diagnostics_configured : Bool
  exclusive_lease_expiry_reconciler_healthy : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// A stale success must not mask a newer failed probe.
fn latest_component_event_healthy(
  events : Array[@observability.OperationalEvent],
  event_code : String,
  target_type : String,
  since_unix_ms : Int64,
) -> Bool {
  let mut latest_time = 0L
  let mut healthy = false
  for event in events {
    if event.event_code == event_code &&
      event.target_type == target_type &&
      event.timestamp_unix_ms >= since_unix_ms &&
      event.timestamp_unix_ms >= latest_time {
      latest_time = event.timestamp_unix_ms
      healthy = event.outcome == "healthy" &&
        event.status_code >= 200 &&
        event.status_code < 300
    }
  }
  latest_time > 0L && healthy
}

///| Safe Kubernetes readiness: only local controller authorities and durable

///| stores. External providers are deliberately evaluated by the protected

///|
/// production-acceptance contract below.
pub async fn ApiService::internal_component_ready(self : ApiService) -> Bool {
  self.store.current_epoch_is_durable() &&
  self.notification_store is Some(_) &&
  self.observability_store is Some(_) &&
  self.offline_commerce_store is Some(_) &&
  self.exclusive_lease_store is Some(_) &&
  self.credential_handoff_store is Some(_)
}

///|
pub async fn ApiService::management_readiness(
  self : ApiService,
  now_unix_ms : Int64,
) -> ManagementReadiness {
  let notification_delivery = match self.notification_store {
    Some(store) =>
      Some(
        store.delivery_readiness(
          self.notification_delivery_adapter_configured,
          now_unix_ms~,
        ),
      )
    None => None
  }
  let observability = match self.observability_store {
    Some(store) =>
      Some(
        store.readiness(
          external_collector_configured=self.external_observability_collector_configured,
          now_unix_ms~,
        ),
      )
    None => None
  }
  let offline_commerce = self.offline_readiness(now_unix_ms)
  let credential_broker_configured = match self.credential_handoff_store {
    Some(store) => store.issuer_adapter_ready(now_unix_ms)
    None => false
  }
  let machine_helper_receipt_verifier_configured = self.lease_helper_receipt_secret.length() >=
    32
  let eligible_enrolled_node_ids = match self.enrollment {
    Some(enrollment) => enrollment.active_node_ids(now_unix_ms)
    None => []
  }
  let machine_helper_adapter_node_scope = match
    self.machine_helper_adapter_evidence {
    Some(evidence) => Some(evidence.node_scope)
    None => None
  }
  let machine_helper_covered_node_count = match
    self.machine_helper_adapter_evidence {
    Some(evidence) => evidence.covered_node_ids.length()
    None => 0
  }
  let heartbeats = self.store.heartbeats()
  let fresh_eligible_nodes = eligible_enrolled_node_ids.all(node_id => {
    heartbeats.any(heartbeat => {
      heartbeat.node_id == node_id &&
      heartbeat.state != Unreachable &&
      heartbeat.state != Retired &&
      heartbeat.timestamp_unix_ms <= now_unix_ms &&
      now_unix_ms - heartbeat.timestamp_unix_ms <=
      self.global_settings.control_timing.heartbeat_timeout_ms
    })
  })
  let machine_helper_adapter_verified = match
    self.machine_helper_adapter_evidence {
    Some(evidence) => {
      let covered = evidence.covered_node_ids.copy()
      covered.sort()
      @nodelease.machine_helper_adapter_evidence_ready(evidence, now_unix_ms) &&
      (match self.enrollment {
        Some(_) => covered == eligible_enrolled_node_ids && fresh_eligible_nodes
        None => true
      })
    }
    None => false
  }
  let exclusive_machine_authority_configured = self.exclusive_lease_store
    is Some(_) &&
    credential_broker_configured &&
    machine_helper_receipt_verifier_configured &&
    machine_helper_adapter_verified
  let artifact_signature_verifier_configured = self.signature_verifier
    is Some(_)
  let guide_diagnostics_configured = self.guide_diagnostics_token.length() >= 32 &&
    (match self.observability_store {
      Some(store) =>
        latest_component_event_healthy(
          store.snapshot().events,
          "GuideDiagnosticsProbeCompleted",
          "guide",
          (now_unix_ms - 120000L).max(1L),
        )
      None => false
    })
  let exclusive_lease_expiry_reconciler_healthy = match
    self.observability_store {
    Some(store) =>
      latest_component_event_healthy(
        store.snapshot().events,
        "ExclusiveLeaseExpiryReconciliationCompleted",
        "exclusive_lease",
        (now_unix_ms - 120000L).max(1L),
      )
    None => false
  }
  let blockers : Array[String] = []
  match notification_delivery {
    None => blockers.push("NotificationStoreUnavailable")
    Some(readiness) =>
      if readiness.state != DeliveryReady {
        blockers.push("NotificationDeliveryNotReady")
      }
  }
  match observability {
    None => blockers.push("ObservabilityStoreUnavailable")
    Some(readiness) =>
      if readiness.state != LocalJsonReady {
        blockers.push("ExternalObservabilityNotReady")
      }
  }
  if offline_commerce.status != OfflineCommerceReady {
    blockers.push("OfflineCommerceNotReady")
  }
  if !credential_broker_configured {
    blockers.push("CredentialBrokerUnavailable")
  }
  if !machine_helper_receipt_verifier_configured {
    blockers.push("MachineHelperVerifierUnavailable")
  }
  if !machine_helper_adapter_verified {
    blockers.push("MachineHelperAdapterUnverified")
  }
  if !exclusive_machine_authority_configured {
    blockers.push("ExclusiveMachineAuthorityUnavailable")
  }
  if !artifact_signature_verifier_configured {
    blockers.push("ArtifactSignatureVerifierUnavailable")
  }
  if !guide_diagnostics_configured {
    blockers.push("GuideDiagnosticsUnavailable")
  }
  if !exclusive_lease_expiry_reconciler_healthy {
    blockers.push("ExclusiveLeaseExpiryReconcilerUnavailable")
  }
  {
    version: "lunanexa.management-readiness.v1",
    ready: blockers.length() == 0,
    blocker_codes: blockers,
    notification_delivery,
    observability,
    offline_commerce,
    credential_broker_configured,
    machine_helper_receipt_verifier_configured,
    machine_helper_adapter_verified,
    machine_helper_adapter_node_scope,
    machine_helper_covered_node_count,
    eligible_enrolled_node_count: eligible_enrolled_node_ids.length(),
    exclusive_machine_authority_configured,
    artifact_signature_verifier_configured,
    guide_diagnostics_configured,
    exclusive_lease_expiry_reconciler_healthy,
  }
}
