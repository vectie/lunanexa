///|
pub(all) enum EnterpriseRoute {
  Overview
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
  route : EnterpriseRoute
  locale : @i18n.Locale
  membership : @portal.EnterpriseMembership?
  account : AccountView?
  trial : TrialEntitlementView?
  browser_sessions : Array[BrowserSessionView]
  api_keys : Array[ApiCredentialView]
  api_key_issue_draft : ApiKeyIssueDraft
  api_key_issue_open : Bool
  api_key_revoke_id : String?
  one_time_api_key_secret : OneTimeApiKeySecret?
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
  CopyOneTimeApiKeySecret
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
  MarkNotificationRead(String, Int64)
  SetNotificationEmail(@notifications.NotificationTopic, Bool)
  MachineAccess(@machine_access.MachineAccessMessage)
  OfflineCommerce(@offline_commerce.OfflineCommerceMessage)
  ContractDocuments(@contract_documents.ContractDocumentsMessage)
  ClearNotice
} derive(Eq)

///|
fn copy(locale : @i18n.Locale, english : String, chinese : String) -> String {
  if locale.is_chinese() {
    chinese
  } else {
    english
  }
}

///|
pub fn default_state(now_unix_ms : Int64) -> EnterpriseState {
  {
    route: Overview,
    locale: @i18n.default_locale(),
    membership: None,
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
      { field_id: "lessee.name", value: "Northstar Research" },
      { field_id: "lease.start_date", value: "2025-09-01" },
      { field_id: "lease.end_date", value: "2026-08-31" },
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
  {
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
      packets: [demo_packet, effective_packet],
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
    project_id: "project-vision-lab",
    unix_username: "alice",
    model_ids: "qwen3-32b, bge-m3",
    justification: "Private evaluation and adapter validation.",
  }
}

///|
pub fn EnterpriseState::update(
  self : EnterpriseState,
  message : EnterpriseMessage,
) -> EnterpriseState {
  match message {
    Navigate(route) =>
      { ..self, route, success_message: None, error_message: None }
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
      { ..self, api_key_issue_open: false, error_message: None }
    ApiKeyDisplayNameChanged(value) =>
      {
        ..self,
        api_key_issue_draft: { ..self.api_key_issue_draft, display_name: value },
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
      { ..self, loading: true, success_message: None, error_message: None }
    CopyOneTimeApiKeySecret => self
    DismissOneTimeApiKeySecret => { ..self, one_time_api_key_secret: None }
    BeginRevokeApiKey(key_id) =>
      {
        ..self,
        api_key_issue_open: false,
        api_key_revoke_id: Some(key_id),
        one_time_api_key_secret: None,
        success_message: None,
        error_message: None,
      }
    CancelRevokeApiKey => { ..self, api_key_revoke_id: None }
    ConfirmRevokeApiKey(_) =>
      { ..self, loading: true, success_message: None, error_message: None }
    ProjectChanged(value) => { ..self, project_id: value }
    UsernameChanged(value) => { ..self, unix_username: value }
    ModelsChanged(value) => { ..self, model_ids: value }
    JustificationChanged(value) => { ..self, justification: value }
    SignAgreement(_) =>
      { ..self, loading: true, success_message: None, error_message: None }
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
      { ..self, loading: true, success_message: None, error_message: None }
    LaunchDesktopClient =>
      { ..self, loading: true, success_message: None, error_message: None }
    MarkNotificationRead(_, _) => self
    SetNotificationEmail(_, _) =>
      { ..self, loading: true, success_message: None, error_message: None }
    MachineAccess(message) =>
      { ..self, machine_access: self.machine_access.update(message) }
    OfflineCommerce(message) =>
      { ..self, offline_commerce: self.offline_commerce.update(message) }
    ContractDocuments(message) =>
      { ..self, contract_documents: self.contract_documents.update(message) }
    ClearNotice => { ..self, success_message: None, error_message: None }
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
    Overview => copy(locale, "Overview", "概览")
    AccountAccess => copy(locale, "Account & API keys", "账户与 API 密钥")
    Agreements => copy(locale, "Agreements", "协议")
    LeaseRequests => copy(locale, "Lease requests", "租用申请")
    Notifications => copy(locale, "Notifications", "通知")
    Costs => copy(locale, "Usage & costs", "用量与成本")
    Models => copy(locale, "Model catalog", "模型目录")
    DesktopIde => copy(locale, "WebIDE", "WebIDE")
    MachineAccess => copy(locale, "My machine", "我的机器")
    OfflineCommerce => copy(locale, "Orders & documents", "订单与材料")
    ContractDocuments => copy(locale, "Contract forms", "合同表单")
  }
}

///|
fn state_label(
  locale : @i18n.Locale,
  state : @portal.PortalAgreementState,
) -> String {
  match state {
    ReviewRequired => copy(locale, "Review required", "待审阅")
    SignatureRequested => copy(locale, "Signature in progress", "签署中")
    Executed => copy(locale, "Executed", "已签署")
    Declined => copy(locale, "Declined", "已拒绝")
    Superseded => copy(locale, "Superseded", "已替代")
  }
}

///|
fn provider_state_label(
  locale : @i18n.Locale,
  state : @commercial_integrations.ExternalRecordState,
) -> String {
  match state {
    Pending => copy(locale, "Preparing secure link", "正在准备安全链接")
    Submitted => copy(locale, "Ready to continue", "可继续办理")
    Verified => copy(locale, "Verified", "已验证")
    Authorized => copy(locale, "Authorized", "已授权")
    Settled => copy(locale, "Paid", "已支付")
    Issued => copy(locale, "Issued", "已开具")
    Failed => copy(locale, "Failed", "失败")
    Expired => copy(locale, "Expired", "已过期")
    Voided => copy(locale, "Voided", "已作废")
    Credited => copy(locale, "Credited", "已贷记")
    Refunded => copy(locale, "Refunded", "已退款")
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
    Submitted => copy(locale, "Awaiting operator", "等待运维审核")
    Approved => copy(locale, "Node reserved", "节点已预留")
    Rejected => copy(locale, "Rejected", "已拒绝")
    Cancelled => copy(locale, "Cancelled", "已取消")
  }
}

///|
fn navigation(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let items = [
    for
      route in [
        Overview,
        AccountAccess,
        Agreements,
        LeaseRequests,
        MachineAccess,
        OfflineCommerce,
        ContractDocuments,
        Notifications,
        Costs,
        Models,
        DesktopIde,
      ] => {
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
      )
    }
  ]
  @html.aside(class="enterprise-sidebar", [
    @html.a(class="enterprise-brand", href="/enterprise/", [
      @html.span(class="brand-mark", "LN"),
      @html.span([
        @html.strong("LunaNexa"),
        @html.small(copy(state.locale, "Enterprise", "企业平台")),
      ]),
    ]),
    @html.nav(
      attrs=@html.Attrs::build().aria_label(
        copy(state.locale, "Enterprise navigation", "企业导航"),
      ),
      items,
    ),
    @html.div(class="trust-note", [
      @html.strong(copy(state.locale, "Customer boundary", "客户边界")),
      @html.p(
        copy(
          state.locale,
          "You request capacity here. LunaNexa operators select and prepare the assigned DGX node.",
          "您在此申请容量；LunaNexa 运维人员选择并准备分配的 DGX 节点。",
        ),
      ),
    ]),
  ])
}

///|
fn page_header(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let organization = match state.membership {
    Some(value) => value.organization_id
    None => copy(state.locale, "Not connected", "未连接")
  }
  @html.header(class="enterprise-topbar", [
    @html.div([
      @html.p(
        class="eyebrow",
        copy(state.locale, "ENTERPRISE CONTROL CENTER", "企业控制中心"),
      ),
      @html.h1(route_label(state.locale, state.route)),
    ]),
    @html.div(class="topbar-actions", [
      @html.div(class="locale-control", [
        @html.label(
          for_="enterprise-locale",
          copy(state.locale, "Language", "语言"),
        ),
        @html.select(
          id="enterprise-locale",
          on_change=text_command(emit, value => {
            LocaleChanged(@i18n.parse_locale(value))
          }),
          attrs=@html.Attrs::build().aria_label(
            copy(state.locale, "Interface language", "界面语言"),
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
      @html.div(class="topbar-meta", [
        @html.span(class="status-dot", ""),
        @html.span(organization),
        @html.span(
          class="role-pill",
          copy(state.locale, "Tenant scoped", "限定租户范围"),
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
            copy(
              state.locale,
              "FREE SHARED-INFERENCE TRIAL",
              "免费共享推理体验",
            ),
          ),
          @html.h2(
            if active {
              copy(state.locale, "Your trial is ready", "您的体验已就绪")
            } else {
              copy(
                state.locale,
                "Your trial has ended",
                "您的体验已结束",
              )
            },
          ),
          @html.p(
            if active {
              copy(
                state.locale,
                "Use the approved model through a quota-bound API key. This trial never grants SSH or exclusive machine access.",
                "通过受额度约束的 API 密钥使用已批准模型。体验不会授予 SSH 或独占机器权限。",
              )
            } else {
              copy(
                state.locale,
                "Your account remains active. Ask your organization for an invitation to continue with governed enterprise access.",
                "您的账户仍然有效。如需继续，请向组织申请邀请并升级为受治理的企业访问。",
              )
            },
          ),
          @html.p(
            class="secondary",
            "\{copy(state.locale, "Expires", "到期时间")} · \{@contractdoc.format_unix_ms_utc(trial.expires_unix_ms)} · \{copy(state.locale, "Requests", "请求数")} \{consumed}/\{trial.maximum_requests} · \{trial.allowed_models.join(", ")}",
          ),
        ]),
        @html.button(
          type_="button",
          class="primary-action",
          disabled=!active,
          on_click=command(emit, Navigate(AccountAccess)),
          if trial.api_key_id is None {
            copy(
              state.locale,
              "Create trial API key",
              "创建体验 API 密钥",
            )
          } else {
            copy(state.locale, "View trial API key", "查看体验 API 密钥")
          },
        ),
      ])
    }
    _ => @html.nothing
  }
  @html.div(class="page-stack", [
    trial_panel,
    @html.section(class="welcome-panel", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(state.locale, "YOUR LUNANEXA TENANT", "您的 LUNANEXA 租户"),
        ),
        @html.h2(
          copy(
            state.locale,
            "From agreement to an isolated GPU workspace",
            "从协议签署到隔离 GPU 工作区",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Review required agreements, request a time window, then follow preparation status. Node selection and activation remain operator-controlled.",
            "审阅必需协议、申请使用时段，然后跟踪准备状态。节点选择与激活仍由运维人员控制。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        on_click=command(emit, Navigate(LeaseRequests)),
        copy(state.locale, "Request capacity", "申请容量"),
      ),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(
          copy(state.locale, "Agreements to review", "待审阅协议"),
        ),
        @html.strong("\{pending}"),
        @html.small(
          copy(
            state.locale,
            "Legal signer action",
            "需要法定签署人操作",
          ),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(
          copy(state.locale, "Open lease requests", "待处理租用申请"),
        ),
        @html.strong("\{open_requests}"),
        @html.small(
          copy(state.locale, "Operator review queue", "运维审核队列"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Models entitled", "可用模型")),
        @html.strong(state.model_catalog.length().to_string()),
        @html.small(
          copy(state.locale, "Shared central catalog", "中央共享目录"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Current spend", "当前支出")),
        @html.strong(state.provisional_spend),
        @html.small(
          copy(state.locale, "Provisional central ledger", "中央台账暂计"),
        ),
      ]),
    ]),
    @html.section(class="workflow-panel", [
      @html.h2(copy(state.locale, "Lease readiness", "租用准备流程")),
      @html.ol(class="workflow-steps", [
        @html.li(class="is-complete", [
          @html.span("1"),
          @html.div([
            @html.strong(
              copy(state.locale, "Enterprise verified", "企业已验证"),
            ),
            @html.p(
              copy(
                state.locale,
                "Organization membership and signer authority recorded.",
                "组织成员身份与签署权限已记录。",
              ),
            ),
          ]),
        ]),
        @html.li(
          class=if pending == 0 { "is-complete" } else { "is-current" },
          [
            @html.span("2"),
            @html.div([
              @html.strong(
                copy(
                  state.locale,
                  "Execute required agreements",
                  "签署必需协议",
                ),
              ),
              @html.p(
                copy(
                  state.locale,
                  "External signature evidence is verified before execution.",
                  "外部签名证据验证后才标记为已签署。",
                ),
              ),
            ]),
          ],
        ),
        @html.li(class=if open_requests > 0 { "is-current" } else { "" }, [
          @html.span("3"),
          @html.div([
            @html.strong(copy(state.locale, "Request capacity", "申请容量")),
            @html.p(
              copy(
                state.locale,
                "Choose project, time window, username and required models.",
                "选择项目、时段、用户名与所需模型。",
              ),
            ),
          ]),
        ]),
        @html.li([
          @html.span("4"),
          @html.div([
            @html.strong(
              copy(
                state.locale,
                "Operator assigns one node",
                "运维分配一个节点",
              ),
            ),
            @html.p(
              copy(
                state.locale,
                "A credential reference is created; no raw password is stored.",
                "系统创建凭据引用，不存储明文密码。",
              ),
            ),
          ]),
        ]),
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
      copy(locale, "Organization administrator", "组织管理员")
    LegalSigner => copy(locale, "Legal signer", "法定签署人")
    LeaseRequester => copy(locale, "Lease requester", "租用申请人")
    BillingViewer => copy(locale, "Billing viewer", "账单查看者")
    Developer => copy(locale, "Developer", "开发者")
  }
}

///|
fn account_role_label(locale : @i18n.Locale, role : AccountRole) -> String {
  match role {
    PlatformOperator => copy(locale, "Platform operator", "平台运维人员")
    AuditReader => copy(locale, "Audit reader", "审计查看者")
    EnterpriseUser => copy(locale, "Enterprise user", "企业用户")
  }
}

///|
fn account_state_label(locale : @i18n.Locale, state : AccountState) -> String {
  match state {
    Invited => copy(locale, "Invited", "已邀请")
    Active => copy(locale, "Active", "有效")
    Suspended => copy(locale, "Suspended", "已暂停")
    Revoked => copy(locale, "Revoked", "已撤销")
  }
}

///|
fn api_key_scope_label(locale : @i18n.Locale, scope : ApiKeyScope) -> String {
  match scope {
    ModelList => copy(locale, "Model list", "模型列表")
    Inference => copy(locale, "Inference", "推理")
  }
}

///|
fn api_key_state(
  locale : @i18n.Locale,
  key : ApiCredentialView,
  now_unix_ms : Int64,
) -> (String, String) {
  if key.revoked_unix_ms is Some(_) {
    (copy(locale, "Revoked", "已撤销"), "revoked")
  } else if key.expires_unix_ms <= now_unix_ms {
    (copy(locale, "Expired", "已过期"), "expired")
  } else if key.consumed_requests >= key.maximum_requests {
    (copy(locale, "Quota exhausted", "配额已用尽"), "expired")
  } else {
    (copy(locale, "Active", "有效"), "active")
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
          copy(state.locale, "Create API key", "创建 API 密钥"),
        ),
        @html.p(
          id="api-key-issue-description",
          copy(
            state.locale,
            "The secret is shown once. Issuance also requires an effective MasterLease and Developer role.",
            "密钥仅显示一次。签发还要求有效的主租约和开发者角色。",
          ),
        ),
        @html.div(class="account-form", [
          @html.div(class="field", [
            @html.label(
              for_="api-key-project-id",
              copy(state.locale, "Billing project", "计费项目"),
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
              copy(state.locale, "Key name", "密钥名称"),
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
            @html.legend(copy(state.locale, "Scopes", "权限范围")),
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
              copy(state.locale, "Model list", "模型列表"),
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
              copy(state.locale, "Inference", "推理"),
            ),
          ]),
          @html.div(class="field", [
            @html.label(
              for_="api-key-models",
              copy(state.locale, "Allowed models", "允许的模型"),
            ),
            @html.input(
              id="api-key-models",
              value=draft.allowed_models,
              placeholder=copy(
                state.locale,
                "Optional, comma-separated aliases",
                "可选，使用英文逗号分隔别名",
              ),
              on_input=text_command(emit, value => {
                ApiKeyAllowedModelsChanged(value)
              }),
            ),
            @html.small(
              copy(
                state.locale,
                "Leave empty to allow every model granted by the account contract.",
                "留空表示允许账户合同授予的所有模型。",
              ),
            ),
          ]),
          @html.div(class="account-form-grid", [
            @html.div(class="field", [
              @html.label(
                for_="api-key-lifetime",
                copy(state.locale, "Lifetime", "有效期"),
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
                    copy(state.locale, "1 day", "1 天"),
                  ),
                  @html.option(
                    value="7",
                    selected=draft.lifetime_days == 7,
                    copy(state.locale, "7 days", "7 天"),
                  ),
                  @html.option(
                    value="30",
                    selected=draft.lifetime_days == 30,
                    copy(state.locale, "30 days", "30 天"),
                  ),
                  @html.option(
                    value="90",
                    selected=draft.lifetime_days == 90,
                    copy(state.locale, "90 days", "90 天"),
                  ),
                  @html.option(
                    value="365",
                    selected=draft.lifetime_days == 365,
                    copy(state.locale, "1 year", "1 年"),
                  ),
                ],
              ),
            ]),
            @html.div(class="field", [
              @html.label(
                for_="api-key-maximum-requests",
                copy(state.locale, "Request quota", "请求配额"),
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
            copy(state.locale, "Cancel", "取消"),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=!api_key_issue_valid(state),
            on_click=command(emit, SubmitApiKeyIssue),
            if state.loading {
              copy(state.locale, "Creating…", "正在创建…")
            } else {
              copy(state.locale, "Create key", "创建密钥")
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
          copy(state.locale, "Save this secret now", "请立即保存此密钥"),
        ),
        @html.p(
          id="api-key-secret-description",
          copy(
            state.locale,
            "LunaNexa stores only its hash. This secret cannot be retrieved after you close this dialog.",
            "LunaNexa 仅存储其哈希值。关闭此对话框后将无法再次获取该密钥。",
          ),
        ),
        @html.dl(class="account-facts", [
          @html.div([
            @html.dt(copy(state.locale, "Name", "名称")),
            @html.dd(value.display_name),
          ]),
          @html.div([
            @html.dt(copy(state.locale, "Key ID", "密钥 ID")),
            @html.dd(class="mono", value.key_id),
          ]),
        ]),
        @html.pre(class="one-time-secret", value.secret),
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, CopyOneTimeApiKeySecret),
            copy(state.locale, "Copy secret", "复制密钥"),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            on_click=command(emit, DismissOneTimeApiKeySecret),
            copy(
              state.locale,
              "I saved it — clear secret",
              "我已保存 — 清除密钥",
            ),
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
          copy(state.locale, "Revoke API key?", "撤销 API 密钥？"),
        ),
        @html.p(
          id="api-key-revoke-description",
          copy(
            state.locale,
            "Requests using this key will fail immediately. This action cannot be undone.",
            "使用此密钥的请求将立即失败。此操作无法撤销。",
          ),
        ),
        @html.p(class="confirmation-scope mono", scope),
        @html.div(class="dialog-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.loading,
            on_click=command(emit, CancelRevokeApiKey),
            copy(state.locale, "Cancel", "取消"),
          ),
          @html.button(
            type_="button",
            class="danger-button",
            disabled=state.loading,
            on_click=command(emit, ConfirmRevokeApiKey(key_id)),
            if state.loading {
              copy(state.locale, "Revoking…", "正在撤销…")
            } else {
              copy(state.locale, "Revoke key", "撤销密钥")
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
      copy(
        state.locale,
        "Account identity is unavailable.",
        "账户身份不可用。",
      ),
    )
  }
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
        @html.span(class="mono", browser_session.session_id),
        @html.span(
          "\{copy(state.locale, "Expires", "到期时间")} · \{@contractdoc.format_unix_ms_utc(browser_session.expires_unix_ms)}",
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
            copy(state.locale, "AUTHENTICATED ACCOUNT", "已认证账户"),
          ),
          @html.h2(
            copy(state.locale, "Identity & membership", "身份与成员资格"),
          ),
          @html.p(
            copy(
              state.locale,
              "Authentication is supplied by the trusted ingress. LunaNexa stores only the opaque subject and authorization records.",
              "身份验证由受信任入口提供。LunaNexa 仅存储不透明主体和授权记录。",
            ),
          ),
        ]),
        @html.span(
          class=if membership.active {
            "state-pill account-state-active"
          } else {
            "state-pill account-state-inactive"
          },
          if membership.active {
            copy(state.locale, "Active membership", "有效成员资格")
          } else {
            copy(state.locale, "Inactive membership", "成员资格已停用")
          },
        ),
      ]),
      match state.account {
        Some(account) =>
          @html.div([
            @html.dl(class="account-facts", [
              @html.div([
                @html.dt(copy(state.locale, "Account", "账户")),
                @html.dd(account.display_name),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Email", "电子邮箱")),
                @html.dd(account.email),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Account ID", "账户 ID")),
                @html.dd(class="mono", account.account_id),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Account state", "账户状态")),
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
            copy(
              state.locale,
              "Development fallback: the gateway account profile is unavailable; only portal membership is shown.",
              "开发后备方式：网关账户资料不可用；仅显示门户成员资格。",
            ),
          )
      },
      @html.dl(class="account-facts", [
        @html.div([
          @html.dt(copy(state.locale, "Organization", "组织")),
          @html.dd(class="mono", membership.organization_id),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Tenant", "租户")),
          @html.dd(class="mono", membership.tenant_ref),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Subject", "主体")),
          @html.dd(class="mono", membership.subject_ref),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Browser session", "浏览器会话")),
          @html.dd(
            copy(
              state.locale,
              "Ends on logout or reload",
              "退出登录或重新加载时结束",
            ),
          ),
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
            @html.h3(copy(state.locale, "Browser sessions", "浏览器会话")),
            ..browser_session_rows,
          ],
        )
      },
    ]),
    @html.section(class="api-key-panel", [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(copy(state.locale, "API keys", "API 密钥")),
          @html.p(
            copy(
              state.locale,
              "Keys are subject-bound, expiring, model-scoped credentials for API clients.",
              "密钥是绑定主体、具有有效期并限定模型范围的 API 客户端凭据。",
            ),
          ),
        ]),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!can_issue || state.loading,
          title=if can_issue {
            copy(
              state.locale,
              "Create a scoped API key",
              "创建限定范围的 API 密钥",
            )
          } else {
            match state.trial {
              Some(trial) if trial.organization_id == membership.organization_id &&
                trial.api_key_id is Some(_) =>
                copy(
                  state.locale,
                  "The one-time trial API key has already been issued",
                  "一次性体验 API 密钥已经签发",
                )
              _ =>
                copy(
                  state.locale,
                  "An active Developer membership or available trial is required",
                  "需要有效的开发者成员资格或可用体验权益",
                )
            }
          },
          on_click=command(emit, OpenApiKeyIssue),
          copy(state.locale, "Create API key", "创建 API 密钥"),
        ),
      ]),
      @html.p(class="rotation-note", [
        @html.strong(copy(state.locale, "Rotation", "轮换")),
        @html.span(
          copy(
            state.locale,
            "Atomic rotation is not available yet. Create a replacement, update the client, then revoke the old key.",
            "原子轮换暂不可用。请先创建替代密钥、更新客户端，再撤销旧密钥。",
          ),
        ),
      ]),
      if state.api_keys.length() == 0 {
        @html.p(
          class="empty-state",
          copy(
            state.locale,
            "No API keys exist for this account.",
            "此账户尚无 API 密钥。",
          ),
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
                    @html.span(class="mono secondary", key.key_id),
                  ]),
                  @html.span(
                    class="state-pill api-key-state-\{status_class}",
                    status,
                  ),
                ]),
                @html.dl(class="account-facts api-key-facts", [
                  @html.div([
                    @html.dt(copy(state.locale, "Scopes", "权限范围")),
                    @html.dd(
                      key.scopes
                      .map(scope => api_key_scope_label(state.locale, scope))
                      .join(", "),
                    ),
                  ]),
                  @html.div([
                    @html.dt(copy(state.locale, "Models", "模型")),
                    @html.dd(
                      if key.allowed_models.length() == 0 {
                        copy(
                          state.locale,
                          "All entitled models",
                          "所有已授权模型",
                        )
                      } else {
                        key.allowed_models.join(", ")
                      },
                    ),
                  ]),
                  @html.div([
                    @html.dt(copy(state.locale, "Expires", "到期时间")),
                    @html.dd(
                      @contractdoc.format_unix_ms_utc(key.expires_unix_ms),
                    ),
                  ]),
                  @html.div([
                    @html.dt(copy(state.locale, "Requests", "请求数")),
                    @html.dd(
                      "\{key.consumed_requests} / \{key.maximum_requests}",
                    ),
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
                    copy(state.locale, "Revoke…", "撤销…"),
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
          copy(
            state.locale,
            "Agreements requiring your organization",
            "您组织需要处理的协议",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Review the immutable document hash before opening the external signature ceremony.",
            "在打开外部签署流程前，请核对不可变文档哈希。",
          ),
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
            copy(state.locale, "Refreshing…", "正在刷新…")
          } else {
            copy(state.locale, "Refresh status", "刷新状态")
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
            copy(state.locale, "Requesting…", "正在发起…")
          } else {
            copy(state.locale, "Review & sign", "审阅并签署")
          },
        ),
        @html.small(
          copy(
            state.locale,
            "LunaNexa requests a provider handoff and never collects signing credentials.",
            "LunaNexa 仅请求服务商交接，不会收集签署凭据。",
          ),
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
                copy(
                  state.locale,
                  "Signing link expired",
                  "签署链接已过期",
                )
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
                  copy(
                    state.locale,
                    "Continue with signature provider",
                    "前往签署服务商继续办理",
                  ),
                )
              None if record.state == Submitted && expired =>
                @html.button(
                  type_="button",
                  class="primary-action",
                  disabled=state.loading,
                  on_click=command(emit, SignAgreement(agreement.agreement_id)),
                  copy(
                    state.locale,
                    "Renew signing session",
                    "重新发起签署会话",
                  ),
                )
              None =>
                @html.small(
                  if record.action_url is Some(_) {
                    copy(
                      state.locale,
                      "The provider link was blocked because it is not a valid, unexpired HTTPS action.",
                      "服务商链接不是有效且未过期的 HTTPS 操作地址，已被 LunaNexa 阻止。",
                    )
                  } else if expired {
                    copy(
                      state.locale,
                      "The provider link is no longer usable. Refresh until the provider marks it expired, then renew the session.",
                      "服务商链接已不可用。请刷新；服务商标记过期后即可重新发起会话。",
                    )
                  } else {
                    copy(
                      state.locale,
                      "The provider is preparing a secure HTTPS link. Refresh in a moment.",
                      "服务商正在准备安全 HTTPS 链接，请稍后刷新。",
                    )
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
              copy(
                state.locale,
                "Provider request missing",
                "缺少服务商请求",
              ),
            ),
            @html.button(
              type_="button",
              class="primary-action",
              disabled=state.loading || state.provider_requests_loading,
              on_click=command(emit, SignAgreement(agreement.agreement_id)),
              copy(state.locale, "Repair signing session", "修复签署会话"),
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
          @html.dt(copy(state.locale, "Template", "模板")),
          @html.dd(agreement.template_ref),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Document hash", "文档哈希")),
          @html.dd(class="mono", agreement.rendered_document_hash),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Generation", "版本代")),
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
        copy(
          state.locale,
          "NEW EXCLUSIVE CAPACITY REQUEST",
          "新建独占容量申请",
        ),
      ),
      @html.h2(
        copy(
          state.locale,
          "Request a time-bounded workspace",
          "申请有时限的工作区",
        ),
      ),
      @html.p(
        copy(
          state.locale,
          "Request requirements, not a specific machine. An operator selects one eligible DGX Spark node after policy and availability checks.",
          "请提交需求，而不是指定机器。运维人员将在策略与可用性检查后选择一个符合条件的 DGX Spark 节点。",
        ),
      ),
      @html.div(class="form-grid", [
        @html.div(class="field", [
          @html.label(
            for_="lease-project",
            copy(state.locale, "Project ID", "项目 ID"),
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
            copy(state.locale, "Unix username", "Unix 用户名"),
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
            copy(
              state.locale,
              "Password is not accepted. Use a non-reserved lowercase Unix username; access uses a short-lived credential reference.",
              "请使用非保留的小写 Unix 用户名；不接受密码。访问使用短期凭据引用。",
            ),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-models",
            copy(state.locale, "Model IDs", "模型 ID"),
          ),
          @html.input(
            id="lease-models",
            value=state.model_ids,
            maxlength=1000,
            on_input=text_command(emit, value => ModelsChanged(value)),
          ),
          @html.small(
            copy(
              state.locale,
              "Comma-separated models from the shared catalog.",
              "使用共享目录中的模型，逗号分隔。",
            ),
          ),
        ]),
        @html.div(class="field field-wide", [
          @html.label(
            for_="lease-justification",
            copy(state.locale, "Business justification", "业务说明"),
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
        @html.strong(copy(state.locale, "What happens next", "后续流程")),
        @html.p(
          copy(
            state.locale,
            "The request enters the operator queue. Approval reserves exactly one node, then provisioning, access issuance and sanitization follow the exclusive-lease state machine.",
            "申请进入运维队列。批准后只预留一个节点，随后按独占租用状态机完成配置、访问授权与清理。",
          ),
        ),
      ]),
      @html.button(
        type_="button",
        class="primary-action",
        disabled=!lease_form_valid(state),
        on_click=command(emit, SubmitLease),
        copy(state.locale, "Submit lease request", "提交租用申请"),
      ),
    ]),
    @html.section(class="request-history", [
      @html.h2(copy(state.locale, "Request history", "申请记录")),
      if state.lease_requests.length() == 0 {
        @html.p(
          class="empty",
          copy(state.locale, "No requests yet.", "暂无申请。"),
        )
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
                @html.p(request.submission.justification),
                @html.dl(class="record-meta", [
                  @html.div([
                    @html.dt(copy(state.locale, "Project", "项目")),
                    @html.dd(request.submission.project_id),
                  ]),
                  @html.div([
                    @html.dt(copy(state.locale, "Models", "模型")),
                    @html.dd(request.submission.requested_model_ids.join(", ")),
                  ]),
                  @html.div([
                    @html.dt(
                      copy(state.locale, "Assigned node", "已分配节点"),
                    ),
                    @html.dd(
                      request.assigned_node_id.unwrap_or(
                        copy(state.locale, "Not assigned", "尚未分配"),
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
            copy(state.locale, "Payment request", "支付请求"),
            amount => {
              "\{record.currency.unwrap_or("—")} \{amount} · scale \{record.money_scale.unwrap_or(0)}"
            },
          ),
        ),
        @html.span(class="mono secondary", record.record_id),
      ]),
      @html.span(
        class=provider_state_class(record.state),
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        if expired {
          copy(state.locale, "Checkout link expired", "支付链接已过期")
        } else {
          provider_state_label(state.locale, record.state)
        },
      ),
    ]),
    @html.p(
      "\{record.provider} · \{record.environment} · \{copy(state.locale, "Updated", "更新时间")} \{@contractdoc.format_unix_ms_utc(record.updated_unix_ms)}",
    ),
    match action_url {
      Some(url) =>
        @html.a(
          class="primary-action external-action",
          href=url,
          target=Blank,
          rel="noopener noreferrer",
          escape=true,
          copy(
            state.locale,
            "Continue with payment provider",
            "前往支付服务商继续办理",
          ),
        )
      None if record.state == Submitted && expired =>
        @html.button(
          type_="button",
          class="primary-action",
          disabled=state.payment_checkout_loading,
          on_click=command(emit, SubmitPaymentCheckout),
          copy(
            state.locale,
            "Renew secure checkout",
            "续期安全支付会话",
          ),
        )
      None =>
        @html.small(
          if record.action_url is Some(_) {
            copy(
              state.locale,
              "The provider link was blocked because it is not a valid, unexpired HTTPS action.",
              "服务商链接不是有效且未过期的 HTTPS 操作地址，已被 LunaNexa 阻止。",
            )
          } else if expired {
            copy(
              state.locale,
              "This link cannot be opened. Refresh before creating a replacement checkout.",
              "此链接无法继续使用。请先刷新状态，再创建新的支付请求。",
            )
          } else if record.state == Pending {
            copy(
              state.locale,
              "A secure HTTPS checkout link is being prepared.",
              "正在准备安全 HTTPS 支付链接。",
            )
          } else {
            copy(
              state.locale,
              "No browser action is required for this state.",
              "当前状态无需浏览器操作。",
            )
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
          @html.span(class="mono secondary", center.cost_center_id),
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
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(
          copy(
            state.locale,
            "Usage and cost allocation",
            "用量与成本分摊",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "Tenant-scoped projections from the central commercial ledger.",
            "来自中央商业台账的限定租户范围视图。",
          ),
        ),
      ]),
    ]),
    @html.div(class="metric-grid", [
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Provisional charges", "暂计费用")),
        @html.strong(state.provisional_spend),
        @html.small(
          copy(state.locale, "Central ledger projection", "中央台账视图"),
        ),
      ]),
      @html.div(class="metric", [
        @html.span(copy(state.locale, "Cost centers", "成本中心")),
        @html.strong(state.cost_centers.length().to_string()),
        @html.small(copy(state.locale, "Tenant scoped", "限定租户范围")),
      ]),
    ]),
    @html.section(class="checkout-panel", [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            copy(state.locale, "ONLINE PAYMENT", "在线支付"),
          ),
          @html.h3(
            copy(
              state.locale,
              "Pay a finalized billing period",
              "支付已结算账期",
            ),
          ),
          @html.p(
            copy(
              state.locale,
              "Amount, currency, scale and retry-safe idempotency are derived from the finalized billing period. You confirm before leaving LunaNexa.",
              "金额、币种、精度和可安全重试的幂等键均由已结算账期自动派生。离开 LunaNexa 前由您确认。",
            ),
          ),
        ]),
        @html.button(
          type_="button",
          class="quiet-button compact-button",
          disabled=state.provider_requests_loading,
          on_click=command(emit, RefreshProviderRequests),
          if state.provider_requests_loading {
            copy(state.locale, "Refreshing…", "正在刷新…")
          } else {
            copy(state.locale, "Refresh payment status", "刷新支付状态")
          },
        ),
      ]),
      match state.payment_checkout_quote {
        Some(quote) =>
          @html.div(class="checkout-summary", [
            @html.dl(class="checkout-facts", [
              @html.div([
                @html.dt(copy(state.locale, "Checkout total", "支付金额")),
                @html.dd(class="checkout-total", quote.display_amount),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Billing period", "账期")),
                @html.dd(class="mono", quote.period_id),
              ]),
              @html.div([
                @html.dt(
                  copy(state.locale, "Authoritative amount", "权威金额"),
                ),
                @html.dd(
                  class="mono",
                  "\{quote.expected_amount_minor} \{copy(state.locale, "minor units", "最小货币单位")}",
                ),
              ]),
              @html.div([
                @html.dt(
                  copy(state.locale, "Currency / scale", "币种 / 精度"),
                ),
                @html.dd(
                  class="mono",
                  "\{quote.currency} / \{quote.money_scale}",
                ),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Ledger revision", "台账版本")),
                @html.dd(
                  "\{quote.ledger_entry_count} \{copy(state.locale, "entries", "条记录")} · \{@contractdoc.format_unix_ms_utc(quote.ledger_revision_unix_ms)}",
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
                  copy(
                    state.locale,
                    "Creating secure checkout…",
                    "正在创建安全支付请求…",
                  )
                } else if checkout_in_progress {
                  copy(
                    state.locale,
                    "Checkout already in progress",
                    "支付请求正在处理中",
                  )
                } else if payment_checkout_terminal(state) {
                  match checkout_record {
                    Some(record) if record.state == Settled =>
                      copy(
                        state.locale,
                        "Billing period paid",
                        "该账期已支付",
                      )
                    _ =>
                      copy(
                        state.locale,
                        "Checkout is not renewable",
                        "支付请求不可续期",
                      )
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
                  copy(
                    state.locale,
                    "Renew secure checkout",
                    "续期安全支付会话",
                  )
                } else {
                  copy(
                    state.locale,
                    "Create secure checkout",
                    "创建安全支付请求",
                  )
                },
              ),
              @html.small(
                id="checkout-action-help",
                copy(
                  state.locale,
                  "Creating a checkout does not charge funds. Payment completes only after independently verified provider evidence.",
                  "创建支付请求不会直接扣款；仅在服务商独立验证证据后才会完成支付。",
                ),
              ),
            ]),
          ])
        None =>
          @html.p(
            class="empty-state",
            copy(
              state.locale,
              "No positive finalized billing period is available for online checkout.",
              "当前没有可用于在线支付的正数已结算账期。",
            ),
          )
      },
    ]),
    @html.section(class="provider-history", [
      @html.h3(
        copy(state.locale, "Online payment activity", "在线支付记录"),
      ),
      if state.provider_requests_loading {
        @html.p(
          class="provider-loading",
          attrs=@html.Attrs::build().role("status").aria_live("polite"),
          copy(
            state.locale,
            "Loading provider status…",
            "正在加载服务商状态…",
          ),
        )
      } else if payment_records.length() == 0 {
        @html.p(
          class="empty",
          copy(
            state.locale,
            "No online payment requests yet.",
            "暂无在线支付请求。",
          ),
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
        copy(
          state.locale,
          "Commercial state is not configured for this organization.",
          "此组织尚未配置商业状态。",
        ),
      )
    } else {
      @html.section(class="data-table-panel", [
        @html.h3(copy(state.locale, "Cost centers", "成本中心")),
        @html.table([
          @html.thead([
            @html.tr([
              @html.th(copy(state.locale, "Cost center", "成本中心")),
              @html.th(copy(state.locale, "Projects", "项目数")),
              @html.th(copy(state.locale, "Spend", "支出")),
              @html.th(copy(state.locale, "Status", "状态")),
            ]),
          ]),
          @html.tbody(rows),
        ]),
      ])
    },
  ])
}

///|
fn models_view(state : EnterpriseState) -> @rabbita.Html {
  let cards = [
    for model in state.model_catalog => {
      model_card(
        state,
        model.model_id,
        model.alias_name.unwrap_or(model.version),
        "\{model.minimum_memory_mib} MiB",
      )
    }
  ]
  @html.div(class="page-stack", [
    @html.section(class="section-heading", [
      @html.div([
        @html.h2(
          copy(state.locale, "Shared model catalog", "共享模型目录"),
        ),
        @html.p(
          copy(
            state.locale,
            "One management-plane catalog feeds portal requests, one-click deployments and WebIDE selectors.",
            "同一个管理平面目录为企业申请、一键部署与 WebIDE 选择器提供数据。",
          ),
        ),
      ]),
    ]),
    if cards.length() == 0 {
      @html.p(
        class="empty",
        copy(
          state.locale,
          "No approved models are entitled for this tenant.",
          "此租户暂无已批准模型。",
        ),
      )
    } else {
      @html.div(class="model-grid", cards)
    },
  ])
}

///|
fn desktop_ide_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let (
    name,
    lifetime,
    connected,
    contract_ready,
    workspace_ready,
    models_ready,
    ready,
    aliases,
  ) = match state.desktop_client {
    Some(client) =>
      (
        client.display_name,
        client.handoff_lifetime_ms / 1000L,
        client.connected_handoffs,
        client.contract_ready,
        client.workspace_ready,
        client.models_ready,
        client.ready,
        client.approved_model_aliases,
      )
    None =>
      (
        copy(state.locale, "Desktop client", "桌面客户端"),
        0L,
        0,
        false,
        false,
        false,
        false,
        [],
      )
  }
  let available = ready && !state.loading
  let next_action = if state.desktop_client is None {
    copy(
      state.locale,
      "Your operator must finish desktop integration setup.",
      "需要运维人员完成桌面集成设置。",
    )
  } else if !contract_ready {
    copy(
      state.locale,
      "Complete the MasterLease. Everything else stays saved.",
      "请完成主租约，其余设置会保留。",
    )
  } else if !workspace_ready {
    copy(
      state.locale,
      "Your operator needs to enable the prepared workspace lease.",
      "需要运维人员启用已准备的工作区租约。",
    )
  } else if !models_ready {
    copy(
      state.locale,
      "Your operator needs to approve at least one model alias.",
      "需要运维人员批准至少一个模型别名。",
    )
  } else {
    copy(
      state.locale,
      "Everything is ready. Open the desktop and start working.",
      "所有项目均已就绪。打开桌面并开始工作。",
    )
  }
  @html.div(class="page-stack", [
    @html.section(class="welcome-panel", [
      @html.div([
        @html.p(
          class="eyebrow",
          copy(state.locale, "SECURE DESKTOP HANDOFF", "安全桌面交接"),
        ),
        @html.h2(
          copy(
            state.locale,
            "Continue your leased workspace in \{name}",
            "在 \{name} 中继续使用租赁工作区",
          ),
        ),
        @html.p(next_action),
      ]),
      if !contract_ready && state.desktop_client is Some(_) {
        @html.button(
          type_="button",
          class="primary-action",
          on_click=command(emit, Navigate(ContractDocuments)),
          copy(state.locale, "Complete MasterLease", "完成主租约"),
        )
      } else {
        @html.button(
          type_="button",
          class="primary-action",
          disabled=!available,
          on_click=command(emit, LaunchDesktopClient),
          if state.loading {
            copy(state.locale, "Connecting…", "正在连接…")
          } else {
            copy(state.locale, "Open desktop WebIDE", "打开桌面 WebIDE")
          },
        )
      },
    ]),
    @html.section(class="workflow-panel", [
      @html.h2(copy(state.locale, "Your access journey", "您的访问流程")),
      @html.ul(class="workflow-steps", [
        @html.li(class="is-complete", [
          @html.span("1"),
          @html.div([
            @html.strong(copy(state.locale, "Signed in", "已登录")),
            @html.p(
              copy(
                state.locale,
                "Your identity and Developer membership are verified.",
                "您的身份和开发者成员资格已验证。",
              ),
            ),
          ]),
        ]),
        @html.li(
          class=if contract_ready { "is-complete" } else { "is-current" },
          [
            @html.span("2"),
            @html.div([
              @html.strong(copy(state.locale, "MasterLease", "主租约")),
              @html.p(
                if contract_ready {
                  copy(
                    state.locale,
                    "Contract is effective.",
                    "合同已生效。",
                  )
                } else {
                  copy(
                    state.locale,
                    "Review and complete the contract template.",
                    "查看并完成合同模板。",
                  )
                },
              ),
            ]),
          ],
        ),
        @html.li(
          class=if workspace_ready {
            "is-complete"
          } else if contract_ready {
            "is-current"
          } else {
            ""
          },
          [
            @html.span("3"),
            @html.div([
              @html.strong(
                copy(state.locale, "Workspace access", "工作区访问"),
              ),
              @html.p(
                if workspace_ready {
                  copy(
                    state.locale,
                    "Developer lease is active.",
                    "开发者租约已生效。",
                  )
                } else {
                  copy(
                    state.locale,
                    "Waiting for operator enablement.",
                    "等待运维人员启用。",
                  )
                },
              ),
            ]),
          ],
        ),
        @html.li(
          class=if models_ready {
            "is-complete"
          } else if contract_ready && workspace_ready {
            "is-current"
          } else {
            ""
          },
          [
            @html.span("4"),
            @html.div([
              @html.strong(
                copy(state.locale, "Approved models", "已批准模型"),
              ),
              @html.p(
                if models_ready {
                  aliases.join(", ")
                } else {
                  copy(
                    state.locale,
                    "No model alias is ready yet.",
                    "尚无可用模型别名。",
                  )
                },
              ),
            ]),
          ],
        ),
        @html.li(class=if ready { "is-current" } else { "" }, [
          @html.span("5"),
          @html.div([
            @html.strong(copy(state.locale, "Open WebIDE", "打开 WebIDE")),
            @html.p(
              copy(
                state.locale,
                "One click opens \{name} with a \{lifetime}-second single-use handoff.",
                "点击一次即可通过 \{lifetime} 秒有效的单次交接打开 \{name}。",
              ),
            ),
          ]),
        ]),
      ]),
      @html.p(
        class="request-boundary",
        copy(
          state.locale,
          "Approved models: \{aliases.length()} · Previous connections: \{connected} · Access remains lease-bound",
          "已批准模型：\{aliases.length()} · 历史连接：\{connected} · 访问权限仍受租约约束",
        ),
      ),
    ]),
  ])
}

///|
fn model_card(
  state : EnterpriseState,
  name : String,
  kind : String,
  size : String,
) -> @rabbita.Html {
  @html.article(class="model-card", [
    @html.div(class="model-icon", "M"),
    @html.h3(name),
    @html.p(kind),
    @html.dl([
      @html.div([
        @html.dt(copy(state.locale, "Availability", "可用性")),
        @html.dd(copy(state.locale, "Managed centrally", "中央托管")),
      ]),
      @html.div([
        @html.dt(copy(state.locale, "Artifact", "制品")),
        @html.dd(size),
      ]),
    ]),
    @html.span(class="entitled", copy(state.locale, "Entitled", "已授权")),
  ])
}

///|
fn notification_code_label(locale : @i18n.Locale, code : String) -> String {
  match code {
    "LeaseRequestApproved" =>
      copy(locale, "Capacity request approved", "容量申请已批准")
    "LeaseAccessReady" =>
      copy(locale, "Machine access is ready", "机器访问已就绪")
    "LeaseExpiring" =>
      copy(locale, "Machine access expires soon", "机器访问即将到期")
    "LeaseTerminating" =>
      copy(locale, "Machine access is terminating", "机器访问正在终止")
    "LeaseCompleted" =>
      copy(locale, "Machine access ended", "机器访问已结束")
    "AgreementActionRequired" =>
      copy(locale, "Agreement action required", "协议需要处理")
    "OfflineDocumentsRequired" =>
      copy(locale, "Offline documents required", "需要线下文件")
    "QuoteReady" => copy(locale, "Quote is ready", "报价已生成")
    "OfflinePacketReady" =>
      copy(
        locale, "Offline contract packet is ready", "线下合同文件包已生成",
      )
    "EvidenceReviewStarted" =>
      copy(locale, "Evidence review started", "凭证审核已开始")
    "EvidenceCorrectionRequired" =>
      copy(locale, "Evidence needs correction", "凭证需要修正")
    "FulfillmentReady" =>
      copy(locale, "Resource fulfillment is ready", "资源交付已就绪")
    "CommercialReversalStarted" =>
      copy(locale, "Commercial reversal started", "商务撤销已开始")
    "ContractObligationOverdue" =>
      copy(
        locale, "Contract obligation is overdue", "合同履约义务已逾期",
      )
    "ContractExpiring" =>
      copy(locale, "Contract expires soon", "合同即将到期")
    "AccessCredentialsRevoked" =>
      copy(locale, "Contract access was revoked", "合同访问权限已撤销")
    _ => code
  }
}

///|
fn notification_severity_label(
  locale : @i18n.Locale,
  severity : @notifications.NotificationSeverity,
) -> String {
  match severity {
    Information => copy(locale, "Information", "提示")
    Warning => copy(locale, "Warning", "警告")
    Critical => copy(locale, "Critical", "严重")
  }
}

///|
fn notification_lifecycle_label(
  locale : @i18n.Locale,
  lifecycle : @notifications.NotificationLifecycle,
) -> String {
  match lifecycle {
    Unread => copy(locale, "Unread", "未读")
    Read => copy(locale, "Read", "已读")
    Acknowledged => copy(locale, "Acknowledged", "已确认")
    Resolved => copy(locale, "Resolved", "已解决")
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
      copy(
        locale, "An operator approved your capacity request. Provisioning starts next.",
        "运维人员已批准您的容量申请，接下来将开始配置。",
      )
    "LeaseAccessReady" =>
      copy(
        locale, "Your exclusive machine is ready. Open its access details before the credential expires.",
        "您的独占机器已就绪。请在凭据到期前查看访问详情。",
      )
    "LeaseExpiring" =>
      copy(
        locale, "Save your work and request an extension if needed. Access closes automatically at the lease boundary.",
        "请保存工作；如有需要请申请延期。访问权限将在租约边界自动关闭。",
      )
    "LeaseTerminating" =>
      copy(
        locale, "New sessions are blocked while the node is drained and sanitized.",
        "节点正在排空并清理，新的会话已被阻止。",
      )
    "LeaseCompleted" =>
      copy(
        locale, "Credentials are revoked and the node has left your tenant boundary.",
        "凭据已撤销，节点已离开您的租户边界。",
      )
    "AgreementActionRequired" =>
      copy(
        locale, "Review the agreement and complete the requested action.", "请审阅协议并完成所需操作。",
      )
    "OfflineDocumentsRequired" =>
      copy(
        locale, "Upload the executed contract, payment receipt, and invoice evidence to continue.",
        "请上传已签署合同、付款回执和发票证据以继续流程。",
      )
    "ContractExpiring" =>
      copy(
        locale,
        "Your contract ends on \{record.event.parameters.get("end_date").unwrap_or("unknown")} (\{record.event.parameters.get("days_remaining").unwrap_or("?")} days remaining). Contact the operator or request a renewal from the contract page.",
        "您的合同将于 \{record.event.parameters.get("end_date").unwrap_or("未知日期")} 到期（剩余 \{record.event.parameters.get("days_remaining").unwrap_or("?")} 天）。请联系运营方，或在合同页面发起续约。",
      )
    "AccessCredentialsRevoked" =>
      copy(
        locale, "Your API credentials were revoked because the master lease closed.",
        "由于主租赁合同已关闭，您的 API 访问凭据已被撤销。",
      )
    _ =>
      copy(
        locale, "Open the related record for details.", "请打开相关记录查看详情。",
      )
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
        @html.h2(copy(state.locale, "Notification inbox", "通知收件箱")),
        @html.p(
          copy(
            state.locale,
            "Durable updates for agreements, machine access, expiry, and offline reconciliation.",
            "查看协议、机器访问、到期与线下对账的持久化更新。",
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
          copy(state.locale, "Delivery preferences", "投递偏好"),
        ),
        @html.p(
          copy(
            state.locale,
            "In-app delivery always remains enabled. External delivery starts only when the platform adapter is configured.",
            "站内通知始终开启。仅在平台配置外部投递适配器后，外部投递才会生效。",
          ),
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
        ]),
      ],
    ),
    if state.notifications.length() == 0 {
      @html.p(
        class="empty",
        copy(state.locale, "No notifications yet.", "暂无通知。"),
      )
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
                      notification_code_label(state.locale, record.event.code),
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
                      @html.dt(copy(state.locale, "Received", "接收时间")),
                      @html.dd(
                        class="mono",
                        @contractdoc.format_unix_ms_utc(
                          record.event.created_unix_ms,
                        ),
                      ),
                    ]),
                    @html.div([
                      @html.dt(copy(state.locale, "Receipt", "回执")),
                      @html.dd(class="mono", record.event.source_receipt),
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
                      copy(state.locale, "Mark as read", "标记为已读"),
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
    AccountAccess => account_access_view(state, emit)
    Agreements => agreements_view(state, emit)
    LeaseRequests => lease_requests_view(state, emit)
    Notifications => notifications_view(state, emit)
    Costs => costs_view(state, emit)
    Models => models_view(state)
    DesktopIde => desktop_ide_view(state, emit)
    MachineAccess => {
      let machine = { ..state.machine_access, locale: state.locale }
      match emit {
        Some(send) =>
          @machine_access.interactive_view(
            machine,
            send.map(message => MachineAccess(message)),
          )
        None => @machine_access.view(machine)
      }
    }
    OfflineCommerce => {
      let commerce = { ..state.offline_commerce, locale: state.locale }
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
      let documents = { ..state.contract_documents, locale: state.locale }
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
    @html.a(
      class="skip-link",
      href="#enterprise-main",
      copy(state.locale, "Skip to content", "跳到内容"),
    ),
    navigation(state, emit),
    @html.div(class="enterprise-main", [
      page_header(state, emit),
      success_notice,
      error_notice,
      @html.main_(id="enterprise-main", class="enterprise-content", [
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
