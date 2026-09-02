///|
/// The administrator settings mounted by the production manifests must stay
/// parseable by the control-plane binary. This catches schema drift between
/// the reviewed deployment artifact and the MoonBit settings contract.
async test "deployment administrator settings match the control-plane contract" {
  let payload = @fs.read_file("deploy/admin-settings.example.json").text()
  let parsed = @settings.parse_global_admin_settings(payload) catch {
    InvalidGlobalSetting(section) =>
      fail("invalid deployment settings: \{section}")
    error => fail("unexpected deployment settings error: \{Repr(error)}")
  }
  assert_eq(parsed.schema_version, "lunanexa.settings.v1")
  assert_eq(parsed.generation, 1L)
}
