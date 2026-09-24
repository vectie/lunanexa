///|
pub(all) enum SelfServiceProduct {
  SharedMaaS
  DedicatedMaaS
  BareGpu
} derive(Debug, Eq)

///|
pub(all) enum OrganizationSetupMode {
  CreateCompany
  JoinCompany
} derive(Debug, Eq)

///|
pub(all) enum SelfServiceStep {
  ChooseService
  Organization
  Capacity
  Quote
  ContractPayment
  Provisioning
} derive(Debug, Eq)

///|
pub(all) enum MachineOrderStatus {
  AwaitingPayment
  PaymentSettled
  ProvisioningOrder
  ActiveOrder
  CancellationPending
  TerminationPending
  CompensationPending
  CancelledOrder
  TerminatedOrder
  FailedOrder
} derive(Debug, Eq)

///|
/// Redacted organization projection returned to the browser.
pub(all) struct SelfServiceOrganizationSummary {
  organization_id : String
  display_name : String
  state : @commercial.OrganizationState
  verification_ref : String?
  legal_profile : @commercial.OrganizationLegalProfile?
} derive(Debug, Eq, FromJson)

///|
pub(all) struct SelfServiceOrganizationVerificationRecord {
  provider : String
  state : String
  action_url : String?
  action_expires_unix_ms : Int64?
  updated_unix_ms : Int64
} derive(Debug, Eq, FromJson)

///|
pub(all) struct SelfServiceOrganizationVerificationView {
  required : Bool
  record : SelfServiceOrganizationVerificationRecord?
  blocker_code : String?
} derive(Debug, Eq, FromJson)

///|
/// Browser view returned by `GET /v1/portal/self/organizations`.
pub(all) struct SelfServiceOrganizationView {
  organization : SelfServiceOrganizationSummary
  membership : @portal.EnterpriseMembership
  default_project_id : String?
  verification : SelfServiceOrganizationVerificationView?
} derive(Debug, Eq, FromJson)

///|
pub(all) struct SelfServiceOfferingView {
  offering_id : String
  kind : SelfServiceProduct
  display_name : String
  gpu_sku : String
  accelerator_count : Int
  accelerator_memory_mib : Int
  regions : Array[String]
  minimum_duration_hours : Int
  maximum_duration_hours : Int
  price_summary : String
  allowed_model_template_refs : Array[String]
  available : Bool
} derive(Debug, Eq)

///|
pub(all) struct SelfServiceQuoteView {
  quote_id : String
  offering_id : String
  display_amount : String
  expected_amount_minor : Int64
  currency : String
  money_scale : Int
  valid_until_unix_ms : Int64
  terms_digest : String
} derive(Debug, Eq)

///|
pub(all) struct SelfServiceOrderView {
  order_id : String
  kind : SelfServiceProduct
  status : MachineOrderStatus
  project_id : String
  gpu_sku : String
  region : String
  duration_hours : Int
  model_selector : String?
  display_amount : String
  lease_ref : String?
  deployment_ref : String?
  generation : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq)

///| Payment-provider projection returned with a newly created machine order.

///|
/// It intentionally contains no provider secret or physical node identity.
pub(all) struct SelfServiceCheckoutView {
  state : String
  provider : String
  action_url : String?
  action_expires_unix_ms : Int64?
} derive(Debug, Eq)

///|
pub(all) struct SelfServiceTermsView {
  template_id : String
  version : String
  locale : String
  rendered_document_hash : String
  document_uri : String
} derive(Debug, Eq)

///|
pub(all) struct SelfServiceState {
  selected_product : SelfServiceProduct?
  step : SelfServiceStep
  organization_mode : OrganizationSetupMode
  subject_kind : String
  legal_name : String
  display_name : String
  country_region : String
  registered_address : String
  registration_number : String
  tax_identifier : String
  billing_contact_name : String
  billing_email : String
  invitation_code : String
  offerings : Array[SelfServiceOfferingView]
  offerings_loading : Bool
  offerings_loaded : Bool
  offerings_error : String?
  selected_offering_id : String
  project_id : String
  unix_username : String
  region : String
  duration_hours : Int
  model_selector : String
  model_template_ref : String
  quote : SelfServiceQuoteView?
  order : SelfServiceOrderView?
  orders : Array[SelfServiceOrderView]
  checkout : SelfServiceCheckoutView?
  terms : SelfServiceTermsView?
  terms_accepted : Bool
  terms_reviewed : Bool
  action_loading : Bool
  action_error : String?
} derive(Debug, Eq)

///|
pub(all) enum SelfServiceMessage {
  SelectProduct(SelfServiceProduct)
  SelectOrganization(String)
  ChooseOrganizationMode(OrganizationSetupMode)
  SubjectKindChanged(String)
  LegalNameChanged(String)
  CompanyDisplayNameChanged(String)
  CountryRegionChanged(String)
  RegisteredAddressChanged(String)
  RegistrationNumberChanged(String)
  TaxIdentifierChanged(String)
  BillingContactNameChanged(String)
  BillingEmailChanged(String)
  InvitationCodeChanged(String)
  SubmitCreateCompany
  SubmitJoinCompany
  RefreshOrganizations
  ContinueWithOrganization
  RefreshOfferings
  SelectOffering(String)
  SelfServiceProjectChanged(String)
  UnixUsernameChanged(String)
  RegionChanged(String)
  DurationChanged(Int)
  ModelSelectorChanged(String)
  ModelTemplateChanged(String)
  RequestQuote
  CreateMachineOrder
  AcceptMachineTerms
  ConfirmMachineTermsReviewed
  RefreshMachineOrders
  CancelMachineOrder(String, Int64)
  TerminateMachineOrder(String, Int64)
  ViewProvisioning
  PreviousSelfServiceStep
  RestartSelfService
  DismissSelfServiceError
} derive(Debug, Eq)

///|
pub fn default_self_service_state() -> SelfServiceState {
  {
    selected_product: None,
    step: ChooseService,
    organization_mode: CreateCompany,
    subject_kind: "Company",
    legal_name: "",
    display_name: "",
    country_region: "",
    registered_address: "",
    registration_number: "",
    tax_identifier: "",
    billing_contact_name: "",
    billing_email: "",
    invitation_code: "",
    offerings: [],
    offerings_loading: false,
    offerings_loaded: false,
    offerings_error: None,
    selected_offering_id: "",
    project_id: "",
    unix_username: "",
    region: "",
    duration_hours: 24,
    model_selector: "",
    model_template_ref: "",
    quote: None,
    order: None,
    orders: [],
    checkout: None,
    terms: None,
    terms_accepted: false,
    terms_reviewed: false,
    action_loading: false,
    action_error: None,
  }
}

///|
fn demo_self_service_state(now_unix_ms : Int64) -> SelfServiceState {
  let order : SelfServiceOrderView = {
    order_id: "machine-order-demo",
    kind: DedicatedMaaS,
    status: ProvisioningOrder,
    project_id: "project-vision-lab",
    gpu_sku: "NVIDIA RTX 5060 Ti",
    region: "cn-north-1",
    duration_hours: 168,
    model_selector: Some("qwen3-32b"),
    display_amount: "CNY 1,444.80",
    lease_ref: Some("exclusive-lease-demo"),
    deployment_ref: Some("deployment-qwen-demo"),
    generation: 3L,
    updated_unix_ms: now_unix_ms - 30000L,
  }
  {
    ..default_self_service_state(),
    selected_product: Some(DedicatedMaaS),
    step: Capacity,
    offerings: [
      {
        offering_id: "dedicated-rtx-5060-ti",
        kind: DedicatedMaaS,
        display_name: "Dedicated model endpoint",
        gpu_sku: "NVIDIA RTX 5060 Ti",
        accelerator_count: 1,
        accelerator_memory_mib: 16384,
        regions: ["cn-north-1", "cn-east-1"],
        minimum_duration_hours: 24,
        maximum_duration_hours: 720,
        price_summary: "From CNY 8.60 / hour",
        allowed_model_template_refs: ["qwen-template-v1"],
        available: true,
      },
      {
        offering_id: "bare-rtx-2080",
        kind: BareGpu,
        display_name: "Bare GPU workspace",
        gpu_sku: "NVIDIA RTX 2080",
        accelerator_count: 1,
        accelerator_memory_mib: 8192,
        regions: ["cn-north-1"],
        minimum_duration_hours: 24,
        maximum_duration_hours: 720,
        price_summary: "From CNY 3.20 / hour",
        allowed_model_template_refs: [],
        available: true,
      },
    ],
    offerings_loaded: true,
    selected_offering_id: "dedicated-rtx-5060-ti",
    project_id: "project-vision-lab",
    region: "cn-north-1",
    duration_hours: 168,
    model_selector: "qwen3-32b",
    model_template_ref: "qwen-template-v1",
    quote: Some({
      quote_id: "quote-dedicated-demo",
      offering_id: "dedicated-rtx-5060-ti",
      display_amount: "CNY 1,444.80",
      expected_amount_minor: 144480L,
      currency: "CNY",
      money_scale: 2,
      valid_until_unix_ms: now_unix_ms + 900000L,
      terms_digest: "sha256:demo-machine-terms",
    }),
    order: Some(order),
    orders: [order],
    checkout: Some({
      state: "Submitted",
      provider: "qualified-services-demo",
      action_url: Some("https://pay.example.invalid/checkout/machine-demo"),
      action_expires_unix_ms: Some(now_unix_ms + 900000L),
    }),
    terms: Some({
      template_id: "machine-self-service-v1",
      version: "v1",
      locale: "en",
      rendered_document_hash: "sha256:" + "d".repeat(64),
      document_uri: "/docs/legal/machine-self-service-v1.html",
    }),
    terms_accepted: true,
    terms_reviewed: true,
  }
}

