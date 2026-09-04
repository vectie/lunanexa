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
      { ..self, organization_mode: mode, action_error: None }
    SubjectKindChanged(value) => { ..self, subject_kind: value }
    LegalNameChanged(value) => { ..self, legal_name: value }
    CompanyDisplayNameChanged(value) => { ..self, display_name: value }
    CountryRegionChanged(value) => { ..self, country_region: value }
    RegisteredAddressChanged(value) => { ..self, registered_address: value }
    RegistrationNumberChanged(value) => { ..self, registration_number: value }
    TaxIdentifierChanged(value) => { ..self, tax_identifier: value }
    BillingContactNameChanged(value) => { ..self, billing_contact_name: value }
    BillingEmailChanged(value) => { ..self, billing_email: value }
    InvitationCodeChanged(value) => { ..self, invitation_code: value }
    SubmitCreateCompany
    | SubmitJoinCompany
    | RefreshOrganizations
    | RequestQuote
    | CreateMachineOrder
    | AcceptMachineTerms
    | RefreshMachineOrders
    | CancelMachineOrder(_, _)
    | TerminateMachineOrder(_, _) =>
      { ..self, action_loading: true, action_error: None }
    ConfirmMachineTermsReviewed =>
      { ..self, terms_reviewed: true, action_error: None }
    ContinueWithOrganization => { ..self, step: Capacity, action_error: None }
    RefreshOfferings =>
      { ..self, offerings_loading: true, offerings_error: None }
    SelectOffering(offering_id) => {
      let template = match
        self.offerings
        .iter()
        .find_first(value => value.offering_id == offering_id) {
        Some(value) => value.allowed_model_template_refs.get(0).unwrap_or("")
        None => ""
      }
      {
        ..self,
        selected_offering_id: offering_id,
        region: "",
        model_template_ref: template,
        quote: None,
        action_error: None,
      }
    }
    SelfServiceProjectChanged(value) => { ..self, project_id: value }
    UnixUsernameChanged(value) => { ..self, unix_username: value }
    RegionChanged(value) => { ..self, region: value, quote: None }
    DurationChanged(value) => { ..self, duration_hours: value, quote: None }
    ModelSelectorChanged(value) =>
      { ..self, model_selector: value, quote: None }
    ModelTemplateChanged(value) =>
      { ..self, model_template_ref: value, quote: None }
    ViewProvisioning => { ..self, step: Provisioning, action_error: None }
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
    DismissSelfServiceError => { ..self, action_error: None }
  }
}

