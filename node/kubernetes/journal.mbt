///|
pub type JournalCommit = async (String) -> Unit

///|
struct ResourceRecord {
  collection : String
  resource : Json
  mut uid : String?
  mut gone : Bool
} derive(ToJson, FromJson)

///|
struct RuntimeRecord {
  name : String
  assignment_id : String
  generation : Int64
  image_ref : String
  image_digest : String
  artifact_digest : String
  lease_expires_unix_ms : Int64
  intent : String
  resources : Array[ResourceRecord]
  mut stopping : Bool
} derive(ToJson, FromJson)

///|
struct RuntimeJournal {
  version : String
  settings : RuntimeSettings
  owner : String
  mut runtimes : Array[RuntimeRecord]
} derive(ToJson, FromJson)

///|
pub struct RuntimeSupervisor {
  journal : RuntimeJournal
  transport : Transport
  commit : JournalCommit
  mutex : @async.Mutex
  file_lock : @fs.File?
  mut closed : Bool
  clock : () -> Int64
}

///|
pub(all) struct RuntimeObservation {
  assignment_id : String
  pod_name : String
  state : @contracts.DeploymentState
  address : String
} derive(Debug, Eq)

///|
fn digest_text(value : String) -> String {
  @crypto.bytes_to_hex_string(@crypto.sha256(@utf8.encode(value)))
}

///|
/// Restore a node-owned journal. The nonce for a fresh journal must come from
/// the host CSPRNG; it is an ownership correlation marker, not an API credential.
pub fn RuntimeSupervisor::restore(
  settings : RuntimeSettings,
  transport : Transport,
  commit : JournalCommit,
  snapshot : String?,
  fresh_owner : String,
  clock? : () -> Int64 = @async.now,
) -> RuntimeSupervisor raise {
  let stored_journal : RuntimeJournal = match snapshot {
    Some(value) => @json.from_json(@json.parse(value))
    None =>
      {
        version: "lunanexa.kubernetes.runtime.v1",
        settings,
        owner: fresh_owner,
        runtimes: [],
      }
  }
  if stored_journal.version != "lunanexa.kubernetes.runtime.v1" ||
    {
      ..stored_journal.settings,
      runtime_secrets: None,
      controller_addresses: [],
    } !=
    { ..settings, runtime_secrets: None, controller_addresses: [], } ||
    (
      stored_journal.settings.controller_addresses !=
      settings.controller_addresses &&
      (
        !stored_journal.runtimes.is_empty() ||
        settings.controller_addresses.is_empty() ||
        !settings.controller_addresses.all(private_address)
      )
    ) ||
    !@contracts.valid_sha256_digest("sha256:" + stored_journal.owner) ||
    stored_journal.runtimes.length() > 1024 {
    raise LifecycleError::InvalidResource
  }
  // New image-bound references must not prevent cleanup of previous resources.
  // A live generation still has to match its persisted immutable resource intent.
  // Controller source routes may change only after every owned runtime has been
  // confirmed gone. Preserve the owner nonce and all identity/cache boundaries;
  // never discard a journal merely to apply a network-policy correction.
  let journal = { ..stored_journal, settings, }
  let names : Map[String, Bool] = Map([])
  for record in journal.runtimes {
    if !dns_label(record.name) ||
      !dns_label(record.assignment_id) ||
      names.contains(record.name) ||
      record.resources.length() < 2 ||
      record.resources.length() > 3 {
      raise LifecycleError::InvalidResource
    }
    names[record.name] = true
    for i, resource in record.resources {
      let expected = if i == 0 {
        AuxiliaryKind::NetworkPolicy.collection(settings.namespace_name)
      } else if i == record.resources.length() - 1 {
        "/api/v1/namespaces/\{settings.namespace_name}/pods"
      } else {
        AuxiliaryKind::ClaimTemplate.collection(settings.namespace_name)
      }
      if resource.collection != expected || resource.uid == Some("") {
        raise LifecycleError::InvalidResource
      }
      ignore(
        validate_owned_resource(
          journal,
          record,
          resource,
          resource.resource,
          require_uid=false,
        ),
      )
    }
  }
  {
    journal,
    transport,
    commit,
    mutex: @async.Mutex(),
    file_lock: None,
    closed: false,
    clock,
  }
}

