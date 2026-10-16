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
  // Long reasoning and coding streams must survive the former two-minute cap.
  assert_eq(parsed.request_budgets.openai_default_deadline_ms, 1800000L)
  assert_eq(parsed.request_budgets.openai_max_deadline_ms, 1800000L)
  let manifest = @fs.read_file("deploy/prerequisites.yaml").text()
  let line = manifest
    .split("\n")
    .find_first(line => line.trim().has_prefix("\"request_budgets\":"))
    .unwrap()
  let raw = line
    .trim()
    .strip_prefix("\"request_budgets\":")
    .unwrap()
    .strip_suffix(",")
    .unwrap()
    .to_owned()
  let deployed : @settings.RequestBudgetSettings = @json.from_json(
    @json.parse(raw),
  )
  assert_eq(
    deployed.openai_default_deadline_ms,
    parsed.request_budgets.openai_default_deadline_ms,
  )
  assert_eq(
    deployed.openai_max_deadline_ms,
    parsed.request_budgets.openai_max_deadline_ms,
  )
}
