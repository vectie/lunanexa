///|
pub(all) enum EnterpriseRoute {
  Overview
  SelfService
  AccountAccess
  Agreements
  LeaseRequests
  Notifications
  Costs
  Models
  DesktopIde
  MachineAccess
  OfflineCommerce
  ContractDocuments
} derive(Debug, Eq)

///|
pub(all) struct EnterpriseCostCenterRow {
  cost_center_id : String
  display_name : String
  project_count : Int
  provisional_spend : String
  budget_posture : String
} derive(Debug, Eq)

///|
/// An immutable checkout quote derived from a finalized billing period. The
/// browser never asks the user to retype authoritative money fields.
pub(all) struct PaymentCheckoutQuote {
  period_id : String
  expected_amount_minor : Int64
  currency : String
  money_scale : Int
  display_amount : String
  idempotency_key : String
  entitlement_transaction_ref_sha256 : String
  ledger_entry_count : Int
  ledger_revision_unix_ms : Int64
} derive(Debug, Eq)

///|
pub(all) struct EnterpriseDesktopClient {
  client_id : String
  display_name : String
  launch_uri : String
  handoff_lifetime_ms : Int64
  connected_handoffs : Int
  contract_ready : Bool
  workspace_ready : Bool
  models_ready : Bool
  ready : Bool
  blocker_codes : Array[String]
  approved_model_aliases : Array[String]
} derive(Debug, Eq)

///|
pub(all) enum DesktopConnectPhase {
  NotStarted
  IssuingHandoff
  ClientOpened
  ConnectFailed
} derive(Debug, Eq)

///|
pub extend DesktopConnectPhase with Debug::{to_repr}

///|
pub extend DesktopConnectPhase with Eq::{equal, not_equal}

///|
pub(all) struct ApiKeyIssueDraft {
  display_name : String
  model_list_scope : Bool
  inference_scope : Bool
  allowed_models : String
  lifetime_days : Int
  maximum_requests : Int64
} derive(Debug, Eq)

///|
pub(all) struct OneTimeApiKeySecret {
  key_id : String
  display_name : String
  secret : String
  allowed_models : Array[String]
  api_base_url : String?
  tenant_ref : String
  memory_ceiling_mib : Int?
} derive(Debug, Eq)

