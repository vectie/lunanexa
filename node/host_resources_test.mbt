///|
test "Linux host resource inventory validates actual procfs fields" {
  let cpu = "processor\t: 0\nmodel name : test\n\nprocessor\t: 3\n"
  let resources = @node.parse_linux_host_resources(
    cpu, "MemTotal:       134217728 kB\nMemFree: 1024 kB\n",
  )
  assert_eq(resources.cpu_count, 2)
  assert_eq(resources.memory_total_mib, 131072L)
  for
    sample in [
      ("", "MemTotal: 1024 kB"),
      ("processor: 0\nprocessor: 0", "MemTotal: 1024 kB"),
      ("processor: -1", "MemTotal: 1024 kB"),
      (cpu, "MemFree: 1024 kB"),
      (cpu, "MemTotal: 1024 MB"),
      (cpu, "MemTotal: 0 kB"),
      (cpu, "MemTotal: 1024 kB\nMemTotal: 2048 kB"),
      (cpu, "MemTotal: 999999999999999999999999999 kB"),
    ] {
    let (processors, memory) = sample
    try @node.parse_linux_host_resources(processors, memory) catch {
      _ => ()
    } noraise {
      _ => fail("invalid host inventory accepted")
    }
  }
}

///|
test "measured host resources replace static labels without mutating inventory" {
  let base : @contracts.NodeInventory = {
    node_id: "test-only",
    agent_version: "test",
    os_release: "test",
    runtime_names: [],
    accelerators: [],
    labels: {
      "lunanexa.io/region": "test-region",
      "lunanexa.io/host-cpu-count": "999",
    },
    taints: [],
  }
  assert_eq(@node.inventory_host_resources(base), None)
  let measured : @node.HostResources = {
    cpu_count: 2,
    memory_total_mib: 4096L,
  }
  let updated = measured.inventory(base)
  assert_eq(@node.inventory_host_resources(updated), Some(measured))
  assert_eq(base.labels.get("lunanexa.io/host-cpu-count"), Some("999"))
  assert_eq(updated.labels.get("lunanexa.io/region"), Some("test-region"))
  updated.labels["lunanexa.io/host-memory-mib"] = "-1"
  assert_eq(@node.inventory_host_resources(updated), None)
}

///|
test "missing host measurement keeps identity but removes stale paid capacity claims" {
  let base : @contracts.NodeInventory = {
    node_id: "unmeasured-test",
    agent_version: "test",
    os_release: "test",
    runtime_names: [],
    accelerators: [],
    labels: {
      "lunanexa.io/host-cpu-count": "999",
      "lunanexa.io/host-memory-mib": "999999",
      "lunanexa.io/region": "test",
    },
    taints: [],
  }
  assert_true(@node.inventory_host_resources(base) is Some(_))
  let safe = @node.inventory_without_host_resources(base)
  assert_eq(safe.node_id, base.node_id)
  assert_eq(safe.labels.get("lunanexa.io/region"), Some("test"))
  assert_eq(@node.inventory_host_resources(safe), None)
  assert_eq(safe.labels.get("lunanexa.io/host-cpu-count"), None)
  assert_eq(safe.labels.get("lunanexa.io/host-memory-mib"), None)
  assert_eq(base.labels.get("lunanexa.io/host-cpu-count"), Some("999"))
}
