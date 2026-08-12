///|
test "cleanup evidence releases only a completely clean node" {
  let clean : @leasehelper.CleanupEvidence = {
    account_absent: true,
    processes_absent: true,
    containers_absent: true,
    volumes_absent: true,
    home_absent: true,
    lease_state_absent: true,
    access_material_absent: true,
  }
  assert_true(clean.verified())
  assert_false({ ..clean, containers_absent: false }.verified())
  assert_false({ ..clean, lease_state_absent: false }.verified())
}

///|
test "host cleanup paths cannot escape their dedicated roots" {
  assert_eq(
    @leasehelper.scoped_host_path("/var/lib/lunanexa/lease-homes", "tenant_1"),
    Some("/var/lib/lunanexa/lease-homes/tenant_1"),
  )
  assert_eq(@leasehelper.scoped_host_path("/", "tenant_1"), None)
  assert_eq(
    @leasehelper.scoped_host_path("/var/lib/lunanexa/lease-homes", "../../root"),
    None,
  )
}

///|
test "helper requests reject unsafe users stale provisioning and object IDs" {
  assert_true(
    @leasehelper.valid_helper_request(
      "sanitize", "lease-1", "tenant_1", 3L, 0L, 1000L,
    ),
  )
  assert_false(
    @leasehelper.valid_helper_request(
      "sanitize", "lease-1", "root", 3L, 0L, 1000L,
    ),
  )
  assert_false(
    @leasehelper.valid_helper_request(
      "provision", "lease-1", "tenant_1", 3L, 999L, 1000L,
    ),
  )
  assert_true(@leasehelper.valid_runtime_object_id("volume.lease-1"))
  assert_false(@leasehelper.valid_runtime_object_id("../../host"))
}

///|
test "cleanup identifier fuzz never escapes the dedicated root" {
  let root = "/var/lib/lunanexa/exclusive-leases"
  for length in 0..<=180 {
    let identifier = "a".repeat(length)
    let path = @leasehelper.scoped_host_path(root, identifier)
    assert_eq(path is Some(_), length > 0 && length <= 128)
    if path is Some(value) {
      assert_true(value.has_prefix("\{root}/"))
      assert_false(value.contains(".."))
    }
  }
  for
    hostile in [
      "../lease", "lease/child", "lease child", "lease\nchild", "..", ".", "租约",
    ] {
    assert_eq(@leasehelper.scoped_host_path(root, hostile), None)
  }
}