///|
/// Browser-portable account API scope. This deliberately mirrors the portal
/// JSON contract without importing the native access store into the JS UI.
pub(all) enum ApiKeyScope {
  ModelList
  Inference
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct ApiCredentialView {
  key_id : String
  tenant_ref : String
  subject_ref : String
  organization_id : String?
  project_id : String?
  display_name : String
  scopes : Array[ApiKeyScope]
  allowed_models : Array[String]
  issued_unix_ms : Int64
  expires_unix_ms : Int64
  maximum_requests : Int64
  consumed_requests : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct IssuedApiKeyView {
  credential : ApiCredentialView
  secret : String
  api_base_url : String?
} derive(Debug, Eq, FromJson)

///|
pub(all) enum AccountRole {
  PlatformOperator
  AuditReader
  EnterpriseUser
} derive(Debug, Eq, FromJson)

///|
pub(all) enum AccountState {
  Invited
  Active
  Suspended
  Revoked
} derive(Debug, Eq, FromJson)

///|
pub(all) struct AccountView {
  account_id : String
  subject_ref : String
  identity_issuer : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[AccountRole]
  state : AccountState
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, FromJson)

///|
pub(all) struct BrowserSessionView {
  session_id : String
  account_id : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  last_used_unix_ms : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, FromJson)

///|
pub(all) struct TrialEntitlementView {
  trial_id : String
  organization_id : String
  tenant_ref : String
  project_id : String
  allowed_models : Array[String]
  maximum_requests : Int64
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  api_key_id : String?
  revoked_unix_ms : Int64?
} derive(Debug, Eq, FromJson)

///|
pub(all) struct EnterpriseState {
  docs_base_url : String?
  route : EnterpriseRoute
  locale : @i18n.Locale
  membership : @portal.EnterpriseMembership?
  organizations : Array[SelfServiceOrganizationView]
  selected_organization_id : String?
  account : AccountView?
  trial : TrialEntitlementView?
  browser_sessions : Array[BrowserSessionView]
  api_keys : Array[ApiCredentialView]
  api_key_issue_draft : ApiKeyIssueDraft
  api_key_issue_open : Bool
  api_key_revoke_id : String?
  one_time_api_key_secret : OneTimeApiKeySecret?
  member_invite_email : String
  member_invite_secret : String?
  member_invite_loading : Bool
  agreements : Array[@portal.PortalAgreement]
  lease_requests : Array[@portal.EnterpriseLeaseRequest]
  notifications : Array[@notifications.NotificationRecord]
  notification_preferences : Array[@notifications.NotificationPreferenceView]
  machine_access : @machine_access.MachineAccessState
  offline_commerce : @offline_commerce.OfflineCommerceState
  contract_documents : @contract_documents.ContractDocumentsState
  cost_centers : Array[EnterpriseCostCenterRow]
  provisional_spend : String
  payment_checkout_quote : PaymentCheckoutQuote?
  provider_requests : Array[@commercial_integrations.ExternalRecordView]
  provider_requests_loading : Bool
  payment_checkout_loading : Bool
  model_catalog : Array[@portal.EnterpriseModelSummary]
  desktop_client : EnterpriseDesktopClient?
  desktop_clients : Array[EnterpriseDesktopClient]
  webide_order_id : String?
  desktop_connect_phase : DesktopConnectPhase
  deliveries : DeliveryPanel
  self_service : SelfServiceState
  project_id : String
  unix_username : String
  model_ids : String
  justification : String
  starts_unix_ms : Int64
  expires_unix_ms : Int64
  loading : Bool
  success_message : String?
  error_message : String?
} derive(Eq)

///|
pub(all) enum EnterpriseMessage {
  Navigate(EnterpriseRoute)
  SelfService(SelfServiceMessage)
  LocaleChanged(@i18n.Locale)
  OpenApiKeyIssue
  CancelApiKeyIssue
  ApiKeyDisplayNameChanged(String)
  ToggleApiKeyModelListScope
  ToggleApiKeyInferenceScope
  ApiKeyAllowedModelsChanged(String)
  ApiKeyLifetimeChanged(Int)
  ApiKeyMaximumRequestsChanged(Int64)
  SubmitApiKeyIssue
  MemberInviteEmailChanged(String)
  SubmitMemberInvite
  DismissMemberInviteSecret
  CopyOneTimeApiKeySecret
  CopyFirstCallExample
  CopyDetail(String)
  ExportCosts
  DismissOneTimeApiKeySecret
  BeginRevokeApiKey(String)
  CancelRevokeApiKey
  ConfirmRevokeApiKey(String)
  ProjectChanged(String)
  UsernameChanged(String)
  ModelsChanged(String)
  JustificationChanged(String)
  SignAgreement(String)
  RefreshProviderRequests
  SubmitPaymentCheckout
  SubmitLease
  LaunchDesktopClient
  SelectWebIde(String)
  SelectWebIdeOrder(String)
  Delivery(DeliveryMessage)
  MarkNotificationRead(String, Int64)
  SetNotificationEmail(@notifications.NotificationTopic, Bool)
  MachineAccess(@machine_access.MachineAccessMessage)
  OfflineCommerce(@offline_commerce.OfflineCommerceMessage)
  ContractDocuments(@contract_documents.ContractDocumentsMessage)
  ClearNotice
} derive(Eq)

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  @i18n.copy(locale, english, chinese)
}

///|
pub fn default_state(now_unix_ms : Int64) -> EnterpriseState {
  {
    docs_base_url: None,
    route: Overview,
    locale: @i18n.default_locale(),
    membership: None,
    organizations: [],
    selected_organization_id: None,
    account: None,
    trial: None,
    browser_sessions: [],
    api_keys: [],
    api_key_issue_draft: {
      display_name: "",
      model_list_scope: true,
      inference_scope: true,
      allowed_models: "",
      lifetime_days: 30,
      maximum_requests: 10000L,
    },
    api_key_issue_open: false,
    api_key_revoke_id: None,
    one_time_api_key_secret: None,
    member_invite_email: "",
    member_invite_secret: None,
    member_invite_loading: false,
    agreements: [],
    lease_requests: [],
    notifications: [],
    notification_preferences: [],
    machine_access: @machine_access.default_state(@i18n.default_locale()),
    offline_commerce: @offline_commerce.default_state(
      @i18n.default_locale(),
      CustomerCommerce,
    ),
    contract_documents: @contract_documents.default_state(
      @i18n.default_locale(),
    ),
    cost_centers: [],
    provisional_spend: "—",
    payment_checkout_quote: None,
    provider_requests: [],
    provider_requests_loading: false,
    payment_checkout_loading: false,
    model_catalog: [],
    desktop_client: None,
    desktop_clients: [],
    webide_order_id: None,
    desktop_connect_phase: NotStarted,
    deliveries: default_delivery_panel(),
    self_service: default_self_service_state(),
    project_id: "",
    unix_username: "",
    model_ids: "",
    justification: "",
    starts_unix_ms: now_unix_ms + 3600000L,
    expires_unix_ms: now_unix_ms + 90000000L,
    loading: false,
    success_message: None,
    error_message: None,
  }
}

///|
pub fn demo_state() -> EnterpriseState {
  let now = 1786320000000L
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let undertaking_manifest = @contractdoc.undertaking_manifest()
  let undertaking_draft = try! @contractdoc.new_packet(
    undertaking_manifest,
    "packet-demo-undertaking",
    "packet-demo-undertaking-key",
    "tenant-northstar",
    "org-northstar",
    "subject-alice",
    "order-demo-undertaking",
    None,
    [MasterLease],
    now,
  )
  let undertaking_packet = {
    ..undertaking_draft,
    values: [
      { field_id: "lessee.name", value: "Northstar Research", },
      { field_id: "undertaking.signed_date", value: "2026-09-16", },
      { field_id: "lease.start_date", value: "2026-09-17", },
      { field_id: "lease.end_date", value: "2026-10-17", },
      { field_id: "lease.total_rent", value: "1290.00", },
    ],
    state: ReadyForConfirmation,
  }
  let demo_packet : @contractdoc.ContractPacket = {
    packet_id: "packet-demo-youthpolicy",
    idempotency_key: "packet-demo-youthpolicy-key",
    template_id: manifest.template_id,
    template_version: manifest.template_version,
    template_sha256: manifest.sha256,
    tenant_ref: "tenant-northstar",
    organization_id: "org-northstar",
    subject_ref: "subject-alice",
    order_ref: "order-capacity-2026-08",
    preceding_packet_ref: None,
    active_forms: [
      MasterLease,
      ReservationApplication,
      AccessConfirmation,
      ViolationNotice,
      DamageAssessment,
      SettlementConfirmation,
      EarlyTerminationApplication,
    ],
    values: [],
    assignments: [],
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    artifacts: [],
    state: InformationDraft,
    execution: None,
    closure: None,
    supersession: None,
    generation_failure: None,
    revision: 1L,
    created_unix_ms: now,
    updated_unix_ms: now,
  }
  let effective_packet : @contractdoc.ContractPacket = {
    ..demo_packet,
    packet_id: "packet-demo-effective",
    idempotency_key: "packet-demo-effective-key",
    order_ref: "order-capacity-2025-08",
    preceding_packet_ref: Some("packet-demo-youthpolicy"),
    active_forms: [MasterLease],
    values: [
      { field_id: "lessee.name", value: "Northstar Research", },
      { field_id: "lease.start_date", value: "2025-09-01", },
      { field_id: "lease.end_date", value: "2026-08-31", },
    ],
    values_sha256: Some(
      "sha256:7ca7d84d5b028ed5825a0e87104737c15d6f4c71463d8c567ce17e108075eb41",
    ),
    state: Effective,
    execution: Some({
      evidence_sha256: "sha256:22aeaa2c7a7590c2f7c61c63b0ba354b86d1df1a75d8d13ab3084cf99966fc0a",
      signed_on: "2025-08-28",
      registered_by: "operator-demo",
      registered_unix_ms: now - 30000000000L,
    }),
    revision: 8L,
    created_unix_ms: now - 30000000000L,
    updated_unix_ms: now - 86400000L,
  }
  let customer_approval : @contractdoc.ContractApproval = {
    approval_id: "contract-approval-customer-demo",
    packet_id: effective_packet.packet_id,
    action: "close:EarlyTermination",
    expected_revision: effective_packet.revision,
    payload: {
      evidence_sha256: None,
      signed_on: None,
      kind: Some(EarlyTermination),
      reason: Some("operator review required"),
      amount_minor_units: Some(190000L),
      packet_values_sha256: effective_packet.values_sha256,
    },
    initiator: "operator-a",
    created_unix_ms: now - 1800000L,
    status: Pending,
    decided_by: None,
    decided_unix_ms: None,
    decision_reason: None,
  }
  let payment_obligation : @contractdoc.ContractObligation = {
    obligation_id: "contract-obligation-payment-demo",
    tenant_ref: effective_packet.tenant_ref,
    packet_id: effective_packet.packet_id,
    kind: PaymentMilestone,
    title: "September capacity payment",
    owner_ref: "subject-alice",
    due_unix_ms: now + 604800000L,
    amount_minor_units: Some(190000L),
    state: Open,
    evidence_ref: None,
    completed_by: None,
    completed_unix_ms: None,
    created_by: Some("operator-a"),
    created_unix_ms: now - 86400000L,
    updated_unix_ms: now - 86400000L,
    revision: 1L,
  }
  let state = {
    ..default_state(now),
    membership: Some({
      membership_id: "membership-northstar",
      tenant_ref: "tenant-northstar",
      organization_id: "org-northstar",
      subject_ref: "subject-alice",
      roles: [OrganizationAdministrator, LegalSigner, LeaseRequester, Developer],
      active: true,
      created_unix_ms: now - 2592000000L,
    }),
    organizations: [
      {
        organization: {
          organization_id: "org-northstar",
          display_name: "Northstar Research",
          state: Active,
          verification_ref: Some("verification-demo"),
          legal_profile: Some({
            subject_kind: Company,
            legal_name: "Northstar Research Ltd.",
            country_code: "CN",
            registration_number: Some("REG-DEMO"),
            tax_identifier: Some("TAX-DEMO"),
            registered_address: "100 Science Road, Beijing",
            billing_contact: {
              display_name: "Alice Chen",
              email: "alice@example.invalid",
              phone: None,
            },
          }),
        },
        membership: {
          membership_id: "membership-northstar",
          tenant_ref: "tenant-northstar",
          organization_id: "org-northstar",
          subject_ref: "subject-alice",
          roles: [
            OrganizationAdministrator,
            LegalSigner,
            LeaseRequester,
            BillingViewer,
            Developer,
          ],
          active: true,
          created_unix_ms: now - 2592000000L,
        },
        default_project_id: Some("project-vision-lab"),
        verification: Some({
          required: false,
          record: None,
          blocker_code: None,
        }),
      },
    ],
    selected_organization_id: Some("org-northstar"),
    account: Some({
      account_id: "account-alice",
      subject_ref: "subject-alice",
      identity_issuer: "https://identity.demo.invalid",
      display_name: "Alice Chen",
      email: "alice@example.invalid",
      identity_receipt: "identity:demo",
      roles: [EnterpriseUser],
      state: Active,
      created_unix_ms: now - 2592000000L,
      updated_unix_ms: now - 86400000L,
    }),
    browser_sessions: [
      {
        session_id: "session-demo-current",
        account_id: "account-alice",
        created_unix_ms: now - 3600000L,
        expires_unix_ms: now + 3600000L,
        last_used_unix_ms: now - 60000L,
        revoked_unix_ms: None,
      },
    ],
    api_keys: [
      {
        key_id: "key-notebook-active",
        tenant_ref: "tenant-northstar",
        subject_ref: "subject-alice",
        organization_id: Some("org-northstar"),
        project_id: Some("project-aurora"),
        display_name: "Research notebook",
        scopes: [ModelList, Inference],
        allowed_models: ["qwen3-32b"],
        issued_unix_ms: now - 86400000L,
        expires_unix_ms: now + 2505600000L,
        maximum_requests: 10000L,
        consumed_requests: 184L,
        revoked_unix_ms: None,
      },
      {
        key_id: "key-ci-revoked",
        tenant_ref: "tenant-northstar",
        subject_ref: "subject-alice",
        organization_id: Some("org-northstar"),
        project_id: Some("project-aurora"),
        display_name: "Retired CI client",
        scopes: [Inference],
        allowed_models: ["qwen3-32b", "bge-m3"],
        issued_unix_ms: now - 2592000000L,
        expires_unix_ms: now + 86400000L,
        maximum_requests: 1000L,
        consumed_requests: 612L,
        revoked_unix_ms: Some(now - 3600000L),
      },
    ],
    agreements: [
      {
        agreement_id: "agreement-framework-2026",
        tenant_ref: "tenant-northstar",
        organization_id: "org-northstar",
        template_ref: "framework-v3",
        title: "Enterprise capacity framework",
        summary: "Terms for time-bounded exclusive GPU capacity, acceptable use, support and sanitization.",
        rendered_document_hash: "sha256:4f94d8f0a2",
        state: ReviewRequired,
        generation: 1L,
        signer_subject_ref: None,
        signature_request_receipt: None,
        executed_artifact_hash: None,
        created_unix_ms: now - 86400000L,
        updated_unix_ms: now - 86400000L,
      },
      {
        agreement_id: "agreement-dpa-2026",
        tenant_ref: "tenant-northstar",
        organization_id: "org-northstar",
        template_ref: "dpa-v2",
        title: "Data processing agreement",
        summary: "Processing scope, retention, subprocessors and incident response evidence.",
        rendered_document_hash: "sha256:95a01f36bd",
        state: Executed,
        generation: 3L,
        signer_subject_ref: Some("subject-alice"),
        signature_request_receipt: Some("portal-signature:demo-dpa"),
        executed_artifact_hash: Some("sha256:executed-dpa"),
        created_unix_ms: now - 172800000L,
        updated_unix_ms: now - 86400000L,
      },
    ],
    lease_requests: [
      {
        submission: {
          request_id: "request-eval-042",
          idempotency_key: "submit-eval-042",
          tenant_ref: "tenant-northstar",
          organization_id: "org-northstar",
          project_id: "project-vision-lab",
          unix_username: "alice",
          starts_unix_ms: now + 86400000L,
          expires_unix_ms: now + 176400000L,
          requested_model_ids: ["qwen3-32b", "bge-m3"],
          justification: "Private evaluation and adapter validation.",
        },
        subject_ref: "subject-alice",
        state: Submitted,
        generation: 1L,
        assigned_node_id: None,
        exclusive_lease_id: None,
        decision_receipt: None,
        created_unix_ms: now - 3600000L,
        updated_unix_ms: now - 3600000L,
      },
    ],
    notifications: [
      {
        event: {
          version: @notifications.contract_version,
          notification_id: "notice-access-ready-demo",
          deduplication_key: "access-ready-demo",
          source_receipt: "exclusive-lease:demo:5",
          topic: AccessCredential,
          code: "LeaseAccessReady",
          severity: Information,
          audience: Subject(
            tenant_ref="tenant-northstar",
            subject_ref="subject-alice",
          ),
          title_key: "notifications.lease_access_ready.title",
          body_key: "notifications.lease_access_ready.body",
          parameters: {
            "lease_ref": "exclusive-lease-demo",
            "credential_ref": "credential://vault/access-demo",
          },
          created_unix_ms: now - 1800000L,
          expires_unix_ms: None,
        },
        lifecycle: Unread,
        generation: 1L,
        assigned_to: None,
        acknowledged_by: None,
        acknowledged_unix_ms: None,
        silenced_until_unix_ms: None,
        resolved_by: None,
        resolved_unix_ms: None,
        updated_unix_ms: now - 1800000L,
      },
    ],
    notification_preferences: [
      {
        topic: LeaseLifecycle,
        channels: [InApp, Email],
        minimum_severity: Information,
        updated_unix_ms: now - 1800000L,
      },
    ],
    machine_access: {
      ..@machine_access.default_state(@i18n.default_locale()),
      now_unix_ms: now,
      machines: [
        {
          version: @nodelease.contract_version,
          lease_ref: "exclusive-lease-demo",
          machine_ref: "assigned-machine:exclusive-lease-demo",
          state: Active,
          generation: 5L,
          username: "alice",
          starts_unix_ms: now - 3600000L,
          expires_unix_ms: now + 86400000L,
          updated_unix_ms: now - 1800000L,
          reachability: Online,
          last_seen_unix_ms: Some(now - 5000L),
          credential_handoff: {
            state: Available,
            handoff_ref: None,
            credential_kind: "short-lived-ssh-certificate",
            valid_until_unix_ms: now + 86400000L,
            raw_secret_included: false,
          },
          can_terminate: true,
          termination_confirmation: Some("TERMINATE exclusive-lease-demo"),
        },
      ],
    },
    offline_commerce: {
      ..@offline_commerce.demo_state(@i18n.default_locale(), CustomerCommerce),
      project_id: "project-vision-lab",
    },
    contract_documents: {
      ..@contract_documents.default_state(@i18n.default_locale()),
      manifest: Some(manifest),
      available_manifests: [manifest, undertaking_manifest],
      packets: [demo_packet, effective_packet, undertaking_packet],
      events: [
        {
          event_id: "contract-event-customer-demo-created",
          packet_id: effective_packet.packet_id,
          revision: 1L,
          kind: PacketCreated,
          actor_ref: "operator-demo",
          changed_field_ids: [],
          values_sha256: None,
          artifact_sha256: None,
          occurred_unix_ms: effective_packet.created_unix_ms,
        },
        {
          event_id: "contract-event-customer-demo-effective",
          packet_id: effective_packet.packet_id,
          revision: effective_packet.revision,
          kind: ExecutionRegisteredEvent,
          actor_ref: "operator-demo",
          changed_field_ids: [],
          values_sha256: effective_packet.values_sha256,
          artifact_sha256: effective_packet.execution.map(value => {
            value.evidence_sha256
          }),
          occurred_unix_ms: effective_packet.updated_unix_ms,
        },
      ],
      approvals: [customer_approval],
      obligations: [payment_obligation],
      now_unix_ms: now,
      selected_packet_id: Some("packet-demo-youthpolicy"),
      selected_form: Some(MasterLease),
    },
    cost_centers: [
      {
        cost_center_id: "cc-research",
        display_name: "AI Research",
        project_count: 2,
        provisional_spend: "CNY 12,760.00",
        budget_posture: "Within budget",
      },
      {
        cost_center_id: "cc-platform",
        display_name: "Platform",
        project_count: 1,
        provisional_spend: "CNY 5,660.00",
        budget_posture: "Within budget",
      },
    ],
    provisional_spend: "CNY 18,420.00",
    payment_checkout_quote: Some({
      period_id: "period-2026-08",
      expected_amount_minor: 1842000L,
      currency: "CNY",
      money_scale: 2,
      display_amount: "CNY 18,420.00",
      idempotency_key: "checkout-period-period-2026-08",
      entitlement_transaction_ref_sha256: "sha256:40ad9defdemo",
      ledger_entry_count: 3,
      ledger_revision_unix_ms: now - 86400000L,
    }),
    provider_requests: [
      {
        record_id: "payment-demo-settled",
        organization_id: "org-northstar",
        kind: Payment,
        provider: "qualified-services-demo",
        environment: "test",
        external_ref_sha256: "sha256:payment-demo",
        state: Settled,
        expected_amount_minor: Some(920000L),
        currency: Some("CNY"),
        money_scale: Some(2),
        expected_document_hash: None,
        entitlement_transaction_ref_sha256: None,
        action_url: None,
        action_expires_unix_ms: None,
        updated_unix_ms: now - 30000L,
      },
      {
        record_id: "signature-demo-submitted",
        organization_id: "org-northstar",
        kind: QualifiedSignature,
        provider: "qualified-services-demo",
        environment: "test",
        external_ref_sha256: "sha256:signature-demo",
        state: Submitted,
        expected_amount_minor: None,
        currency: None,
        money_scale: None,
        expected_document_hash: Some("sha256:4f94d8f0a2"),
        entitlement_transaction_ref_sha256: Some("sha256:agreement-demo"),
        action_url: Some("https://sign.example.invalid/ceremony/demo"),
        action_expires_unix_ms: Some(now + 900000L),
        updated_unix_ms: now - 10000L,
      },
    ],
    provider_requests_loading: false,
    payment_checkout_loading: false,
    model_catalog: [
      {
        model_id: "qwen3-32b",
        version: "v1",
        alias_name: Some("text.default"),
        compatible_architectures: ["nvidia-gb10"],
        minimum_memory_mib: 65536,
      },
      {
        model_id: "bge-m3",
        version: "v2",
        alias_name: Some("embedding.default"),
        compatible_architectures: ["nvidia-gb10"],
        minimum_memory_mib: 4096,
      },
    ],
    desktop_client: Some({
      client_id: "desktop-workspace",
      display_name: "Desktop WebIDE",
      launch_uri: "/workbench/?demo=1",
      handoff_lifetime_ms: 120000L,
      connected_handoffs: 0,
      contract_ready: true,
      workspace_ready: true,
      models_ready: true,
      ready: true,
      blocker_codes: [],
      approved_model_aliases: ["text.default"],
    }),
    self_service: demo_self_service_state(now),
    project_id: "project-vision-lab",
    unix_username: "alice",
    model_ids: "qwen3-32b, bge-m3",
    justification: "Private evaluation and adapter validation.",
  }
  let clients = match state.desktop_client {
    Some(desktop) =>
      [
        desktop,
        {
          ..desktop,
          client_id: "comfyui",
          display_name: "ComfyUI",
          launch_uri: "https://creative.example.invalid/connect",
          models_ready: false,
          ready: false,
          blocker_codes: ["ApprovedModelRequired"],
          approved_model_aliases: [],
        },
      ]
    None => []
  }
  { ..state, desktop_clients: clients, }
}

///|
pub fn EnterpriseState::update(
  self : EnterpriseState,
  message : EnterpriseMessage,
) -> EnterpriseState {
  match message {
    Delivery(message) =>
      { ..self, deliveries: self.deliveries.update(message), }
    SelectWebIdeOrder(order_id) => {
      if self.loading {
        return self
      }
      {
        ..self,
        webide_order_id: if order_id == "" {
          None
        } else {
          Some(order_id)
        },
        desktop_connect_phase: NotStarted,
        success_message: None,
        error_message: None,
      }
    }
    SelectWebIde(client_id) => {
      if self.loading {
        return self
      }
      match
        self.desktop_clients
        .filter(client => client.client_id == client_id)
        .get(0) {
        Some(client) =>
          {
            ..self,
            desktop_client: Some(client),
            desktop_connect_phase: NotStarted,
            success_message: None,
            error_message: None,
          }
        None => self
      }
    }
    Navigate(route) => {
      let dedicated = if route == AccountAccess {
        self.self_service.order.filter(order => {
          order.kind == DedicatedMaaS && order.status == ActiveOrder
        })
      } else {
        None
      }
      match dedicated {
        Some(order) =>
          {
            ..self,
            route,
            api_key_issue_draft: {
              ..self.api_key_issue_draft,
              display_name: "Dedicated · \{order.order_id}",
              allowed_models: order.model_selector.unwrap_or(""),
              lifetime_days: ((order.duration_hours + 23) / 24).max(1),
            },
            api_key_issue_open: true,
            success_message: None,
            error_message: None,
          }
        None => { ..self, route, success_message: None, error_message: None, }
      }
    }
    LocaleChanged(locale) =>
      {
        ..self,
        locale,
        machine_access: { ..self.machine_access, locale, },
        offline_commerce: { ..self.offline_commerce, locale, },
        contract_documents: { ..self.contract_documents, locale, },
        success_message: None,
        error_message: None,
      }
    SelfService(SelectProduct(product)) => {
      let selected = self.self_service.update(SelectProduct(product))
      let organization_ready = has_customer_membership(self) &&
        (match self.membership {
          Some(membership) =>
            self.organizations.any(value => {
              value.organization.organization_id == membership.organization_id &&
              value.organization.state == Active
            })
          None => false
        })
      {
        ..self,
        route: SelfService,
        self_service: {
          ..selected,
          step: if organization_ready {
            Capacity
          } else {
            Organization
          },
        },
        success_message: None,
        error_message: None,
      }
    }
    SelfService(SelectOrganization(organization_id)) => {
      let selection = self.organizations
        .iter()
        .find_first(value => {
          value.organization.organization_id == organization_id &&
          value.membership.active
        })
      match selection {
        Some(value) => {
          let project_id = value.default_project_id.unwrap_or("")
          {
            ..self,
            membership: Some(value.membership),
            selected_organization_id: Some(organization_id),
            project_id,
            member_invite_email: "",
            member_invite_secret: None,
            offline_commerce: {
              ..self.offline_commerce,
              project_id,
              orders: [],
              artifacts: [],
              selected_order_id: None,
            },
            self_service: {
              ..self.self_service,
              project_id,
              quote: None,
              order: None,
              orders: [],
              checkout: None,
              terms_accepted: false,
              terms_reviewed: false,
              action_error: None,
            },
            success_message: None,
            error_message: None,
          }
        }
        None =>
          {
            ..self,
            selected_organization_id: None,
            membership: None,
            member_invite_email: "",
            member_invite_secret: None,
            self_service: {
              ..self.self_service,
              quote: None,
              order: None,
              orders: [],
              checkout: None,
              terms_accepted: false,
              terms_reviewed: false,
              action_error: Some(
                enterprise_copy(
                  self.locale,
                  SelectAnActiveOrganizationBeforeContinuing,
                ),
              ),
            },
          }
      }
    }
    SelfService(RequestQuote) =>
      {
        ..self,
        self_service: { ..self.self_service.update(RequestQuote), step: Quote, },
      }
    SelfService(CreateMachineOrder) =>
      {
        ..self,
        self_service: {
          ..self.self_service.update(CreateMachineOrder),
          step: ContractPayment,
        },
      }
    SelfService(message) =>
      { ..self, self_service: self.self_service.update(message), }
    OpenApiKeyIssue =>
      {
        ..self,
        api_key_issue_open: true,
        api_key_revoke_id: None,
        one_time_api_key_secret: None,
        success_message: None,
        error_message: None,
      }
    CancelApiKeyIssue =>
      { ..self, api_key_issue_open: false, error_message: None, }
    ApiKeyDisplayNameChanged(value) =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          display_name: value,
        },
      }
    ToggleApiKeyModelListScope =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          model_list_scope: !self.api_key_issue_draft.model_list_scope,
        },
      }
    ToggleApiKeyInferenceScope =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          inference_scope: !self.api_key_issue_draft.inference_scope,
        },
      }
    ApiKeyAllowedModelsChanged(value) =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          allowed_models: value,
        },
      }
    ApiKeyLifetimeChanged(value) =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          lifetime_days: value,
        },
      }
    ApiKeyMaximumRequestsChanged(value) =>
      {
        ..self,
        api_key_issue_draft: {
          ..self.api_key_issue_draft,
          maximum_requests: value,
        },
      }
    SubmitApiKeyIssue =>
      { ..self, loading: true, success_message: None, error_message: None, }
    MemberInviteEmailChanged(value) => { ..self, member_invite_email: value, }
    SubmitMemberInvite =>
      {
        ..self,
        member_invite_loading: true,
        success_message: None,
        error_message: None,
      }
    DismissMemberInviteSecret => { ..self, member_invite_secret: None, }
    CopyOneTimeApiKeySecret
    | CopyFirstCallExample
    | CopyDetail(_)
    | ExportCosts => self
    DismissOneTimeApiKeySecret => { ..self, one_time_api_key_secret: None, }
    BeginRevokeApiKey(key_id) =>
      {
        ..self,
        api_key_issue_open: false,
        api_key_revoke_id: Some(key_id),
        one_time_api_key_secret: None,
        success_message: None,
        error_message: None,
      }
    CancelRevokeApiKey => { ..self, api_key_revoke_id: None, }
    ConfirmRevokeApiKey(_) =>
      { ..self, loading: true, success_message: None, error_message: None, }
    ProjectChanged(value) => { ..self, project_id: value, }
    UsernameChanged(value) => { ..self, unix_username: value, }
    ModelsChanged(value) => { ..self, model_ids: value, }
    JustificationChanged(value) => { ..self, justification: value, }
    SignAgreement(_) =>
      { ..self, loading: true, success_message: None, error_message: None, }
    RefreshProviderRequests =>
      {
        ..self,
        provider_requests_loading: true,
        success_message: None,
        error_message: None,
      }
    SubmitPaymentCheckout =>
      {
        ..self,
        payment_checkout_loading: true,
        success_message: None,
        error_message: None,
      }
    SubmitLease =>
      { ..self, loading: true, success_message: None, error_message: None, }
    LaunchDesktopClient =>
      {
        ..self,
        loading: true,
        desktop_connect_phase: IssuingHandoff,
        success_message: None,
        error_message: None,
      }
    MarkNotificationRead(_, _) => self
    SetNotificationEmail(_, _) =>
      { ..self, loading: true, success_message: None, error_message: None, }
    MachineAccess(message) =>
      { ..self, machine_access: self.machine_access.update(message), }
    OfflineCommerce(message) =>
      { ..self, offline_commerce: self.offline_commerce.update(message), }
    ContractDocuments(message) =>
      { ..self, contract_documents: self.contract_documents.update(message), }
    ClearNotice => { ..self, success_message: None, error_message: None, }
  }
}

