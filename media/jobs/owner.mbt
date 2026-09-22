///|
/// Preserve commercial JSON byte-for-byte, including field order, because it
/// participates in persisted idempotency digests. Private ownership is explicit.

///|
pub extend Owner with ToJson::{to_json}

///|
pub impl ToJson for Owner with fn to_json(self) {
  let fields : Map[String, Json] = {
    "tenant_ref": self.tenant_ref.to_json(),
    "subject_ref": self.subject_ref.to_json(),
    "organization_id": self.organization_id.to_json(),
    "project_id": self.project_id.to_json(),
  }
  match self.authority {
    DedicatedOrder(id) => fields["order_id"] = id.to_json()
    PrivateWorkspace(id) => fields["workspace_lease_id"] = id.to_json()
  }
  fields.to_json()
}

///|
priv struct OwnerWire {
  tenant_ref : String
  subject_ref : String
  organization_id : String
  project_id : String
  order_id : String?
  workspace_lease_id : String?
} derive(FromJson)

///|
pub extend Owner with FromJson::{from_json}

///|
pub impl @json.FromJson for Owner with fn from_json(value, path) {
  let wire : OwnerWire = @json.from_json(value, path~)
  let authority = match (wire.order_id, wire.workspace_lease_id) {
    (Some(id), None) => DedicatedOrder(id)
    (None, Some(id)) => PrivateWorkspace(id)
    _ =>
      raise JsonDecodeError((path, "exactly one media authority is required"))
  }
  {
    tenant_ref: wire.tenant_ref,
    subject_ref: wire.subject_ref,
    organization_id: wire.organization_id,
    project_id: wire.project_id,
    authority,
  }
}

///|
fn Authority::reference(self : Authority) -> String {
  match self {
    DedicatedOrder(id) | PrivateWorkspace(id) => id
  }
}

///|
fn Authority::slot(self : Authority) -> String {
  match self {
    DedicatedOrder(id) => "order:" + id
    PrivateWorkspace(id) => "workspace:" + id
  }
}
