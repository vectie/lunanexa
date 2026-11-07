///|
priv struct GroupTarget {
  host : String
  unit : String?
  container : String?
  image : String?
} derive(FromJson)

///|
priv struct RuntimeGroup {
  runtime : String
  targets : Array[GroupTarget]
  start_order : Array[Int32]
  stop_order : Array[Int32]
} derive(FromJson)

///|
fn validate_group(group : RuntimeGroup) -> Unit raise {
  let count = group.targets.length()
  guard count > 0 &&
    count <= 32 &&
    ["docker", "systemd-user"].contains(group.runtime) else {
    raise Failure("invalid runtime group")
  }
  for order in [group.start_order, group.stop_order] {
    guard order.length() == count else {
      raise Failure("invalid runtime lifecycle order")
    }
    for i in 0..<count {
      guard order.count_if(x => x == i) == 1 else {
        raise Failure("invalid runtime lifecycle order")
      }
    }
  }
  for target in group.targets {
    guard target.host != "" && !target.host.has_prefix("-") else {
      raise Failure("invalid runtime host")
    }
    if group.runtime == "systemd-user" {
      guard target.unit is Some(unit) &&
        unit.has_suffix(".service") &&
        unit.all(c => {
          c is ('a'..<='z' | 'A'..<='Z' | '0'..<='9' | '-' | '_' | '.')
        }) else {
        raise Failure("invalid runtime unit")
      }
    } else {
      guard target.container is Some(name) &&
        name != "" &&
        !name.has_prefix("-") &&
        target.image is Some(image) &&
        image.contains("@sha256:") else {
        raise Failure("pinned runtime container identity required")
      }
    }
  }
}

///|
fn runtime_group() -> RuntimeGroup raise {
  let group : RuntimeGroup = @json.from_json(
    @json.parse(required("LUNANEXA_RUNTIME_GROUP_JSON")),
  )
  validate_group(group)
  group
}
