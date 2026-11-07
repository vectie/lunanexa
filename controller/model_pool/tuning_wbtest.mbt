///|
test "tuning changes explicit execution options only and requires observed rollout" {
  let tuning : Tuning = {
    prefix_caching: Some(true),
    cache_aware_routing: true,
    chunked_prefill: Some(true),
    max_num_batched_tokens: 2048,
  }
  let args = runtime_args(
    fixture_selection(),
    1,
    tuning~,
    profile=fixture_runtime_profile(),
  )
  assert_true(args.contains("--enable-prefix-caching"))
  assert_true(args.contains("--enable-chunked-prefill"))
  assert_true(args.contains("--max-num-batched-tokens"))
  assert_false(
    args.any(s => {
      s.contains("max-num-seqs") ||
      s.contains("kv-cache-dtype") ||
      s.contains("disable-by-batch")
    }),
  )
  assert_false(
    configuration_observation(
      rollout_fixture(1),
      fixture_selection(),
      1,
      "pinned",
      tuning~,
    ).ready,
  )
  let old : Journal = @json.from_json({
    "replicas": [],
    "generation": Json(0L),
    "switched": [],
  })
  assert_true(old.tuning is None)
  let restored : Tuning = @json.from_json(Json(tuning))
  assert_true(restored == tuning)
}
