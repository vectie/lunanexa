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