///|
pub fn api_key_issue_valid(state : EnterpriseState) -> Bool {
  guard state.membership is Some(membership) else { return false }
  let draft = state.api_key_issue_draft
  membership.active &&
  @portal.role_allows(membership.roles, Developer) &&
  draft.display_name.trim() != "" &&
  draft.display_name.length() <= 128 &&
  state.project_id.trim() != "" &&
  (draft.model_list_scope || draft.inference_scope) &&
  (
    draft.lifetime_days == 1 ||
    draft.lifetime_days == 7 ||
    draft.lifetime_days == 30 ||
    draft.lifetime_days == 90 ||
    draft.lifetime_days == 365
  ) &&
  draft.maximum_requests > 0L &&
  draft.maximum_requests <= 1000000000L &&
  !state.loading
}

///|
pub fn api_key_scopes(state : EnterpriseState) -> Array[ApiKeyScope] {
  let scopes : Array[ApiKeyScope] = []
  if state.api_key_issue_draft.model_list_scope {
    scopes.push(ModelList)
  }
  if state.api_key_issue_draft.inference_scope {
    scopes.push(Inference)
  }
  scopes
}

///|
pub fn api_key_allowed_models(state : EnterpriseState) -> Array[String] {
  state.api_key_issue_draft.allowed_models
  .split(",")
  .map(value => value.trim().to_owned())
  .filter(value => value != "")
  .to_array()
}

///|
pub fn lease_form_valid(state : EnterpriseState) -> Bool {
  state.membership is Some(_) &&
  state.project_id.trim() != "" &&
  @portal.valid_unix_username(state.unix_username.trim().to_owned()) &&
  state.model_ids.trim() != "" &&
  state.justification.trim() != "" &&
  state.expires_unix_ms > state.starts_unix_ms &&
  !state.loading
}

///|
fn command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  message : EnterpriseMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  wrap : (String) -> EnterpriseMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn route_label(locale : @i18n.Locale, route : EnterpriseRoute) -> String {
  match route {
    Overview => enterprise_copy(locale, Overview)
    SelfService => enterprise_copy(locale, GetStarted)
    AccountAccess => enterprise_copy(locale, AccountApiKeys)
    Agreements => enterprise_copy(locale, Agreements)
    LeaseRequests => enterprise_copy(locale, ManagedRequests)
    Notifications => enterprise_copy(locale, Notifications)
    Costs => enterprise_copy(locale, UsageCosts)
    Models => enterprise_copy(locale, ModelCatalog)
    DesktopIde => enterprise_copy(locale, Webide)
    MachineAccess => enterprise_copy(locale, MyMachine)
    OfflineCommerce => enterprise_copy(locale, OrdersDocuments)
    ContractDocuments => enterprise_copy(locale, ContractForms)
  }
}

///|
fn state_label(
  locale : @i18n.Locale,
  state : @portal.PortalAgreementState,
) -> String {
  match state {
    ReviewRequired => enterprise_copy(locale, ReviewRequired)
    SignatureRequested => enterprise_copy(locale, SignatureInProgress)
    Executed => enterprise_copy(locale, Executed)
    Declined => enterprise_copy(locale, Declined)
    Superseded => enterprise_copy(locale, Superseded)
  }
}

///|
fn provider_state_label(
  locale : @i18n.Locale,
  state : @commercial_integrations.ExternalRecordState,
) -> String {
  match state {
    Pending => enterprise_copy(locale, PreparingSecureLink)
    Submitted => enterprise_copy(locale, ReadyToContinue)
    Verified => enterprise_copy(locale, Verified)
    Authorized => enterprise_copy(locale, Authorized)
    Settled => enterprise_copy(locale, Paid)
    Issued => enterprise_copy(locale, Issued)
    Failed => enterprise_copy(locale, Failed)
    Expired => enterprise_copy(locale, Expired)
    Voided => enterprise_copy(locale, Voided)
    Credited => enterprise_copy(locale, Credited)
    Refunded => enterprise_copy(locale, Refunded)
  }
}

///|
fn provider_state_class(
  state : @commercial_integrations.ExternalRecordState,
) -> String {
  match state {
    Settled | Verified | Issued => "state-pill provider-state-success"
    Failed | Expired | Voided => "state-pill provider-state-error"
    Pending => "state-pill provider-state-pending"
    _ => "state-pill provider-state-active"
  }
}

///|
pub fn valid_provider_action_url(value : String) -> Bool {
  if !value.has_prefix("https://") ||
    value.length() <= "https://".length() ||
    value.length() > 2048 ||
    value.contains("#") ||
    value.contains("\\") ||
    value.any(character => character.is_whitespace()) {
    return false
  }
  let authority = value["https://".length():]
    .split("/")
    .next()
    .map(part => part.to_owned())
    .unwrap_or("")
  authority != "" && !authority.contains("@")
}

///|
fn usable_provider_action(
  record : @commercial_integrations.ExternalRecordView,
  now_unix_ms : Int64,
) -> String? {
  guard record.action_url is Some(action_url) &&
    record.action_expires_unix_ms is Some(expires_unix_ms) &&
    expires_unix_ms > now_unix_ms &&
    valid_provider_action_url(action_url) else {
    return None
  }
  Some(action_url)
}

///|
fn provider_action_expired(
  record : @commercial_integrations.ExternalRecordView,
  now_unix_ms : Int64,
) -> Bool {
  record.state == Expired ||
  record.action_expires_unix_ms
  .map(expires => expires <= now_unix_ms)
  .unwrap_or(false)
}

///|
fn signature_provider_request(
  state : EnterpriseState,
  agreement : @portal.PortalAgreement,
) -> @commercial_integrations.ExternalRecordView? {
  state.provider_requests
  .iter()
  .filter(record => {
    record.kind == QualifiedSignature &&
    record.expected_document_hash == Some(agreement.rendered_document_hash)
  })
  .last()
}

///|
fn payment_request_matches_quote(
  record : @commercial_integrations.ExternalRecordView,
  quote : PaymentCheckoutQuote,
) -> Bool {
  record.kind == Payment &&
  record.entitlement_transaction_ref_sha256 ==
  Some(quote.entitlement_transaction_ref_sha256) &&
  record.expected_amount_minor == Some(quote.expected_amount_minor) &&
  record.currency == Some(quote.currency) &&
  record.money_scale == Some(quote.money_scale)
}

///|
fn payment_request_in_progress(state : EnterpriseState) -> Bool {
  guard state.payment_checkout_quote is Some(quote) else { return false }
  state.provider_requests.any(record => {
    payment_request_matches_quote(record, quote) &&
    (match record.state {
      Pending | Authorized => true
      Submitted =>
        !provider_action_expired(record, state.machine_access.now_unix_ms)
      _ => false
    })
  })
}

///|
fn payment_request_for_quote(
  state : EnterpriseState,
) -> @commercial_integrations.ExternalRecordView? {
  guard state.payment_checkout_quote is Some(quote) else { return None }
  state.provider_requests
  .iter()
  .filter(record => payment_request_matches_quote(record, quote))
  .last()
}

///|
fn payment_checkout_terminal(state : EnterpriseState) -> Bool {
  guard payment_request_for_quote(state) is Some(record) else { return false }
  match record.state {
    Settled | Failed | Expired | Voided | Refunded => true
    _ => false
  }
}

///|
pub fn payment_checkout_available(state : EnterpriseState) -> Bool {
  guard state.membership is Some(membership) &&
    state.payment_checkout_quote is Some(quote) else {
    return false
  }
  membership.active &&
  (
    @portal.role_allows(membership.roles, BillingViewer) ||
    @portal.role_allows(membership.roles, OrganizationAdministrator)
  ) &&
  quote.expected_amount_minor > 0L &&
  quote.currency.length() == 3 &&
  quote.money_scale >= 0 &&
  quote.money_scale <= 9 &&
  !state.payment_checkout_loading &&
  !payment_request_in_progress(state) &&
  !payment_checkout_terminal(state)
}

///|
fn request_state_label(
  locale : @i18n.Locale,
  state : @portal.LeaseRequestState,
) -> String {
  match state {
    Submitted => enterprise_copy(locale, AwaitingOperator)
    Approved => enterprise_copy(locale, NodeReserved)
    Rejected => enterprise_copy(locale, Rejected)
    Cancelled => enterprise_copy(locale, Cancelled)
  }
}

///|
fn navigation(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let items : Array[@rabbita.Html] = []
  for
    route in [
      EnterpriseRoute::Overview,
      SelfService,
      MachineAccess,
      LeaseRequests,
      OfflineCommerce,
      DesktopIde,
      Models,
      AccountAccess,
      Agreements,
      ContractDocuments,
      Costs,
      Notifications,
    ] {
    let group = match route {
      Overview => Some(copy(state.locale, "Start", "开始"))
      MachineAccess =>
        Some(
          copy(state.locale, "IaaS · company machines", "IaaS · 企业机器"),
        )
      DesktopIde =>
        Some(
          copy(
            state.locale,
            "PaaS · personal applications",
            "PaaS · 个人应用",
          ),
        )
      Models =>
        Some(
          copy(state.locale, "MaaS · company models", "MaaS · 企业模型"),
        )
      Agreements =>
        Some(copy(state.locale, "Company administration", "企业管理"))
      _ => None
    }
    if group is Some(label) {
      items.push(
        @html.p(
          class="nav-group-label",
          style=[
            "grid-column: 1 / -1", "margin: .9rem .65rem .2rem", "color: var(--muted)",
            "font-size: .72rem", "font-weight: 800",
          ],
          label,
        ),
      )
    }
    items.push(
      @html.button(
        type_="button",
        class=if state.route == route {
          "nav-item is-active"
        } else {
          "nav-item"
        },
        attrs=@html.Attrs::build().aria_current(
          if state.route == route {
            "page"
          } else {
            "false"
          },
        ),
        on_click=command(emit, Navigate(route)),
        route_label(state.locale, route),
      ),
    )
  }
  @html.aside(class="enterprise-sidebar", [
    @html.a(class="enterprise-brand", href="./", [
      @html.span(
        class="brand-mark",
        style=[
          "overflow: hidden", "flex-shrink: 0", "width: 3.5rem", "height: 3.5rem",
        ],
        [
          @html.img(src="/assets/platform-logo-light.png", alt="", style=[
            "display: block", "width: 100%", "height: 100%", "object-fit: contain",
            "transform: scale(1.22)", "transform-origin: center",
          ]),
        ],
      ),
      @html.span([
        @html.strong("能源谷“创未来”生态街区"),
        @html.small(enterprise_copy(state.locale, Enterprise)),
      ]),
    ]),
    @html.nav(
      attrs=@html.Attrs::build().aria_label(
        enterprise_copy(state.locale, EnterpriseNavigation),
      ),
      items,
    ),
    @html.div(class="trust-note", [
      @html.strong(enterprise_copy(state.locale, CustomerBoundary)),
      @html.p(enterprise_copy(state.locale, CatalogOrdersAreSelfServiceManaged)),
    ]),
  ])
}

///|
fn page_header(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let organization_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.selected_organization_id is None,
      enterprise_copy(state.locale, SelectOrganization),
    ),
  ]
  for value in state.organizations {
    organization_options.push(
      @html.option(
        value=value.organization.organization_id,
        selected=state.selected_organization_id ==
          Some(value.organization.organization_id),
        value.organization.display_name,
      ),
    )
  }
  @html.header(class="enterprise-topbar", [
    @html.div([
      @html.p(
        class="eyebrow",
        enterprise_copy(state.locale, EnterpriseControlCenter),
      ),
      @html.h1(route_label(state.locale, state.route)),
    ]),
    @html.div(class="topbar-actions", [
      @html.div(class="locale-control", [
        @html.label(
          for_="enterprise-locale",
          enterprise_copy(state.locale, Language),
        ),
        @html.select(
          id="enterprise-locale",
          on_change=text_command(emit, value => {
            LocaleChanged(@i18n.parse_locale(value))
          }),
          attrs=@html.Attrs::build().aria_label(
            enterprise_copy(state.locale, InterfaceLanguage),
          ),
          [
            @html.option(
              value=@i18n.English.storage_value(),
              selected=state.locale == English,
              @i18n.English.label(),
            ),
            @html.option(
              value=@i18n.ChineseSimplified.storage_value(),
              selected=state.locale == ChineseSimplified,
              @i18n.ChineseSimplified.label(),
            ),
          ],
        ),
      ]),
      if state.organizations.length() > 1 {
        @html.div(class="organization-control", [
          @html.label(
            for_="enterprise-organization",
            enterprise_copy(state.locale, Organization),
          ),
          @html.select(
            id="enterprise-organization",
            attrs=@html.Attrs::build().aria_label(
              enterprise_copy(state.locale, ActiveOrganizationForScopedRequests),
            ),
            on_change=self_service_text_command(emit, value => {
              SelectOrganization(value)
            }),
            organization_options,
          ),
        ])
      } else {
        @html.nothing
      },
      @html.div(class="topbar-meta", [
        @html.span(class="status-dot", ""),
        @html.span(
          class="role-pill",
          enterprise_copy(state.locale, TenantScoped),
        ),
      ]),
    ]),
  ])
}

///|
fn overview_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let pending = state.agreements
    .filter(value => value.state == ReviewRequired)
    .length()
  let open_requests = state.lease_requests
    .filter(value => value.state == Submitted)
    .length()
  let trial_panel = match state.trial {
    Some(trial) if trial.revoked_unix_ms is None => {
      let active = trial.expires_unix_ms > state.machine_access.now_unix_ms
      let consumed = match trial.api_key_id {
        Some(key_id) =>
          state.api_keys
          .iter()
          .find_first(key => key.key_id == key_id)
          .map(key => key.consumed_requests)
          .unwrap_or(0L)
        None => 0L
      }
      @html.section(class="welcome-panel trial-panel", [
        @html.div([
          @html.p(
            class="eyebrow",
            enterprise_copy(state.locale, FreeSharedInferenceTrial),
          ),
          @html.h2(
            if active {
              enterprise_copy(state.locale, YourTrialIsReady)
            } else {
              enterprise_copy(state.locale, YourTrialHasEnded)
            },
          ),
          @html.p(
            if active {
              enterprise_copy(state.locale, UseTheApprovedModelThroughA)
            } else {
              enterprise_copy(state.locale, YourAccountRemainsActiveAskYour)
            },
          ),
          @html.p(
            class="secondary",
            "\{expiry_label(state.locale, trial.expires_unix_ms, state.machine_access.now_unix_ms)} · \{enterprise_copy(state.locale, Requests)} \{consumed}/\{trial.maximum_requests} · \{trial.allowed_models.join(", ")}",
          ),
          @html.p(message(state.locale, TrialSecret)),
          if active {
            @html.a(
              class="quiet-button external-action",
              href="/workbench/?trial=1",
              enterprise_copy(state.locale, TryAPromptInTheWorkbench),
            )
          } else {
            @html.nothing
          },
        ]),
        @html.button(
          type_="button",
          class="primary-action",
          disabled=!active,
          on_click=command(emit, Navigate(AccountAccess)),
          if trial.api_key_id is None {
            enterprise_copy(state.locale, CreateTrialApiKey)
          } else {
            enterprise_copy(state.locale, ViewTrialApiKey)
          },
        ),
      ])
    }
    _ => @html.nothing
  }
  @html.div(class="page-stack", [
    trial_panel,
    product_choices(state, emit, true),
    @html.section(class="welcome-panel", [
      @html.div([
        @html.p(
          class="eyebrow",
          enterprise_copy(state.locale, YourLunanexaTenant),
        ),
        @html.h2(enterprise_copy(state.locale, NeedAManagedCapacityException)),
        @html.p(enterprise_copy(state.locale, UseThisPathWhenTheSelf)),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        on_click=command(emit, Navigate(LeaseRequests)),
        enterprise_copy(state.locale, RequestManagedCapacity),
      ),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, AgreementsToReview)),
        @html.strong("\{pending}"),
        @html.small(enterprise_copy(state.locale, LegalSignerAction)),
      ]),
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, OpenLeaseRequests)),
        @html.strong("\{open_requests}"),
        @html.small(enterprise_copy(state.locale, OperatorReviewQueue)),
      ]),
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, ModelsEntitled)),
        @html.strong(state.model_catalog.length().to_string()),
        @html.small(enterprise_copy(state.locale, SharedCentralCatalog)),
      ]),
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, CurrentSpend)),
        @html.strong(state.provisional_spend),
        @html.small(enterprise_copy(state.locale, ProvisionalCentralLedger)),
      ]),
    ]),
  ])
}

