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
  let (memory_total_mib, _) = parse_linux_memory_mib(meminfo)
  { cpu_count: processors.length(), memory_total_mib, }
}

///|
/// Read `MemTotal` and `MemAvailable` from /proc/meminfo in one pass, as MiB.
///
/// `MemAvailable` is optional on purpose. Kernels before 3.14 do not report it,
/// and deriving an availability from `MemFree` would understate what the kernel
/// can actually hand out, because most of the page cache is reclaimable.
/// Unknown has to stay unknown: callers are expected to omit the metric rather
/// than publish a made-up number.
pub fn parse_linux_memory_mib(meminfo : String) -> (Int64, Int64?) raise {
  guard meminfo.length() <= 65536 else {
    raise TelemetryCollectorError::MalformedSample("meminfo size")
  }
  let mut total : Int64? = None
  let mut available : Int64? = None
  for line in meminfo.split("\n") {
    if line.find(":") is Some(separator) {
      let name = line[:separator].trim()
      if name == "MemTotal" || name == "MemAvailable" {
        let fields = line[separator + 1:]
          .trim()
          .split(" ")
          .filter(field => field != "")
          .to_array()
        guard fields.length() == 2 &&
          fields[1] == "kB" &&
          fields[0].all(c => c >= '0' && c <= '9') else {
          raise TelemetryCollectorError::MalformedSample(name + " units")
        }
        let kib = @string.parse_int64(fields[0])
        guard kib >= 1024L else {
          raise TelemetryCollectorError::MalformedSample(name + " value")
        }
        if name == "MemTotal" {
          guard total is None else {
            raise TelemetryCollectorError::MalformedSample("duplicate MemTotal")
          }
          total = Some(kib / 1024L)
        } else {
          guard available is None else {
            raise TelemetryCollectorError::MalformedSample(
              "duplicate MemAvailable",
            )
          }
          available = Some(kib / 1024L)
        }
      }
    }
  }
  guard total is Some(memory_total_mib) else {
    raise TelemetryCollectorError::MalformedSample("missing MemTotal")
  }
  if available is Some(memory_available_mib) {
    guard memory_available_mib <= memory_total_mib else {
      raise TelemetryCollectorError::MalformedSample("MemAvailable over MemTotal")
    }
  }
  (memory_total_mib, available)
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
/// Missing measurement does not suppress the control heartbeat. It does
/// remove all reserved capacity claims, including stale static labels, so
/// paid-machine admission continues to fail closed.
pub fn inventory_without_host_resources(
  base : @contracts.NodeInventory,
) -> @contracts.NodeInventory {
  let labels = base.labels.copy()
  labels.remove("lunanexa.io/host-cpu-count")
  labels.remove("lunanexa.io/host-memory-mib")
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

///|
/// Volatile host load, sampled fresh on every reconcile.
///
/// Deliberately separate from `HostResources`: that type is the *capacity claim*
/// which goes into signed inventory labels, and neither memory availability nor
/// CPU load is a capacity claim. Keeping them apart is what stops a static
/// descriptor from being republished as a measurement — the failure this
/// codebase shipped with.
pub(all) struct HostUtilization {
  memory_total_mib : Int64
  /// `None` when the kernel does not expose `MemAvailable`. Callers must omit
  /// the metric rather than substitute a number.
  memory_available_mib : Int64?
  cpu_utilization_per_mille : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Aggregate CPU time counters from the first `cpu` line of /proc/stat, as
/// `(total, idle)` in kernel jiffies.
///
/// `idle` includes `iowait`. The `guest` and `guest_nice` columns are excluded
/// from `total` because the kernel already counts them inside `user` and `nice`,
/// and double counting them would understate the busy share.
pub fn parse_linux_cpu_times(stat : String) -> (Int64, Int64) raise {
  guard stat.length() <= 65536 else {
    raise TelemetryCollectorError::MalformedSample("stat size")
  }
  // cpu + user nice system idle iowait irq softirq steal
  let required_columns = 9
  for line in stat.split("\n") {
    let fields = line
      .trim()
      .split(" ")
      .filter(field => field != "")
      .to_array()
    if fields.length() >= required_columns && fields[0] == "cpu" {
      let mut total = 0L
      for index = 1; index <= 8; index = index + 1 {
        guard fields[index].all(c => c >= '0' && c <= '9') else {
          raise TelemetryCollectorError::MalformedSample("cpu jiffies")
        }
        total = total + @string.parse_int64(fields[index])
      }
      let idle = @string.parse_int64(fields[4]) + @string.parse_int64(fields[5])
      return (total, idle)
    }
  }
  raise TelemetryCollectorError::MalformedSample("missing cpu line")
}

///|
/// Busy share between two /proc/stat samples, as per-mille (0-1000).
///
/// Fails closed rather than inventing a percentage: both samples have to be well
/// formed and the second has to be strictly later, so a missing or rewound
/// counter can never be rendered as "0% busy".
pub fn parse_linux_cpu_utilization_per_mille(
  first : (Int64, Int64),
  second : (Int64, Int64),
) -> Int raise {
  let total_delta = second.0 - first.0
  let idle_delta = second.1 - first.1
  guard total_delta > 0L && idle_delta >= 0L && idle_delta <= total_delta else {
    raise TelemetryCollectorError::MalformedSample(
      "cpu counters did not advance",
    )
  }
  let busy_delta = total_delta - idle_delta
  ((busy_delta * 1000L) / total_delta).to_int().clamp(min=0, max=1000)
}

///|
/// Sample the host's current memory availability and CPU busy share.
///
/// CPU load is a rate, so it needs two counter reads; one short window is used
/// rather than carrying state between reconciles, which keeps the collector
/// stateless and the metric a true sample of the interval. 250 ms is short
/// enough not to matter to a reconcile loop measured in seconds, and long enough
/// that scheduler noise does not dominate the estimate.
pub async fn collect_linux_host_utilization() -> HostUtilization {
  let (memory_total_mib, memory_available_mib) = parse_linux_memory_mib(
    @fs.read_file("/proc/meminfo").text(),
  )
  let first = parse_linux_cpu_times(@fs.read_file("/proc/stat").text())
  @async.sleep(250)
  let second = parse_linux_cpu_times(@fs.read_file("/proc/stat").text())
  {
    memory_total_mib,
    memory_available_mib,
    cpu_utilization_per_mille: parse_linux_cpu_utilization_per_mille(
      first,
      second,
    ),
  }
}