///|
fn SelfServiceState::update(
  self : SelfServiceState,
  message : SelfServiceMessage,
) -> SelfServiceState {
  match message {
    SelectProduct(product) =>
      {
        ..self,
        selected_product: Some(product),
        selected_offering_id: "",
        region: "",
        model_selector: "",
        model_template_ref: "",
        quote: None,
        order: None,
        checkout: None,
        terms_accepted: false,
        terms_reviewed: false,
        action_error: None,
      }
    SelectOrganization(_) => self
    ChooseOrganizationMode(mode) =>
      { ..self, organization_mode: mode, action_error: None, }
    SubjectKindChanged(value) => { ..self, subject_kind: value, }
    LegalNameChanged(value) => { ..self, legal_name: value, }
    CompanyDisplayNameChanged(value) => { ..self, display_name: value, }
    CountryRegionChanged(value) => { ..self, country_region: value, }
    RegisteredAddressChanged(value) => { ..self, registered_address: value, }
    RegistrationNumberChanged(value) => { ..self, registration_number: value, }
    TaxIdentifierChanged(value) => { ..self, tax_identifier: value, }
    BillingContactNameChanged(value) => { ..self, billing_contact_name: value, }
    BillingEmailChanged(value) => { ..self, billing_email: value, }
    InvitationCodeChanged(value) => { ..self, invitation_code: value, }
    SubmitCreateCompany
    | SubmitJoinCompany
    | RefreshOrganizations
    | RequestQuote
    | CreateMachineOrder
    | AcceptMachineTerms
    | RefreshMachineOrders
    | CancelMachineOrder(_, _)
    | TerminateMachineOrder(_, _) =>
      { ..self, action_loading: true, action_error: None, }
    ConfirmMachineTermsReviewed =>
      { ..self, terms_reviewed: true, action_error: None, }
    ContinueWithOrganization => { ..self, step: Capacity, action_error: None, }
    RefreshOfferings =>
      { ..self, offerings_loading: true, offerings_error: None, }
    SelectOffering(offering_id) => {
      guard self.offerings
        .iter()
        .find_first(value => value.offering_id == offering_id && value.available)
        is Some(offering) else {
        return self
      }
      let template = offering.allowed_model_template_refs.get(0).unwrap_or("")
      {
        ..self,
        selected_offering_id: offering_id,
        region: "",
        model_template_ref: template,
        quote: None,
        action_error: None,
      }
    }
    SelfServiceProjectChanged(value) => { ..self, project_id: value, }
    UnixUsernameChanged(value) => { ..self, unix_username: value, }
    RegionChanged(value) => { ..self, region: value, quote: None, }
    DurationChanged(value) => { ..self, duration_hours: value, quote: None, }
    ModelSelectorChanged(value) =>
      { ..self, model_selector: value, quote: None, }
    ModelTemplateChanged(value) =>
      { ..self, model_template_ref: value, quote: None, }
    ViewProvisioning => { ..self, step: Provisioning, action_error: None, }
    PreviousSelfServiceStep =>
      {
        ..self,
        step: match self.step {
          ChooseService => ChooseService
          Organization => ChooseService
          Capacity => Organization
          Quote => Capacity
          ContractPayment => Quote
          Provisioning => ContractPayment
        },
        action_error: None,
      }
    RestartSelfService => default_self_service_state()
    DismissSelfServiceError => { ..self, action_error: None, }
  }
}

///|
pub fn company_creation_valid(state : SelfServiceState) -> Bool {
  state.legal_name.trim() != "" &&
  state.legal_name.length() <= 240 &&
  state.display_name.trim() != "" &&
  state.display_name.length() <= 128 &&
  (state.subject_kind == "Company" || state.subject_kind == "Individual") &&
  (
    state.subject_kind == "Individual" ||
    state.registration_number.trim() != "" ||
    state.tax_identifier.trim() != ""
  ) &&
  state.country_region.trim().length() == 2 &&
  state.registered_address.trim() != "" &&
  state.registered_address.length() <= 500 &&
  state.billing_contact_name.trim() != "" &&
  state.billing_contact_name.length() <= 128 &&
  state.billing_email.trim().contains("@") &&
  state.billing_email.length() <= 320 &&
  !state.action_loading
}

///|
pub fn company_join_valid(state : SelfServiceState) -> Bool {
  let value = state.invitation_code.trim()
  value.length() >= 8 && value.length() <= 512 && !state.action_loading
}

///|
fn selected_offering(state : SelfServiceState) -> SelfServiceOfferingView? {
  state.offerings
  .iter()
  .find_first(value => value.offering_id == state.selected_offering_id)
}

///|
pub fn self_service_configuration_valid(state : SelfServiceState) -> Bool {
  guard state.selected_product is Some(product) else { return false }
  if product == SharedMaaS {
    return true
  }
  guard selected_offering(state) is Some(offering) else { return false }
  offering.available &&
  offering.kind == product &&
  offering.regions.contains(state.region) &&
  state.project_id.trim() != "" &&
  state.project_id.length() <= 160 &&
  state.duration_hours >= offering.minimum_duration_hours &&
  state.duration_hours <= offering.maximum_duration_hours &&
  (
    product == BareGpu ||
    (
      state.model_selector.trim() != "" &&
      state.model_template_ref.trim() != "" &&
      offering.allowed_model_template_refs.contains(
        state.model_template_ref.trim().to_owned(),
      )
    )
  ) &&
  (
    product != BareGpu ||
    @portal.valid_unix_username(state.unix_username.trim().to_owned())
  ) &&
  !state.action_loading
}

///| Returns the explicit organization selector used by every scoped portal

///| request. More than one membership with no selection deliberately returns

///|
/// `None`, allowing the transport to fail closed instead of guessing.
pub fn selected_organization_header(state : EnterpriseState) -> String? {
  match state.selected_organization_id {
    Some(value) if state.organizations.any(item => {
        item.organization.organization_id == value && item.membership.active
      }) => Some(value)
    _ =>
      if state.organizations.length() == 1 &&
        state.organizations[0].membership.active {
        Some(state.organizations[0].organization.organization_id)
      } else if state.organizations.length() == 0 {
        state.membership.map(value => value.organization_id)
      } else {
        None
      }
  }
}

///|
fn self_service_command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  message : SelfServiceMessage,
) -> @rabbita.Cmd {
  command(emit, SelfService(message))
}

///|
fn self_service_text_command(
  emit : @rabbita.Emit[EnterpriseMessage]?,
  wrap : (String) -> SelfServiceMessage,
) -> @rabbita.Emit[String] {
  text_command(emit, value => SelfService(wrap(value)))
}

///|
fn product_label(locale : @i18n.Locale, product : SelfServiceProduct) -> String {
  match product {
    SharedMaaS => "MaaS · \{enterprise_copy(locale, SharedMaas)}"
    DedicatedMaaS => "MaaS · \{enterprise_copy(locale, DedicatedMaas)}"
    BareGpu => "IaaS · \{enterprise_copy(locale, BareGpu)}"
  }
}

///|
fn product_card(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  product : SelfServiceProduct,
  title : String,
  description : String,
  outcome : String,
) -> @rabbita.Html {
  @html.article(class="service-choice", [
    @html.p(class="eyebrow", product_label(state.locale, product)),
    @html.p(
      class="service-owner",
      copy(
        state.locale,
        "Owned by the selected company",
        "归当前选择的企业所有",
      ),
    ),
    @html.h3(title),
    @html.p(description),
    @html.p(class="service-outcome", outcome),
    @html.button(
      type_="button",
      class="quiet-button",
      on_click=self_service_command(emit, SelectProduct(product)),
      enterprise_copy(state.locale, ChooseThisService),
    ),
  ])
}

