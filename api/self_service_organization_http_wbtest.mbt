///|
priv struct TestSelfServiceOrganizationView {
  organization : TestSelfServiceOrganizationSummary
  membership : @portal.EnterpriseMembership
  default_project_id : String?
  verification : TestSelfServiceOrganizationVerificationView?
} derive(FromJson)

///|
priv struct TestSelfServiceOrganizationSummary {
  organization_id : String
  display_name : String
  state : @commercial.OrganizationState
  verification_ref : String?
  legal_profile : @commercial.OrganizationLegalProfile?
} derive(FromJson)

///|
priv struct TestSelfServiceOrganizationVerificationView {
  required : Bool
  record : @commercial_integrations.ExternalRecordView?
  blocker_code : String?
} derive(FromJson)

///|
priv struct TestSelfServiceOrganizationsView {
  version : String
  organizations : Array[TestSelfServiceOrganizationView]
} derive(FromJson)

///|
priv struct TestSelfServiceInvitationAcceptanceView {
  invitation : @account.AccountInvitationView
  membership : @portal.EnterpriseMembership
} derive(FromJson)

///|
priv struct TestSelfServiceInvitationAcceptanceIntent {
  invitation_secret : String
} derive(ToJson)

///|
async test "self-service organizations are session-bound idempotent and multi-organization safe" {
  let directory = @fs.tmpdir(prefix="lunanexa-self-organization-")
  let now = @async.now()
  let accounts = @account.AccountStore::open(
    "\{directory}/accounts.json",
    "browser-session-self-organization-secret-more-than-32-bytes",
  )
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-self-organization",
      subject_ref: "subject-self-organization",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-subject-self-organization",
      ),
      display_name: "Organization Creator",
      email: "creator@example.invalid",
      identity_receipt: "identity-proof:self-organization",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now - 1L,
      updated_unix_ms: now - 1L,
    }),
  )
  let session = accounts.issue_session(
    "https://identity.example/realms/lunanexa", "provider-subject-self-organization",
    "self-organization-session-assertion", 60000L, now,
  )
  let portal = @portal_store.FilePortalStore::open("\{directory}/portal.json")
  let durable = @store.FileStore::open("\{directory}/control.json")
  durable.fence_controller(1L)
  let runtime = @runtimes.OpenAiTextRuntime::new(
    "http://127.0.0.1:1/v1/responses",
    "runtime-secret",
    "runtime-v1",
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    allow_http_loopback=true,
  )
  let service = ApiService::new(
      durable, runtime, "operator-token", "inference-token", "node-token", "0.1.0",
    )
    .with_account_store(
      accounts, "identity-assertion-self-organization-secret-more-than-32-bytes",
    )
    .with_portal_store(portal)
  let body =
    #|{"idempotency_key":"create-company-a","display_name":"Luna Research","legal_profile":{"subject_kind":"Company","legal_name":"Luna Research Limited","country_code":"cn","registration_number":"91310000LUNA000001","registered_address":"Shanghai","billing_contact":{"display_name":"Billing Team","email":"BILLING@EXAMPLE.INVALID","phone":"+86-21-5555-0100"}}}
  let unauthenticated = service.handle(
    Post,
    "/v1/portal/self/organizations",
    Map([]),
    body,
  )
  assert_eq(unauthenticated.status, 401)
  let headers = { "Authorization": "Bearer \{session.secret}" }
  let created = service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    body,
  )
  assert_eq(created.status, 201)
  let first : TestSelfServiceOrganizationView = @json.from_json(
    @json.parse(created.body),
  )
  assert_eq(first.organization.state, PendingVerification)
  assert_eq(first.organization.display_name, "Luna Research")
  assert_eq(first.organization.verification_ref, None)
  assert_true(first.verification.unwrap().required)
  assert_eq(first.verification.unwrap().record, None)
  assert_eq(
    first.verification.unwrap().blocker_code,
    Some("CommercialProviderUnavailable"),
  )
  assert_eq(first.organization.legal_profile.unwrap().country_code, "CN")
  assert_eq(
    first.organization.legal_profile.unwrap().billing_contact.email,
    "billing@example.invalid",
  )
  assert_eq(first.membership.subject_ref, "subject-self-organization")
  assert_true(first.membership.roles.contains(OrganizationAdministrator))
  assert_true(first.membership.roles.contains(LeaseRequester))
  assert_true(first.default_project_id is Some(_))
  let commercial = service.commercial_store.snapshot(
    first.organization.organization_id,
  )
  assert_eq(commercial.cost_centers.length(), 1)
  assert_eq(commercial.projects.length(), 1)
  assert_true(
    commercial.role_grants.any(grant => {
      grant.user_id == "subject-self-organization" &&
      grant.role == OrganizationOwner
    }),
  )
  let replay = service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    body,
  )
  assert_eq(replay.status, 200)
  assert_eq(replay.body, created.body)
  let changed = service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    body.replace(old="Luna Research Limited", new="Different Legal Name"),
  )
  assert_eq(changed.status, 409)
  let forbidden = service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    body.replace(
      old="\"display_name\":\"Luna Research\"",
      new="\"organization_id\":\"forged\",\"display_name\":\"Luna Research\"",
    ),
  )
  assert_eq(forbidden.status, 400)
  let second_body = body
    .replace(old="create-company-a", new="create-company-b")
    .replace(old="Luna Research", new="Luna Systems")
    .replace(old="91310000LUNA000001", new="91310000LUNA000002")
  let second_reply = service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    second_body,
  )
  assert_eq(second_reply.status, 201)
  let second : TestSelfServiceOrganizationView = @json.from_json(
    @json.parse(second_reply.body),
  )
  assert_true(
    second.organization.organization_id != first.organization.organization_id,
  )
  let listed = service.handle(Get, "/v1/portal/self/organizations", headers, "")
  let list : TestSelfServiceOrganizationsView = @json.from_json(
    @json.parse(listed.body),
  )
  assert_eq(list.version, @portal.contract_version)
  assert_eq(list.organizations.length(), 2)
  let ambiguous = service.handle(Get, "/v1/portal/self", headers, "")
  assert_eq(ambiguous.status, 409)
  assert_true(ambiguous.body.contains("OrganizationSelectionRequired"))
  let selected_headers = {
    "Authorization": "Bearer \{session.secret}",
    "X-LunaNexa-Organization": first.organization.organization_id,
  }
  let selected = service.handle(Get, "/v1/portal/self", selected_headers, "")
  assert_eq(selected.status, 200)
  assert_true(selected.body.contains(first.organization.organization_id))
  assert_false(selected.body.contains(second.organization.organization_id))
  assert_eq(service.trusted_operational_tenant_hash(headers, false), None)
  assert_eq(
    service.trusted_operational_tenant_hash(selected_headers, false),
    Some("sha256:\{digest_hex(first.membership.tenant_ref)}"),
  )
  assert_true(service.credential_subject_context(headers, false) is None)
  assert_true(
    service.credential_subject_context(selected_headers, false)
    is Some(("subject-self-organization", _)),
  )
  assert_eq(
    service.notification_subject_context(selected_headers, false),
    Some(
      (
        first.membership.tenant_ref,
        first.organization.organization_id,
        "subject-self-organization",
      ),
    ),
  )
  ignore(
    service.commercial_store.ingest_usage({
      event_id: "usage-self-organization-private",
      organization_id: first.organization.organization_id,
      project_id: first.default_project_id.unwrap(),
      actor_ref: "operator:private-actor",
      workload_id: "workload-private",
      node_id: "physical-node-private",
      lease_epoch: 1L,
      meter: "gpu_seconds",
      quantity: 5L,
      unit: "second",
      started_unix_ms: now,
      ended_unix_ms: now + 1000L,
      observed_unix_ms: now + 1000L,
    }),
  )
  let owner_commercial = service.handle(
    Get,
    "/v1/portal/self/commercial",
    selected_headers,
    "",
  )
  assert_eq(owner_commercial.status, 200)
  assert_true(owner_commercial.body.contains("\"usage_observations\":[]"))
  assert_false(owner_commercial.body.contains("physical-node-private"))
  assert_false(owner_commercial.body.contains("operator:private-actor"))
  ignore(
    portal.put_membership({
      membership_id: "membership-billing-viewer",
      tenant_ref: first.membership.tenant_ref,
      organization_id: first.organization.organization_id,
      subject_ref: "subject-billing-viewer",
      roles: [BillingViewer],
      active: true,
      created_unix_ms: now,
    }),
  )
  let billing_commercial = service.handle(
    Get,
    "/v1/portal/self/commercial",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-billing-viewer",
      "X-LunaNexa-Organization": first.organization.organization_id,
    },
    "",
  )
  assert_eq(billing_commercial.status, 200)
  assert_true(billing_commercial.body.contains("\"role_grants\":[]"))
  assert_false(billing_commercial.body.contains("physical-node-private"))
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-billing-viewer",
      subject_ref: "subject-billing-viewer",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-subject-billing-viewer",
      ),
      display_name: "Billing Viewer",
      email: "billing-viewer@example.invalid",
      identity_receipt: "identity-proof:billing-viewer",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let billing_session = accounts.issue_session(
    "https://identity.example/realms/lunanexa", "provider-subject-billing-viewer",
    "billing-viewer-session-assertion", 60000L, now,
  )
  let billing_organizations = service.handle(
    Get,
    "/v1/portal/self/organizations",
    { "Authorization": "Bearer \{billing_session.secret}" },
    "",
  )
  assert_eq(billing_organizations.status, 200)
  assert_true(billing_organizations.body.contains("Luna Research Limited"))
  assert_true(billing_organizations.body.contains("91310000LUNA000001"))
  assert_false(billing_organizations.body.contains("\"verification\":"))
  assert_false(billing_organizations.body.contains("\"verification_ref\":"))
  ignore(
    portal.put_membership({
      membership_id: "membership-developer-only",
      tenant_ref: first.membership.tenant_ref,
      organization_id: first.organization.organization_id,
      subject_ref: "subject-developer-only",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  let developer_commercial = service.handle(
    Get,
    "/v1/portal/self/commercial",
    {
      "Authorization": "Bearer inference-token",
      "X-LunaNexa-Subject": "subject-developer-only",
      "X-LunaNexa-Organization": first.organization.organization_id,
    },
    "",
  )
  assert_eq(developer_commercial.status, 403)
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-developer-only",
      subject_ref: "subject-developer-only",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-subject-developer-only",
      ),
      display_name: "Developer Only",
      email: "developer-only@example.invalid",
      identity_receipt: "identity-proof:developer-only",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let developer_session = accounts.issue_session(
    "https://identity.example/realms/lunanexa", "provider-subject-developer-only",
    "developer-only-session-assertion", 60000L, now,
  )
  let developer_organizations = service.handle(
    Get,
    "/v1/portal/self/organizations",
    { "Authorization": "Bearer \{developer_session.secret}" },
    "",
  )
  assert_eq(developer_organizations.status, 200)
  assert_true(
    developer_organizations.body.contains(first.organization.organization_id),
  )
  assert_true(developer_organizations.body.contains("Luna Research"))
  assert_false(developer_organizations.body.contains("Luna Research Limited"))
  assert_false(developer_organizations.body.contains("91310000LUNA000001"))
  assert_false(developer_organizations.body.contains("Shanghai"))
  assert_false(developer_organizations.body.contains("billing@example.invalid"))
  assert_false(developer_organizations.body.contains("\"legal_profile\":"))
  assert_false(developer_organizations.body.contains("\"verification\":"))
  assert_false(developer_organizations.body.contains("\"verification_ref\":"))
  let forged_selection = service.handle(
    Get,
    "/v1/portal/self",
    {
      "Authorization": "Bearer \{session.secret}",
      "X-LunaNexa-Organization": "organization-not-owned",
    },
    "",
  )
  assert_eq(forged_selection.status, 403)
  ignore(
    portal.put_membership({
      membership_id: "trial-membership-self-organization",
      tenant_ref: "trial-tenant-self-organization",
      organization_id: "trial-org-self-organization",
      subject_ref: "subject-self-organization",
      roles: [Developer],
      active: true,
      created_unix_ms: now,
    }),
  )
  service.commercial_store.add_organization({
    organization_id: "organization-invited",
    display_name: "Invited Organization",
    state: Active,
    verification_ref: Some("verification:invited"),
    legal_profile: None,
    created_unix_ms: now,
  })
  service.commercial_store.add_cost_center({
    cost_center_id: "cost-center-invited",
    organization_id: "organization-invited",
    parent_cost_center_id: None,
    display_name: "Default",
    created_unix_ms: now,
  })
  service.commercial_store.add_project({
    project_id: "project-invited",
    organization_id: "organization-invited",
    cost_center_id: "cost-center-invited",
    display_name: "Default project",
    created_unix_ms: now,
  })
  let invitation = accounts.issue_invitation(
    {
      invitation_id: "invitation-existing-account",
      email: "creator@example.invalid",
      organization_id: "organization-invited",
      tenant_ref: "tenant-invited",
      project_id: "project-invited",
      created_by: "operator-one",
      expires_unix_ms: now + 60000L,
    },
    now,
  )
  let memberships_before_invitation = portal.snapshot().memberships.length()
  let accepted = service.handle(
    Post,
    "/v1/portal/self/invitations:accept",
    headers,
    ToJson::to_json(TestSelfServiceInvitationAcceptanceIntent::{
      invitation_secret: invitation.secret,
    }).stringify(),
  )
  assert_eq(accepted.status, 201)
  let joined : TestSelfServiceInvitationAcceptanceView = @json.from_json(
    @json.parse(accepted.body),
  )
  assert_eq(joined.membership.organization_id, "organization-invited")
  assert_eq(joined.invitation.invitation_id, "invitation-existing-account")
  assert_eq(joined.membership.roles, [Developer])
  assert_eq(
    portal.snapshot().memberships.length(),
    memberships_before_invitation + 1,
  )
  assert_true(
    portal.snapshot().memberships.any(membership => {
      membership.membership_id == "trial-membership-self-organization" &&
      membership.active
    }),
  )
  let accepted_replay = service.handle(
    Post,
    "/v1/portal/self/invitations:accept",
    headers,
    ToJson::to_json(TestSelfServiceInvitationAcceptanceIntent::{
      invitation_secret: invitation.secret,
    }).stringify(),
  )
  assert_eq(accepted_replay.status, 200)
  assert_eq(
    portal.snapshot().memberships.length(),
    memberships_before_invitation + 1,
  )
  ignore(
    accounts.create({
      version: @account.contract_version,
      account_id: "account-invitation-attacker",
      subject_ref: "subject-invitation-attacker",
      identity_issuer: "https://identity.example/realms/lunanexa",
      identity_subject_sha256: @account.identity_subject_digest(
        "https://identity.example/realms/lunanexa", "provider-subject-invitation-attacker",
      ),
      display_name: "Invitation Attacker",
      email: "attacker@example.invalid",
      identity_receipt: "identity-proof:invitation-attacker",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now,
      updated_unix_ms: now,
    }),
  )
  let attacker_session = accounts.issue_session(
    "https://identity.example/realms/lunanexa", "provider-subject-invitation-attacker",
    "invitation-attacker-session-assertion", 60000L, now,
  )
  let cross_account_replay = service.handle(
    Post,
    "/v1/portal/self/invitations:accept",
    { "Authorization": "Bearer \{attacker_session.secret}" },
    ToJson::to_json(TestSelfServiceInvitationAcceptanceIntent::{
      invitation_secret: invitation.secret,
    }).stringify(),
  )
  assert_eq(cross_account_replay.status, 401)
  let provider_secret = "self-organization-provider-callback-secret-more-than-32-bytes"
  let provider_service = service
    .with_provider_callback_secrets({
      "identity-provider|sandbox": provider_secret,
    })
    .with_commercial_provider_adapter(
      "self-organization-provider-adapter-token-more-than-32-bytes", "identity-provider",
      "sandbox", "https://identity-provider.example",
    )
  let queued_reply = provider_service.handle(
    Post,
    "/v1/portal/self/organizations",
    headers,
    body,
  )
  assert_eq(queued_reply.status, 200)
  let queued : TestSelfServiceOrganizationView = @json.from_json(
    @json.parse(queued_reply.body),
  )
  assert_true(queued.verification.unwrap().required)
  assert_eq(queued.verification.unwrap().blocker_code, None)
  assert_true(
    queued.verification.unwrap().record is Some(record) &&
    record.state == Pending,
  )
  let record_id = self_service_verification_record_id(
    first.organization.organization_id,
  )
  let internal_record = provider_service.commercial_integrations
    .record_by_id(record_id)
    .unwrap()
  // Reconstructing both stores from their durable snapshots models a
  // controller crash between queueing and provider callback delivery.
  let recovered = {
    ..provider_service,
    commercial_store: @commercial.CommercialStore::from_durable_snapshot(
      provider_service.commercial_store.durable_snapshot(),
    ),
    commercial_integrations: @commercial_integrations.IntegrationStore::from_durable_snapshot(
      provider_service.commercial_integrations.durable_snapshot(),
    ),
  }
  assert_true(
    recovered.commercial_integrations.record_by_id(record_id) is Some(_),
  )
  let event_now = @async.now()
  let callback : @commercial_integrations.ExternalCallback = {
    callback_id: "identity-verified-self-organization",
    record_id,
    organization_id: first.organization.organization_id,
    provider: internal_record.provider,
    environment: internal_record.environment,
    external_ref: internal_record.external_ref,
    expected_previous_state: Pending,
    next_state: Verified,
    amount_minor: None,
    currency: None,
    document_hash: None,
    provider_event_unix_ms: event_now,
    received_unix_ms: event_now,
    signature_verified: false,
  }
  let callback_body = callback.to_json().stringify()
  let callback_signature = provider_callback_signature(
    callback.provider,
    callback.environment,
    callback.callback_id,
    event_now,
    callback_body,
    provider_secret,
  )
  let verified = recovered.handle(
    Post,
    "/v1/provider-callbacks/commercial",
    {
      "X-LunaNexa-Provider": callback.provider,
      "X-LunaNexa-Environment": callback.environment,
      "X-LunaNexa-Event-Id": callback.callback_id,
      "X-LunaNexa-Event-Timestamp": event_now.to_string(),
      "X-LunaNexa-Signature": callback_signature,
    },
    callback_body,
  )
  assert_eq(verified.status, 200)
  assert_eq(
    recovered.commercial_store
    .organization(first.organization.organization_id)
    .unwrap().state,
    Active,
  )
  let after_verification : TestSelfServiceOrganizationsView = @json.from_json(
    @json.parse(
      recovered.handle(Get, "/v1/portal/self/organizations", headers, "").body,
    ),
  )
  let activated = after_verification.organizations
    .iter()
    .find_first(value => {
      value.organization.organization_id == first.organization.organization_id
    })
    .unwrap()
  assert_false(activated.verification.unwrap().required)
  assert_true(
    activated.verification.unwrap().record is Some(record) &&
    record.state == Verified,
  )
  @fs.rmdir(directory, recursive=true)
}