///|
fn enterprise_role_label(
  locale : @i18n.Locale,
  role : @portal.EnterpriseRole,
) -> String {
  match role {
    OrganizationAdministrator =>
      enterprise_copy(locale, OrganizationAdministrator)
    LegalSigner => enterprise_copy(locale, LegalSigner)
    LeaseRequester => enterprise_copy(locale, LeaseRequester)
    BillingViewer => enterprise_copy(locale, BillingViewer)
    Developer => enterprise_copy(locale, Developer)
  }
}

///|
fn account_role_label(locale : @i18n.Locale, role : AccountRole) -> String {
  match role {
    PlatformOperator => enterprise_copy(locale, PlatformOperator)
    AuditReader => enterprise_copy(locale, AuditReader)
    EnterpriseUser => enterprise_copy(locale, EnterpriseUser)
  }
}

///|
fn account_state_label(locale : @i18n.Locale, state : AccountState) -> String {
  match state {
    Invited => enterprise_copy(locale, Invited)
    Active => enterprise_copy(locale, Active)
    Suspended => enterprise_copy(locale, Suspended)
    Revoked => enterprise_copy(locale, Revoked)
  }
}

///|
fn api_key_scope_label(locale : @i18n.Locale, scope : ApiKeyScope) -> String {
  match scope {
    ModelList => enterprise_copy(locale, ModelList)
    Inference => enterprise_copy(locale, Inference)
  }
}

///|
fn api_key_state(
  locale : @i18n.Locale,
  key : ApiCredentialView,
  now_unix_ms : Int64,
) -> (String, String) {
  if key.revoked_unix_ms is Some(_) {
    (enterprise_copy(locale, Revoked), "revoked")
  } else if key.expires_unix_ms <= now_unix_ms {
    (enterprise_copy(locale, Expired), "expired")
  } else if key.consumed_requests >= key.maximum_requests {
    (enterprise_copy(locale, QuotaExhausted), "expired")
  } else {
    (enterprise_copy(locale, Active), "active")
  }
}

///|
fn api_key_issue_dialog(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  if !state.api_key_issue_open {
    return @html.nothing
  }
  let draft = state.api_key_issue_draft
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog account-dialog",
      attrs=@html.Attrs::build()
        .role("dialog")
        .aria_modal("true")
        .aria_labelledby("api-key-issue-title")
        .aria_describedby("api-key-issue-description"),
      [
        @html.h2(
          id="api-key-issue-title",
          enterprise_copy(state.locale, CreateApiKey),
        ),
        @html.p(
          id="api-key-issue-description",
          enterprise_copy(state.locale, TheSecretIsShownOnceTrial),
        ),
        @html.div(class="account-form", [
          @html.div(class="field", [
            @html.label(
              for_="api-key-project-id",
              enterprise_copy(state.locale, BillingProject),
            ),
            @html.input(
              id="api-key-project-id",
              value=state.project_id,
              maxlength=256,
              required=true,
              on_input=text_command(emit, value => ProjectChanged(value)),
            ),
          ]),
          @html.div(class="field", [
            @html.label(
              for_="api-key-display-name",
              enterprise_copy(state.locale, KeyName),
            ),
            @html.input(
              id="api-key-display-name",
              value=draft.display_name,
              maxlength=128,
              required=true,
              on_input=text_command(emit, value => {
                ApiKeyDisplayNameChanged(value)
              }),
            ),
          ]),
          @html.fieldset(class="scope-picker", [
            @html.legend(enterprise_copy(state.locale, Scopes)),
            @html.button(
              type_="button",
              class=if draft.model_list_scope {
                "scope-toggle is-selected"
              } else {
                "scope-toggle"
              },
              attrs=@html.Attrs::build().aria_pressed(
                if draft.model_list_scope {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, ToggleApiKeyModelListScope),
              enterprise_copy(state.locale, ModelList),
            ),
            @html.button(
              type_="button",
              class=if draft.inference_scope {
                "scope-toggle is-selected"
              } else {
                "scope-toggle"
              },
              attrs=@html.Attrs::build().aria_pressed(
                if draft.inference_scope {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, ToggleApiKeyInferenceScope),
              enterprise_copy(state.locale, Inference),
            ),
          ]),
          @html.div(class="field", [
            @html.label(
              for_="api-key-models",
              enterprise_copy(state.locale, AllowedModels),
            ),
            @html.input(
              id="api-key-models",
              value=draft.allowed_models,
              placeholder=enterprise_copy(
                state.locale,
                OptionalCommaSeparatedAliases,
              ),
              on_input=text_command(emit, value => {
                ApiKeyAllowedModelsChanged(value)
              }),
            ),
            @html.small(
              enterprise_copy(state.locale, LeaveEmptyToAllowEveryModel),
            ),
          ]),
          @html.div(class="account-form-grid", [
            @html.div(class="field", [
              @html.label(
                for_="api-key-lifetime",
                enterprise_copy(state.locale, Lifetime),
              ),
              @html.select(
                id="api-key-lifetime",
                on_change=text_command(emit, value => {
                  ApiKeyLifetimeChanged(
                    match value {
                      "1" => 1
                      "7" => 7
                      "90" => 90
                      "365" => 365
                      _ => 30
                    },
                  )
                }),
                [
                  @html.option(
                    value="1",
                    selected=draft.lifetime_days == 1,
                    enterprise_copy(state.locale, Day),
                  ),
                  @html.option(
                    value="7",
                    selected=draft.lifetime_days == 7,
                    enterprise_copy(state.locale, Days),
                  ),
                  @html.option(
                    value="30",
                    selected=draft.lifetime_days == 30,
                    enterprise_copy(state.locale, Days101),
                  ),
                  @html.option(
                    value="90",
                    selected=draft.lifetime_days == 90,
                    enterprise_copy(state.locale, Days102),
                  ),
                  @html.option(
                    value="365",
                    selected=draft.lifetime_days == 365,
                    enterprise_copy(state.locale, Year),
                  ),
                ],
              ),
            ]),
            @html.div(class="field", [
              @html.label(
                for_="api-key-maximum-requests",
                enterprise_copy(state.locale, RequestQuota),
              ),
              @html.select(
                id="api-key-maximum-requests",
                on_change=text_command(emit, value => {
                  ApiKeyMaximumRequestsChanged(
                    match value {
                      "100" => 100L
                      "1000" => 1000L
                      "100000" => 100000L
                      _ => 10000L
                    },
                  )
                }),
                [
                  @html.option(
                    value="100",
                    selected=draft.maximum_requests == 100L,
                    "100",
                  ),
                  @html.option(
                    value="1000",
                    selected=draft.maximum_requests == 1000L,
                    "1,000",
                  ),
                  @html.option(
                    value="10000",
                    selected=draft.maximum_requests == 10000L,
                    "10,000",
                  ),
                  @html.option(
                    value="100000",
                    selected=draft.maximum_requests == 100000L,
                    "100,000",
                  ),
                ],
              ),
            ]),
          ]),
        ]),
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.loading,
            on_click=command(emit, CancelApiKeyIssue),
            id="api-key-issue-cancel",
            enterprise_copy(state.locale, Cancel),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=!api_key_issue_valid(state),
            on_click=command(emit, SubmitApiKeyIssue),
            if state.loading {
              enterprise_copy(state.locale, Creating)
            } else {
              enterprise_copy(state.locale, CreateKey)
            },
          ),
        ]),
      ],
    ),
  ])
}

///|
fn one_time_secret_dialog(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  guard state.one_time_api_key_secret is Some(value) else {
    return @html.nothing
  }
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog account-dialog",
      attrs=@html.Attrs::build()
        .role("alertdialog")
        .aria_modal("true")
        .aria_labelledby("api-key-secret-title")
        .aria_describedby("api-key-secret-description"),
      [
        @html.h2(
          id="api-key-secret-title",
          enterprise_copy(state.locale, SaveThisSecretNow),
        ),
        if value.secret == "DEMO-NOT-A-CREDENTIAL" {
          @html.p(
            class="notice",
            enterprise_copy(state.locale, DemoPreviewThisIsNotA),
          )
        } else {
          @html.nothing
        },
        @html.p(
          id="api-key-secret-description",
          enterprise_copy(state.locale, LunanexaStoresOnlyItsHashThis),
        ),
        @html.dl(class="account-facts", [
          @html.div([
            @html.dt(enterprise_copy(state.locale, Name)),
            @html.dd(value.display_name),
          ]),
          @html.div([
            @html.dt(enterprise_copy(state.locale, KeyId)),
            @html.dd([copy_detail(state, emit, value.key_id)]),
          ]),
        ]),
        @html.pre(class="one-time-secret", value.secret),
        @html.section(class="first-call-guide", [
          @html.h3(enterprise_copy(state.locale, MakeYourFirstCall)),
          @html.p(message(state.locale, FirstCallSetup)),
          if value.api_base_url is None {
            @html.p(message(state.locale, MissingApiEntrance))
          } else {
            @html.nothing
          },
          @html.pre(class="mono", first_call_example(value)),
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, CopyFirstCallExample),
            enterprise_copy(state.locale, CopyFirstCallExample),
          ),
          @html.p(message(state.locale, FirstCallErrors)),
        ]),
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, CopyOneTimeApiKeySecret),
            enterprise_copy(state.locale, CopySecret),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            on_click=command(emit, DismissOneTimeApiKeySecret),
            id="api-key-secret-dismiss",
            enterprise_copy(state.locale, ISavedItClearSecret),
          ),
        ]),
      ],
    ),
  ])
}

///|
fn revoke_api_key_dialog(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  guard state.api_key_revoke_id is Some(key_id) else { return @html.nothing }
  let key = state.api_keys.iter().find_first(value => value.key_id == key_id)
  let scope = key
    .map(value => {
      "\{value.display_name} · \{value.scopes.map(item => api_key_scope_label(state.locale, item)).join(", ")}"
    })
    .unwrap_or(key_id)
  @html.div(class="modal-backdrop", [
    @html.section(
      class="confirmation-dialog account-dialog",
      attrs=@html.Attrs::build()
        .role("alertdialog")
        .aria_modal("true")
        .aria_labelledby("api-key-revoke-title")
        .aria_describedby("api-key-revoke-description"),
      [
        @html.h2(
          id="api-key-revoke-title",
          enterprise_copy(state.locale, RevokeApiKey),
        ),
        @html.p(
          id="api-key-revoke-description",
          enterprise_copy(state.locale, RequestsUsingThisKeyWillFail),
        ),
        @html.p(class="confirmation-scope mono", scope),
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.loading,
            on_click=command(emit, CancelRevokeApiKey),
            id="api-key-revoke-cancel",
            enterprise_copy(state.locale, Cancel),
          ),
          @html.button(
            type_="button",
            class="danger-button",
            disabled=state.loading,
            on_click=command(emit, ConfirmRevokeApiKey(key_id)),
            if state.loading {
              enterprise_copy(state.locale, Revoking)
            } else {
              enterprise_copy(state.locale, RevokeKey)
            },
          ),
        ]),
      ],
    ),
  ])
}

///|
fn account_access_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  guard state.membership is Some(membership) else {
    return @html.p(
      class="empty-state",
      enterprise_copy(state.locale, AccountIdentityIsUnavailable),
    )
  }
  let company_active = state.organizations.any(value => {
    value.organization.organization_id == membership.organization_id &&
    value.organization.state == Active
  })
  let can_issue = membership.active &&
    @portal.role_allows(membership.roles, Developer) &&
    (match state.trial {
      Some(trial) if trial.organization_id == membership.organization_id &&
        trial.revoked_unix_ms is None =>
        trial.expires_unix_ms > state.machine_access.now_unix_ms &&
        trial.api_key_id is None
      _ => true
    })
  let browser_session_rows = [
    for browser_session in state.browser_sessions => {
      @html.div(class="browser-session-row", [
        copy_detail(state, emit, browser_session.session_id),
        @html.span(
          "\{enterprise_copy(state.locale, Expires)} · \{@contractdoc.format_unix_ms_beijing(browser_session.expires_unix_ms)}",
        ),
      ])
    }
  ]
  @html.div(class="page-stack account-access-page", [
    @html.section(class="account-identity", [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            enterprise_copy(state.locale, AuthenticatedAccount),
          ),
          @html.h2(enterprise_copy(state.locale, IdentityMembership)),
          @html.p(
            enterprise_copy(state.locale, AuthenticationIsSuppliedByTheTrusted),
          ),
        ]),
        @html.span(
          class=if membership.active {
            "state-pill account-state-active"
          } else {
            "state-pill account-state-inactive"
          },
          if membership.active {
            enterprise_copy(state.locale, ActiveMembership)
          } else {
            enterprise_copy(state.locale, InactiveMembership)
          },
        ),
      ]),
      match state.account {
        Some(account) =>
          @html.div([
            @html.dl(class="account-facts", [
              @html.div([
                @html.dt(enterprise_copy(state.locale, Account)),
                @html.dd(account.display_name),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, Email)),
                @html.dd(account.email),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, AccountId)),
                @html.dd([copy_detail(state, emit, account.account_id)]),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, AccountState)),
                @html.dd(account_state_label(state.locale, account.state)),
              ]),
            ]),
            @html.div(
              class="role-list",
              [
                for role in account.roles => {
                  @html.span(
                    class="role-pill",
                    account_role_label(state.locale, role),
                  )
                }
              ],
            ),
          ])
        None =>
          @html.p(
            class="development-warning",
            enterprise_copy(
              state.locale,
              DevelopmentFallbackTheGatewayAccountProfile,
            ),
          )
      },
      @html.dl(class="account-facts", [
        @html.div([
          @html.dt(enterprise_copy(state.locale, Organization)),
          @html.dd([copy_detail(state, emit, membership.organization_id)]),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Tenant)),
          @html.dd([copy_detail(state, emit, membership.tenant_ref)]),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Subject)),
          @html.dd([copy_detail(state, emit, membership.subject_ref)]),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, BrowserSession)),
          @html.dd(enterprise_copy(state.locale, EndsOnLogoutOrReload)),
        ]),
      ]),
      @html.div(
        class="role-list",
        [
          for role in membership.roles => {
            @html.span(
              class="role-pill",
              enterprise_role_label(state.locale, role),
            )
          }
        ],
      ),
      if state.browser_sessions.length() == 0 {
        @html.nothing
      } else {
        @html.div(
          class="browser-session-list",
          [
            @html.h3(enterprise_copy(state.locale, BrowserSessions)),
            ..browser_session_rows,
          ],
        )
      },
    ]),
    if membership.active && membership.roles.contains(OrganizationAdministrator) {
      @html.section(class="api-key-panel", [
        @html.div(class="section-heading", [
          @html.div([
            @html.h2(copy(state.locale, "Company members", "企业成员")),
            @html.p(
              copy(
                state.locale,
                "Invite a teammate to this company as a Developer. Their WebIDE and chat remain personal; company models and machines are shared by authorization.",
                "邀请同事以开发者身份加入企业。各人的 WebIDE 和聊天独立；模型与机器由企业授权共享。",
              ),
            ),
          ]),
        ]),
        @html.div(class="field", [
          @html.label(
            for_="member-invite-email",
            copy(state.locale, "Teammate email", "同事邮箱"),
          ),
          @html.input(
            id="member-invite-email",
            value=state.member_invite_email,
            maxlength=320,
            on_input=text_command(emit, value => MemberInviteEmailChanged(value)),
          ),
        ]),
        if company_active {
          @html.nothing
        } else {
          @html.p(
            class="notice is-warning",
            copy(
              state.locale,
              "Company registration is awaiting platform review. You can invite members after approval.",
              "企业注册正在等待平台管理员审核；审核通过后即可邀请成员。",
            ),
          )
        },
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!company_active ||
            state.member_invite_loading ||
            !state.member_invite_email.contains("@"),
          on_click=command(emit, SubmitMemberInvite),
          if state.member_invite_loading {
            copy(
              state.locale,
              "Creating invitation…",
              "正在创建邀请…",
            )
          } else {
            copy(state.locale, "Create member invitation", "创建成员邀请")
          },
        ),
        match state.member_invite_secret {
          Some(secret) =>
            @html.div(class="terms-acceptance", [
              @html.p(
                copy(
                  state.locale,
                  "Copy this one-time invitation code and send it to the teammate. It will not be displayed again.",
                  "请复制一次性邀请码并发送给同事；关闭后不再显示。",
                ),
              ),
              @html.code(secret),
              @html.button(
                type_="button",
                class="quiet-button",
                on_click=command(emit, DismissMemberInviteSecret),
                copy(state.locale, "Done", "完成"),
              ),
            ])
          None => @html.nothing
        },
      ])
    } else {
      @html.nothing
    },
    @html.section(class="api-key-panel", [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(enterprise_copy(state.locale, ApiKeys)),
          @html.p(
            enterprise_copy(state.locale, KeysAreSubjectBoundExpiringModel),
          ),
        ]),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!can_issue || state.loading,
          title=if can_issue {
            enterprise_copy(state.locale, CreateAScopedApiKey)
          } else {
            match state.trial {
              Some(trial) if trial.organization_id == membership.organization_id &&
                trial.api_key_id is Some(_) =>
                enterprise_copy(state.locale, TheOneTimeTrialApiKey)
              _ =>
                enterprise_copy(
                  state.locale,
                  AnActiveDeveloperMembershipOrAvailable,
                )
            }
          },
          on_click=command(emit, OpenApiKeyIssue),
          enterprise_copy(state.locale, CreateApiKey),
        ),
      ]),
      @html.p(class="rotation-note", [
        @html.strong(enterprise_copy(state.locale, Rotation)),
        @html.span(
          if state.trial is Some(trial) && trial.revoked_unix_ms is None {
            message(state.locale, TrialSecret)
          } else {
            enterprise_copy(state.locale, AtomicRotationIsNotAvailableYet)
          },
        ),
      ]),
      if state.trial is Some(_) {
        @html.p(message(state.locale, TrialSecret))
      } else {
        @html.nothing
      },
      if state.api_keys.length() == 0 {
        @html.p(
          class="empty-state",
          enterprise_copy(state.locale, NoApiKeysExistForThis),
        )
      } else {
        @html.div(
          class="api-key-list",
          [
            for key in state.api_keys => {
              let (status, status_class) = api_key_state(
                state.locale,
                key,
                state.machine_access.now_unix_ms,
              )
              @html.article(class="api-key-card", [
                @html.div(class="api-key-card-heading", [
                  @html.div([
                    @html.h3(key.display_name),
                    copy_detail(state, emit, key.key_id),
                  ]),
                  @html.span(
                    class="state-pill api-key-state-\{status_class}",
                    status,
                  ),
                ]),
                @html.dl(class="account-facts api-key-facts", [
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Scopes)),
                    @html.dd(
                      key.scopes
                      .map(scope => api_key_scope_label(state.locale, scope))
                      .join(", "),
                    ),
                  ]),
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Models)),
                    @html.dd(
                      if key.allowed_models.length() == 0 {
                        enterprise_copy(state.locale, AllEntitledModels)
                      } else {
                        key.allowed_models.join(", ")
                      },
                    ),
                  ]),
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Expires)),
                    @html.dd(
                      expiry_label(
                        state.locale,
                        key.expires_unix_ms,
                        state.machine_access.now_unix_ms,
                      ),
                    ),
                  ]),
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Requests)),
                    @html.dd(
                      "\{key.consumed_requests} / \{key.maximum_requests}",
                    ),
                    @html.dd(
                      if key.maximum_requests <= 0L ||
                        key.consumed_requests >= key.maximum_requests {
                        enterprise_copy(state.locale, QuotaExhausted148)
                      } else if key.consumed_requests >=
                        key.maximum_requests - key.maximum_requests / 5L {
                        enterprise_copy(state.locale, WarningLessThanRemaining)
                      } else {
                        enterprise_copy(state.locale, QuotaAvailable)
                      },
                    ),
                    @html.dd([quota_indicator(state.locale, key)]),
                  ]),
                ]),
                @html.div(class="api-key-actions", [
                  @html.button(
                    type_="button",
                    class="danger-button",
                    disabled=key.revoked_unix_ms is Some(_) ||
                      key.expires_unix_ms <= state.machine_access.now_unix_ms ||
                      state.loading,
                    on_click=command(emit, BeginRevokeApiKey(key.key_id)),
                    enterprise_copy(state.locale, Revoke),
                  ),
                ]),
              ])
            }
          ],
        )
      },
    ]),
    api_key_issue_dialog(state, emit),
    one_time_secret_dialog(state, emit),
    revoke_api_key_dialog(state, emit),
  ])
}