///|
fn product_choices(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  compact : Bool,
) -> @rabbita.Html {
  @html.section(
    class=if compact { "service-entry compact-entry" } else { "service-entry" },
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            enterprise_copy(state.locale, StartWithAnOutcome),
          ),
          @html.h2(enterprise_copy(state.locale, WhatDoYouWantToRun)),
          @html.p(enterprise_copy(state.locale, ChooseAnApiAManagedDedicated)),
        ]),
      ]),
      @html.div(class="service-choice-grid", [
        product_card(
          state,
          emit,
          BareGpu,
          enterprise_copy(state.locale, RentAGpuWorkspace),
          enterprise_copy(state.locale, ChooseCapacityAndManageYourOwn),
          enterprise_copy(state.locale, YouReceiveSshAndWebideAccess),
        ),
        @html.article(class="service-choice", [
          @html.p(class="eyebrow", "PaaS · WebIDE"),
          @html.h3(
            copy(
              state.locale,
              "Open my personal workspace",
              "打开我的个人工作台",
            ),
          ),
          @html.p(
            copy(
              state.locale,
              "Your own MoonDesk application and saved work. Your company authorizes its resources; teammates keep separate workspaces.",
              "MoonDesk 应用与保存的工作归你个人；企业授权资源，同事各自拥有独立工作台。",
            ),
          ),
          @html.p(
            class="service-outcome",
            copy(
              state.locale,
              "I receive my own WebIDE, using company-authorized models.",
              "获得个人 WebIDE，使用企业授权的模型。",
            ),
          ),
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=command(emit, Navigate(DesktopIde)),
            copy(state.locale, "Open WebIDE", "打开 WebIDE"),
          ),
        ]),
        product_card(
          state,
          emit,
          SharedMaaS,
          enterprise_copy(state.locale, CallAModelApi),
          enterprise_copy(state.locale, NoMachineSelectionStartWithA),
          enterprise_copy(state.locale, YouReceiveAnApiKey),
        ),
        product_card(
          state,
          emit,
          DedicatedMaaS,
          enterprise_copy(state.locale, DeployAPrivateModelEndpoint),
          enterprise_copy(state.locale, ChooseAGpuAndApprovedModel),
          enterprise_copy(state.locale, YouReceiveAPrivateEndpoint),
        ),
      ]),
    ],
  )
}

///|
fn self_service_step_number(step : SelfServiceStep) -> Int {
  match step {
    ChooseService => 1
    Organization => 2
    Capacity => 3
    Quote => 4
    ContractPayment => 5
    Provisioning => 6
  }
}

///|
fn self_service_progress(state : EnterpriseState) -> @rabbita.Html {
  let current = self_service_step_number(state.self_service.step)
  let labels = [
    enterprise_copy(state.locale, Service),
    enterprise_copy(state.locale, Organization),
    enterprise_copy(state.locale, Capacity),
    enterprise_copy(state.locale, Quote),
    enterprise_copy(state.locale, ContractPayment),
    enterprise_copy(state.locale, Provisioning),
  ]
  @html.nav(
    class="purchase-progress",
    attrs=@html.Attrs::build().aria_label(
      enterprise_copy(state.locale, OrderProgress),
    ),
    @html.ol(
      [
        for index, label in labels => {
          let number = index + 1
          @html.li(
            class=if number < current {
              "is-complete"
            } else if number == current {
              "is-current"
            } else {
              ""
            },
            attrs=@html.Attrs::build().aria_current(
              if number == current {
                "step"
              } else {
                "false"
              },
            ),
            [@html.span("\{number}"), @html.strong(label)],
          )
        }
      ],
    ),
  )
}

///|
fn has_customer_membership(state : EnterpriseState) -> Bool {
  guard state.membership is Some(membership) && membership.active else {
    return false
  }
  // Trial membership authorizes bounded shared inference, not a customer entity.
  match state.trial {
    Some(trial) if trial.organization_id == membership.organization_id => false
    _ => true
  }
}

