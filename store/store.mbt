///|
pub(open) trait MetadataStore {
  fn put_assignment(Self, @contracts.DesiredAssignment) -> Unit raise
  fn get_assignment(Self, String) -> @contracts.DesiredAssignment? raise
  fn append_audit(Self, @contracts.AuditEvent) -> Unit raise
  fn audit_events(Self) -> Array[@contracts.AuditEvent] raise
}