///|
fn agreements_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let records = [
    for agreement in state.agreements => agreement_card(state, emit, agreement)
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading provider-section-heading", [
      @html.div([
        @html.h2(
          enterprise_copy(state.locale, AgreementsRequiringYourOrganization),
        ),
        @html.p(
          enterprise_copy(state.locale, ReviewTheImmutableDocumentHashBefore),
        ),
      ]),
      @html.div(class="section-actions", [
        @html.span(class="count-pill", "\{state.agreements.length()}"),
        @html.button(
          type_="button",
          class="quiet-button compact-button",
          disabled=state.provider_requests_loading,
          on_click=command(emit, RefreshProviderRequests),
          if state.provider_requests_loading {
            enterprise_copy(state.locale, Refreshing)
          } else {
            enterprise_copy(state.locale, RefreshStatus)
          },
        ),
      ]),
    ]),
    @html.div(class="record-list", records),
  ])
}

///|
fn agreement_card(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  agreement : @portal.PortalAgreement,
) -> @rabbita.Html {
  let provider_request = signature_provider_request(state, agreement)
  let action = match agreement.state {
    ReviewRequired =>
      @html.div(class="record-actions", [
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.loading,
          on_click=command(emit, SignAgreement(agreement.agreement_id)),
          if state.loading {
            enterprise_copy(state.locale, Requesting)
          } else {
            enterprise_copy(state.locale, ReviewSign)
          },
        ),
        @html.small(
          enterprise_copy(state.locale, LunanexaRequestsAProviderHandoffAnd),
        ),
      ])
    SignatureRequested =>
      match provider_request {
        Some(record) => {
          let action_url = usable_provider_action(
            record,
            state.machine_access.now_unix_ms,
          )
          let expired = provider_action_expired(
            record,
            state.machine_access.now_unix_ms,
          )
          @html.div(class="record-actions provider-actions", [
            @html.span(
              class=provider_state_class(record.state),
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              if expired {
                enterprise_copy(state.locale, SigningLinkExpired)
              } else {
                provider_state_label(state.locale, record.state)
              },
            ),
            match action_url {
              Some(url) =>
                @html.a(
                  class="primary-action external-action",
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  escape=true,
                  enterprise_copy(state.locale, ContinueWithSignatureProvider),
                )
              None if record.state == Submitted && expired =>
                @html.button(
                  type_="button",
                  class="primary-action",
                  disabled=state.loading,
                  on_click=command(emit, SignAgreement(agreement.agreement_id)),
                  enterprise_copy(state.locale, RenewSigningSession),
                )
              None =>
                @html.small(
                  if record.action_url is Some(_) {
                    enterprise_copy(
                      state.locale,
                      TheProviderLinkWasBlockedBecause,
                    )
                  } else if expired {
                    enterprise_copy(state.locale, TheProviderLinkIsNoLonger)
                  } else {
                    enterprise_copy(state.locale, TheProviderIsPreparingASecure)
                  },
                )
            },
            @html.small(
              "\{record.provider} · \{record.environment} · \{record.record_id}",
            ),
          ])
        }
        None =>
          @html.div(class="record-actions provider-actions", [
            @html.span(
              class="state-pill provider-state-pending",
              enterprise_copy(state.locale, ProviderRequestMissing),
            ),
            @html.button(
              type_="button",
              class="primary-action",
              disabled=state.loading || state.provider_requests_loading,
              on_click=command(emit, SignAgreement(agreement.agreement_id)),
              enterprise_copy(state.locale, RepairSigningSession),
            ),
          ])
      }
    _ => @html.nothing
  }
  @html.article(class="record-card", [
    @html.div(class="record-main", [
      @html.div(class="record-title", [
        @html.h3(agreement.title),
        @html.span(
          class="state-pill",
          state_label(state.locale, agreement.state),
        ),
      ]),
      @html.p(agreement.summary),
      @html.dl(class="record-meta", [
        @html.div([
          @html.dt(enterprise_copy(state.locale, Template)),
          @html.dd([copy_detail(state, emit, agreement.template_ref)]),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, DocumentHash)),
          @html.dd([copy_detail(state, emit, agreement.rendered_document_hash)]),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Generation)),
          @html.dd("\{agreement.generation}"),
        ]),
      ]),
    ]),
    action,
  ])
}

///|
fn lease_requests_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.div(class="lease-layout", [
    @html.section(class="request-form", [
      @html.p(
        class="eyebrow",
        enterprise_copy(state.locale, ManagedCapacityRequest),
      ),
      @html.h2(enterprise_copy(state.locale, RequestAManuallyAssignedWorkspace)),
      @html.p(
        enterprise_copy(state.locale, RequestRequirementsNotASpecificMachine),
      ),
      @html.p(enterprise_copy(state.locale, DescribeYourWorkloadAndModelsThe)),
      @html.div(class="form-grid", [
        @html.div(class="field", [
          @html.label(
            for_="lease-project",
            enterprise_copy(state.locale, ProjectId),
          ),
          @html.input(
            id="lease-project",
            value=state.project_id,
            maxlength=160,
            on_input=text_command(emit, value => ProjectChanged(value)),
          ),
        ]),
        @html.div(class="field", [
          @html.label(
            for_="lease-username",
            enterprise_copy(state.locale, UnixUsername),
          ),
          @html.input(
            id="lease-username",
            value=state.unix_username,
            maxlength=32,
            auto_complete=Off,
            attrs=@html.Attrs::build()
              .aria_describedby("lease-username-help")
              .aria_invalid(
                if state.unix_username.trim() != "" &&
                  !@portal.valid_unix_username(
                    state.unix_username.trim().to_owned(),
                  ) {
                  "true"
                } else {
                  "false"
                },
              ),
            on_input=text_command(emit, value => UsernameChanged(value)),
          ),
          @html.small(
            id="lease-username-help",
            class=if state.unix_username.trim() != "" &&
              !@portal.valid_unix_username(
                state.unix_username.trim().to_owned(),
              ) {
              "field-error"
            } else {
              ""
            },
            enterprise_copy(state.locale, PasswordIsNotAcceptedUseA),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-models",
            enterprise_copy(state.locale, ModelIds),
          ),
          @html.input(
            id="lease-models",
            value=state.model_ids,
            maxlength=1000,
            on_input=text_command(emit, value => ModelsChanged(value)),
          ),
          @html.small(
            enterprise_copy(state.locale, CommaSeparatedModelsFromTheShared),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-justification",
            enterprise_copy(state.locale, BusinessJustification),
          ),
          @html.textarea(
            id="lease-justification",
            maxlength=1000,
            value=state.justification,
            on_input=text_command(emit, value => JustificationChanged(value)),
            "",
          ),
        ]),
      ]),
      @html.div(class="request-boundary", [
        @html.strong(enterprise_copy(state.locale, WhatHappensNext)),
        @html.p(enterprise_copy(state.locale, TheRequestEntersTheOperatorQueue)),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        disabled=!lease_form_valid(state),
        on_click=command(emit, SubmitLease),
        enterprise_copy(state.locale, SubmitLeaseRequest),
      ),
    ]),
    @html.section(class="request-history", [
      @html.h2(enterprise_copy(state.locale, RequestHistory)),
      if state.lease_requests.length() == 0 {
        @html.p(class="empty", enterprise_copy(state.locale, NoRequestsYet))
      } else {
        @html.div(
          class="record-list compact",
          [
            for request in state.lease_requests => {
              @html.article(class="record-card", [
                @html.div(class="record-title", [
                  @html.h3(request.submission.request_id),
                  @html.span(
                    class="state-pill",
                    request_state_label(state.locale, request.state),
                  ),
                ]),
                @html.p(
                  enterprise_copy(
                    state.locale,
                    AnOperatorReviewsPolicyHealthAnd,
                  ),
                ),
                @html.p(request.submission.justification),
                @html.dl(class="record-meta", [
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Project)),
                    @html.dd(request.submission.project_id),
                  ]),
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, Models)),
                    @html.dd(request.submission.requested_model_ids.join(", ")),
                  ]),
                  @html.div([
                    @html.dt(enterprise_copy(state.locale, AssignedNode)),
                    @html.dd(
                      request.assigned_node_id.unwrap_or(
                        enterprise_copy(state.locale, NotAssigned),
                      ),
                    ),
                  ]),
                ]),
              ])
            }
          ],
        )
      },
    ]),
  ])
}

///|
fn payment_provider_record(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  record : @commercial_integrations.ExternalRecordView,
) -> @rabbita.Html {
  let action_url = usable_provider_action(
    record,
    state.machine_access.now_unix_ms,
  )
  let expired = provider_action_expired(
    record,
    state.machine_access.now_unix_ms,
  )
  @html.article(class="provider-request-row", [
    @html.div(class="provider-request-heading", [
      @html.div([
        @html.strong(
          record.expected_amount_minor.map_or(
            enterprise_copy(state.locale, PaymentRequest),
            amount => {
              "\{record.currency.unwrap_or("—")} \{amount} · scale \{record.money_scale.unwrap_or(0)}"
            },
          ),
        ),
        copy_detail(state, emit, record.record_id),
      ]),
      @html.span(
        class=provider_state_class(record.state),
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        if expired {
          enterprise_copy(state.locale, CheckoutLinkExpired)
        } else {
          provider_state_label(state.locale, record.state)
        },
      ),
    ]),
    @html.p(
      "\{record.provider} · \{record.environment} · \{enterprise_copy(state.locale, Updated)} \{@contractdoc.format_unix_ms_beijing(record.updated_unix_ms)}",
    ),
    match action_url {
      Some(url) =>
        @html.a(
          class="primary-action external-action",
          href=url,
          target=Blank,
          rel="noopener noreferrer",
          escape=true,
          enterprise_copy(state.locale, ContinueWithPaymentProvider),
        )
      None if record.state == Submitted && expired =>
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.payment_checkout_loading,
          on_click=command(emit, SubmitPaymentCheckout),
          enterprise_copy(state.locale, RenewSecureCheckout),
        )
      None =>
        @html.small(
          if record.action_url is Some(_) {
            enterprise_copy(state.locale, TheProviderLinkWasBlockedBecause)
          } else if expired {
            enterprise_copy(state.locale, ThisLinkCannotBeOpenedRefresh)
          } else if record.state == Pending {
            enterprise_copy(state.locale, ASecureHttpsCheckoutLinkIs)
          } else {
            enterprise_copy(state.locale, NoBrowserActionIsRequiredFor)
          },
        )
    },
  ])
}