///|
fn organization_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  match state.membership {
    Some(membership) if has_customer_membership(state) => {
      let selected = state.organizations
        .iter()
        .find_first(value => {
          value.organization.organization_id == membership.organization_id
        })
      let organization_active = state.organizations.length() == 0 ||
        (match selected {
          Some(value) => value.organization.state == Active
          None => false
        })
      let verification = match selected {
        Some(value) => value.verification
        None => None
      }
      @html.section(class="guided-panel", [
        @html.p(class="eyebrow", enterprise_copy(state.locale, Organization338)),
        @html.h2(
          if organization_active {
            enterprise_copy(state.locale, OrganizationReady)
          } else {
            enterprise_copy(state.locale, OrganizationVerificationPending)
          },
        ),
        @html.p(
          if organization_active {
            enterprise_copy(state.locale, ThisOrderWillBeOwnedBy)
          } else {
            enterprise_copy(state.locale, YourCompanyRecordExistsButMachine)
          },
        ),
        @html.dl(class="selection-summary", [
          @html.div([
            @html.dt(enterprise_copy(state.locale, Organization)),
            @html.dd([copy_detail(state, emit, membership.organization_id)]),
          ]),
          @html.div([
            @html.dt(enterprise_copy(state.locale, Tenant)),
            @html.dd([copy_detail(state, emit, membership.tenant_ref)]),
          ]),
        ]),
        if !organization_active {
          match verification {
            Some(value) if value.record is Some(record) &&
              record.action_url is Some(url) =>
              @html.div(class="terms-acceptance", [
                @html.p(
                  copy(
                    state.locale,
                    "Identity provider status: " + record.state,
                    "身份验证服务商状态：" + record.state,
                  ),
                ),
                @html.a(
                  class="primary-button action-link",
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  escape=true,
                  enterprise_copy(state.locale, VerifyOrganization),
                ),
              ])
            Some(value) if value.blocker_code == Some("OperatorReviewPending") =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                copy(
                  state.locale,
                  "Your company registration has been sent to platform administrators for review. No external identity provider is required. Refresh after approval to continue.",
                  "企业注册已提交平台管理员审核，无需外部认证服务。审核通过后刷新此页继续。",
                ),
              )
            Some(value) if value.blocker_code ==
              Some("CommercialProviderUnavailable") =>
              @html.div(
                class="notice is-error",
                attrs=@html.Attrs::build().role("alert"),
                enterprise_copy(
                  state.locale,
                  IdentityVerificationProviderIsUnavailableMachine,
                ),
              )
            Some(value) if value.blocker_code ==
              Some("IdentityVerificationQueueRetryRequired") =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                enterprise_copy(
                  state.locale,
                  VerificationDispatchNeedsRetryRefreshingThis,
                ),
              )
            _ =>
              @html.div(
                class="inline-state",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                enterprise_copy(
                  state.locale,
                  TheVerificationRequestIsPendingWhile,
                ),
              )
          }
        } else {
          @html.nothing
        },
        @html.div(class="wizard-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=self_service_command(emit, PreviousSelfServiceStep),
            enterprise_copy(state.locale, Back),
          ),
          if !organization_active {
            @html.button(
              type_="button",
              class="quiet-button",
              disabled=state.self_service.action_loading,
              on_click=self_service_command(emit, RefreshOrganizations),
              enterprise_copy(state.locale, RefreshVerification),
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            class="primary-button",
            disabled=!organization_active,
            on_click=self_service_command(emit, ContinueWithOrganization),
            if organization_active {
              enterprise_copy(state.locale, Continue)
            } else {
              enterprise_copy(state.locale, WaitingForVerification)
            },
          ),
        ]),
      ])
    }
    _ =>
      @html.section(class="guided-panel", [
        @html.p(class="eyebrow", enterprise_copy(state.locale, Organization338)),
        @html.h2(enterprise_copy(state.locale, CreateACompanyOrJoinOne)),
        @html.p(
          enterprise_copy(state.locale, ACompanyIdentityProviderIsOptional),
        ),
        @html.div(class="segmented-control", [
          @html.button(
            type_="button",
            class=if state.self_service.organization_mode == CreateCompany {
              "segment is-selected"
            } else {
              "segment"
            },
            attrs=@html.Attrs::build().aria_pressed(
              if state.self_service.organization_mode == CreateCompany {
                "true"
              } else {
                "false"
              },
            ),
            on_click=self_service_command(
              emit,
              ChooseOrganizationMode(CreateCompany),
            ),
            enterprise_copy(state.locale, CreateCompany),
          ),
          @html.button(
            type_="button",
            class=if state.self_service.organization_mode == JoinCompany {
              "segment is-selected"
            } else {
              "segment"
            },
            attrs=@html.Attrs::build().aria_pressed(
              if state.self_service.organization_mode == JoinCompany {
                "true"
              } else {
                "false"
              },
            ),
            on_click=self_service_command(
              emit,
              ChooseOrganizationMode(JoinCompany),
            ),
            enterprise_copy(state.locale, JoinCompany),
          ),
        ]),
        if state.self_service.organization_mode == CreateCompany {
          @html.div(class="guided-form", [
            @html.div(class="form-grid", [
              @html.div(class="field", [
                @html.label(
                  for_="company-subject-kind",
                  enterprise_copy(state.locale, LegalSubjectType),
                ),
                @html.select(
                  id="company-subject-kind",
                  on_change=self_service_text_command(emit, value => {
                    SubjectKindChanged(value)
                  }),
                  [
                    @html.option(
                      value="Company",
                      selected=state.self_service.subject_kind == "Company",
                      enterprise_copy(state.locale, Company),
                    ),
                    @html.option(
                      value="Individual",
                      selected=state.self_service.subject_kind == "Individual",
                      enterprise_copy(state.locale, Individual),
                    ),
                  ],
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-legal-name",
                  enterprise_copy(state.locale, LegalName),
                ),
                @html.input(
                  id="company-legal-name",
                  value=state.self_service.legal_name,
                  maxlength=256,
                  on_input=self_service_text_command(emit, value => {
                    LegalNameChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-display-name",
                  enterprise_copy(state.locale, DisplayName),
                ),
                @html.input(
                  id="company-display-name",
                  value=state.self_service.display_name,
                  maxlength=128,
                  on_input=self_service_text_command(emit, value => {
                    CompanyDisplayNameChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-country",
                  enterprise_copy(state.locale, CountryCode),
                ),
                @html.input(
                  id="company-country",
                  value=state.self_service.country_region,
                  maxlength=2,
                  on_input=self_service_text_command(emit, value => {
                    CountryRegionChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-registration-number",
                  enterprise_copy(state.locale, RegistrationNumberOptional),
                ),
                @html.input(
                  id="company-registration-number",
                  value=state.self_service.registration_number,
                  maxlength=128,
                  on_input=self_service_text_command(emit, value => {
                    RegistrationNumberChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-tax-id",
                  enterprise_copy(state.locale, TaxOrRegistrationIdOptional),
                ),
                @html.input(
                  id="company-tax-id",
                  value=state.self_service.tax_identifier,
                  maxlength=128,
                  on_input=self_service_text_command(emit, value => {
                    TaxIdentifierChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field field-wide", [
                @html.label(
                  for_="company-address",
                  enterprise_copy(state.locale, RegisteredAddress),
                ),
                @html.input(
                  id="company-address",
                  value=state.self_service.registered_address,
                  maxlength=512,
                  on_input=self_service_text_command(emit, value => {
                    RegisteredAddressChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-billing-contact",
                  enterprise_copy(state.locale, BillingContact),
                ),
                @html.input(
                  id="company-billing-contact",
                  value=state.self_service.billing_contact_name,
                  maxlength=128,
                  on_input=self_service_text_command(emit, value => {
                    BillingContactNameChanged(value)
                  }),
                ),
              ]),
              @html.div(class="field field-wide", [
                @html.label(
                  for_="company-billing-email",
                  enterprise_copy(state.locale, BillingEmail),
                ),
                @html.input(
                  id="company-billing-email",
                  input_type=Email,
                  value=state.self_service.billing_email,
                  maxlength=320,
                  on_input=self_service_text_command(emit, value => {
                    BillingEmailChanged(value)
                  }),
                ),
                @html.small(
                  enterprise_copy(
                    state.locale,
                    TheCreatorBecomesOrganizationOwnerMachine,
                  ),
                ),
              ]),
            ]),
            @html.button(
              type_="button",
              class="primary-button",
              disabled=!company_creation_valid(state.self_service),
              on_click=self_service_command(emit, SubmitCreateCompany),
              if state.self_service.action_loading {
                enterprise_copy(state.locale, CreatingCompany)
              } else {
                enterprise_copy(state.locale, CreateCompany)
              },
            ),
          ])
        } else {
          @html.div(class="guided-form", [
            @html.div(class="field", [
              @html.label(
                for_="company-invitation",
                enterprise_copy(state.locale, InvitationCode),
              ),
              @html.input(
                id="company-invitation",
                value=state.self_service.invitation_code,
                maxlength=512,
                auto_complete=Off,
                on_input=self_service_text_command(emit, value => {
                  InvitationCodeChanged(value)
                }),
              ),
              @html.small(
                enterprise_copy(state.locale, TheSignedOneTimeInvitationSelects),
              ),
            ]),
            @html.button(
              type_="button",
              class="primary-button",
              disabled=!company_join_valid(state.self_service),
              on_click=self_service_command(emit, SubmitJoinCompany),
              if state.self_service.action_loading {
                enterprise_copy(state.locale, JoiningCompany)
              } else {
                enterprise_copy(state.locale, JoinCompany)
              },
            ),
          ])
        },
        @html.div(class="wizard-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=self_service_command(emit, PreviousSelfServiceStep),
            enterprise_copy(state.locale, Back),
          ),
        ]),
        @html.details(class="integration-contract", [
          @html.summary(enterprise_copy(state.locale, IntegrationContract)),
          @html.p(enterprise_copy(state.locale, ListOrCreateGetPostV)),
        ]),
      ])
  }
}

///|
fn offering_card(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
  offering : SelfServiceOfferingView,
) -> @rabbita.Html {
  let selected = offering.offering_id == state.self_service.selected_offering_id
  @html.article(
    class=if selected { "offering-card is-selected" } else { "offering-card" },
    [
      @html.div(class="offering-heading", [
        @html.div([
          @html.h3(offering.display_name),
          @html.p([copy_detail(state, emit, offering.gpu_sku)]),
        ]),
        @html.span(
          class=if offering.available {
            "availability available"
          } else {
            "availability"
          },
          if offering.available {
            enterprise_copy(state.locale, Available)
          } else {
            enterprise_copy(state.locale, Unavailable)
          },
        ),
      ]),
      @html.dl(class="selection-summary", [
        @html.div([
          @html.dt(enterprise_copy(state.locale, Gpu)),
          @html.dd("\{offering.accelerator_count}"),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Memory)),
          @html.dd("\{offering.accelerator_memory_mib / 1024} GiB"),
        ]),
        @html.div([
          @html.dt(enterprise_copy(state.locale, Regions)),
          @html.dd(offering.regions.join(", ")),
        ]),
      ]),
      @html.p(class="price-summary", offering.price_summary),
      @html.button(
        type_="button",
        class=if selected { "primary-button" } else { "quiet-button" },
        disabled=!offering.available,
        attrs=@html.Attrs::build().aria_pressed(
          if selected {
            "true"
          } else {
            "false"
          },
        ),
        on_click=self_service_command(
          emit,
          SelectOffering(offering.offering_id),
        ),
        if selected {
          enterprise_copy(state.locale, Selected)
        } else {
          enterprise_copy(state.locale, SelectCapacity)
        },
      ),
    ],
  )
}

///|
fn capacity_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  guard state.self_service.selected_product is Some(product) else {
    return product_choices(state, emit, false)
  }
  if product == SharedMaaS {
    return @html.section(class="guided-panel", [
      @html.p(class="eyebrow", product_label(state.locale, product)),
      @html.h2(enterprise_copy(state.locale, StartWithTheSharedApi)),
      @html.p(enterprise_copy(state.locale, SharedMaasDoesNotRequireA)),
      @html.div(class="wizard-actions", [
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, PreviousSelfServiceStep),
          enterprise_copy(state.locale, Back),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          on_click=command(emit, Navigate(AccountAccess)),
          enterprise_copy(state.locale, CreateApiKey),
        ),
      ]),
    ])
  }
  let matching = state.self_service.offerings.filter(value => {
    value.kind == product
  })
  let available = matching.filter(value => value.available)
  let chosen = selected_offering(state.self_service)
  let region_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.self_service.region == "",
      enterprise_copy(state.locale, SelectARegion),
    ),
  ]
  let model_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.self_service.model_selector == "",
      enterprise_copy(state.locale, SelectAModel),
    ),
  ]
  let template_options : Array[@rabbita.Html] = []
  match chosen {
    Some(offering) => {
      for region in offering.regions {
        region_options.push(
          @html.option(
            value=region,
            selected=state.self_service.region == region,
            region,
          ),
        )
      }
      for template in offering.allowed_model_template_refs {
        template_options.push(
          @html.option(
            value=template,
            selected=state.self_service.model_template_ref == template,
            template,
          ),
        )
      }
    }
    None => ()
  }
  for model in state.model_catalog {
    let label = match model.alias_name {
      Some(model_alias) => "\{model_alias} · \{model.model_id}"
      None => model.model_id
    }
    model_options.push(
      @html.option(
        value=model.model_id,
        selected=state.self_service.model_selector == model.model_id,
        label,
      ),
    )
  }
  @html.section(class="guided-panel", [
    @html.p(class="eyebrow", product_label(state.locale, product)),
    @html.h2(enterprise_copy(state.locale, ChooseCapacity)),
    @html.p(
      if product == DedicatedMaaS {
        enterprise_copy(state.locale, TheSelectedApprovedModelWillBe)
      } else {
        enterprise_copy(state.locale, YouReceiveAnIsolatedWorkspaceNo)
      },
    ),
    if state.self_service.offerings_loading {
      @html.p(
        class="inline-state",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        enterprise_copy(state.locale, LoadingLiveCapacity),
      )
    } else if state.self_service.offerings_error is Some(error) {
      @html.div(class="inline-state is-error", [
        @html.p(attrs=@html.Attrs::build().role("alert"), error),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, RefreshOfferings),
          enterprise_copy(state.locale, RetryCatalog),
        ),
      ])
    } else if state.self_service.offerings_loaded && available.length() == 0 {
      @html.div(class="inline-state", [
        @html.h3(enterprise_copy(state.locale, NoCapacityAvailable)),
        @html.p(
          enterprise_copy(state.locale, TryAnotherServiceOrRefreshAvailability),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, RefreshOfferings),
          enterprise_copy(state.locale, RefreshAvailability),
        ),
      ])
    } else if !state.self_service.offerings_loaded {
      @html.div(class="inline-state", [
        @html.p(
          enterprise_copy(state.locale, LoadCurrentSkuRegionAndAvailability),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          on_click=self_service_command(emit, RefreshOfferings),
          enterprise_copy(state.locale, LoadCapacity),
        ),
      ])
    } else {
      @html.div(
        class="offering-grid",
        [
          for offering in available => offering_card(state, emit, offering)
        ],
      )
    },
    match chosen {
      Some(offering) if offering.kind == product && offering.available =>
        @html.div(class="guided-form capacity-configuration", [
          @html.h3(enterprise_copy(state.locale, ConfigureOrder)),
          @html.div(class="form-grid", [
            @html.div(class="field", [
              @html.label(
                for_="self-service-project",
                enterprise_copy(state.locale, Project),
              ),
              @html.input(
                id="self-service-project",
                value=state.self_service.project_id,
                maxlength=160,
                on_input=self_service_text_command(emit, value => {
                  SelfServiceProjectChanged(value)
                }),
              ),
            ]),
            if product == BareGpu {
              @html.div(class="field", [
                @html.label(
                  for_="self-service-unix-username",
                  enterprise_copy(state.locale, LinuxUsername),
                ),
                @html.input(
                  id="self-service-unix-username",
                  value=state.self_service.unix_username,
                  maxlength=32,
                  auto_complete=Off,
                  attrs=@html.Attrs::build().aria_invalid(
                    if state.self_service.unix_username.trim() != "" &&
                      !@portal.valid_unix_username(
                        state.self_service.unix_username.trim().to_owned(),
                      ) {
                      "true"
                    } else {
                      "false"
                    },
                  ),
                  on_input=self_service_text_command(emit, value => {
                    UnixUsernameChanged(value)
                  }),
                ),
                @html.small(
                  class=if state.self_service.unix_username.trim() != "" &&
                    !@portal.valid_unix_username(
                      state.self_service.unix_username.trim().to_owned(),
                    ) {
                    "field-error"
                  } else {
                    ""
                  },
                  enterprise_copy(state.locale, RequiredForBareGpuAccessStart),
                ),
              ])
            } else {
              @html.nothing
            },
            @html.div(class="field", [
              @html.label(
                for_="self-service-region",
                enterprise_copy(state.locale, Region),
              ),
              @html.select(
                id="self-service-region",
                on_change=self_service_text_command(emit, value => {
                  RegionChanged(value)
                }),
                region_options,
              ),
            ]),
            @html.div(class="field", [
              @html.label(
                for_="self-service-duration",
                enterprise_copy(state.locale, RentalPeriod),
              ),
              @html.select(
                id="self-service-duration",
                on_change=self_service_text_command(emit, value => {
                  DurationChanged(
                    match value {
                      "168" => 168
                      "720" => 720
                      _ => 24
                    },
                  )
                }),
                [
                  @html.option(
                    value="24",
                    selected=state.self_service.duration_hours == 24,
                    enterprise_copy(state.locale, Hours),
                  ),
                  @html.option(
                    value="168",
                    selected=state.self_service.duration_hours == 168,
                    enterprise_copy(state.locale, Days),
                  ),
                  @html.option(
                    value="720",
                    selected=state.self_service.duration_hours == 720,
                    enterprise_copy(state.locale, Days101),
                  ),
                ],
              ),
              @html.small(
                "\{offering.minimum_duration_hours}–\{offering.maximum_duration_hours} \{enterprise_copy(state.locale, HoursAllowed)}",
              ),
              // The caption above states the allowance but not what happens when
              // the selection is outside it: Review price simply went grey, and
              // on a trial that is the only visible consequence of picking a
              // longer period. Say which limit was crossed and what to do.
              if state.self_service.duration_hours >
                offering.maximum_duration_hours {
                @html.small(
                  class="field-error",
                  "\{state.self_service.duration_hours} \{enterprise_copy(state.locale, LongerThanThisOfferingAllows)}",
                )
              } else {
                @html.nothing
              },
            ]),
            if product == DedicatedMaaS {
              @html.div([
                @html.div(class="field", [
                  @html.label(
                    for_="self-service-model",
                    enterprise_copy(state.locale, ApprovedModel),
                  ),
                  @html.select(
                    id="self-service-model",
                    on_change=self_service_text_command(emit, value => {
                      ModelSelectorChanged(value)
                    }),
                    model_options,
                  ),
                  if state.model_catalog.length() == 0 {
                    @html.small(
                      class="field-error",
                      enterprise_copy(
                        state.locale,
                        NoApprovedModelIsAvailableFor,
                      ),
                    )
                  } else {
                    @html.small(
                      enterprise_copy(
                        state.locale,
                        OnlyCatalogApprovedModelsCanBe,
                      ),
                    )
                  },
                ]),
                @html.div(class="field", [
                  @html.label(
                    for_="self-service-model-template",
                    enterprise_copy(state.locale, DeploymentTemplate),
                  ),
                  @html.select(
                    id="self-service-model-template",
                    on_change=self_service_text_command(emit, value => {
                      ModelTemplateChanged(value)
                    }),
                    template_options,
                  ),
                  @html.small(
                    enterprise_copy(
                      state.locale,
                      OnlyTemplatesReviewedForThisSku,
                    ),
                  ),
                ]),
              ])
            } else {
              @html.div(class="field", [
                @html.label(enterprise_copy(state.locale, ManagedModel)),
                @html.p(
                  class="read-only-value",
                  enterprise_copy(state.locale, NoneYouManageThisWorkspace),
                ),
              ])
            },
          ]),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=!self_service_configuration_valid(state.self_service),
            on_click=self_service_command(emit, RequestQuote),
            if state.self_service.action_loading {
              enterprise_copy(state.locale, CalculatingSignedQuote)
            } else {
              enterprise_copy(state.locale, ReviewPrice)
            },
          ),
        ])
      _ => @html.nothing
    },
    @html.div(class="wizard-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=self_service_command(emit, PreviousSelfServiceStep),
        enterprise_copy(state.locale, Back),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(enterprise_copy(state.locale, IntegrationContract)),
      @html.p(
        "GET /v1/portal/self/machine-offerings · POST /v1/portal/self/machine-quotes · BareMachine quotes require unix_username; DedicatedEndpoint quotes omit it · X-LunaNexa-Organization: <selected organization>",
      ),
    ]),
  ])
}

