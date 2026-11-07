///|
test "automatic service name is stable across retries and explicit names are preserved" {
  let initial = { ..@ui.demo_state(), quick_deployment_id: "", }
  let prepared = quick_deployment_named(initial, "service-generated")
  assert_eq(prepared.quick_deployment_id, "service-generated")
  let retry = quick_deployment_named(prepared, "another-name")
  assert_eq(retry.quick_deployment_id, prepared.quick_deployment_id)
  assert_eq(
    quick_deployment_intent(prepared, 1L),
    quick_deployment_intent(retry, 2L),
  )
  let explicit = { ..initial, quick_deployment_id: "my-service", }
  assert_eq(
    quick_deployment_named(explicit, "generated").quick_deployment_id,
    "my-service",
  )
}

///|
test "adoption uses verified import metadata without guessing hardware requirements" {
  let source = onboarding_verified_import()
  let draft = adoption_defaults(source)
  assert_eq(draft.import_id, source.import_id)
  assert_eq(draft.model_id, source.model_id.replace(old="/", new="-"))
  assert_eq(draft.version, source.revision)
  assert_eq(draft.license_id, source.license)
  assert_eq(draft.minimum_memory_mib, "")
  assert_eq(draft.compatible_architectures, "")
  let missing = adoption_defaults({
    ..source,
    license: "not a valid id",
    revision: "",
  })
  assert_eq(missing.license_id, "")
  assert_eq(missing.version, "")
}
