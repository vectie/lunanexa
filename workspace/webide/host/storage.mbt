///|
fn storage_owner(claim : Json) -> String? {
  match claim {
    {
      "metadata": {
        "annotations": { "lunanexa.io/storage-writer": String(owner), .. },
        ..
      },
      ..
    } if owner != "" => Some(owner)
    _ => None
  }
}

///|
fn storage_cas_version(path : String, body : Json?) -> String? {
  if !path.contains("/persistentvolumeclaims/") {
    return None
  }
  match body {
    Some(
      Array(
        [
          {
            "op": String("test"),
            "path": String("/metadata/resourceVersion"),
            "value": String(version),
            ..
          },
          ..,
        ]
      )
    ) => Some(version)
    _ => None
  }
}

///|
fn storage_cas_conflict(
  status : Int,
  path : String,
  body : Json?,
  observed : Json?,
) -> Bool {
  guard storage_cas_version(path, body) is Some(expected) else { return false }
  if status == 409 {
    return true
  }
  // Kubernetes can report a failed JSON Patch test as 422. Distinguish an
  // actual version race by rereading, not by exposing/parsing its error text.
  status == 422 &&
  observed
  is Some({ "metadata": { "resourceVersion": String(current), .. }, .. }) &&
  current != expected
}

///|
fn storage_profile_matches(claim : Json, config : HostConfig) -> Bool {
  claim
  is {
    "spec": {
      "storageClassName": String(storage_class),
      "accessModes": Array(modes),
      ..
    },
    ..
  } &&
  storage_class == config.storage_class &&
  modes == [config.storage_access_mode.unwrap_or("ReadWriteOnce").to_json()]
}

///|
fn volume_accepts_node(volume : Json, node : String) -> Bool {
  match volume {
    {
      "spec": {
        "nodeAffinity": {
          "required": { "nodeSelectorTerms": Array(terms), .. },
          ..
        },
        ..
      },
      ..
    } =>
      terms.any(term => {
        guard term is { "matchExpressions": Array(expressions), .. } else {
          return false
        }
        expressions.all(expression => {
          expression
          is {
            "key": String("kubernetes.io/hostname"),
            "operator": String("In"),
            "values": Array(values),
            ..
          } &&
          values.contains(node.to_json())
        })
      })
    _ => true
  }
}

///|
async fn WorkspaceHost::ensure_storage(
  self : WorkspaceHost,
  id : String,
  placement : ExclusivePlacement,
  path : String,
  desired : Json,
) -> Unit {
  guard desired is { "metadata": { "name": String(name), .. }, .. } else {
    raise HostError::InvalidConfiguration
  }
  let (_, found) = self.kubernetes(
    Get,
    "/api/v1/namespaces/\{self.config.namespace_name}/persistentvolumeclaims?fieldSelector=metadata.name%3D\{name}",
    None,
  )
  let claim = match found {
    { "items": Array([]), .. } => {
      if self.config.storage_access_mode == Some("ReadWriteMany") {
        let (_, classes) = self.kubernetes(
          Get,
          "/apis/storage.k8s.io/v1/storageclasses?fieldSelector=metadata.name%3D\{self.config.storage_class}",
          None,
        )
        if classes is { "items": Array([]), .. } {
          raise @webide.BridgeError::StorageNotConfigured
        }
      }
      let (_, created) = self.kubernetes(
        Patch,
        path + "?fieldManager=lunanexa-webide&force=false",
        Some(desired),
      )
      created
    }
    { "items": Array([existing]), .. } => existing
    _ => raise HostError::WorkspaceUnavailable
  }
  if !storage_profile_matches(claim, self.config) {
    raise @webide.BridgeError::StorageMigrationRequired
  }
  if self.config.storage_access_mode.unwrap_or("ReadWriteOnce") ==
    "ReadWriteOnce" &&
    claim
    is {
      "metadata": {
        "annotations": {
          "volume.kubernetes.io/selected-node": String(selected),
          ..
        },
        ..
      },
      ..
    } &&
    selected != placement.node_name {
    raise @webide.BridgeError::StorageMigrationRequired
  }
  if claim is { "spec": { "volumeName": String(volume_name), .. }, .. } {
    if !dns_label(volume_name) {
      raise HostError::InvalidConfiguration
    }
    let (_, volume) = self.kubernetes(
      Get,
      "/api/v1/persistentvolumes/\{volume_name}",
      None,
    )
    if !volume_accepts_node(volume, placement.node_name) {
      raise @webide.BridgeError::StorageMigrationRequired
    }
  }
  if storage_owner(claim) is Some(owner) {
    if owner != id {
      raise @webide.BridgeError::StorageBusy
    }
    return
  }
  self.set_storage_owner(path, claim, id)
}

///|
async fn WorkspaceHost::set_storage_owner(
  self : WorkspaceHost,
  path : String,
  claim : Json,
  owner : String,
) -> Unit {
  guard claim is { "metadata": { "resourceVersion": String(version), .. }, .. } else {
    raise HostError::WorkspaceUnavailable
  }
  let annotations = match claim {
    { "metadata": { "annotations": Object(values), .. }, .. } => values.copy()
    _ => Map([])
  }
  annotations["lunanexa.io/storage-writer"] = owner.to_json()
  let patch : Json = [
    { "op": "test", "path": "/metadata/resourceVersion", "value": version },
    {
      "op": "add",
      "path": "/metadata/annotations",
      "value": annotations.to_json(),
    },
  ]
  // Kubernetes CAS is the lock across gateway instances, not an in-memory
  // mutex or RWX access mode. A racing writer retries through normal launch.
  ignore(self.kubernetes(Patch, path, Some(patch)))
}

///|
async fn WorkspaceHost::release_storage(
  self : WorkspaceHost,
  id : String,
) -> Unit {
  let prefix = "/api/v1/namespaces/\{self.config.namespace_name}/persistentvolumeclaims"
  let (_, response) = self.kubernetes(
    Get,
    prefix + "?labelSelector=app.kubernetes.io%2Fmanaged-by%3Dlunanexa-webide",
    None,
  )
  guard response is { "items": Array(claims), .. } else {
    raise HostError::WorkspaceUnavailable
  }
  for claim in claims {
    if storage_owner(claim) != Some(id) {
      continue
    }
    guard claim is { "metadata": { "name": String(name), .. }, .. } &&
      dns_label(name) else {
      raise HostError::WorkspaceUnavailable
    }
    self.set_storage_owner(prefix + "/" + name, claim, "")
  }
}