///|
fn quote_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let agreements_ready = state.agreements.any(value => value.state == Executed)
  let terms_ready = agreements_ready || state.self_service.terms_accepted
  @html.section(class="guided-panel", [
    @html.p(class="eyebrow", enterprise_copy(state.locale, SignedQuote)),
    @html.h2(enterprise_copy(state.locale, ReviewPriceAndScope)),
    if state.self_service.action_loading {
      @html.p(
        class="inline-state",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        enterprise_copy(state.locale, CalculatingAnAuthoritativeQuote),
      )
    } else if state.self_service.action_error is Some(error) {
      @html.div(class="inline-state is-error", [
        @html.p(attrs=@html.Attrs::build().role("alert"), error),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, DismissSelfServiceError),
          enterprise_copy(state.locale, Dismiss),
        ),
      ])
    } else {
      match state.self_service.quote {
        Some(quote) =>
          @html.div(class="quote-review", [
            @html.dl(class="selection-summary quote-facts", [
              @html.div([
                @html.dt(enterprise_copy(state.locale, Total)),
                @html.dd(class="quote-total", quote.display_amount),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, Quote)),
                @html.dd([copy_detail(state, emit, quote.quote_id)]),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, ValidUntil)),
                @html.dd(
                  @contractdoc.format_unix_ms_beijing(quote.valid_until_unix_ms),
                ),
              ]),
              @html.div([
                @html.dt(enterprise_copy(state.locale, CurrencyScale)),
                @html.dd("\{quote.currency} / \{quote.money_scale}"),
              ]),
            ]),
            @html.p(
              class="trust-callout",
              enterprise_copy(
                state.locale,
                AmountAvailabilityWindowAndTermsDigest,
              ),
            ),
            copy_detail(state, emit, quote.terms_digest),
            if !agreements_ready {
              match state.self_service.terms {
                Some(terms) =>
                  @html.div(class="terms-acceptance", [
                    @html.strong(
                      enterprise_copy(state.locale, MachineSelfServiceTerms),
                    ),
                    @html.p(
                      "\{terms.template_id} · \{terms.version} · \{terms.locale}",
                    ),
                    copy_detail(state, emit, terms.rendered_document_hash),
                    @html.a(
                      class="quiet-button action-link",
                      href=terms.document_uri,
                      target=Blank,
                      rel="noopener noreferrer",
                      escape=true,
                      enterprise_copy(state.locale, OpenImmutableTermsDocument),
                    ),
                    if state.self_service.terms_accepted {
                      @html.p(
                        class="success-copy",
                        enterprise_copy(
                          state.locale,
                          AcceptanceEvidenceRecordedForThisSession,
                        ),
                      )
                    } else {
                      @html.div(class="wizard-actions", [
                        @html.button(
                          type_="button",
                          class="quiet-button",
                          disabled=state.self_service.terms_reviewed,
                          on_click=self_service_command(
                            emit,
                            ConfirmMachineTermsReviewed,
                          ),
                          if state.self_service.terms_reviewed {
                            enterprise_copy(state.locale, DocumentReviewed)
                          } else {
                            enterprise_copy(state.locale, IReviewedThisDocument)
                          },
                        ),
                        @html.button(
                          type_="button",
                          class="primary-button",
                          disabled=!state.self_service.terms_reviewed ||
                            state.self_service.action_loading,
                          on_click=self_service_command(
                            emit,
                            AcceptMachineTerms,
                          ),
                          enterprise_copy(state.locale, AcceptTermsToContinue),
                        ),
                      ])
                    },
                  ])
                None =>
                  @html.p(
                    class="notice is-error",
                    attrs=@html.Attrs::build().role("alert"),
                    enterprise_copy(
                      state.locale,
                      MachineTermsAreUnavailableOrderingRemains,
                    ),
                  )
              }
            } else {
              @html.p(
                class="success-copy",
                enterprise_copy(
                  state.locale,
                  AnExecutedOrganizationAgreementSatisfiesThe,
                ),
              )
            },
            @html.button(
              type_="button",
              class="primary-button",
              disabled=!terms_ready || state.self_service.action_loading,
              on_click=self_service_command(emit, CreateMachineOrder),
              enterprise_copy(state.locale, CreateOrder),
            ),
          ])
        None =>
          @html.div(class="inline-state", [
            @html.h3(enterprise_copy(state.locale, QuoteNotAvailable)),
            @html.p(
              enterprise_copy(
                state.locale,
                ReturnToCapacityVerifyTheConfiguration,
              ),
            ),
          ])
      }
    },
    @html.div(class="wizard-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=self_service_command(emit, PreviousSelfServiceStep),
        enterprise_copy(state.locale, BackToCapacity),
      ),
    ]),
  ])
}

