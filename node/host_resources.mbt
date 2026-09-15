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
  { cpu_count: processors.length(), memory_total_mib, }
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

///|
/// Reserved signed-inventory labels are overwritten from measurement, never
/// inherited from the static inventory file or a customer offering.
pub fn HostResources::inventory(
  self : HostResources,
  base : @contracts.NodeInventory,
) -> @contracts.NodeInventory {
  let labels = base.labels.copy()
  labels["lunanexa.io/host-cpu-count"] = self.cpu_count.to_string()
  labels["lunanexa.io/host-memory-mib"] = self.memory_total_mib.to_string()
  { ..base, labels, }
}

///|
/// Older agents without host measurements remain enrolled but cannot satisfy
/// paid machine capacity. Invalid signed measurements fail closed as well.
pub fn inventory_host_resources(
  inventory : @contracts.NodeInventory,
) -> HostResources? {
  try {
    guard inventory.labels.get("lunanexa.io/host-cpu-count") is Some(cpu) &&
      inventory.labels.get("lunanexa.io/host-memory-mib") is Some(memory) &&
      cpu.length() > 0 &&
      memory.length() > 0 &&
      cpu.all(c => c >= '0' && c <= '9') &&
      memory.all(c => c >= '0' && c <= '9') else {
      return None
    }
    let cpu_count = @string.parse_int(cpu)
    let memory_total_mib = @string.parse_int64(memory)
    guard cpu_count > 0 && memory_total_mib > 0L else { return None }
    Some({ cpu_count, memory_total_mib, })
  } catch {
    _ => None
  }
}
