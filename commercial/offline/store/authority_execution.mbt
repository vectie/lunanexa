///|
/// Serializes actual authority execution against cancellation and expiry.
/// Callbacks must not reenter this store. The target mutation is idempotent so
/// a process crash before the completion commit can safely replay the work.
pub async fn[T] OfflineCommerceStore::with_authority_execution(
  self : OfflineCommerceStore,
  execute : async (
    @offline.OfflineCommerceSnapshot,
    async (@offline.EntitlementActivation) -> @offline.CommercialOrder,
    async (@offline.CommercialReversal) -> @offline.CommercialOrder,
  ) -> T,
) -> T {
  self.mutex.acquire()
  defer self.mutex.release()
  execute(
    self.snapshot_unlocked(),
    result => self.complete_activation_unlocked(result),
    result => self.complete_reversal_unlocked(result),
  )
}
