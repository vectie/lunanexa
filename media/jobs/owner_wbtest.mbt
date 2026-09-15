///|
test "legacy commercial owner retains exact idempotency JSON" {
  let encoded = "{\"tenant_ref\":\"t\",\"subject_ref\":\"s\",\"organization_id\":\"o\",\"project_id\":\"p\",\"order_id\":\"r\"}"
  let owner : Owner = @json.from_json(@json.parse(encoded))
  assert_eq(owner.authority, DedicatedOrder("r"))
  assert_eq(owner.to_json().stringify(), encoded)
  let private_owner = { ..owner, authority: PrivateWorkspace("r") }
  assert_false(private_owner.to_json().stringify().contains("order_id"))
  let decoded : Owner = @json.from_json(private_owner.to_json())
  assert_true(decoded == private_owner)
  assert_false(owner == private_owner)
  assert_false(owner.authority.slot() == private_owner.authority.slot())
}

///|
async test "private ownership survives recovery without colliding with commercial order ids" {
  let commercial : Owner = {
    tenant_ref: "t",
    subject_ref: "s",
    organization_id: "o",
    project_id: "p",
    authority: DedicatedOrder("same-id"),
  }
  let private_owner = { ..commercial, authority: PrivateWorkspace("same-id") }
  let store = JobStore::restore({ schema_version, jobs: [] }, _ => ())
  let (paid, _) = store.reserve(
    commercial,
    "paid",
    digest("request"),
    "video",
    "deployment",
    1000L,
    2000L,
    5000L,
    maximum_active=2,
  )
  let (private_job, _) = store.reserve(
    private_owner,
    "private",
    digest("request"),
    "video",
    "deployment",
    1000L,
    2000L,
    5000L,
    maximum_active=2,
  )
  assert_false(paid.job_id == private_job.job_id)
  ignore(store.begin_submission(private_job.job_id, private_owner, 1001L))
  let decoded : Snapshot = @json.from_json(store.snapshot().to_json())
  let restored = JobStore::restore(decoded, _ => ())
  assert_eq(
    restored.get(private_job.job_id, private_owner).state,
    SubmissionUnknown,
  )
  try restored.get(private_job.job_id, commercial) catch {
    JobError::NotFound => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("commercial owner read a private job")
  }
}

///|
test "media ownership rejects ambiguous and absent entitlement" {
  let invalid : Array[Json] = [
    {
      "tenant_ref": "t",
      "subject_ref": "s",
      "organization_id": "o",
      "project_id": "p",
    },
    {
      "tenant_ref": "t",
      "subject_ref": "s",
      "organization_id": "o",
      "project_id": "p",
      "order_id": "r",
      "workspace_lease_id": "w",
    },
  ]
  for value in invalid {
    try {
      let _ : Owner = @json.from_json(value)
    } catch {
      _ => ()
    } noraise {
      _ => fail("invalid media authority accepted")
    }
  }
}
