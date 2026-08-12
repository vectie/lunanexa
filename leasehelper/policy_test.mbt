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

///|
test "helper action and runtime object mutation fuzz is deny by default" {
  for
    action in [
      "", "Provision", "provision ", "revoke\n", "sanitize/host", "quarantine:all",
      "delete", "shell",
    ] {
    assert_false(
      @leasehelper.valid_helper_request(
        action, "lease-1", "tenant_1", 1L, 2000L, 1000L,
      ),
    )
  }
  for generation in [-9223372036854775807L, -1L, 0L] {
    assert_false(
      @leasehelper.valid_helper_request(
        "sanitize", "lease-1", "tenant_1", generation, 0L, 1000L,
      ),
    )
  }
  for length in 0..<=140 {
    assert_eq(
      @leasehelper.valid_runtime_object_id("a".repeat(length)),
      length > 0 && length <= 128,
    )
  }
  for position in 0..<=64 {
    for mutation in ["/", "\\", " ", "\n", "\r", ":", "%", "服务"] {
      let value = "a".repeat(position) + mutation + "b".repeat(64 - position)
      assert_false(@leasehelper.valid_runtime_object_id(value))
    }
  }
  for
    root in [
      "/", "relative/root", "/var/lib/lunanexa/", "/var//lib/lunanexa", "/var/lib/lunanexa/..",
      "/var/lib/lunanexa/../root", "/var/lib/lunanexa\n/root", "/var/lib/lunanexa root",
    ] {
    assert_false(@leasehelper.valid_host_root(root))
  }
}
