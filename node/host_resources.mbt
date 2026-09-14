///|
pub(all) struct HostResources {
  cpu_count : Int
  memory_total_mib : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Parse Linux host inventory, not container limits or advertised SKU values.
/// Missing, duplicate or malformed measurements fail closed.
pub fn parse_linux_host_resources(
  cpuinfo : String,
  meminfo : String,
) -> HostResources raise {
  guard cpuinfo.length() <= 4194304 && meminfo.length() <= 65536 else {
    raise TelemetryCollectorError::MalformedSample("host inventory size")
  }
  let processors : Map[Int, Bool] = Map([])
  for line in cpuinfo.split("\n") {
    if line.find(":") is Some(separator) &&
      line[:separator].trim() == "processor" {
      let raw = line[separator + 1:].trim()
      guard raw.length() > 0 && raw.all(c => c >= '0' && c <= '9') else {
        raise TelemetryCollectorError::MalformedSample("processor identifier")
      }
      let id = @string.parse_int(raw)
      guard id >= 0 && !processors.contains(id) else {
        raise TelemetryCollectorError::MalformedSample("duplicate processor")
      }
      processors[id] = true
    }
  }
  guard processors.length() > 0 else {
    raise TelemetryCollectorError::MalformedSample("missing processors")
  }
  let mut total : Int64? = None
  for line in meminfo.split("\n") {
    if line.find(":") is Some(separator) &&
      line[:separator].trim() == "MemTotal" {
      guard total is None else {
        raise TelemetryCollectorError::MalformedSample("duplicate MemTotal")
      }
      let fields = line[separator + 1:]
        .trim()
        .split(" ")
        .filter(field => field != "")
        .to_array()
      guard fields.length() == 2 &&
        fields[1] == "kB" &&
        fields[0].all(c => c >= '0' && c <= '9') else {
        raise TelemetryCollectorError::MalformedSample("MemTotal units")
      }
      let kib = @string.parse_int64(fields[0])
      guard kib >= 1024L else {
        raise TelemetryCollectorError::MalformedSample("MemTotal value")
      }
      total = Some(kib / 1024L)
    }
  }
  guard total is Some(memory_total_mib) else {
    raise TelemetryCollectorError::MalformedSample("missing MemTotal")
  }
  { cpu_count: processors.length(), memory_total_mib }
}

///|
/// Read Linux procfs. Callers running in containers must not interpret this
/// host measurement as their container's allocatable resource limit.
pub async fn collect_linux_host_resources() -> HostResources {
  parse_linux_host_resources(
    @fs.read_file("/proc/cpuinfo").text(),
    @fs.read_file("/proc/meminfo").text(),
  )
}
