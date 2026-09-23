///|
#borrow(path)
extern "c" fn native_storage_statvfs(path : Bytes) -> Bytes = "lunanexa_storage_statvfs"

///|
priv struct StorageCapacity {
  total_bytes : Int64
  free_bytes : Int64
  available_bytes : Int64
  total_inodes : Int64
  available_inodes : Int64
}

///|
fn parse_storage_capacity(value : String) -> StorageCapacity? {
  let fields = value.split(",").to_array()
  if fields.length() != 5 {
    return None
  }
  try {
    let total = @string.parse_int64(fields[0])
    let free = @string.parse_int64(fields[1])
    let available = @string.parse_int64(fields[2])
    let inodes = @string.parse_int64(fields[3])
    let available_inodes = @string.parse_int64(fields[4])
    guard total > 0L &&
      free >= 0L &&
      available >= 0L &&
      free <= total &&
      available <= free &&
      inodes >= 0L &&
      available_inodes >= 0L &&
      available_inodes <= inodes else {
      return None
    }
    Some({
      total_bytes: total,
      free_bytes: free,
      available_bytes: available,
      total_inodes: inodes,
      available_inodes,
    })
  } catch {
    _ => None
  }
}

///|
fn read_storage_capacity(path : String) -> StorageCapacity? {
  if !path.has_prefix("/") || path.length() > 512 || path.contains("..") {
    return None
  }
  parse_storage_capacity(
    @utf8.decode_lossy(native_storage_statvfs(@utf8.encode(path))),
  )
}

///|
async fn ApiService::handle_storage_nodes(
  self : ApiService,
  verb : ApiMethod,
  headers : Map[String, String],
) -> HttpReply {
  if verb != Get {
    return api_error(
      405, "MethodNotAllowed", "storage monitoring is read only", false,
    )
  }
  if !self.operator_authorized(headers) {
    return api_error(
      401, "Unauthenticated", "operator authority is required", false,
    )
  }
  guard @env.get_env_var("LUNANEXA_STORAGE_MONITOR_PATH") is Some(path) &&
    path != "" else {
    return json_reply(200, ([] : Array[Json]).to_json())
  }
  let node_id = @env.get_env_var("LUNANEXA_STORAGE_NODE_ID").unwrap_or(
    "management-storage",
  )
  let sampled_at_ms = @async.now()
  let row : Json = match read_storage_capacity(path) {
    Some(capacity) =>
      {
        "node_id": node_id,
        "state": "healthy",
        "total_bytes": capacity.total_bytes.to_json(),
        "used_bytes": (capacity.total_bytes - capacity.free_bytes).to_json(),
        "available_bytes": capacity.available_bytes.to_json(),
        "total_inodes": capacity.total_inodes.to_json(),
        "available_inodes": capacity.available_inodes.to_json(),
        "sampled_at_ms": sampled_at_ms.to_json(),
      }
    None =>
      {
        "node_id": node_id,
        "state": "unavailable",
        "total_bytes": Json::null(),
        "used_bytes": Json::null(),
        "available_bytes": Json::null(),
        "total_inodes": Json::null(),
        "available_inodes": Json::null(),
        "sampled_at_ms": sampled_at_ms.to_json(),
      }
  }
  json_reply(200, [row].to_json())
}