///|
fn order_status_label(
  locale : @i18n.Locale,
  status : MachineOrderStatus,
) -> String {
  match status {
    AwaitingPayment => enterprise_copy(locale, AwaitingPayment)
    PaymentSettled => enterprise_copy(locale, PaymentSettled)
    ProvisioningOrder => enterprise_copy(locale, Provisioning431)
    ActiveOrder => enterprise_copy(locale, Active432)
    CancellationPending => enterprise_copy(locale, CancellationPending)
    TerminationPending => enterprise_copy(locale, TerminationPending)
    CompensationPending => enterprise_copy(locale, CompensationPending)
    CancelledOrder => enterprise_copy(locale, Cancelled)
    TerminatedOrder => enterprise_copy(locale, Terminated)
    FailedOrder => enterprise_copy(locale, Failed)
  }
}

///|
fn contract_payment_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  let agreements_ready = state.agreements.any(value => value.state == Executed) ||
    state.self_service.terms_accepted
  @html.section(class="guided-panel", [
    @html.p(class="eyebrow", enterprise_copy(state.locale, ContractPayment437)),
    @html.h2(enterprise_copy(state.locale, CompleteCommercialGates)),
    match state.self_service.order {
      Some(order) =>
        @html.div(class="order-gates", [
          @html.div(class="gate-row", [
            @html.span(
              class=if agreements_ready {
                "gate-mark ready"
              } else {
                "gate-mark"
              },
              if agreements_ready {
                "✓"
              } else {
                "1"
              },
            ),
            @html.div([
              @html.h3(enterprise_copy(state.locale, RequiredAgreements)),
              @html.p(
                if agreements_ready {
                  enterprise_copy(state.locale, ExecutedEvidenceIsVerified)
                } else {
                  enterprise_copy(state.locale, ALegalSignerMustCompleteEvery)
                },
              ),
            ]),
            @html.button(
              type_="button",
              class="quiet-button",
              on_click=command(emit, Navigate(Agreements)),
              enterprise_copy(state.locale, OpenAgreements),
            ),
          ]),
          @html.div(class="gate-row", [
            @html.span(
              class=if order.status != AwaitingPayment {
                "gate-mark ready"
              } else {
                "gate-mark"
              },
              if order.status != AwaitingPayment {
                "✓"
              } else {
                "2"
              },
            ),
            @html.div([
              @html.h3(enterprise_copy(state.locale, SecurePayment)),
              @html.p(
                if order.status == AwaitingPayment {
                  enterprise_copy(
                    state.locale,
                    PaymentSettlementIsVerifiedIndependentlyBefore,
                  )
                } else {
                  enterprise_copy(state.locale, PaymentEvidenceReceived)
                },
              ),
            ]),
            match state.self_service.checkout {
              Some(checkout) if checkout.action_url is Some(url) &&
                order.status == AwaitingPayment =>
                @html.a(
                  class="primary-button action-link",
                  href=url,
                  target=Blank,
                  rel="noopener noreferrer",
                  escape=true,
                  [
                    @html.span(
                      enterprise_copy(state.locale, OpenSecureCheckout),
                    ),
                    @html.span(" · \{checkout.provider}"),
                  ],
                )
              _ =>
                @html.button(
                  type_="button",
                  class="primary-button",
                  on_click=self_service_command(emit, RefreshMachineOrders),
                  if order.status == AwaitingPayment {
                    enterprise_copy(state.locale, RefreshPaymentStatus)
                  } else {
                    enterprise_copy(state.locale, RefreshOrder)
                  },
                )
            },
            match state.self_service.checkout {
              Some(checkout) =>
                @html.p(
                  class="provider-checkout-state",
                  attrs=@html.Attrs::build().role("status").aria_live("polite"),
                  copy(
                    state.locale,
                    "Provider checkout state: " + checkout.state,
                    "支付服务商状态：" + checkout.state,
                  ),
                )
              None => @html.nothing
            },
          ]),
          @html.div(class="order-reference", [
            @html.strong(
              "\{enterprise_copy(state.locale, Order)} · \{order_status_label(state.locale, order.status)}",
            ),
            copy_detail(state, emit, order.order_id),
          ]),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=order.status == AwaitingPayment,
            on_click=self_service_command(emit, ViewProvisioning),
            enterprise_copy(state.locale, TrackProvisioning),
          ),
          if order.status == AwaitingPayment {
            @html.button(
              type_="button",
              class="danger-button",
              disabled=state.self_service.action_loading,
              on_click=self_service_command(
                emit,
                CancelMachineOrder(order.order_id, order.generation),
              ),
              enterprise_copy(state.locale, CancelUnpaidOrder),
            )
          } else {
            @html.nothing
          },
        ])
      None =>
        @html.div(class="inline-state", [
          @html.h3(enterprise_copy(state.locale, OrderNotCreated)),
          @html.p(enterprise_copy(state.locale, NoPaymentRequestWillBeCreated)),
        ])
    },
    @html.div(class="wizard-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=self_service_command(emit, PreviousSelfServiceStep),
        enterprise_copy(state.locale, BackToQuote),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(enterprise_copy(state.locale, IntegrationContract)),
      @html.p(
        "POST /v1/portal/self/machine-orders · X-LunaNexa-Organization: <selected organization> · entitlement_transaction_ref = machine-order:<order_id>",
      ),
    ]),
  ])
}