///|
fn costs_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let rows = [
    for center in state.cost_centers => {
      @html.tr([
        @html.td([
          @html.strong(center.display_name),
          copy_detail(state, emit, center.cost_center_id),
        ]),
        @html.td(center.project_count.to_string()),
        @html.td(center.provisional_spend),
        @html.td(center.budget_posture),
      ])
    }
  ]
  let payment_records = state.provider_requests.filter(record => {
    record.kind == Payment
  })
  let checkout_in_progress = payment_request_in_progress(state)
  let checkout_record = payment_request_for_quote(state)
  @html.div(class="page-stack", [
    @html.button(
      type_="button",
      class="quiet-button",
      on_click=command(emit, ExportCosts),
      enterprise_copy(state.locale, ExportCostsCsv),
    ),
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(enterprise_copy(state.locale, UsageAndCostAllocation)),
        @html.p(
          enterprise_copy(state.locale, TenantScopedProjectionsFromTheCentral),
        ),
      ]),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, ProvisionalCharges)),
        @html.strong(state.provisional_spend),
        @html.small(enterprise_copy(state.locale, CentralLedgerProjection)),
      ]),
      @html.div(class="metric", [
        @html.span(enterprise_copy(state.locale, CostCenters)),
        @html.strong(state.cost_centers.length().to_string()),
        @html.small(enterprise_copy(state.locale, TenantScoped)),
      ]),
    ]),
    @html.section(class="checkout-panel", [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(class="eyebrow", enterprise_copy(state.locale, OnlinePayment)),
          @html.h3(enterprise_copy(state.locale, PayAFinalizedBillingPeriod)),
          @html.p(
            enterprise_copy(state.locale, AmountCurrencyScaleAndRetrySafe),
          ),
        ]),
        @html.button(
          type_="button",
          class="quiet-button compact-button",
          disabled=state.provider_requests_loading,
          on_click=command(emit, RefreshProviderRequests),
          if state.provider_requests_loading {
            enterprise_copy(state.locale, Refreshing)
          } else {
            enterprise_copy(state.locale, RefreshPaymentStatus)
          },
        ),
      ]),
      match state.payment_checkout_quote {
        Some(quote) =>
          @html.div(class="checkout-summary", [
            @html.dl(class="checkout-facts", [
              @html.div([
                @html.dt(enterprise_copy(state.locale, CheckoutTotal)),
                @html.dd(class="checkout-total", quote.display_amount),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, BillingPeriod)),
                @html.dd([copy_detail(state, emit, quote.period_id)]),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, AuthoritativeAmount)),
                @html.dd(
                  class="mono",
                  "\{quote.expected_amount_minor} \{enterprise_copy(state.locale, MinorUnits)}",
                ),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, CurrencyScale)),
                @html.dd(
                  class="mono",
                  "\{quote.currency} / \{quote.money_scale}",
                ),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, LedgerRevision)),
                @html.dd(
                  "\{quote.ledger_entry_count} \{enterprise_copy(state.locale, Entries)} · \{@contractdoc.format_unix_ms_beijing(quote.ledger_revision_unix_ms)}",
                ),
              ]),
            ]),
            @html.div(class="checkout-action", [
              @html.button(
                type_="button",
                class="primary-action",
                disabled=!payment_checkout_available(state),
                attrs=@html.Attrs::build().aria_describedby(
                  "checkout-action-help",
                ),
                on_click=command(emit, SubmitPaymentCheckout),
                if state.payment_checkout_loading {
                  enterprise_copy(state.locale, CreatingSecureCheckout)
                } else if checkout_in_progress {
                  enterprise_copy(state.locale, CheckoutAlreadyInProgress)
                } else if payment_checkout_terminal(state) {
                  match checkout_record {
                    Some(record) if record.state == Settled =>
                      enterprise_copy(state.locale, BillingPeriodPaid)
                    _ => enterprise_copy(state.locale, CheckoutIsNotRenewable)
                  }
                } else if checkout_record
                  .map(record => {
                    record.state == Submitted &&
                    provider_action_expired(
                      record,
                      state.machine_access.now_unix_ms,
                    )
                  })
                  .unwrap_or(false) {
                  enterprise_copy(state.locale, RenewSecureCheckout)
                } else {
                  enterprise_copy(state.locale, CreateSecureCheckout)
                },
              ),
              @html.small(
                id="checkout-action-help",
                enterprise_copy(state.locale, CreatingACheckoutDoesNotCharge),
              ),
            ]),
          ])
        None =>
          @html.p(
            class="empty-state",
            enterprise_copy(state.locale, NoPositiveFinalizedBillingPeriodIs),
          )
      },
    ]),
    @html.section(class="provider-history", [
      @html.h3(enterprise_copy(state.locale, OnlinePaymentActivity)),
      if state.provider_requests_loading {
        @html.p(
          class="provider-loading",
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          enterprise_copy(state.locale, LoadingProviderStatus),
        )
      } else if payment_records.length() == 0 {
        @html.p(
          class="empty",
          enterprise_copy(state.locale, NoOnlinePaymentRequestsYet),
        )
      } else {
        @html.div(
          class="provider-request-list",
          [
            for record in payment_records => {
              payment_provider_record(state, emit, record)
            }
          ],
        )
      },
    ]),
    if rows.length() == 0 {
      @html.p(
        class="empty",
        enterprise_copy(state.locale, CommercialStateIsNotConfiguredFor),
      )
    } else {
      @html.section(class="data-table-panel", [
        @html.h3(enterprise_copy(state.locale, CostCenters)),
        @html.table([
          @html.thead([
            @html.tr([
              @html.th(enterprise_copy(state.locale, CostCenter)),
              @html.th(enterprise_copy(state.locale, Projects)),
              @html.th(enterprise_copy(state.locale, Spend)),
              @html.th(enterprise_copy(state.locale, Status)),
            ]),
          ]),
          @html.tbody(rows),
        ]),
      ])
    },
  ])
}

///|
fn models_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let cards = [
    for model in state.model_catalog => {
      model_card(
        state,
        emit,
        model.model_id,
        model.alias_name.unwrap_or(model.version),
        "\{model.minimum_memory_mib} MiB",
        model.alias_name is Some(_),
      )
    }
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(enterprise_copy(state.locale, SharedModelCatalog)),
        @html.p(
          enterprise_copy(state.locale, OneManagementPlaneCatalogFeedsPortal),
        ),
      ]),
    ]),
    if cards.length() == 0 {
      @html.p(
        class="empty",
        enterprise_copy(state.locale, NoApprovedModelsAreEntitledFor),
      )
    } else {
      @html.div(class="model-grid", cards)
    },
    if state.deliveries.options.templates.any(value => value.kind == "ModelApi") ||
      state.deliveries.operations.any(value => value.kind == "ModelApi") {
      delivery_panel_view(state.deliveries, state.locale, emit, "ModelApi")
    } else {
      @html.nothing
    },
  ])
}

///|
/// Resolves the user's explicit model source without silently falling back
/// from a missing, terminated or stale dedicated order to shared inference.
pub fn webide_launch_selection(
  state : EnterpriseState,
) -> (String?, String, Array[String])? {
  guard state.desktop_client is Some(client) &&
    client.client_id != "comfyui" &&
    // A loopback MoonDesk is one machine-wide profile, not a tenant-isolated
    // hosted workspace. Never issue another person's handoff into it.
    !(client.client_id == "desktop-workspace" &&
    (
      client.launch_uri.contains("127.0.0.1") ||
      client.launch_uri.contains("localhost")
    )) &&
    client.ready &&
    !client.approved_model_aliases.is_empty() else {
    return None
  }
  match state.webide_order_id {
    None =>
      if state.project_id.is_empty() {
        None
      } else {
        Some((None, state.project_id, client.approved_model_aliases))
      }
    Some(order_id) => {
      let orders = webide_orders(state)
      guard orders.filter(order => order.order_id == order_id).get(0)
        is Some(order) &&
        order.kind == DedicatedMaaS &&
        order.status == ActiveOrder &&
        order.deployment_ref is Some(_) &&
        order.model_selector is Some(model) &&
        client.approved_model_aliases.contains(model) else {
        return None
      }
      Some((Some(order_id), order.project_id, [model]))
    }
  }
}

///|
fn webide_orders(state : EnterpriseState) -> Array[SelfServiceOrderView] {
  let values : Map[String, SelfServiceOrderView] = Map([])
  for order in state.self_service.orders {
    values[order.order_id] = order
  }
  if state.self_service.order is Some(order) {
    if values
      .get(order.order_id)
      .map_or(true, previous => previous.updated_unix_ms < order.updated_unix_ms) {
      values[order.order_id] = order
    }
  }
  let result = values.values().to_array()
  result.sort_by_key(order => order.order_id)
  result
}

///|
fn desktop_connect_progress_view(state : EnterpriseState) -> @rabbita.Html {
  let client = state.desktop_client
  let model_ready = client.map_or(false, value => value.models_ready)
  let access_ready = client.map_or(false, value => value.workspace_ready)
  let percent = match state.desktop_connect_phase {
    IssuingHandoff => 50
    ClientOpened => 75
    NotStarted | ConnectFailed =>
      if model_ready && access_ready {
        25
      } else {
        0
      }
  }
  let status = match state.desktop_connect_phase {
    IssuingHandoff =>
      copy(
        state.locale,
        "Model and access checked. Issuing a single-use connection…",
        "模型与权限已检查，正在签发一次性连接…",
      )
    ClientOpened =>
      copy(
        state.locale,
        "Handoff issued. Continue in MoonDesk to see redemption and MoonGate progress.",
        "一次性交接已签发。请在 MoonDesk 查看核销与 MoonGate 接通进度。",
      )
    ConnectFailed =>
      copy(
        state.locale,
        "Connection stopped. See the error above, then retry from this button.",
        "连接已停在失败步骤。请查看上方错误，再从此按钮重试。",
      )
    NotStarted =>
      if !model_ready {
        copy(
          state.locale,
          "Waiting for a serving model.",
          "等待可调用模型。",
        )
      } else if !access_ready {
        copy(
          state.locale,
          "No active workspace access: not yet enabled, expired, or revoked.",
          "无有效工作区权限：尚未开通、已到期或已撤销。",
        )
      } else {
        copy(
          state.locale,
          "Model and access are ready. Click once to connect.",
          "模型与权限已就绪。点击一次开始贯通连接。",
        )
      }
  }
  @html.section(class="workflow-panel", [
    @html.h2(copy(state.locale, "One-click connection", "一键贯通认证")),
    @html.p(
      copy(state.locale, "Available model: ", "可用模型：") +
      client.map_or("", value => value.approved_model_aliases.join(", ")),
    ),
    @html.p(
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      status,
    ),
    @html.span(
      class="quota-track",
      attrs=@html.Attrs::build()
        .role("progressbar")
        .aria_label(copy(state.locale, "Connection progress", "贯通进度"))
        .aria_valuemin("0")
        .aria_valuemax("100")
        .aria_valuenow(percent.to_string()),
      [@html.span(class="quota-fill", style=["width:\{percent}%"], "")],
    ),
    @html.ol(class="workflow-steps", [
      @html.li(class=if model_ready { "is-complete" } else { "is-current" }, [
        @html.span("1"),
        @html.strong(copy(state.locale, "Serving model", "可调用模型")),
      ]),
      @html.li(
        class=if access_ready {
          "is-complete"
        } else if model_ready {
          "is-current"
        } else {
          ""
        },
        [
          @html.span("2"),
          @html.strong(
            copy(state.locale, "Account and lease", "账户与租约"),
          ),
        ],
      ),
      @html.li(
        class=if state.desktop_connect_phase == ClientOpened {
          "is-complete"
        } else if state.desktop_connect_phase == IssuingHandoff {
          "is-current"
        } else {
          ""
        },
        [
          @html.span("3"),
          @html.strong(
            copy(state.locale, "One-time handoff", "一次性交接"),
          ),
        ],
      ),
      @html.li(
        class=if state.desktop_connect_phase == ClientOpened {
          "is-current"
        } else {
          ""
        },
        [
          @html.span("4"),
          @html.strong(
            copy(state.locale, "MoonGate and Code", "MoonGate 与 Code"),
          ),
        ],
      ),
    ]),
  ])
}

///|
fn desktop_ide_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let is_comfyui = state.desktop_client.map_or(false, client => {
    client.client_id == "comfyui"
  })
  let (name, contract_ready, workspace_ready, models_ready, ready) = match
    state.desktop_client {
    Some(client) =>
      (
        client.display_name,
        client.contract_ready,
        client.workspace_ready,
        client.models_ready,
        client.ready,
      )
    None =>
      (enterprise_copy(state.locale, DesktopClient), false, false, false, false)
  }
  let available = ready &&
    !state.loading &&
    webide_launch_selection(state) is Some(_)
  let next_action = if state.desktop_client is None {
    enterprise_copy(state.locale, YourOperatorMustFinishDesktopIntegration)
  } else if state.desktop_client is Some(client) &&
    client.client_id == "desktop-workspace" &&
    (
      client.launch_uri.contains("127.0.0.1") ||
      client.launch_uri.contains("localhost")
    ) {
    copy(
      state.locale,
      "This legacy local MoonDesk shares one data directory. Hosted one-click access is paused until each account has its own container and saved volume; existing files were not deleted.",
      "旧版本机 MoonDesk 共用同一数据目录。已暂停一键打开，待每个账户接入独立容器和持久化卷；现有文件未删除。",
    )
  } else if state.desktop_client is Some(client) &&
    client.client_id == "comfyui" {
    copy(
      state.locale,
      "ComfyUI needs an active GPU delivery. Select an authorized resource and published template in Exclusive resource services below, then open it from that delivery. A workspace lease alone does not reserve a machine.",
      "ComfyUI 需要有效的 GPU 交付。请在下方「独占资源服务」选择已授权资源和已发布模板，再从该交付打开。仅有工作区租约不会预留机器。",
    )
  } else if !contract_ready {
    enterprise_copy(state.locale, CompleteTheMasterleaseEverythingElseStays)
  } else if !workspace_ready {
    enterprise_copy(state.locale, YourOperatorNeedsToEnableThe)
  } else if !models_ready {
    copy(
      state.locale,
      "A model must be deployed and serving before MoonDesk / MoonCode can open.",
      "请先部署并验证至少一个可调用模型，然后再打开 MoonDesk / MoonCode。",
    )
  } else if state.webide_order_id is Some(_) &&
    webide_launch_selection(state) is None {
    enterprise_copy(state.locale, TheSelectedPaidEndpointIsUnavailable)
  } else {
    enterprise_copy(state.locale, YourAccessIsReadyOpenThe)
  }
  @html.div(class="page-stack", [
    if state.desktop_clients.length() > 1 {
      @html.section(class="workflow-panel", [
        @html.h2(enterprise_copy(state.locale, ChooseYourWebide)),
        @html.p(
          enterprise_copy(
            state.locale,
            OpenYourPreferredWorkspaceCreativeWorkflows,
          ),
        ),
        @html.div(
          class="api-key-actions",
          [
            for client in state.desktop_clients => {
              let selected = state.desktop_client.map_or(false, current => {
                current.client_id == client.client_id
              })
              @html.button(
                type_="button",
                class=if selected {
                  "scope-toggle is-selected"
                } else {
                  "scope-toggle"
                },
                disabled=state.loading,
                attrs=@html.Attrs::build().aria_pressed(
                  if selected {
                    "true"
                  } else {
                    "false"
                  },
                ),
                on_click=command(emit, SelectWebIde(client.client_id)),
                client.display_name,
              )
            }
          ],
        ),
      ])
    } else {
      @html.span("")
    },
    if !is_comfyui {
      @html.section(class="workflow-panel", [
        @html.label(
          for_="webide-model-source",
          enterprise_copy(state.locale, ModelSource),
        ),
        @html.select(
          id="webide-model-source",
          disabled=state.loading,
          on_change=text_command(emit, value => SelectWebIdeOrder(value)),
          [
            @html.option(
              value="",
              selected=state.webide_order_id is None,
              enterprise_copy(state.locale, AuthorizedSharedModels),
            ),
            ..match state.webide_order_id {
              Some(id) if !webide_orders(state).any(order => {
                  order.order_id == id && order.kind == DedicatedMaaS
                }) =>
                [
                  @html.option(
                    value=id,
                    disabled=true,
                    selected=true,
                    enterprise_copy(state.locale, SelectedOrderIsUnavailable),
                  ),
                ]
              _ => []
            },
            ..[
              for order in webide_orders(state) if order.kind == DedicatedMaaS => {
                @html.option(
                  value=order.order_id,
                  disabled=order.status != ActiveOrder,
                  selected=state.webide_order_id == Some(order.order_id),
                  order.gpu_sku +
                  " · " +
                  order.model_selector.unwrap_or("") +
                  " · " +
                  order.order_id,
                )
              }
            ],
          ],
        ),
        @html.p(enterprise_copy(state.locale, DedicatedOrdersStayBoundToTheir)),
      ])
    } else {
      @html.nothing
    },
    @html.section(class="welcome-panel", [
      @html.div([
        @html.p(
          class="eyebrow",
          enterprise_copy(state.locale, SecureWebideHandoff),
        ),
        @html.h2(
          copy(
            state.locale,
            "Continue working in \{name}",
            "在 \{name} 中继续工作",
          ),
        ),
        @html.p(next_action),
      ]),
      if is_comfyui {
        @html.nothing
      } else if !contract_ready && state.desktop_client is Some(_) {
        @html.button(
          type_="button",
          class="primary-action",
          on_click=command(emit, Navigate(ContractDocuments)),
          enterprise_copy(state.locale, CompleteMasterlease),
        )
      } else {
        @html.button(
          type_="button",
          class="primary-action",
          disabled=!available,
          on_click=command(emit, LaunchDesktopClient),
          if state.loading {
            enterprise_copy(state.locale, Connecting)
          } else {
            copy(state.locale, "Open \{name}", "打开 \{name}")
          },
        )
      },
    ]),
    if !is_comfyui {
      desktop_connect_progress_view(state)
    } else {
      @html.nothing
    },
    if is_comfyui ||
      state.deliveries.options.templates.any(value => value.kind == "Workspace") ||
      state.deliveries.operations.any(value => value.kind == "Workspace") {
      delivery_panel_view(state.deliveries, state.locale, emit, "Workspace")
    } else {
      @html.nothing
    },
  ])
}