///|
pub fn RuntimeSupervisor::snapshot(self : RuntimeSupervisor) -> String {
  ToJson::to_json(self.journal).stringify()
}

///|
async fn RuntimeSupervisor::persist(self : RuntimeSupervisor) -> Unit {
  (self.commit)(self.snapshot())
}

///|
fn stamp(
  resource : Json,
  owner : String,
  intent : String,
) -> Json raise LifecycleError {
  guard resource
    is { "metadata": { "annotations": Object(annotations), .. }, .. } else {
    raise InvalidResource
  }
  annotations["lunanexa.io/owner"] = owner.to_json()
  annotations["lunanexa.io/intent"] = intent.to_json()
  resource
}

///|
/// Kubernetes may add defaults, but must not change a submitted field or add
/// array members (for example a container, mount, GPU request or egress rule).
fn contains_submitted(actual : Json, submitted : Json) -> Bool {
  match (actual, submitted) {
    (Object(actual_fields), Object(expected_fields)) =>
      expected_fields
      .iter()
      .all(pair => {
        let (key, value) = pair
        match actual_fields.get(key) {
          Some(actual_value) => contains_submitted(actual_value, value)
          None =>
            match value {
              False | Null => true
              Array(values) => values.is_empty()
              Object(values) => values.is_empty()
              _ => false
            }
        }
      })
    (Array(actual_values), Array(expected_values)) => {
      if actual_values.length() != expected_values.length() {
        return false
      }
      for i, value in expected_values {
        if !contains_submitted(actual_values[i], value) {
          return false
        }
      }
      true
    }
    _ => actual == submitted
  }
}

///|
fn validate_owned_resource(
  journal : RuntimeJournal,
  record : RuntimeRecord,
  resource : ResourceRecord,
  actual : Json,
  require_uid? : Bool = true,
) -> String raise LifecycleError {
  guard actual
    is {
      "metadata": {
        "namespace": String(namespace_name),
        "name": String(name),
        "annotations": {
          "lunanexa.io/owner": String(owner),
          "lunanexa.io/intent": String(intent),
          ..
        },
        ..
      },
      ..
    } &&
    namespace_name == journal.settings.namespace_name &&
    name == record.name &&
    owner == journal.owner &&
    intent == record.intent &&
    contains_submitted(actual, resource.resource) else {
    raise OwnershipConflict
  }
  if !require_uid {
    return ""
  }
  guard actual is { "metadata": { "uid": String(uid), .. }, .. } && uid != "" else {
    raise InvalidResource
  }
  if resource.uid is Some(expected) && expected != uid {
    raise OwnershipConflict
  }
  uid
}

///|
/// Cleanup of a recorded UID must remain possible after its mutable contents
/// were changed. For an ambiguous create with no recorded UID, require the
/// durable owner/intent markers before issuing a conditional deletion.
fn cleanup_uid(
  journal : RuntimeJournal,
  record : RuntimeRecord,
  resource : ResourceRecord,
  actual : Json,
) -> String raise LifecycleError {
  guard actual
    is {
      "metadata": {
        "namespace": String(namespace_name),
        "name": String(name),
        "uid": String(uid),
        ..
      },
      ..
    } &&
    namespace_name == journal.settings.namespace_name &&
    name == record.name &&
    uid != "" else {
    raise OwnershipConflict
  }
  match resource.uid {
    Some(expected) => if uid != expected { raise OwnershipConflict }
    None => {
      guard actual
        is {
          "metadata": {
            "annotations": {
              "lunanexa.io/owner": String(owner),
              "lunanexa.io/intent": String(intent),
              ..
            },
            ..
          },
          ..
        } &&
        owner == journal.owner &&
        intent == record.intent else {
        raise OwnershipConflict
      }
    }
  }
  uid
}