///|
fn provisioning_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.section(class="guided-panel", [
    @html.p(class="eyebrow", enterprise_copy(state.locale, LiveOrder)),
    @html.h2(enterprise_copy(state.locale, ProvisioningProgress)),
    match state.self_service.order {
      Some(order) =>
        @html.div([
          @html.div(class="order-status-heading", [
            @html.div([
              @html.strong(order_status_label(state.locale, order.status)),
              @html.p([copy_detail(state, emit, order.order_id)]),
            ]),
            @html.span(
              class="state-pill",
              "\{enterprise_copy(state.locale, Generation456)} \{order.generation}",
            ),
          ]),
          match order.status {
            CompensationPending =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                enterprise_copy(
                  state.locale,
                  PaymentWasVerifiedButCapacityCould,
                ),
              )
            FailedOrder =>
              @html.div(
                class="notice is-error",
                attrs=@html.Attrs::build().role("alert"),
                enterprise_copy(state.locale, ThisOrderFailedRefreshForThe),
              )
            CancellationPending | TerminationPending =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                enterprise_copy(state.locale, TheRequestedShutdownIsInProgress),
              )
            _ => @html.nothing
          },
          @html.ol(class="provisioning-timeline", [
            @html.li(class="is-complete", [
              @html.strong(enterprise_copy(state.locale, OrderAccepted)),
              @html.p(enterprise_copy(state.locale, CommercialScopeIsImmutable)),
            ]),
            @html.li(
              class=if order.status == AwaitingPayment {
                "is-current"
              } else {
                "is-complete"
              },
              [
                @html.strong(enterprise_copy(state.locale, PaymentSettled462)),
                @html.p(
                  enterprise_copy(state.locale, ProviderEvidenceIsVerified),
                ),
              ],
            ),
            @html.li(
              class=if order.status == ProvisioningOrder {
                "is-current"
              } else if order.status == ActiveOrder {
                "is-complete"
              } else {
                ""
              },
              [
                @html.strong(enterprise_copy(state.locale, CapacityProvisioned)),
                @html.p(
                  enterprise_copy(state.locale, ALeaseIsReservedAndPrepared),
                ),
              ],
            ),
            if order.kind == DedicatedMaaS {
              @html.li(
                class=if order.status == ProvisioningOrder {
                  "is-current"
                } else if order.status == ActiveOrder {
                  "is-complete"
                } else {
                  ""
                },
                [
                  @html.strong(enterprise_copy(state.locale, ModelDeployed)),
                  @html.p(
                    enterprise_copy(
                      state.locale,
                      ArtifactTransferVerificationAndLunafluxDeployment,
                    ),
                  ),
                ],
              )
            } else {
              @html.li(
                class=if order.status == ActiveOrder {
                  "is-complete"
                } else {
                  ""
                },
                [
                  @html.strong(enterprise_copy(state.locale, AccessIssued)),
                  @html.p(
                    enterprise_copy(state.locale, ShortLivedSshAndWebideAccess),
                  ),
                ],
              )
            },
            @html.li(
              class=if order.status == ActiveOrder { "is-complete" } else { "" },
              [
                @html.strong(enterprise_copy(state.locale, Ready)),
                @html.p(
                  if order.kind == DedicatedMaaS {
                    enterprise_copy(
                      state.locale,
                      UseTheCanonicalVWorkloadsEndpoint,
                    )
                  } else {
                    enterprise_copy(
                      state.locale,
                      MachineAccessBecomesVisibleInMy,
                    )
                  },
                ),
              ],
            ),
          ]),
          @html.dl(class="selection-summary", [
            @html.div([
              @html.dt(enterprise_copy(state.locale, Gpu)),
              @html.dd(order.gpu_sku),
            ]),
            @html.div([
              @html.dt(enterprise_copy(state.locale, Region)),
              @html.dd(order.region),
            ]),
            @html.div([
              @html.dt(enterprise_copy(state.locale, Lease)),
              @html.dd([
                copy_detail(state, emit, order.lease_ref.unwrap_or("—")),
              ]),
            ]),
            @html.div([
              @html.dt(enterprise_copy(state.locale, Deployment)),
              @html.dd([
                copy_detail(state, emit, order.deployment_ref.unwrap_or("—")),
              ]),
            ]),
            if order.kind == DedicatedMaaS && order.status == ActiveOrder {
              @html.div([
                @html.dt(enterprise_copy(state.locale, Endpoint)),
                @html.dd([copy_detail(state, emit, "/v1/workloads")]),
              ])
            } else {
              @html.nothing
            },
          ]),
          if order.status == ActiveOrder {
            @html.div(class="wizard-actions", [
              @html.button(
                type_="button",
                class="primary-button",
                on_click=command(
                  emit,
                  Navigate(
                    if order.kind == BareGpu {
                      MachineAccess
                    } else {
                      AccountAccess
                    },
                  ),
                ),
                if order.kind == BareGpu {
                  enterprise_copy(state.locale, OpenMachineAccess)
                } else {
                  enterprise_copy(state.locale, ViewEndpointAccess)
                },
              ),
              @html.button(
                type_="button",
                class="danger-button",
                disabled=state.self_service.action_loading,
                on_click=self_service_command(
                  emit,
                  TerminateMachineOrder(order.order_id, order.generation),
                ),
                enterprise_copy(state.locale, TerminateService),
              ),
            ])
          } else {
            @html.p(
              class="inline-state",
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              enterprise_copy(state.locale, YouCanSafelyLeaveThisPage),
            )
          },
          if order.status == PaymentSettled || order.status == ProvisioningOrder {
            @html.button(
              type_="button",
              class="danger-button",
              disabled=state.self_service.action_loading,
              on_click=self_service_command(
                emit,
                CancelMachineOrder(order.order_id, order.generation),
              ),
              enterprise_copy(state.locale, RequestCancellation),
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.self_service.action_loading,
            on_click=self_service_command(emit, RefreshMachineOrders),
            enterprise_copy(state.locale, RefreshOrderStatus),
          ),
        ])
      None =>
        @html.div(class="inline-state", [
          @html.h3(enterprise_copy(state.locale, NoActiveOrder)),
          @html.p(enterprise_copy(state.locale, StartANewServiceOrderOr)),
        ])
    },
    if state.self_service.orders.length() > 0 {
      @html.section(class="recent-machine-orders", [
        @html.h3(enterprise_copy(state.locale, RecentMachineOrders)),
        @html.ul(
          [
            for order in state.self_service.orders => {
              @html.li([
                copy_detail(state, emit, order.order_id),
                @html.span(order_status_label(state.locale, order.status)),
                @html.span(order.gpu_sku + " · " + order.display_amount),
              ])
            }
          ],
        ),
      ])
    } else {
      @html.nothing
    },
    @html.div(class="wizard-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=self_service_command(emit, RestartSelfService),
        enterprise_copy(state.locale, StartAnotherOrder),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(enterprise_copy(state.locale, IntegrationContract)),
      @html.p(
        "GET /v1/portal/self/machine-orders · POST /v1/portal/self/machine-orders/{id}/cancel · POST /v1/portal/self/machine-orders/{id}/terminate · X-LunaNexa-Organization: <selected organization>",
      ),
    ]),
  ])
}

///|
fn self_service_view(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  @html.div(class="self-service-page page-stack", [
    self_service_progress(state),
    if state.self_service.action_error is Some(error) {
      @html.div(
        class="notice is-error",
        attrs=@html.Attrs::build().role("alert"),
        error,
      )
    } else {
      @html.nothing
    },
    match state.self_service.step {
      ChooseService => product_choices(state, emit, false)
      Organization => organization_step(state, emit)
      Capacity => capacity_step(state, emit)
      Quote => quote_step(state, emit)
      ContractPayment => contract_payment_step(state, emit)
      Provisioning => provisioning_step(state, emit)
    },
  ])
}