///|
pub fn company_creation_valid(state : SelfServiceState) -> Bool {
  state.legal_name.trim() != "" &&
  state.legal_name.length() <= 256 &&
  state.display_name.trim() != "" &&
  state.display_name.length() <= 128 &&
  (state.subject_kind == "Company" || state.subject_kind == "Individual") &&
  state.country_region.trim().length() == 2 &&
  state.registered_address.trim() != "" &&
  state.registered_address.length() <= 512 &&
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
    SharedMaaS => copy(locale, "Shared MaaS", "共享 MaaS")
    DedicatedMaaS => copy(locale, "Dedicated MaaS", "专属 MaaS")
    BareGpu => copy(locale, "Bare GPU", "裸 GPU")
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
    @html.h3(title),
    @html.p(description),
    @html.p(class="service-outcome", outcome),
    @html.button(
      type_="button",
      class="quiet-button",
      on_click=self_service_command(emit, SelectProduct(product)),
      copy(state.locale, "Choose this service", "选择此服务"),
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
            copy(state.locale, "START WITH AN OUTCOME", "从目标开始"),
          ),
          @html.h2(
            copy(
              state.locale,
              "What do you want to run?",
              "您希望以哪种方式运行？",
            ),
          ),
          @html.p(
            copy(
              state.locale,
              "Choose an API, a managed dedicated endpoint, or a machine you control. You can go back without losing entered values.",
              "选择共享 API、托管专属端点，或由您控制的机器。返回上一步不会丢失已填写内容。",
            ),
          ),
        ]),
      ]),
      @html.div(class="service-choice-grid", [
        product_card(
          state,
          emit,
          SharedMaaS,
          copy(state.locale, "Call a model API", "调用模型 API"),
          copy(
            state.locale,
            "No machine selection. Start with a quota-bound key and pay for measured inference.",
            "无需选择机器。先创建受额度约束的密钥，按实际推理用量付费。",
          ),
          copy(
            state.locale,
            "You receive an API key",
            "您将获得 API 密钥",
          ),
        ),
        product_card(
          state,
          emit,
          DedicatedMaaS,
          copy(
            state.locale,
            "Deploy a private model endpoint",
            "部署专属模型端点",
          ),
          copy(
            state.locale,
            "Choose a GPU and approved model. LunaNexa transfers, deploys, and operates the endpoint.",
            "选择 GPU 与已批准模型，由 LunaNexa 完成传输、部署与端点运维。",
          ),
          copy(
            state.locale,
            "You receive a private endpoint",
            "您将获得专属端点",
          ),
        ),
        product_card(
          state,
          emit,
          BareGpu,
          copy(state.locale, "Rent a GPU workspace", "租用 GPU 工作区"),
          copy(
            state.locale,
            "Choose capacity and manage your own software through short-lived SSH or WebIDE access.",
            "选择算力，并通过短期 SSH 或 WebIDE 自主管理软件。",
          ),
          copy(
            state.locale,
            "You receive SSH and WebIDE access",
            "您将获得 SSH 与 WebIDE 访问",
          ),
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
    copy(state.locale, "Service", "服务"),
    copy(state.locale, "Organization", "组织"),
    copy(state.locale, "Capacity", "配置"),
    copy(state.locale, "Quote", "报价"),
    copy(state.locale, "Contract & payment", "合同与支付"),
    copy(state.locale, "Provisioning", "开通"),
  ]
  @html.nav(
    class="purchase-progress",
    attrs=@html.Attrs::build().aria_label(
      copy(state.locale, "Order progress", "订单进度"),
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
fn organization_step(
  state : EnterpriseState,
  emit : @rabbita.Emit[EnterpriseMessage]?,
) -> @rabbita.Html {
  match state.membership {
    Some(membership) if membership.active => {
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
        @html.p(class="eyebrow", copy(state.locale, "ORGANIZATION", "组织")),
        @html.h2(
          if organization_active {
            copy(state.locale, "Organization ready", "组织已就绪")
          } else {
            copy(
              state.locale,
              "Organization verification pending",
              "组织验证待完成",
            )
          },
        ),
        @html.p(
          if organization_active {
            copy(
              state.locale,
              "This order will be owned by your active organization. Tenant and subject identifiers are derived from your signed-in session.",
              "该订单将归属于您的活跃组织。租户和用户标识均从登录会话中派生。",
            )
          } else {
            copy(
              state.locale,
              "Your company record exists, but machine ordering remains fail-closed until verification succeeds. Shared trial access is unaffected.",
              "公司记录已创建，但完成验证前机器下单保持失败关闭；共享试用不受影响。",
            )
          },
        ),
        @html.dl(class="selection-summary", [
          @html.div([
            @html.dt(copy(state.locale, "Organization", "组织")),
            @html.dd(class="mono", membership.organization_id),
          ]),
          @html.div([
            @html.dt(copy(state.locale, "Tenant", "租户")),
            @html.dd(class="mono", membership.tenant_ref),
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
                  copy(state.locale, "Verify organization", "验证组织"),
                ),
              ])
            Some(value) if value.blocker_code ==
              Some("CommercialProviderUnavailable") =>
              @html.div(
                class="notice is-error",
                attrs=@html.Attrs::build().role("alert"),
                copy(
                  state.locale,
                  "Identity verification provider is unavailable. Machine ordering remains blocked; contact platform support.",
                  "身份验证服务商不可用。机器下单保持关闭，请联系平台支持。",
                ),
              )
            Some(value) if value.blocker_code ==
              Some("IdentityVerificationQueueRetryRequired") =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                copy(
                  state.locale,
                  "Verification dispatch needs retry. Refreshing this organization safely retries the durable request.",
                  "验证派发需要重试；刷新组织会安全重试持久化请求。",
                ),
              )
            _ =>
              @html.div(
                class="inline-state",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                copy(
                  state.locale,
                  "The verification request is pending while the provider prepares the secure action.",
                  "验证请求已进入等待，服务商正在准备安全操作入口。",
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
            copy(state.locale, "Back", "返回"),
          ),
          if !organization_active {
            @html.button(
              type_="button",
              class="quiet-button",
              disabled=state.self_service.action_loading,
              on_click=self_service_command(emit, RefreshOrganizations),
              copy(state.locale, "Refresh verification", "刷新验证状态"),
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
              copy(state.locale, "Continue", "继续")
            } else {
              copy(state.locale, "Waiting for verification", "等待验证")
            },
          ),
        ]),
      ])
    }
    _ =>
      @html.section(class="guided-panel", [
        @html.p(class="eyebrow", copy(state.locale, "ORGANIZATION", "组织")),
        @html.h2(
          copy(
            state.locale,
            "Create a company or join one",
            "创建公司或加入已有公司",
          ),
        ),
        @html.p(
          copy(
            state.locale,
            "A company identity provider is optional. Sign in with the platform identity service, then create the legal customer record here.",
            "无需企业身份系统。先使用平台身份服务登录，再在这里建立正式客户主体。",
          ),
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
            copy(state.locale, "Create company", "创建公司"),
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
            copy(state.locale, "Join company", "加入公司"),
          ),
        ]),
        if state.self_service.organization_mode == CreateCompany {
          @html.div(class="guided-form", [
            @html.div(class="form-grid", [
              @html.div(class="field", [
                @html.label(
                  for_="company-subject-kind",
                  copy(state.locale, "Legal subject type", "主体类型"),
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
                      copy(state.locale, "Company", "企业"),
                    ),
                    @html.option(
                      value="Individual",
                      selected=state.self_service.subject_kind == "Individual",
                      copy(state.locale, "Individual", "个人"),
                    ),
                  ],
                ),
              ]),
              @html.div(class="field", [
                @html.label(
                  for_="company-legal-name",
                  copy(state.locale, "Legal name", "法定名称"),
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
                  copy(state.locale, "Display name", "显示名称"),
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
                  copy(state.locale, "Country code", "国家代码"),
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
                  copy(
                    state.locale,
                    "Registration number (optional)",
                    "注册号（可选）",
                  ),
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
                  copy(
                    state.locale,
                    "Tax or registration ID (optional)",
                    "税号或注册号（可选）",
                  ),
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
                  copy(state.locale, "Registered address", "注册地址"),
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
                  copy(state.locale, "Billing contact", "账单联系人"),
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
                  copy(state.locale, "Billing email", "账单邮箱"),
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
                  copy(
                    state.locale,
                    "The creator becomes organization owner. Machine ordering remains blocked until required verification succeeds.",
                    "创建者将成为组织所有者；完成必要验证前，机器下单保持关闭。",
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
                copy(
                  state.locale,
                  "Creating company…",
                  "正在创建公司…",
                )
              } else {
                copy(state.locale, "Create company", "创建公司")
              },
            ),
          ])
        } else {
          @html.div(class="guided-form", [
            @html.div(class="field", [
              @html.label(
                for_="company-invitation",
                copy(state.locale, "Invitation code", "邀请码"),
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
                copy(
                  state.locale,
                  "The signed, one-time invitation selects the organization and granted roles. Do not paste an organization ID.",
                  "一次性签名邀请会确定组织与授权角色，无需粘贴组织 ID。",
                ),
              ),
            ]),
            @html.button(
              type_="button",
              class="primary-button",
              disabled=!company_join_valid(state.self_service),
              on_click=self_service_command(emit, SubmitJoinCompany),
              if state.self_service.action_loading {
                copy(
                  state.locale,
                  "Joining company…",
                  "正在加入公司…",
                )
              } else {
                copy(state.locale, "Join company", "加入公司")
              },
            ),
          ])
        },
        @html.div(class="wizard-actions", [
          @html.button(
            type_="button",
            class="quiet-button",
            on_click=self_service_command(emit, PreviousSelfServiceStep),
            copy(state.locale, "Back", "返回"),
          ),
        ]),
        @html.details(class="integration-contract", [
          @html.summary(
            copy(state.locale, "Integration contract", "集成契约"),
          ),
          @html.p(
            copy(
              state.locale,
              "List or create: GET/POST /v1/portal/self/organizations. Creation sends a legal profile; organization, tenant, owner membership, cost center and project identifiers are server-derived. Join uses POST /v1/portal/self/invitations:accept with a one-time invitation secret. Ambiguous multi-organization requests fail closed until X-LunaNexa-Organization is selected.",
              "查询或创建：GET/POST /v1/portal/self/organizations。创建时提交法定主体资料；组织、租户、所有者成员资格、成本中心与项目标识均由服务端派生。加入使用一次性邀请密钥调用 POST /v1/portal/self/invitations:accept。多组织选择不明确时请求失败关闭，直至选择 X-LunaNexa-Organization。",
            ),
          ),
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
          @html.p(class="mono", offering.gpu_sku),
        ]),
        @html.span(
          class=if offering.available {
            "availability available"
          } else {
            "availability"
          },
          if offering.available {
            copy(state.locale, "Available", "可用")
          } else {
            copy(state.locale, "Unavailable", "暂无资源")
          },
        ),
      ]),
      @html.dl(class="selection-summary", [
        @html.div([
          @html.dt(copy(state.locale, "GPU", "GPU")),
          @html.dd("\{offering.accelerator_count}"),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Memory", "显存")),
          @html.dd("\{offering.accelerator_memory_mib / 1024} GiB"),
        ]),
        @html.div([
          @html.dt(copy(state.locale, "Regions", "区域")),
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
          copy(state.locale, "Selected", "已选择")
        } else {
          copy(state.locale, "Select capacity", "选择此配置")
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
      @html.h2(
        copy(
          state.locale,
          "Start with the shared API",
          "开始使用共享 API",
        ),
      ),
      @html.p(
        copy(
          state.locale,
          "Shared MaaS does not require a machine order. Choose an approved model and create a quota-bound API key from your account.",
          "共享 MaaS 无需机器订单。请从账户中选择已批准模型并创建受额度约束的 API 密钥。",
        ),
      ),
      @html.div(class="wizard-actions", [
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, PreviousSelfServiceStep),
          copy(state.locale, "Back", "返回"),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          on_click=command(emit, Navigate(AccountAccess)),
          copy(state.locale, "Create API key", "创建 API 密钥"),
        ),
      ]),
    ])
  }
  let matching = state.self_service.offerings.filter(value => {
    value.kind == product
  })
  let chosen = selected_offering(state.self_service)
  let region_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.self_service.region == "",
      copy(state.locale, "Select a region", "选择区域"),
    ),
  ]
  let model_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.self_service.model_selector == "",
      copy(state.locale, "Select a model", "选择模型"),
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
    @html.h2(copy(state.locale, "Choose capacity", "选择算力配置")),
    @html.p(
      if product == DedicatedMaaS {
        copy(
          state.locale,
          "The selected approved model will be transferred from object storage and deployed after payment settles.",
          "支付完成后，系统会从对象存储传输已批准模型并自动部署。",
        )
      } else {
        copy(
          state.locale,
          "You receive an isolated workspace. No managed model is installed unless you choose Dedicated MaaS.",
          "您将获得隔离工作区。除非选择专属 MaaS，否则不会安装托管模型。",
        )
      },
    ),
    if state.self_service.offerings_loading {
      @html.p(
        class="inline-state",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        copy(
          state.locale,
          "Loading live capacity…",
          "正在加载实时算力…",
        ),
      )
    } else if state.self_service.offerings_error is Some(error) {
      @html.div(class="inline-state is-error", [
        @html.p(attrs=@html.Attrs::build().role("alert"), error),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, RefreshOfferings),
          copy(state.locale, "Retry catalog", "重试加载目录"),
        ),
      ])
    } else if state.self_service.offerings_loaded && matching.length() == 0 {
      @html.div(class="inline-state", [
        @html.h3(
          copy(state.locale, "No capacity available", "当前无可用算力"),
        ),
        @html.p(
          copy(
            state.locale,
            "Try another service or refresh availability. No order has been created.",
            "请选择其他服务或刷新库存。当前尚未创建订单。",
          ),
        ),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, RefreshOfferings),
          copy(state.locale, "Refresh availability", "刷新库存"),
        ),
      ])
    } else if !state.self_service.offerings_loaded {
      @html.div(class="inline-state", [
        @html.p(
          copy(
            state.locale,
            "Load current SKU, region and availability data before configuring an order.",
            "请先加载当前 SKU、区域和库存数据，再配置订单。",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          on_click=self_service_command(emit, RefreshOfferings),
          copy(state.locale, "Load capacity", "加载算力"),
        ),
      ])
    } else {
      @html.div(
        class="offering-grid",
        [
          for offering in matching => offering_card(state, emit, offering)
        ],
      )
    },
    match chosen {
      Some(offering) if offering.kind == product =>
        @html.div(class="guided-form capacity-configuration", [
          @html.h3(copy(state.locale, "Configure order", "配置订单")),
          @html.div(class="form-grid", [
            @html.div(class="field", [
              @html.label(
                for_="self-service-project",
                copy(state.locale, "Project", "项目"),
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
                  copy(state.locale, "Linux username", "Linux 用户名"),
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
                  copy(
                    state.locale,
                    "Required for bare GPU access: start with a lowercase letter; use a–z, 0–9, _ or -. Reserved system names are rejected.",
                    "裸 GPU 访问必填：以小写字母开头，只可使用 a–z、0–9、_ 或 -；系统保留名称会被拒绝。",
                  ),
                ),
              ])
            } else {
              @html.nothing
            },
            @html.div(class="field", [
              @html.label(
                for_="self-service-region",
                copy(state.locale, "Region", "区域"),
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
                copy(state.locale, "Rental period", "租用周期"),
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
                    copy(state.locale, "24 hours", "24 小时"),
                  ),
                  @html.option(
                    value="168",
                    selected=state.self_service.duration_hours == 168,
                    copy(state.locale, "7 days", "7 天"),
                  ),
                  @html.option(
                    value="720",
                    selected=state.self_service.duration_hours == 720,
                    copy(state.locale, "30 days", "30 天"),
                  ),
                ],
              ),
              @html.small(
                "\{offering.minimum_duration_hours}–\{offering.maximum_duration_hours} \{copy(state.locale, "hours allowed", "小时可选")}",
              ),
            ]),
            if product == DedicatedMaaS {
              @html.div([
                @html.div(class="field", [
                  @html.label(
                    for_="self-service-model",
                    copy(state.locale, "Approved model", "已批准模型"),
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
                      copy(
                        state.locale,
                        "No approved model is available for this organization.",
                        "该组织当前没有可部署的已批准模型。",
                      ),
                    )
                  } else {
                    @html.small(
                      copy(
                        state.locale,
                        "Only catalog-approved models can be materialized.",
                        "仅可传输并部署目录中已批准的模型。",
                      ),
                    )
                  },
                ]),
                @html.div(class="field", [
                  @html.label(
                    for_="self-service-model-template",
                    copy(state.locale, "Deployment template", "部署模板"),
                  ),
                  @html.select(
                    id="self-service-model-template",
                    on_change=self_service_text_command(emit, value => {
                      ModelTemplateChanged(value)
                    }),
                    template_options,
                  ),
                  @html.small(
                    copy(
                      state.locale,
                      "Only templates reviewed for this SKU can be quoted.",
                      "仅可报价已针对该 SKU 审核的模板。",
                    ),
                  ),
                ]),
              ])
            } else {
              @html.div(class="field", [
                @html.label(copy(state.locale, "Managed model", "托管模型")),
                @html.p(
                  class="read-only-value",
                  copy(
                    state.locale,
                    "None — you manage this workspace",
                    "无——由您自行管理工作区",
                  ),
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
              copy(
                state.locale,
                "Calculating signed quote…",
                "正在计算签名报价…",
              )
            } else {
              copy(state.locale, "Review price", "查看报价")
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
        copy(state.locale, "Back", "返回"),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(copy(state.locale, "Integration contract", "集成契约")),
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
    @html.p(class="eyebrow", copy(state.locale, "SIGNED QUOTE", "签名报价")),
    @html.h2(
      copy(state.locale, "Review price and scope", "核对价格与范围"),
    ),
    if state.self_service.action_loading {
      @html.p(
        class="inline-state",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        copy(
          state.locale,
          "Calculating an authoritative quote…",
          "正在计算权威报价…",
        ),
      )
    } else if state.self_service.action_error is Some(error) {
      @html.div(class="inline-state is-error", [
        @html.p(attrs=@html.Attrs::build().role("alert"), error),
        @html.button(
          type_="button",
          class="quiet-button",
          on_click=self_service_command(emit, DismissSelfServiceError),
          copy(state.locale, "Dismiss", "关闭"),
        ),
      ])
    } else {
      match state.self_service.quote {
        Some(quote) =>
          @html.div(class="quote-review", [
            @html.dl(class="selection-summary quote-facts", [
              @html.div([
                @html.dt(copy(state.locale, "Total", "总额")),
                @html.dd(class="quote-total", quote.display_amount),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Quote", "报价")),
                @html.dd(class="mono", quote.quote_id),
              ]),
              @html.div([
                @html.dt(copy(state.locale, "Valid until", "有效期至")),
                @html.dd(
                  @contractdoc.format_unix_ms_utc(quote.valid_until_unix_ms),
                ),
              ]),
              @html.div([
                @html.dt(
                  copy(state.locale, "Currency / scale", "币种 / 精度"),
                ),
                @html.dd("\{quote.currency} / \{quote.money_scale}"),
              ]),
            ]),
            @html.p(
              class="trust-callout",
              copy(
                state.locale,
                "Amount, availability window and terms digest are server-derived and signed. Creating the order is idempotent; it does not mark payment as settled.",
                "金额、库存窗口与条款摘要均由服务端派生并签名。创建订单可安全重试，且不会伪造支付成功状态。",
              ),
            ),
            @html.code(class="mono", quote.terms_digest),
            if !agreements_ready {
              match state.self_service.terms {
                Some(terms) =>
                  @html.div(class="terms-acceptance", [
                    @html.strong(
                      copy(
                        state.locale,
                        "Machine self-service terms",
                        "机器自助服务条款",
                      ),
                    ),
                    @html.p(
                      "\{terms.template_id} · \{terms.version} · \{terms.locale}",
                    ),
                    @html.code(class="mono", terms.rendered_document_hash),
                    @html.a(
                      class="quiet-button action-link",
                      href=terms.document_uri,
                      target=Blank,
                      rel="noopener noreferrer",
                      escape=true,
                      copy(
                        state.locale,
                        "Open immutable terms document",
                        "打开不可变条款文档",
                      ),
                    ),
                    if state.self_service.terms_accepted {
                      @html.p(
                        class="success-copy",
                        copy(
                          state.locale,
                          "Acceptance evidence recorded for this session.",
                          "本次会话的接受证据已记录。",
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
                            copy(
                              state.locale,
                              "Document reviewed",
                              "已阅读文档",
                            )
                          } else {
                            copy(
                              state.locale,
                              "I reviewed this document",
                              "我已阅读此文档",
                            )
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
                          copy(
                            state.locale,
                            "Accept terms to continue",
                            "接受条款并继续",
                          ),
                        ),
                      ])
                    },
                  ])
                None =>
                  @html.p(
                    class="notice is-error",
                    attrs=@html.Attrs::build().role("alert"),
                    copy(
                      state.locale,
                      "Machine terms are unavailable. Ordering remains blocked.",
                      "机器条款不可用，下单保持关闭。",
                    ),
                  )
              }
            } else {
              @html.p(
                class="success-copy",
                copy(
                  state.locale,
                  "An executed organization agreement satisfies the machine terms gate.",
                  "组织已执行的协议满足机器条款门槛。",
                ),
              )
            },
            @html.button(
              type_="button",
              class="primary-button",
              disabled=!terms_ready || state.self_service.action_loading,
              on_click=self_service_command(emit, CreateMachineOrder),
              copy(state.locale, "Create order", "创建订单"),
            ),
          ])
        None =>
          @html.div(class="inline-state", [
            @html.h3(
              copy(state.locale, "Quote not available", "报价尚未生成"),
            ),
            @html.p(
              copy(
                state.locale,
                "Return to capacity, verify the configuration, and request a fresh quote.",
                "请返回配置步骤，确认参数后重新请求报价。",
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
        copy(state.locale, "Back to capacity", "返回配置"),
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
    AwaitingPayment => copy(locale, "Awaiting payment", "等待支付")
    PaymentSettled => copy(locale, "Payment settled", "支付已结算")
    ProvisioningOrder => copy(locale, "Provisioning", "正在开通")
    ActiveOrder => copy(locale, "Active", "已开通")
    CancellationPending => copy(locale, "Cancellation pending", "正在取消")
    TerminationPending => copy(locale, "Termination pending", "正在终止")
    CompensationPending => copy(locale, "Compensation pending", "正在补偿")
    CancelledOrder => copy(locale, "Cancelled", "已取消")
    TerminatedOrder => copy(locale, "Terminated", "已终止")
    FailedOrder => copy(locale, "Failed", "失败")
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
    @html.p(
      class="eyebrow",
      copy(state.locale, "CONTRACT & PAYMENT", "合同与支付"),
    ),
    @html.h2(
      copy(state.locale, "Complete commercial gates", "完成商业准入"),
    ),
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
              @html.h3(
                copy(state.locale, "Required agreements", "必需协议"),
              ),
              @html.p(
                if agreements_ready {
                  copy(
                    state.locale,
                    "Executed evidence is verified.",
                    "签署证据已验证。",
                  )
                } else {
                  copy(
                    state.locale,
                    "A legal signer must complete every required agreement.",
                    "法定签署人必须完成全部必需协议。",
                  )
                },
              ),
            ]),
            @html.button(
              type_="button",
              class="quiet-button",
              on_click=command(emit, Navigate(Agreements)),
              copy(state.locale, "Open agreements", "打开协议"),
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
              @html.h3(copy(state.locale, "Secure payment", "安全支付")),
              @html.p(
                if order.status == AwaitingPayment {
                  copy(
                    state.locale,
                    "Payment settlement is verified independently before capacity is reserved.",
                    "系统独立验证支付结算后才会预留算力。",
                  )
                } else {
                  copy(
                    state.locale,
                    "Payment evidence received.",
                    "已收到支付证据。",
                  )
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
                      copy(
                        state.locale,
                        "Open secure checkout",
                        "打开安全支付",
                      ),
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
                    copy(
                      state.locale,
                      "Refresh payment status",
                      "刷新支付状态",
                    )
                  } else {
                    copy(state.locale, "Refresh order", "刷新订单")
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
              "\{copy(state.locale, "Order", "订单")} · \{order_status_label(state.locale, order.status)}",
            ),
            @html.code(class="mono", order.order_id),
          ]),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=order.status == AwaitingPayment,
            on_click=self_service_command(emit, ViewProvisioning),
            copy(state.locale, "Track provisioning", "跟踪开通进度"),
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
              copy(state.locale, "Cancel unpaid order", "取消未支付订单"),
            )
          } else {
            @html.nothing
          },
        ])
      None =>
        @html.div(class="inline-state", [
          @html.h3(
            copy(state.locale, "Order not created", "订单尚未创建"),
          ),
          @html.p(
            copy(
              state.locale,
              "No payment request will be created until an idempotent machine order exists.",
              "创建可安全重试的机器订单之前，系统不会发起支付请求。",
            ),
          ),
        ])
    },
    @html.div(class="wizard-actions", [
      @html.button(
        type_="button",
        class="quiet-button",
        on_click=self_service_command(emit, PreviousSelfServiceStep),
        copy(state.locale, "Back to quote", "返回报价"),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(copy(state.locale, "Integration contract", "集成契约")),
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
    @html.p(class="eyebrow", copy(state.locale, "LIVE ORDER", "实时订单")),
    @html.h2(copy(state.locale, "Provisioning progress", "开通进度")),
    match state.self_service.order {
      Some(order) =>
        @html.div([
          @html.div(class="order-status-heading", [
            @html.div([
              @html.strong(order_status_label(state.locale, order.status)),
              @html.p(class="mono", order.order_id),
            ]),
            @html.span(
              class="state-pill",
              "\{copy(state.locale, "Generation", "版本")} \{order.generation}",
            ),
          ]),
          match order.status {
            CompensationPending =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                copy(
                  state.locale,
                  "Payment was verified, but capacity could not be completed. Cleanup and refund compensation are being reconciled; do not place a duplicate order.",
                  "支付已验证，但算力未能完成开通。系统正在核对清理与退款补偿，请勿重复下单。",
                ),
              )
            FailedOrder =>
              @html.div(
                class="notice is-error",
                attrs=@html.Attrs::build().role("alert"),
                copy(
                  state.locale,
                  "This order failed. Refresh for the durable final state before starting another order.",
                  "该订单失败。创建新订单前，请刷新并确认其持久化最终状态。",
                ),
              )
            CancellationPending | TerminationPending =>
              @html.div(
                class="notice is-warning",
                attrs=@html.Attrs::build().role("status").aria_live("polite"),
                copy(
                  state.locale,
                  "The requested shutdown is in progress. Access remains untrusted until cleanup is verified.",
                  "关停请求正在处理中；完成清理验证前，不应继续信任访问状态。",
                ),
              )
            _ => @html.nothing
          },
          @html.ol(class="provisioning-timeline", [
            @html.li(class="is-complete", [
              @html.strong(
                copy(state.locale, "Order accepted", "订单已受理"),
              ),
              @html.p(
                copy(
                  state.locale,
                  "Commercial scope is immutable.",
                  "商业范围已固定。",
                ),
              ),
            ]),
            @html.li(
              class=if order.status == AwaitingPayment {
                "is-current"
              } else {
                "is-complete"
              },
              [
                @html.strong(
                  copy(state.locale, "Payment settled", "支付结算"),
                ),
                @html.p(
                  copy(
                    state.locale,
                    "Provider evidence is verified.",
                    "支付服务商证据已验证。",
                  ),
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
                @html.strong(
                  copy(state.locale, "Capacity provisioned", "算力开通"),
                ),
                @html.p(
                  copy(
                    state.locale,
                    "A lease is reserved and prepared.",
                    "正在预留并准备租约。",
                  ),
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
                  @html.strong(
                    copy(state.locale, "Model deployed", "模型部署"),
                  ),
                  @html.p(
                    copy(
                      state.locale,
                      "Artifact transfer, verification and LunaFlux deployment are tracked together.",
                      "模型传输、校验与 LunaFlux 部署统一跟踪。",
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
                  @html.strong(
                    copy(state.locale, "Access issued", "访问已签发"),
                  ),
                  @html.p(
                    copy(
                      state.locale,
                      "Short-lived SSH and WebIDE access only.",
                      "仅签发短期 SSH 与 WebIDE 访问。",
                    ),
                  ),
                ],
              )
            },
            @html.li(
              class=if order.status == ActiveOrder { "is-complete" } else { "" },
              [
                @html.strong(copy(state.locale, "Ready", "已就绪")),
                @html.p(
                  if order.kind == DedicatedMaaS {
                    copy(
                      state.locale,
                      "Use the canonical /v1/workloads endpoint with an order-bound key from Endpoint access.",
                      "使用标准 /v1/workloads 端点，并在“端点访问”中创建订单绑定密钥。",
                    )
                  } else {
                    copy(
                      state.locale,
                      "Machine access becomes visible in My machine.",
                      "机器访问将在“我的机器”中显示。",
                    )
                  },
                ),
              ],
            ),
          ]),
          @html.dl(class="selection-summary", [
            @html.div([
              @html.dt(copy(state.locale, "GPU", "GPU")),
              @html.dd(order.gpu_sku),
            ]),
            @html.div([
              @html.dt(copy(state.locale, "Region", "区域")),
              @html.dd(order.region),
            ]),
            @html.div([
              @html.dt(copy(state.locale, "Lease", "租约")),
              @html.dd(class="mono", order.lease_ref.unwrap_or("—")),
            ]),
            @html.div([
              @html.dt(copy(state.locale, "Deployment", "部署")),
              @html.dd(class="mono", order.deployment_ref.unwrap_or("—")),
            ]),
            if order.kind == DedicatedMaaS && order.status == ActiveOrder {
              @html.div([
                @html.dt(copy(state.locale, "Endpoint", "端点")),
                @html.dd(class="mono", "/v1/workloads"),
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
                  copy(
                    state.locale,
                    "Open machine access",
                    "打开机器访问",
                  )
                } else {
                  copy(
                    state.locale,
                    "View endpoint access",
                    "查看端点访问",
                  )
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
                copy(state.locale, "Terminate service", "终止服务"),
              ),
            ])
          } else {
            @html.p(
              class="inline-state",
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              copy(
                state.locale,
                "You can safely leave this page. Progress is stored with the order and resumes here.",
                "您可以安全离开此页面。进度保存在订单中，返回后可继续跟踪。",
              ),
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
              copy(state.locale, "Request cancellation", "申请取消"),
            )
          } else {
            @html.nothing
          },
          @html.button(
            type_="button",
            class="quiet-button",
            disabled=state.self_service.action_loading,
            on_click=self_service_command(emit, RefreshMachineOrders),
            copy(state.locale, "Refresh order status", "刷新订单状态"),
          ),
        ])
      None =>
        @html.div(class="inline-state", [
          @html.h3(copy(state.locale, "No active order", "没有活跃订单")),
          @html.p(
            copy(
              state.locale,
              "Start a new service order or refresh the order list.",
              "请创建新服务订单或刷新订单列表。",
            ),
          ),
        ])
    },
    if state.self_service.orders.length() > 0 {
      @html.section(class="recent-machine-orders", [
        @html.h3(
          copy(state.locale, "Recent machine orders", "最近机器订单"),
        ),
        @html.ul(
          [
            for order in state.self_service.orders => {
              @html.li([
                @html.code(class="mono", order.order_id),
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
        copy(state.locale, "Start another order", "创建另一个订单"),
      ),
    ]),
    @html.details(class="integration-contract", [
      @html.summary(copy(state.locale, "Integration contract", "集成契约")),
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
