///|
/// A liveness observation is deliberately not business success evidence and
/// does not claim, retry, or complete any work.
pub async fn OfflineCommerceStore::record_dispatcher_heartbeat(
  self : OfflineCommerceStore,
  worker_kind : @offline.OfflineWorkerKind,
  now_unix_ms : Int64,
) -> Unit {
  if now_unix_ms <= 0L {
    raise @offline.OfflineCommerceError::InvalidInput("invalid heartbeat time")
  }
  self.mutex.acquire()
  defer self.mutex.release()
  let before = self.worker_health
  errdefer {
    self.worker_health = before
  }
  self.worker_health = match worker_kind {
    ArtifactDispatcher =>
      { ..before, artifact_dispatcher_heartbeat_unix_ms: Some(now_unix_ms), }
    EntitlementDispatcher =>
      { ..before, entitlement_dispatcher_heartbeat_unix_ms: Some(now_unix_ms), }
  }
  self.persist()
}