///|
fn self_service_styles() -> String {
  let styles =
    #|.service-entry,.guided-panel{padding:1.35rem;border:1px solid var(--line);border-radius:.85rem;background:linear-gradient(145deg,rgba(17,31,41,.96),rgba(10,22,29,.96))}.service-choice-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:.85rem;margin-top:1rem}.service-choice{display:flex;min-width:0;flex-direction:column;padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.service-choice h3{margin:.15rem 0 .45rem;font-size:1.15rem}.service-choice>p:not(.eyebrow){color:var(--muted)}.service-choice .service-outcome{margin-top:auto;padding-top:.75rem;color:var(--ink)!important;font-weight:750}.service-choice button{width:100%}.purchase-progress{overflow-x:auto;padding:.8rem 1rem;border:1px solid var(--line);border-radius:.75rem;background:rgba(7,16,22,.7)}.purchase-progress ol{min-width:46rem;display:grid;grid-template-columns:repeat(6,1fr);gap:.5rem;margin:0;padding:0;list-style:none}.purchase-progress li{display:flex;align-items:center;gap:.45rem;color:var(--muted);font-size:.72rem}.purchase-progress li span{width:1.75rem;height:1.75rem;display:grid;flex:0 0 auto;place-items:center;border:1px solid var(--line);border-radius:50%;font-weight:850}.purchase-progress li.is-complete{color:var(--mint)}.purchase-progress li.is-complete span{background:var(--mint);color:#06251a}.purchase-progress li.is-current{color:var(--amber)}.purchase-progress li.is-current span{border-color:var(--amber)}.guided-panel>h2{margin:.15rem 0 .45rem}.guided-panel>p:not(.eyebrow){max-width:54rem;color:var(--muted)}.segmented-control{display:flex;width:fit-content;gap:.35rem;margin:1rem 0;padding:.25rem;border:1px solid var(--line);border-radius:.65rem}.segment{min-height:44px;padding:.55rem .85rem;border:0;border-radius:.45rem;background:transparent;color:var(--muted);font:inherit;font-weight:750;cursor:pointer}.segment.is-selected{background:rgba(126,224,189,.12);color:var(--mint)}.guided-form{margin-top:1rem;padding-top:1rem;border-top:1px solid var(--line)}.guided-form>.primary-button{margin-left:auto;display:block}.wizard-actions{display:flex;justify-content:space-between;gap:.6rem;margin-top:1rem}.selection-summary{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.75rem;margin:1rem 0}.selection-summary>div{min-width:0;padding:.75rem;border:1px solid var(--line);border-radius:.55rem;background:rgba(7,16,22,.45)}.selection-summary dt{color:var(--muted);font-size:.68rem}.selection-summary dd{margin:.2rem 0 0}.integration-contract{margin-top:1rem;padding:.7rem;border:1px dashed #51636d;border-radius:.55rem;color:var(--muted)}.integration-contract summary{min-height:44px;display:flex;align-items:center;color:var(--ink);font-weight:750;cursor:pointer}.integration-contract p{overflow-wrap:anywhere}.offering-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:.8rem;margin-top:1rem}.offering-card{padding:1rem;border:1px solid var(--line);border-radius:.75rem;background:var(--panel)}.offering-card.is-selected{border-color:var(--mint2);box-shadow:0 0 0 1px rgba(126,224,189,.18)}.offering-heading{display:flex;justify-content:space-between;gap:1rem}.offering-heading h3{margin:0}.offering-heading p{margin:.2rem 0;color:var(--muted)}.availability{height:fit-content;padding:.25rem .45rem;border:1px solid var(--line);border-radius:999px;color:var(--muted);font-size:.67rem}.availability.available{color:var(--mint)}.price-summary{font-size:1.05rem;font-weight:800;color:var(--ink)!important}.offering-card>button{width:100%}.capacity-configuration{margin-top:1.2rem}.capacity-configuration select{width:100%;min-height:44px;padding:.6rem .75rem;border:1px solid #35505f;border-radius:.5rem;background:#09151c;color:var(--ink);font:inherit}.read-only-value{min-height:44px;margin:0;padding:.65rem .75rem;border:1px solid var(--line);border-radius:.5rem;color:var(--muted)}.inline-state{padding:1rem;border:1px dashed var(--line);border-radius:.65rem;background:rgba(7,16,22,.35);color:var(--muted)}.inline-state.is-error{border-color:#7f4148;color:#ffb2b8}.inline-state h3{margin-top:0}.quote-review{margin-top:1rem}.quote-facts{grid-template-columns:repeat(4,minmax(0,1fr))}.quote-total{color:var(--mint);font-size:1.3rem;font-weight:850}.trust-callout{padding:.8rem;border-left:3px solid var(--mint);background:rgba(126,224,189,.06);color:var(--muted)}.quote-review>code{display:block;margin:.75rem 0}.quote-review>.primary-button{display:block;margin-left:auto}.terms-acceptance,.recent-machine-orders{display:grid;gap:.6rem;margin:1rem 0;padding:1rem;border:1px solid var(--line);border-radius:.65rem;background:rgba(7,16,22,.45)}.terms-acceptance p,.recent-machine-orders h3{margin:0}.recent-machine-orders ul{display:grid;gap:.5rem;margin:0;padding:0;list-style:none}.recent-machine-orders li{display:grid;grid-template-columns:minmax(10rem,1fr) auto minmax(12rem,1fr);gap:.75rem;align-items:center;padding:.7rem;border-top:1px solid var(--line)}.action-link{display:inline-flex;align-items:center;justify-content:center;text-decoration:none}.provider-checkout-state{font-size:.72rem}.order-gates{display:grid;gap:.75rem;margin-top:1rem}.gate-row{display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;gap:.8rem;padding:1rem;border:1px solid var(--line);border-radius:.7rem;background:var(--panel)}.gate-row h3,.gate-row p{margin:.1rem 0}.gate-row p{color:var(--muted)}.gate-mark{width:2rem;height:2rem;display:grid;place-items:center;border:1px solid var(--amber);border-radius:50%;color:var(--amber);font-weight:850}.gate-mark.ready{border-color:var(--mint2);background:var(--mint);color:#06251a}.order-reference{display:flex;flex-wrap:wrap;justify-content:space-between;gap:.5rem;padding:.8rem;border-left:3px solid var(--mint);background:rgba(126,224,189,.06)}.order-gates>.primary-button{justify-self:end}.order-status-heading{display:flex;justify-content:space-between;gap:1rem}.order-status-heading p{margin:.25rem 0;color:var(--muted)}.provisioning-timeline{display:grid;gap:0;margin:1rem 0;padding:0;list-style:none}.provisioning-timeline li{position:relative;padding:0 0 1.2rem 2rem;color:var(--muted)}.provisioning-timeline li:before{content:"";position:absolute;left:.35rem;top:.25rem;width:.65rem;height:.65rem;border:2px solid var(--line);border-radius:50%;background:var(--bg)}.provisioning-timeline li:after{content:"";position:absolute;left:.7rem;top:1rem;bottom:0;width:1px;background:var(--line)}.provisioning-timeline li:last-child:after{display:none}.provisioning-timeline li.is-current:before{border-color:var(--amber)}.provisioning-timeline li.is-complete:before{border-color:var(--mint2);background:var(--mint)}.provisioning-timeline strong{color:var(--ink)}.provisioning-timeline p{margin:.2rem 0}.self-service-page>.notice{margin:0}@media(max-width:74rem){.service-choice-grid{grid-template-columns:1fr}.quote-facts{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:52rem){.offering-grid,.selection-summary,.quote-facts{grid-template-columns:1fr}.gate-row{grid-template-columns:auto minmax(0,1fr)}.gate-row button{grid-column:1/-1;width:100%}.wizard-actions{display:grid}.wizard-actions>*{width:100%}.segmented-control{width:100%}.segment{flex:1}.guided-form>.primary-button,.quote-review>.primary-button,.order-gates>.primary-button{width:100%;margin-left:0}.order-status-heading{flex-direction:column}.purchase-progress{margin-inline:-1rem;border-left:0;border-right:0;border-radius:0}.recent-machine-orders li{grid-template-columns:1fr}.action-link{width:100%}}@media(max-width:32rem){.segmented-control{display:grid}.offering-heading{flex-direction:column}.availability{width:fit-content}}
  let controls =
    #|.organization-control{display:flex;align-items:center;gap:.4rem}.organization-control label{color:var(--muted);font-size:.7rem}.organization-control select,.guided-form .field select{min-height:44px;padding:.5rem 1.8rem .5rem .65rem;border:1px solid #35505f;border-radius:.45rem;background:#09151c;color:var(--ink);font:inherit}.organization-control select{max-width:20rem}@media(max-width:52rem){.organization-control{width:100%;display:grid}.organization-control select{width:100%;max-width:none}}
  styles + controls
}
