///|
pub(all) struct BackupBundle {
  version : String
  created_unix_ms : Int64
  controller_snapshot : String
  registry_snapshot : String
  audit_tail_hash : String
  signature_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) suberror BackupError {
  UnsignedBackup
  UnsupportedBackupVersion(String)
  ManifestDigestMismatch
} derive(Debug, Eq)

///|
pub fn create_backup(
  controller_snapshot : String,
  registry_snapshot : String,
  audit_tail_hash : String,
  signature_ref : String,
  now_unix_ms : Int64,
) -> String raise BackupError {
  if signature_ref == "" {
    raise UnsignedBackup
  }
  let bundle : BackupBundle = {
    version: "lunanexa.backup.v1",
    created_unix_ms: now_unix_ms,
    controller_snapshot,
    registry_snapshot,
    audit_tail_hash,
    signature_ref,
  }
  bundle.to_json().stringify()
}

///|
pub fn inspect_backup(json : String) -> BackupBundle raise {
  let bundle : BackupBundle = @json.from_json(@json.parse(json))
  if bundle.version != "lunanexa.backup.v1" {
    raise UnsupportedBackupVersion(bundle.version)
  }
  if bundle.signature_ref == "" {
    raise UnsignedBackup
  }
  bundle
}

///|
pub fn validate_audit_chain(events : Array[@contracts.AuditEvent]) -> Bool {
  for index, event in events {
    if event.sequence != (index + 1).to_int64() {
      return false
    }
    if index == 0 {
      if event.previous_hash != "genesis" {
        return false
      }
    } else if event.previous_hash != events[index - 1].event_hash {
      return false
    }
    if event.event_hash == "" || event.event_hash != audit_event_hash(event) {
      return false
    }
  }
  true
}

///|
pub fn audit_event_hash(event : @contracts.AuditEvent) -> String {
  let material = "lunanexa.audit.v1|\{event.previous_hash}|\{event.sequence}|\{event.event_id}|\{event.timestamp_unix_ms}|\{event.actor}|\{event.policy_version}|\{event.action}|\{event.target}|\{event.prior_state}|\{event.next_state}|\{event.result}|\{event.correlation_receipt}"
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(material)))
}

///|
pub(all) struct FullBackupBundle {
  version : String
  created_unix_ms : Int64
  controller_snapshot : String
  registry_snapshot : String
  enrollment_snapshot : String
  scheduler_snapshot : String
  telemetry_snapshot : String
  audit_tail_hash : String
  manifest_digest : String
  signature_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn full_backup_manifest_digest(
  created_unix_ms : Int64,
  controller_snapshot : String,
  registry_snapshot : String,
  enrollment_snapshot : String,
  scheduler_snapshot : String,
  telemetry_snapshot : String,
  audit_tail_hash : String,
) -> String {
  let manifest : Json = {
    "version": "lunanexa.backup.v2",
    "created_unix_ms": created_unix_ms,
    "controller_snapshot": controller_snapshot,
    "registry_snapshot": registry_snapshot,
    "enrollment_snapshot": enrollment_snapshot,
    "scheduler_snapshot": scheduler_snapshot,
    "telemetry_snapshot": telemetry_snapshot,
    "audit_tail_hash": audit_tail_hash,
  }
  "sha256:\{@crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(manifest.stringify())))}"
}

///|
pub fn create_full_backup(
  controller_snapshot : String,
  registry_snapshot : String,
  enrollment_snapshot : String,
  scheduler_snapshot : String,
  telemetry_snapshot : String,
  audit_tail_hash : String,
  signature_ref : String,
  now_unix_ms : Int64,
) -> String raise BackupError {
  if signature_ref == "" {
    raise UnsignedBackup
  }
  let manifest_digest = full_backup_manifest_digest(
    now_unix_ms, controller_snapshot, registry_snapshot, enrollment_snapshot, scheduler_snapshot,
    telemetry_snapshot, audit_tail_hash,
  )
  let bundle : FullBackupBundle = {
    version: "lunanexa.backup.v2",
    created_unix_ms: now_unix_ms,
    controller_snapshot,
    registry_snapshot,
    enrollment_snapshot,
    scheduler_snapshot,
    telemetry_snapshot,
    audit_tail_hash,
    manifest_digest,
    signature_ref,
  }
  bundle.to_json().stringify()
}

///|
pub fn inspect_full_backup(json : String) -> FullBackupBundle raise {
  let bundle : FullBackupBundle = @json.from_json(@json.parse(json))
  if bundle.version != "lunanexa.backup.v2" {
    raise UnsupportedBackupVersion(bundle.version)
  }
  if bundle.signature_ref == "" ||
    !@contracts.valid_sha256_digest(bundle.manifest_digest) {
    raise UnsignedBackup
  }
  let expected = full_backup_manifest_digest(
    bundle.created_unix_ms,
    bundle.controller_snapshot,
    bundle.registry_snapshot,
    bundle.enrollment_snapshot,
    bundle.scheduler_snapshot,
    bundle.telemetry_snapshot,
    bundle.audit_tail_hash,
  )
  if bundle.manifest_digest != expected {
    raise ManifestDigestMismatch
  }
  bundle
}