///|
fn model_card(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  name : String,
  kind : String,
  size : String,
  callable : Bool,
) -> @rabbita.Html {
  @html.article(class="model-card", [
    @html.div(class="model-icon", "M"),
    @html.h3(name),
    @html.p(kind),
    if callable {
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=command(emit, CopyDetail(kind)),
        enterprise_copy(state.locale, CopyModelAlias),
      )
    } else {
      @html.p(enterprise_copy(state.locale, NoCallableAliasPublished))
    },
    @html.p(
      if kind.has_prefix("text.") {
        enterprise_copy(state.locale, TextGeneration)
      } else if kind.has_prefix("video.") {
        enterprise_copy(state.locale, VideoGeneration)
      } else if kind.has_prefix("image.") {
        enterprise_copy(state.locale, ImageGeneration)
      } else {
        enterprise_copy(state.locale, CheckTheApprovedCapabilityBeforeCalling)
      },
    ),
    @html.dl([
      @html.div([
        @html.dt(enterprise_copy(state.locale, Availability)),
        @html.dd(enterprise_copy(state.locale, ManagedCentrally)),
      ]),
      @html.div([
        @html.dt(enterprise_copy(state.locale, Artifact)),
        @html.dd(size),
      ]),
    ]),
    @html.span(
      class="entitled",
      if callable &&
        state.api_keys.any(key => {
          key.revoked_unix_ms is None &&
          key.expires_unix_ms > state.machine_access.now_unix_ms &&
          key.scopes.contains(Inference) &&
          key.consumed_requests < key.maximum_requests &&
          (key.allowed_models.is_empty() || key.allowed_models.contains(kind))
        }) {
        enterprise_copy(state.locale, AllowedByAnActiveApiKey)
      } else {
        enterprise_copy(state.locale, NoActiveApiKeyAllowsThis)
      },
    ),
  ])
}

///|
fn notification_code_label(locale : @i18n.Locale, code : String) -> String {
  match code {
    "LeaseRequestApproved" => enterprise_copy(locale, CapacityRequestApproved)
    "LeaseAccessReady" => enterprise_copy(locale, MachineAccessIsReady)
    "LeaseExpiring" => enterprise_copy(locale, MachineAccessExpiresSoon)
    "TrialExpiring" | "TrialExpirySoon" =>
      enterprise_copy(locale, YourTrialExpiresSoon)
    "Announcement" | "PlatformAnnouncement" =>
      enterprise_copy(locale, PlatformAnnouncement)
    "LeaseTerminating" => enterprise_copy(locale, MachineAccessIsTerminating)
    "LeaseCompleted" => enterprise_copy(locale, MachineAccessEnded)
    "AgreementActionRequired" =>
      enterprise_copy(locale, AgreementActionRequired)
    "OfflineDocumentsRequired" =>
      enterprise_copy(locale, OfflineDocumentsRequired)
    "QuoteReady" => enterprise_copy(locale, QuoteIsReady)
    "OfflinePacketReady" =>
      enterprise_copy(locale, OfflineContractPacketIsReady)
    "EvidenceReviewStarted" => enterprise_copy(locale, EvidenceReviewStarted)
    "EvidenceCorrectionRequired" =>
      enterprise_copy(locale, EvidenceNeedsCorrection)
    "FulfillmentReady" => enterprise_copy(locale, ResourceFulfillmentIsReady)
    "CommercialReversalStarted" =>
      enterprise_copy(locale, CommercialReversalStarted)
    "ContractObligationOverdue" =>
      enterprise_copy(locale, ContractObligationIsOverdue)
    "ContractExpiring" => enterprise_copy(locale, ContractExpiresSoon)
    "AccessCredentialsRevoked" =>
      enterprise_copy(locale, ContractAccessWasRevoked)
    _ => code
  }
}

///|
fn notification_severity_label(
  locale : @i18n.Locale,
  severity : @notifications.NotificationSeverity,
) -> String {
  match severity {
    Information => enterprise_copy(locale, Information)
    Warning => enterprise_copy(locale, Warning)
    Critical => enterprise_copy(locale, Critical)
  }
}

///|
fn notification_lifecycle_label(
  locale : @i18n.Locale,
  lifecycle : @notifications.NotificationLifecycle,
) -> String {
  match lifecycle {
    Unread => enterprise_copy(locale, Unread)
    Read => enterprise_copy(locale, Read)
    Acknowledged => enterprise_copy(locale, Acknowledged)
    Resolved => enterprise_copy(locale, Resolved)
  }
}

///|
fn notification_detail(
  locale : @i18n.Locale,
  record : @notifications.NotificationRecord,
) -> String {
  let reference = match record.event.parameters.get("lease_ref") {
    Some(value) => value
    None => record.event.parameters.get("agreement_ref").unwrap_or("")
  }
  let explanation = match record.event.code {
    "LeaseRequestApproved" =>
      enterprise_copy(locale, AnOperatorApprovedYourCapacityRequest)
    "LeaseAccessReady" =>
      enterprise_copy(locale, YourExclusiveMachineIsReadyOpen)
    "LeaseExpiring" =>
      enterprise_copy(locale, DownloadYourWorkBeforeExpiryContact)
    "TrialExpiring" | "TrialExpirySoon" =>
      enterprise_copy(locale, YourTrialEndsWithinOneHour)
    "Announcement" | "PlatformAnnouncement" =>
      record.event.parameters
      .get("body")
      .unwrap_or(enterprise_copy(locale, OpenTheAnnouncementForDetails))
    "LeaseTerminating" => enterprise_copy(locale, NewSessionsAreBlockedWhileThe)
    "LeaseCompleted" => enterprise_copy(locale, CredentialsAreRevokedAndTheNode)
    "AgreementActionRequired" =>
      enterprise_copy(locale, ReviewTheAgreementAndCompleteThe)
    "OfflineDocumentsRequired" =>
      enterprise_copy(locale, UploadTheExecutedContractPaymentReceipt)
    "ContractExpiring" =>
      copy(
        locale,
        "Your contract ends on \{record.event.parameters.get("end_date").unwrap_or("unknown")} (\{record.event.parameters.get("days_remaining").unwrap_or("?")} days remaining). Contact the operator or request a renewal from the contract page.",
        "您的合同将于 \{record.event.parameters.get("end_date").unwrap_or("未知日期")} 到期（剩余 \{record.event.parameters.get("days_remaining").unwrap_or("?")} 天）。请联系运营方，或在合同页面发起续约。",
      )
    "AccessCredentialsRevoked" =>
      enterprise_copy(locale, YourApiCredentialsWereRevokedBecause)
    _ => enterprise_copy(locale, OpenTheRelatedRecordForDetails)
  }
  if reference == "" {
    explanation
  } else {
    "\{explanation} · \{reference}"
  }
}

///|
fn notification_email_enabled(
  state : EnterpriseState,
  topic : @notifications.NotificationTopic,
) -> Bool {
  state.notification_preferences.any(preference => {
    preference.topic == topic && preference.channels.contains(Email)
  })
}

///|
fn notification_preference_row(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  topic : @notifications.NotificationTopic,
  english : String,
  chinese : String,
) -> @rabbita.Html {
  let enabled = notification_email_enabled(state, topic)
  @html.li(class="record-card", [
    @html.div(class="record-main", [
      @html.h3(copy(state.locale, english, chinese)),
      @html.p(
        copy(
          state.locale,
          if enabled {
            "Email delivery is on."
          } else {
            "In-app only."
          },
          if enabled {
            "电子邮件投递已开启。"
          } else {
            "仅站内通知。"
          },
        ),
      ),
    ]),
    @html.div(class="record-actions", [
      @html.button(
        type_="button",
        disabled=state.loading,
        on_click=command(emit, SetNotificationEmail(topic, !enabled)),
        copy(
          state.locale,
          if enabled {
            "Disable email"
          } else {
            "Enable email"
          },
          if enabled {
            "关闭邮件"
          } else {
            "开启邮件"
          },
        ),
      ),
    ]),
  ])
}

///|
fn notifications_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let unread = state.notifications.count_if(record => record.lifecycle == Unread)
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(enterprise_copy(state.locale, NotificationInbox)),
        @html.p(
          enterprise_copy(
            state.locale,
            DurableUpdatesForAgreementsMachineAccess,
          ),
        ),
      ]),
      @html.span(
        class="count-pill",
        copy(state.locale, "\{unread} unread", "\{unread} 条未读"),
      ),
    ]),
    @html.section(
      attrs=@html.Attrs::build().aria_labelledby(
        "notification-preferences-title",
      ),
      [
        @html.h2(
          id="notification-preferences-title",
          enterprise_copy(state.locale, DeliveryPreferences),
        ),
        @html.p(
          enterprise_copy(state.locale, InAppDeliveryAlwaysRemainsEnabled),
        ),
        @html.ul(class="record-list", [
          notification_preference_row(
            state,
            emit,
            LeaseLifecycle,
            "Machine and lease lifecycle",
            "机器与租约生命周期",
          ),
          notification_preference_row(
            state,
            emit,
            CommercialAction,
            "Contracts and commercial actions",
            "合同与商务操作",
          ),
          notification_preference_row(
            state,
            emit,
            Announcement,
            "Platform announcements",
            "平台公告",
          ),
        ]),
      ],
    ),
    if state.notifications.length() == 0 {
      @html.p(class="empty", enterprise_copy(state.locale, NoNotificationsYet))
    } else {
      @html.div(
        class="record-list",
        [
          for record in state.notifications => {
            @html.article(
              class=if record.lifecycle == Unread {
                "record-card notification-card is-unread"
              } else {
                "record-card notification-card"
              },
              [
                @html.div(class="record-main", [
                  @html.div(class="record-title", [
                    @html.h3(
                      if record.event.code == "Announcement" ||
                        record.event.topic == Announcement {
                        record.event.parameters
                        .get("title")
                        .unwrap_or(
                          notification_code_label(
                            state.locale,
                            record.event.code,
                          ),
                        )
                      } else {
                        notification_code_label(state.locale, record.event.code)
                      },
                    ),
                    @html.span(
                      class="state-pill",
                      notification_severity_label(
                        state.locale,
                        record.event.severity,
                      ),
                    ),
                    @html.span(
                      class="state-pill",
                      notification_lifecycle_label(
                        state.locale,
                        record.lifecycle,
                      ),
                    ),
                  ]),
                  @html.p(notification_detail(state.locale, record)),
                  @html.dl(class="record-meta", [
                    @html.div([
                      @html.dt(enterprise_copy(state.locale, Received)),
                      @html.dd(
                        class="mono",
                        @contractdoc.format_unix_ms_beijing(
                          record.event.created_unix_ms,
                        ),
                      ),
                    ]),
                    @html.div([
                      @html.dt(enterprise_copy(state.locale, Receipt)),
                      @html.dd([
                        copy_detail(state, emit, record.event.source_receipt),
                      ]),
                    ]),
                  ]),
                ]),
                if record.lifecycle == Unread {
                  @html.div(class="record-actions", [
                    @html.button(
                      type_="button",
                      class="primary-action",
                      on_click=command(
                        emit,
                        MarkNotificationRead(
                          record.event.notification_id,
                          record.generation,
                        ),
                      ),
                      enterprise_copy(state.locale, MarkAsRead),
                    ),
                  ])
                } else {
                  @html.nothing
                },
              ],
            )
          }
        ],
      )
    },
  ])
}

///|
fn content(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  match state.route {
    Overview => overview_view(state, emit)
    SelfService => self_service_view(state, emit)
    AccountAccess => account_access_view(state, emit)
    Agreements => agreements_view(state, emit)
    LeaseRequests => lease_requests_view(state, emit)
    Notifications => notifications_view(state, emit)
    Costs => costs_view(state, emit)
    Models => models_view(state, emit)
    DesktopIde => desktop_ide_view(state, emit)
    MachineAccess => {
      let machine = { ..state.machine_access, locale: state.locale, }
      @html.div(class="page-stack", [
        match emit {
          Some(send) =>
            @machine_access.interactive_view(
              machine,
              send.map(message => MachineAccess(message)),
            )
          None => @machine_access.view(machine)
        },
        delivery_panel_view(
          state.deliveries,
          state.locale,
          emit,
          "GpuContainer",
        ),
      ])
    }
    OfflineCommerce => {
      let commerce = { ..state.offline_commerce, locale: state.locale, }
      match emit {
        Some(send) =>
          @offline_commerce.interactive_view(
            commerce,
            send.map(message => OfflineCommerce(message)),
          )
        None => @offline_commerce.view(commerce)
      }
    }
    ContractDocuments => {
      let documents = { ..state.contract_documents, locale: state.locale, }
      match emit {
        Some(send) =>
          @contract_documents.interactive_view(
            documents,
            send.map(message => ContractDocuments(message)),
          )
        None => @contract_documents.view(documents)
      }
    }
  }
}

