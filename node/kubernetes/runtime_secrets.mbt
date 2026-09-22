///|
/// A deployment-owned Secret reference scoped to one exact immutable image.
/// Secret values never enter the journal, image, assignment or renderer.
pub(all) struct RuntimeSecretBinding {
  image_ref : String
  environment_name : String
  secret_name : String
  secret_key : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RuntimeSecretBinding with Debug::{to_repr}

///|
pub extend RuntimeSecretBinding with Eq::{not_equal, equal}

///|
pub extend RuntimeSecretBinding with ToJson::{to_json}

///|
pub extend RuntimeSecretBinding with FromJson::{from_json}

///|
fn environment_identifier(value : String) -> Bool {
  let first = value.iter().next().unwrap_or('0')
  value.length() > 0 &&
  value.length() <= 128 &&
  ((first >= 'A' && first <= 'Z') || first == '_') &&
  value.all(c => (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_') &&
  !["LUNANEXA_", "NVIDIA_", "CUDA_", "AWS_", "KUBERNETES_", "LD_", "PYTHON"].any(prefix => {
      value.has_prefix(prefix)
    },
  ) &&
  !["PATH", "HOME", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY"].contains(
    value,
  )
}

///|
fn validate_secret_bindings(
  bindings : Array[RuntimeSecretBinding],
) -> Unit raise LifecycleError {
  if bindings.length() > 64 {
    raise InvalidResource
  }
  let seen : Map[String, Bool] = Map([])
  for binding in bindings {
    let image = binding.image_ref.split("@").collect()
    if image.length() != 2 ||
      image[0].length() == 0 ||
      !@contracts.valid_sha256_digest(image[1].to_owned()) ||
      !image[0]
      .to_owned()
      .all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') ||
        c == '/' ||
        c == ':' ||
        c == '.' ||
        c == '_' ||
        c == '-'
      }) ||
      !environment_identifier(binding.environment_name) ||
      !dns_label(binding.secret_name) ||
      !binding.secret_name.has_prefix("lunanexa-runtime-") ||
      binding.secret_key.length() == 0 ||
      binding.secret_key.length() > 253 ||
      !binding.secret_key.all(c => {
        (c >= 'a' && c <= 'z') ||
        (c >= 'A' && c <= 'Z') ||
        (c >= '0' && c <= '9') ||
        c == '_' ||
        c == '-' ||
        c == '.'
      }) {
      raise InvalidResource
    }
    let key = binding.image_ref + "|" + binding.environment_name
    if seen.contains(key) {
      raise InvalidResource
    }
    seen[key] = true
  }
}

///|
fn runtime_environment(
  settings : RuntimeSettings,
  assignment : @contracts.DesiredAssignment,
) -> Array[Json] raise LifecycleError {
  let bindings = settings.runtime_secrets.unwrap_or([])
  validate_secret_bindings(bindings)
  let result : Array[Json] = [
    { "name": "LUNANEXA_MODEL_PATH", "value": "/var/lib/lunanexa/model/model" },
    {
      "name": "LUNANEXA_ARTIFACT_DIGEST",
      "value": assignment.artifact.digest.to_json(),
    },
  ]
  let image = assignment.runtime.name + "@" + assignment.runtime.image_digest
  // The device plugin hands out a count, not an identity, so the exact devices
  // the assignment was signed for are pinned through the variable the GPU
  // runtime reads. Without this, a pod would get whatever GPU the kubelet
  // happened to pick on that node.
  if settings.device_plugin_resource is Some(_) &&
    assignment.devices.length() > 0 {
    result.push({
      "name": "NVIDIA_VISIBLE_DEVICES",
      "value": assignment.devices.join(",").to_json(),
    })
  }
  // A member of a pair is told where it sits and where its one peer is, on the
  // address this node declared for the private fabric. Rank 0 is the head, so
  // both members take their rendezvous point from the head's address.
  if assignment.group is Some(group) {
    let self_address = settings.fabric_address.unwrap_or("")
    let head_address = if group.rank == 0 {
      self_address
    } else {
      group.peer_endpoint
    }
    let member_environment : Array[(String, String)] = [
      ("LUNANEXA_GROUP_ID", group.group_id),
      ("LUNANEXA_RANK", group.rank.to_string()),
      ("LUNANEXA_WORLD_SIZE", group.world_size.to_string()),
      ("LUNANEXA_PEER_ENDPOINT", group.peer_endpoint),
      ("LUNANEXA_SELF_ENDPOINT", self_address),
      ("LUNANEXA_HEAD_ENDPOINT", head_address),
    ]
    for name_and_value in member_environment {
      let (name, value) = name_and_value
      result.push({ "name": name.to_json(), "value": value.to_json() })
    }
  }
  for binding in bindings {
    if binding.image_ref != image {
      continue
    }
    result.push({
      "name": binding.environment_name.to_json(),
      "valueFrom": {
        "secretKeyRef": {
          "name": binding.secret_name.to_json(),
          "key": binding.secret_key.to_json(),
          "optional": false,
        },
      },
    })
  }
  result
}
