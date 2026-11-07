///|
test "MTP toggles only decoding arguments and never introduces concurrency caps" {
  let selection = fixture_selection()
  let off = runtime_args(selection, 0, profile=fixture_runtime_profile())
  for tokens in 1..<=5 {
    let on = runtime_args(selection, tokens, profile=fixture_runtime_profile())
    assert_eq(on.length(), off.length() + 2)
    assert_eq(on[:off.length()].to_owned(), off)
    assert_eq(observed_speculative_tokens(on), tokens)
    let config = @json.parse(on.last().unwrap())
    assert_eq(config, {
      "method": "fixture_mtp",
      "num_speculative_tokens": tokens,
      "moe_backend": "fixture_backend",
    })
    assert_false(
      on.any(a => {
        a.contains("max-num-seqs") || a.contains("disable-by-batch-size")
      }),
    )
    assert_false(config.stringify().contains("synthetic"))
  }
  assert_eq(observed_speculative_tokens(off), 0)
  assert_eq(
    observed_speculative_tokens(["--speculative-config", "invalid"]),
    -1,
  )
  assert_eq(observed_speculative_tokens(["--speculative-config"]), -1)
}

///|
fn rollout_fixture(tokens : Int32) -> Json {
  {
    "metadata": { "generation": 10 },
    "spec": {
      "replicas": 1,
      "template": {
        "spec": {
          "containers": [
            {
              "name": "vllm",
              "command": ["vllm"],
              "image": "pinned",
              "args": Json(
                runtime_args(
                  fixture_selection(),
                  tokens,
                  profile=fixture_runtime_profile(),
                ),
              ),
            },
          ],
        },
      },
    },
    "status": {
      "observedGeneration": 10,
      "replicas": 1,
      "updatedReplicas": 1,
      "readyReplicas": 1,
      "availableReplicas": 1,
    },
  }
}

///|
test "old healthy replica and submitted arguments are not configuration readiness" {
  let selection = fixture_selection()
  assert_true(
    configuration_observation(
      rollout_fixture(1),
      selection,
      1,
      "pinned",
      profile=fixture_runtime_profile(),
    ).ready,
  )
  assert_false(
    configuration_observation(
      rollout_fixture(0),
      selection,
      1,
      "pinned",
      profile=fixture_runtime_profile(),
    ).ready,
  )
  assert_false(
    configuration_observation(
      rollout_fixture(1),
      selection,
      1,
      "other",
      profile=fixture_runtime_profile(),
    ).ready,
  )
  for
    status in [
      {
        "observedGeneration": 9,
        "replicas": 1,
        "updatedReplicas": 1,
        "readyReplicas": 1,
        "availableReplicas": 1,
      },
      {
        "observedGeneration": 10,
        "replicas": 2,
        "updatedReplicas": 1,
        "readyReplicas": 1,
        "availableReplicas": 1,
      },
      {
        "observedGeneration": 10,
        "replicas": 1,
        "updatedReplicas": 1,
        "readyReplicas": 0,
        "availableReplicas": 0,
      },
    ] {
    guard rollout_fixture(1) is Object(fields) else { fail("fixture") }
    fields["status"] = Json(status)
    assert_false(
      configuration_observation(
        Json(fields),
        selection,
        1,
        "pinned",
        profile=fixture_runtime_profile(),
      ).ready,
    )
  }
}