///|
fn enterprise_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let stylesheet =
    #|:root{color-scheme:dark;--bg:#071016;--panel:#0d1820;--panel2:#111f29;--line:#223743;--ink:#ecf5f2;--muted:#91a7ad;--mint:#7ee0bd;--mint2:#35bd8d;--amber:#f1c66c}*{box-sizing:border-box}html{background:var(--bg);scroll-behavior:smooth}body{margin:0;background:radial-gradient(circle at 85% -10%,rgba(53,189,141,.12),transparent 30rem),var(--bg);color:var(--ink);font:14px/1.5 Inter,"PingFang SC","Noto Sans SC",system-ui,sans-serif}.skip-link{position:fixed;left:1rem;top:-5rem;z-index:100;padding:.65rem .9rem;background:var(--mint);color:#04251a}.skip-link:focus{top:1rem}.enterprise-root{min-height:100vh;display:grid;grid-template-columns:16rem minmax(0,1fr)}.enterprise-sidebar{position:sticky;top:0;height:100vh;padding:1.25rem 1rem;border-right:1px solid var(--line);background:rgba(7,16,22,.92);display:flex;flex-direction:column}.enterprise-brand{display:flex;gap:.75rem;align-items:center;padding:.5rem;color:var(--ink);text-decoration:none}.brand-mark{width:2.2rem;height:2.2rem;border-radius:.65rem;background:var(--mint);color:#08251c;display:grid;place-items:center;font-weight:900}.enterprise-brand span:last-child{display:flex;flex-direction:column}.enterprise-brand small{color:var(--muted)}.enterprise-sidebar nav{display:grid;gap:.3rem;margin-top:2rem}.nav-item{min-height:2.75rem;padding:.65rem .8rem;border:1px solid transparent;border-radius:.55rem;background:transparent;color:var(--muted);text-align:left;font:inherit;font-weight:700;cursor:pointer}.nav-item:hover,.nav-item:focus-visible{border-color:var(--line);color:var(--ink)}.nav-item.is-active{background:rgba(126,224,189,.1);border-color:rgba(126,224,189,.25);color:var(--mint)}.nav-link{display:flex;align-items:center;text-decoration:none}.trust-note{margin-top:auto;padding:.85rem;border:1px solid var(--line);border-radius:.7rem;background:var(--panel)}.trust-note strong{font-size:.75rem}.trust-note p{margin:.35rem 0 0;color:var(--muted);font-size:.72rem}.enterprise-main{min-width:0}.enterprise-topbar{min-height:6rem;padding:1.25rem 2rem;border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;gap:1rem}.eyebrow{margin:0 0 .2rem;color:var(--mint);font-size:.66rem;font-weight:850;letter-spacing:.12em}.enterprise-topbar h1{margin:0;font-size:1.65rem}.topbar-actions,.topbar-meta{display:flex;align-items:center;gap:.75rem}.topbar-meta{color:var(--muted)}.locale-control{display:flex;align-items:center;gap:.4rem}.locale-control label{color:var(--muted);font-size:.7rem}.locale-control select{min-height:44px;padding:.5rem 1.8rem .5rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#09151c;color:var(--ink);font:inherit}.status-dot{width:.5rem;height:.5rem;border-radius:50%;background:var(--mint2)}.role-pill,.count-pill,.state-pill,.entitled{padding:.28rem .5rem;border:1px solid var(--line);border-radius:999px;font-size:.67rem}.enterprise-content{max-width:90rem;margin:0 auto;padding:2rem}.page-stack{display:grid;gap:1.25rem}.welcome-panel,.workflow-panel,.request-form,.request-history,.data-table-panel{border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96));padding:1.35rem}.welcome-panel{display:flex;justify-content:space-between;gap:2rem;align-items:end}.welcome-panel h2{max-width:50rem;margin:.2rem 0 .5rem;font-size:clamp(1.6rem,3vw,2.6rem);line-height:1.1}.welcome-panel p:last-child{max-width:48rem;margin:0;color:var(--muted)}.primary-action,.primary-button{min-height:2.75rem;padding:.65rem 1rem;border:1px solid var(--mint2);border-radius:.55rem;background:var(--mint);color:#06251a;font:inherit;font-weight:850;cursor:pointer}.primary-action:disabled,.primary-button:disabled,.quiet-button:disabled{opacity:.42;cursor:not-allowed}.quiet-button{min-height:2.75rem;padding:.65rem 1rem;border:1px solid var(--line);border-radius:.55rem;background:var(--panel2);color:var(--ink);font:inherit;font-weight:700;cursor:pointer}.metric-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.8rem}.metric{min-height:8rem;padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.metric span,.metric small{display:block;color:var(--muted)}.metric strong{display:block;margin:.45rem 0;font-size:1.8rem}.workflow-panel h2,.section-heading h2,.request-form h2,.request-history h2{margin:0}.workflow-steps{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:1rem;padding:0;list-style:none}.workflow-steps li{display:flex;gap:.7rem}.workflow-steps>li>span{flex:0 0 2rem;height:2rem;border:1px solid var(--line);border-radius:50%;display:grid;place-items:center;color:var(--muted);font-weight:800}.workflow-steps .is-complete>span{background:var(--mint);color:#06251a}.workflow-steps .is-current>span{border-color:var(--amber);color:var(--amber)}.workflow-steps p{margin:.25rem 0 0;color:var(--muted);font-size:.75rem}.section-heading{display:flex;justify-content:space-between;gap:1rem;align-items:center}.section-heading p{margin:.3rem 0 0;color:var(--muted)}.record-list{display:grid;gap:.75rem}.record-card{display:flex;justify-content:space-between;gap:1.5rem;padding:1.1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.record-main{min-width:0}.record-title{display:flex;align-items:center;gap:.7rem}.record-title h3{margin:0}.record-card p{color:var(--muted)}.state-pill{color:var(--amber)}.record-meta{display:flex;flex-wrap:wrap;gap:1rem;margin:0}.record-meta div{min-width:9rem}.record-meta dt{color:var(--muted);font-size:.65rem}.record-meta dd{margin:.15rem 0 0}.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;overflow-wrap:anywhere}.record-actions{max-width:16rem;display:flex;flex-direction:column;align-items:flex-end;gap:.5rem}.record-actions small{color:var(--muted);text-align:right}.lease-layout{display:grid;grid-template-columns:minmax(0,1.35fr) minmax(20rem,.65fr);gap:1rem}.request-form>p{color:var(--muted)}.form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.85rem;margin:1.25rem 0}.field-wide{grid-column:1/-1}.field label{display:block;margin-bottom:.35rem;font-weight:750}.field input,.field textarea{width:100%;min-height:2.8rem;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.field textarea{min-height:7rem;resize:vertical}.field small{display:block;margin-top:.3rem;color:var(--muted)}.request-boundary{margin:1rem 0;padding:.8rem;border-left:3px solid var(--mint);background:rgba(126,224,189,.06)}.request-boundary p{margin:.25rem 0 0}.request-history .record-card{display:block}.compact .record-meta{display:grid;gap:.5rem}.empty{color:var(--muted)}.data-table-panel{overflow-x:auto}table{width:100%;border-collapse:collapse}th,td{padding:.75rem;border-bottom:1px solid var(--line);text-align:left}th{color:var(--muted);font-size:.7rem}.model-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.8rem}.model-card{position:relative;padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.model-card h3{margin:.8rem 0 .2rem}.model-card p{margin:0;color:var(--muted)}.model-card dl div{display:flex;justify-content:space-between;gap:.5rem}.model-card dt{color:var(--muted)}.model-card dd{margin:0}.model-icon{width:2.5rem;height:2.5rem;border-radius:.6rem;background:rgba(126,224,189,.13);display:grid;place-items:center;color:var(--mint);font-weight:900}.entitled{position:absolute;right:1rem;top:1rem;color:var(--mint)}.notice{margin:0 2rem;padding:.75rem 1rem;border:1px solid rgba(126,224,189,.35);border-radius:.6rem;background:rgba(126,224,189,.08);color:var(--mint)}.notice.is-error,.notice.error{border-color:rgba(241,111,111,.4);background:rgba(241,111,111,.08);color:#f5a0a0}.contract-documents{display:grid;gap:1rem}.contract-documents-header{display:flex;justify-content:space-between;align-items:end;gap:2rem;padding:1.35rem;border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96))}.contract-documents-header h1{margin:.15rem 0 .45rem}.contract-documents-header p:last-child{max-width:55rem;margin:0;color:var(--muted)}.contract-workspace{border:1px solid var(--line);border-radius:.85rem;background:var(--panel);overflow:hidden}.contract-progress{display:flex;flex-wrap:wrap;gap:.75rem;padding:.85rem 1rem;border-bottom:1px solid var(--line);color:var(--muted)}.contract-progress strong{color:var(--mint);margin-right:auto}.contract-editor-layout{display:grid;grid-template-columns:minmax(15rem,.32fr) minmax(0,1fr)}.contract-form-nav{padding:.8rem;border-right:1px solid var(--line);display:grid;align-content:start;gap:.4rem}.contract-form-tab{min-height:3.2rem;padding:.6rem .75rem;border:1px solid transparent;border-radius:.5rem;background:transparent;color:var(--ink);font:inherit;text-align:left;display:flex;flex-direction:column;cursor:pointer}.contract-form-tab small{color:var(--muted)}.contract-form-tab.is-active{border-color:rgba(126,224,189,.35);background:rgba(126,224,189,.08)}.contract-form-panel{min-width:0;padding:1.25rem}.contract-form-heading{max-width:48rem}.contract-form-heading h2{margin:.15rem 0}.contract-form-heading p:last-child{color:var(--muted)}.contract-field-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.9rem;margin:1.2rem 0}.contract-field label{display:flex;justify-content:space-between;gap:.5rem;margin-bottom:.35rem;font-weight:750}.contract-field label small{color:var(--muted);font-weight:500}.contract-field input,.contract-field select,.contract-field textarea{width:100%;min-height:44px;padding:.65rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.contract-field textarea{min-height:7rem;resize:vertical}.contract-offline-field{padding:.8rem;border:1px dashed #51636d;border-radius:.5rem;background:rgba(145,167,173,.05)}.contract-offline-field p{margin:.25rem 0 0;color:var(--muted)}.contract-actions{display:flex;flex-wrap:wrap;justify-content:flex-end;gap:.65rem;padding-top:1rem;border-top:1px solid var(--line)}.modal-backdrop{position:fixed;inset:0;z-index:50;padding:1rem;background:rgba(0,0,0,.7);display:grid;place-items:center}.confirmation-dialog{width:min(36rem,100%);padding:1.4rem;border:1px solid #416454;border-radius:.8rem;background:#0d1820;box-shadow:0 1.5rem 5rem rgba(0,0,0,.5)}.confirmation-dialog h2{margin-top:0}.confirmation-dialog p{color:var(--muted)}.dialog-actions{display:flex;justify-content:flex-end;gap:.6rem}.empty-state{padding:2rem;border:1px dashed var(--line);border-radius:.8rem;color:var(--muted)}html[lang^=zh] .eyebrow{letter-spacing:.04em}@media(max-width:74rem){.metric-grid,.model-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.workflow-steps{grid-template-columns:repeat(2,minmax(0,1fr))}.lease-layout{grid-template-columns:1fr}}@media(max-width:52rem){.enterprise-root{display:block}.enterprise-sidebar{position:relative;height:auto;border-right:0;border-bottom:1px solid var(--line)}.enterprise-sidebar nav{grid-template-columns:repeat(3,minmax(0,1fr));margin-top:1rem}.trust-note{margin-top:1rem}.enterprise-topbar{padding:1rem;align-items:flex-start}.topbar-actions{align-items:flex-end;flex-direction:column}.topbar-meta{display:none}.enterprise-content{padding:1rem}.welcome-panel,.record-card,.contract-documents-header{align-items:stretch;flex-direction:column}.metric-grid,.model-grid,.workflow-steps,.form-grid,.contract-field-grid{grid-template-columns:1fr}.contract-editor-layout{grid-template-columns:1fr}.contract-form-nav{border-right:0;border-bottom:1px solid var(--line)}.field-wide{grid-column:auto}.record-actions{max-width:none;align-items:stretch}.record-actions small{text-align:left}}@media(max-width:32rem){.enterprise-sidebar nav{grid-template-columns:1fr 1fr}.enterprise-topbar{flex-wrap:wrap}.enterprise-topbar h1{font-size:1.35rem}.topbar-actions,.locale-control{width:100%;align-items:stretch}.locale-control{display:grid}.locale-control select{width:100%}.dialog-actions{display:grid}.contract-actions>*{width:100%}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}*{transition:none!important;animation:none!important}}
  let account_styles =
    #|.danger-button{min-height:2.75rem;padding:.65rem 1rem;border:1px solid #7f4148;border-radius:.55rem;background:#27151a;color:#ffb2b8;font:inherit;font-weight:750;cursor:pointer}.danger-button:disabled{opacity:.42;cursor:not-allowed}.account-identity,.api-key-panel{padding:1.35rem;border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96))}.account-facts{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:.75rem;margin:1.1rem 0}.account-facts>div{min-width:0;padding:.7rem;border:1px solid var(--line);border-radius:.55rem;background:rgba(7,16,22,.5)}.account-facts dt{color:var(--muted);font-size:.68rem}.account-facts dd{margin:.2rem 0 0}.role-list,.api-key-actions{display:flex;flex-wrap:wrap;gap:.5rem}.account-state-active,.api-key-state-active{color:var(--mint)}.account-state-inactive,.api-key-state-expired{color:var(--amber)}.api-key-state-revoked{color:#ffadb3}.rotation-note{display:flex;gap:.65rem;padding:.8rem;border-left:3px solid var(--amber);background:rgba(241,198,108,.06);color:var(--muted)}.rotation-note strong{color:var(--amber)}.api-key-list{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem}.api-key-card{padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.api-key-card-heading{display:flex;justify-content:space-between;gap:1rem}.api-key-card h3{margin:0}.secondary{color:var(--muted);font-size:.7rem}.api-key-facts{grid-template-columns:repeat(2,minmax(0,1fr))}.api-key-actions{justify-content:flex-end}.account-dialog{max-height:calc(100vh - 2rem);overflow:auto}.account-form{display:grid;gap:.8rem}.account-form-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem}.account-form .field select{width:100%;min-height:44px;padding:.6rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.scope-picker{display:flex;flex-wrap:wrap;gap:.5rem;border:1px solid var(--line);border-radius:.55rem;padding:.75rem}.scope-picker legend{padding:0 .35rem;color:var(--muted)}.scope-toggle{min-height:44px;padding:.55rem .75rem;border:1px solid var(--line);border-radius:.5rem;background:var(--panel2);color:var(--ink);font:inherit}.scope-toggle.is-selected{border-color:var(--mint2);background:rgba(126,224,189,.1);color:var(--mint)}.one-time-secret{padding:1rem;border:1px solid var(--mint2);border-radius:.55rem;background:#06100d;color:#a8f4d5;white-space:pre-wrap;overflow-wrap:anywhere}.confirmation-scope{padding:.7rem;border:1px solid var(--line);border-radius:.5rem}@media(max-width:52rem){.account-facts,.api-key-list,.account-form-grid{grid-template-columns:1fr}.account-access-page .section-heading{align-items:stretch;flex-direction:column}.api-key-actions>*{width:100%}}@media(max-width:32rem){.account-dialog .dialog-actions>*{width:100%}}
  let provider_styles =
    #|.section-actions{display:flex;align-items:center;gap:.55rem}.compact-button{min-height:44px;padding:.5rem .75rem}.external-action{display:inline-flex;align-items:center;justify-content:center;text-align:center;text-decoration:none}.provider-actions{min-width:min(18rem,100%)}.provider-state-success{color:var(--mint)}.provider-state-error{color:#ffadb3}.provider-state-pending{color:var(--amber)}.provider-state-active{color:#a9d8ff}.checkout-panel,.provider-history{padding:1.35rem;border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96))}.checkout-panel h3,.provider-history h3{margin:0}.checkout-summary{display:grid;grid-template-columns:minmax(0,1fr) minmax(15rem,.38fr);gap:1rem;margin-top:1rem;padding:1rem;border:1px solid rgba(126,224,189,.25);border-radius:.75rem;background:rgba(126,224,189,.04)}.checkout-facts{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem;margin:0}.checkout-facts>div{min-width:0}.checkout-facts dt{color:var(--muted);font-size:.68rem}.checkout-facts dd{margin:.2rem 0 0}.checkout-total{font-size:1.45rem;font-weight:850;color:var(--mint)}.checkout-action{display:flex;flex-direction:column;align-items:stretch;justify-content:center;gap:.5rem}.checkout-action small,.provider-request-row p,.provider-request-row>small,.provider-loading{color:var(--muted)}.provider-request-list{display:grid;gap:.7rem;margin-top:1rem}.provider-request-row{display:grid;gap:.65rem;padding:1rem;border:1px solid var(--line);border-radius:.7rem;background:var(--panel)}.provider-request-heading{display:flex;justify-content:space-between;align-items:flex-start;gap:1rem}.provider-request-heading strong,.provider-request-heading span{display:block}.provider-request-row p{margin:0}.provider-request-row .external-action{justify-self:start}@media(max-width:52rem){.provider-section-heading,.section-actions,.checkout-panel .section-heading,.provider-request-heading{align-items:stretch;flex-direction:column}.checkout-summary,.checkout-facts{grid-template-columns:1fr}.provider-actions{min-width:0}.provider-request-row .external-action{justify-self:stretch}}@media(max-width:32rem){.section-actions>*{width:100%}}
  let success_notice = match state.success_message {
    Some(value) =>
      @html.p(
        class="notice",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        value,
      )
    None => @html.nothing
  }
  let error_notice = match state.error_message {
    Some(value) =>
      @html.p(
        class="notice is-error",
        attrs=@html.Attrs::build().role("alert"),
        value,
      )
    None => @html.nothing
  }
  @html.div(class="enterprise-root", [
    @html.style_tag(stylesheet),
    @html.style_tag(account_styles),
    @html.style_tag(provider_styles),
    @html.style_tag(self_service_styles()),
    @html.style_tag(
      ".confirmation-dialog{max-height:calc(100dvh - 2rem);overflow:auto}.first-call-guide pre{white-space:pre-wrap;overflow-wrap:anywhere;max-width:100%;font-size:.75rem}.copy-detail{display:inline-flex;flex-wrap:wrap;align-items:center;gap:.5rem}.copy-detail .quiet-button{min-height:44px}.quota-track{display:block;height:.55rem;background:#223743;min-width:8rem;border-radius:.3rem;overflow:hidden}.quota-fill{display:block;height:100%;background:#7ee0bd}.quota-warning .quota-fill{background:#f1c66c}",
    ),
    @html.style_tag(
      ".enterprise-topbar{flex-wrap:wrap}.topbar-actions{min-width:0;max-width:100%;flex-wrap:wrap}.organization-control{display:flex;align-items:center;gap:.4rem;min-width:0}.organization-control select{max-width:min(24rem,70vw);min-width:0;min-height:44px;padding:.5rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#09151c;color:var(--ink);font:inherit}@media(max-width:52rem){.organization-control{width:100%}.organization-control select{max-width:none;width:100%}}",
    ),
    @html.a(
      class="skip-link",
      href="#enterprise-main",
      enterprise_copy(state.locale, SkipToContent),
    ),
    navigation(state, emit),
    @html.div(class="enterprise-main", [
      page_header(state, emit),
      success_notice,
      error_notice,
      if state.error_message is Some(_) {
        guide_link(state, "error-reference", true)
      } else {
        @html.nothing
      },
      @html.main_(id="enterprise-main", class="enterprise-content", [
        guide_link(state, tutorial_page(state.route), false),
        content(state, emit),
      ]),
    ]),
  ])
}

///|
pub fn view(state : EnterpriseState) -> @rabbita.Html {
  enterprise_view(state, None)
}

///|
pub fn interactive_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage],
) -> @rabbita.Html {
  enterprise_view(state, Some(emit))
}

///|
#warnings("-alert_unstable")
pub fn render(state : EnterpriseState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
