///|
async test "credential API issue and redeem is one-time tenant-safe and secret-free" {
  let directory = @fs.tmpdir(prefix="lunanexa-credential-api-")
  let now = @async.now()
  let (service, leases, _, _) = customer_machine_test_service(directory, now)
  let lease = leases.lease("lease-customer-a").unwrap()
  let issue : @credential.CredentialHandoffIssueIntent = {
    request_id: "credential-api-request-a",
    lease_id: lease.intent.lease_id,
    expected_generation: lease.generation,
    host_alias: "customer-a.cluster.example",
    ssh_port: 2222,
    host_key_fingerprint: "SHA256:abcdefghijklmnopqrstuvwxyzABCDEFG1234567890_-",
    issuer_redirect_url: "https://issuer.example/redeem/credential-api-request-a",
  }
  let unverified_store = @credential_store.CredentialHandoffStore::open(
    "\{directory}/unverified-handoffs.json",
    "unverified-credential-store-secret-more-than-32-bytes",
  )
  let unverified = service.with_credential_handoff_store(unverified_store)
  let blocked = unverified.handle(
    Post,
    "/v1/machine-credentials/lease-customer-a:issue",
    { "Authorization": "Bearer operator-token" },
    issue.to_json().stringify(),
  )
  assert_eq(blocked.status, 503)
  assert_true(blocked.body.contains("CredentialIssuerNotReady"))
  let issued = service.handle(
    Post,
    "/v1/machine-credentials/lease-customer-a:issue",
    { "Authorization": "Bearer operator-token" },
    issue.to_json().stringify(),
  )
  assert_eq(issued.status, 201)
  assert_false(issued.body.contains("customer-node-a"))
  assert_false(issued.body.contains("internal-customer-a"))
  assert_false(issued.body.contains("raw_secret"))
  let mismatched_issuer = service.handle(
    Post,
    "/v1/machine-credentials/lease-customer-a:issue",
    { "Authorization": "Bearer operator-token" },
    {
      ..issue,
      request_id: "credential-api-other-origin",
      issuer_redirect_url: "https://attacker.example/redeem/credential-api-request-a",
    }
    .to_json()
    .stringify(),
  )
  assert_eq(mismatched_issuer.status, 400)
  assert_true(mismatched_issuer.body.contains("CredentialIssuerMismatch"))
  let cross_tenant = service.handle(
    Get,
    "/v1/machine-access/self/lease-customer-a/credential",
    customer_headers("subject-b"),
    "",
  )
  assert_eq(cross_tenant.status, 404)
  let view_reply = service.handle(
    Get,
    "/v1/machine-access/self/lease-customer-a/credential",
    customer_headers("subject-a"),
    "",
  )
  assert_eq(view_reply.status, 200)
  let view : @credential.CustomerCredentialHandoffView = @json.from_json(
    @json.parse(view_reply.body),
  )
  assert_eq(view.host_alias, "customer-a.cluster.example")
  assert_false(view_reply.body.contains("customer-node-a"))
  let redeemed = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a/credential:redeem",
    customer_headers("subject-a"),
    ({ "expected_generation": lease.generation } : Json).stringify(),
  )
  assert_eq(redeemed.status, 200)
  let result : @credential.CredentialHandoffRedemption = @json.from_json(
    @json.parse(redeemed.body),
  )
  assert_true(result.one_time)
  assert_false(result.raw_secret_included)
  assert_false(redeemed.body.contains("customer-node-a"))
  assert_false(redeemed.body.contains("internal-customer-a"))
  let replay = service.handle(
    Post,
    "/v1/machine-access/self/lease-customer-a/credential:redeem",
    customer_headers("subject-a"),
    ({ "expected_generation": lease.generation } : Json).stringify(),
  )
  assert_eq(replay.status, 200)
  assert_eq(replay.body, redeemed.body)
  assert_true(result.redemption_receipt.has_prefix("lnxr_"))
  let recovered_view_reply = service.handle(
    Get,
    "/v1/machine-access/self/lease-customer-a/credential",
    customer_headers("subject-a"),
    "",
  )
  let recovered_view : @credential.CustomerCredentialHandoffView = @json.from_json(
    @json.parse(recovered_view_reply.body),
  )
  assert_false(recovered_view.can_redeem)
  assert_true(recovered_view.can_recover)
  let recovered_machines : Array[@nodelease.CustomerExclusiveMachineView] = @json.from_json(
    @json.parse(
      service.handle(
        Get,
        "/v1/machine-access/self",
        customer_headers("subject-a"),
        "",
      ).body,
    ),
  )
  assert_eq(recovered_machines[0].credential_handoff.state, Recoverable)
  @fs.rmdir(directory, recursive=true)
}
