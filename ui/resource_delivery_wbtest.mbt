///|
test "resource chooser hides memory-pressured and unmeasured Sparks" {
  let ready = {
    ..demo_state().nodes[0],
    memory_measured: true,
    total_memory_mib: 122880,
    free_memory_mib: 100000,
    workloads: 0,
  }
  assert_true(resource_node_selectable(ready, [], true))
  assert_true(resource_node_selectable(ready, [], false))
  assert_false(
    resource_node_selectable({ ..ready, free_memory_mib: 20000, }, [], true),
  )
  assert_false(
    resource_node_selectable({ ..ready, memory_measured: false, }, [], false),
  )
  assert_false(
    resource_node_selectable({ ..ready, free_memory_mib: 60000, }, [], true),
  )
  assert_true(
    resource_node_selectable({ ..ready, free_memory_mib: 60000, }, [], false),
  )
}
