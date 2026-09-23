///|
pub(all) struct OverviewMetrics {
  active_nodes : Int
  total_nodes : Int
  active_models : Int
  queue_depth : Int
  alerts : Int
  recent_changes : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend OverviewMetrics with Debug::{to_repr}

///|
pub extend OverviewMetrics with Eq::{not_equal, equal}

///|
pub extend OverviewMetrics with ToJson::{to_json}

///|
pub extend OverviewMetrics with FromJson::{from_json}

///|
pub(all) struct NodeRow {
  node_id : String
  state : @contracts.NodeState
  architecture : String
  total_memory_mib : Int
  free_memory_mib : Int
  used_memory_mib : Int
  /// Whether the memory figures came from a measurement. False means the total
  /// falls back to the declared inventory and must not be presented as memory.
  memory_measured : Bool
  /// Negative means no fresh node-level sensor reading; never render as zero.
  utilization_per_mille : Int
  cpu_per_mille : Int
  /// False when the node reported no host CPU sample, so an absent rate is not
  /// rendered as an idle 0%.
  cpu_measured : Bool
  temperature_celsius : Int
  power_watts : Double
  workloads : Int
  lease_holder : String
  active_assignment : String
  last_seen : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NodeRow with Debug::{to_repr}

///|
pub extend NodeRow with Eq::{not_equal, equal}

///|
pub extend NodeRow with ToJson::{to_json}

///|
pub extend NodeRow with FromJson::{from_json}

///|
/// Storage capacity is measured on the management/data host, not inferred
/// from a GPU node heartbeat or counted as schedulable accelerator capacity.
pub(all) struct StorageNodeRow {
  node_id : String
  state : String
  total_bytes : Int64?
  used_bytes : Int64?
  available_bytes : Int64?
  total_inodes : Int64?
  available_inodes : Int64?
  sampled_at_ms : Int64
} derive(Eq, FromJson)

///|
pub extend StorageNodeRow with Eq::{equal, not_equal}

///|
pub extend StorageNodeRow with FromJson::{from_json}

///|
pub(all) struct ModelRow {
  model_id : String
  version : String
  state : @contracts.ModelState
  license_status : String
  evaluation_status : String
  compatibility : String
  alias_name : String
  /// The pending licence record the registry binds to this model version.
  license_id : String
  /// The immutable artifact the registry attests for this model version.
  artifact_uri : String
  artifact_digest : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelRow with Debug::{to_repr}

///|
pub extend ModelRow with Eq::{not_equal, equal}

///|
pub extend ModelRow with ToJson::{to_json}

///|
pub extend ModelRow with FromJson::{from_json}

///|
pub(all) struct ModelSourceCatalogRow {
  id : String
  display_name : String
  description : String
  downloads : Int64
  likes : Int64
  license : String
  tasks : Array[String]
  created_at : String
  last_modified : String
  file_size : Int64
  params : Int64
  tags : Array[String]
  private : Bool
  gated : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelSourceCatalogRow with Debug::{to_repr}

///|
pub extend ModelSourceCatalogRow with Eq::{not_equal, equal}

///|
pub extend ModelSourceCatalogRow with ToJson::{to_json}

///|
pub extend ModelSourceCatalogRow with FromJson::{from_json}

///|
pub(all) struct ModelSourceCatalogPage {
  models : Array[ModelSourceCatalogRow]
  total_count : Int64
  page_number : Int
  page_size : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelSourceCatalogPage with Debug::{to_repr}

///|
pub extend ModelSourceCatalogPage with Eq::{not_equal, equal}

///|
pub extend ModelSourceCatalogPage with ToJson::{to_json}

///|
pub extend ModelSourceCatalogPage with FromJson::{from_json}

///|
pub(all) enum ModelImportState {
  Queued
  Downloading
  Verifying
  Verified
  Failed
  Cancelled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelImportState with Debug::{to_repr}

///|
pub extend ModelImportState with Eq::{not_equal, equal}

///|
pub extend ModelImportState with ToJson::{to_json}

///|
pub extend ModelImportState with FromJson::{from_json}

///|
pub(all) struct ModelImportRow {
  import_id : String
  source : String
  model_id : String
  revision : String
  state : ModelImportState
  files_total : Int
  files_completed : Int
  bytes_total : Int64
  bytes_completed : Int64
  manifest_digest : String
  artifact_uri : String
  license : String
  local_directory : String
  error_code : String
  cancel_requested : Bool
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelImportRow with Debug::{to_repr}

///|
pub extend ModelImportRow with Eq::{not_equal, equal}

///|
pub extend ModelImportRow with ToJson::{to_json}

///|
pub extend ModelImportRow with FromJson::{from_json}

///|
/// A directory an operator already populated inside the managed model store.
pub(all) struct ModelLocalDirectoryRow {
  directory : String
  files : Int
  bytes : Int64
  registered : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelLocalDirectoryRow with Debug::{to_repr}

///|
pub extend ModelLocalDirectoryRow with Eq::{not_equal, equal}

///|
pub extend ModelLocalDirectoryRow with ToJson::{to_json}

///|
pub extend ModelLocalDirectoryRow with FromJson::{from_json}

///|
pub(all) struct ModelLocalDirectoryListing {
  directories : Array[ModelLocalDirectoryRow]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelLocalDirectoryListing with Debug::{to_repr}

///|
pub extend ModelLocalDirectoryListing with Eq::{not_equal, equal}

///|
pub extend ModelLocalDirectoryListing with ToJson::{to_json}

///|
pub extend ModelLocalDirectoryListing with FromJson::{from_json}

///|
/// Operator intent to bring one local directory into the model plane under a
/// named upstream revision. Nothing is believed until the adapter proves it.
pub(all) struct ModelLocalRegistrationDraft {
  directory : String
  repository : String
  revision : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ModelLocalRegistrationDraft with Debug::{to_repr}

///|
pub extend ModelLocalRegistrationDraft with Eq::{not_equal, equal}

///|
pub extend ModelLocalRegistrationDraft with ToJson::{to_json}

///|
pub extend ModelLocalRegistrationDraft with FromJson::{from_json}

///|
/// Operator-supplied registry identity for one checksum-verified import.
/// Source-derived artifact metadata stays outside this draft and is resolved
/// by the controller from the durable import record.
pub(all) struct ModelAdoptionDraft {
  import_id : String
  model_id : String
  version : String
  license_id : String
  compatible_architectures : String
  minimum_memory_mib : String
} derive(Debug, Eq)

///|
pub extend ModelAdoptionDraft with Debug::{to_repr}

///|
pub extend ModelAdoptionDraft with Eq::{not_equal, equal}

///|
/// Operator acceptance of one candidate's declared upstream licence. Both the
/// record identity and the citation are operator text; the control plane
/// verifies the digest separately and accepts no inferred evidence here.
pub(all) struct ModelLicenseDraft {
  model_id : String
  version : String
  license_id : String
  evidence_ref : String
} derive(Debug, Eq)

///|
pub extend ModelLicenseDraft with Debug::{to_repr}

///|
pub extend ModelLicenseDraft with Eq::{not_equal, equal}

///|
/// Operator promotion of one approved model version onto a serving alias.
pub(all) struct ModelAliasDraft {
  model_id : String
  version : String
  alias_name : String
} derive(Debug, Eq)

///|
pub extend ModelAliasDraft with Debug::{to_repr}

///|
pub extend ModelAliasDraft with Eq::{not_equal, equal}

///|
/// One runtime profile an operator registers with the control plane. The
/// capability is the typed contract value, not a free-form string.
pub(all) struct RuntimeProfileDraft {
  name : String
  version : String
  image_digest : String
  architecture : String
  capability : @contracts.Capability
  supports_batching : Bool
  supports_multi_node : Bool
} derive(Debug, Eq)

///|
pub extend RuntimeProfileDraft with Debug::{to_repr}

///|
pub extend RuntimeProfileDraft with Eq::{not_equal, equal}

///|
pub fn empty_model_license_draft() -> ModelLicenseDraft {
  { model_id: "", version: "", license_id: "", evidence_ref: "", }
}

///|
pub fn empty_model_alias_draft() -> ModelAliasDraft {
  { model_id: "", version: "", alias_name: "", }
}

///|
/// The defaults are the deployment's admitted accelerator profile and the one
/// serving capability every model in this plane begins with.
pub fn default_runtime_draft() -> RuntimeProfileDraft {
  {
    name: "",
    version: "",
    image_digest: "",
    architecture: "nvidia-sm121",
    capability: TextGenerate,
    supports_batching: false,
    supports_multi_node: false,
  }
}

///|
/// A default serving-alias name for a model id: every character outside the
/// identifier alphabet becomes a hyphen, so the operator edits rather than
/// types a first draft.
pub fn model_alias_slug(model_id : String) -> String {
  let mut slug = ""
  for character in model_id.to_lower() {
    if (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '-' ||
      character == '_' ||
      character == '.' ||
      character == ':' {
      slug = slug + "\{character}"
    } else {
      slug = slug + "-"
    }
  }
  slug
}

///|
pub fn model_license_draft_valid(draft : ModelLicenseDraft) -> Bool {
  @contracts.valid_identifier(draft.model_id, maximum_length=128) &&
  @contracts.valid_identifier(draft.version, maximum_length=128) &&
  @contracts.valid_identifier(
    draft.license_id.trim().to_owned(),
    maximum_length=128,
  ) &&
  draft.evidence_ref.trim() != ""
}

///|
pub fn model_alias_draft_valid(draft : ModelAliasDraft) -> Bool {
  @contracts.valid_identifier(draft.model_id, maximum_length=128) &&
  @contracts.valid_identifier(draft.version, maximum_length=128) &&
  @contracts.valid_identifier(
    draft.alias_name.trim().to_owned(),
    maximum_length=128,
  )
}

///|
/// The same shape the registry enforces for a runtime name: no `@`, space, or
/// traversal sequence, bounded length, so the console never offers a doomed
/// registration.
pub fn runtime_profile_name_valid(value : String) -> Bool {
  let name = value.trim().to_owned()
  name != "" &&
  name.length() <= 256 &&
  !name.contains("..") &&
  !name.contains_char('@') &&
  !name.contains_char(' ') &&
  !name.contains_char('\n') &&
  !name.contains_char('\r')
}

///|
pub fn runtime_profile_draft_valid(draft : RuntimeProfileDraft) -> Bool {
  runtime_profile_name_valid(draft.name) &&
  @contracts.valid_identifier(
    draft.version.trim().to_owned(),
    maximum_length=128,
  ) &&
  @contracts.valid_sha256_digest(draft.image_digest.trim().to_owned()) &&
  @contracts.valid_identifier(
    draft.architecture.trim().to_owned(),
    maximum_length=128,
  )
}

///|
/// The serving capabilities the console can register. Model evaluation and
/// training are registry-side work, never a runtime-profile capability here.
pub fn runtime_capability_options() -> Array[@contracts.Capability] {
  [TextGenerate, EmbeddingCreate, ImageGenerate, VideoGenerate, AudioGenerate]
}

///|
pub fn runtime_capability_name(capability : @contracts.Capability) -> String {
  match capability {
    TextGenerate => "TextGenerate"
    EmbeddingCreate => "EmbeddingCreate"
    ImageGenerate => "ImageGenerate"
    VideoGenerate => "VideoGenerate"
    AudioGenerate => "AudioGenerate"
    ModelEvaluate => "ModelEvaluate"
    ModelTrain => "ModelTrain"
  }
}

///|
pub fn parse_runtime_capability(value : String) -> @contracts.Capability {
  match value {
    "EmbeddingCreate" => EmbeddingCreate
    "ImageGenerate" => ImageGenerate
    "VideoGenerate" => VideoGenerate
    "AudioGenerate" => AudioGenerate
    _ => TextGenerate
  }
}

///|
/// The four data classes a template may classify its payloads with.
pub fn data_class_options() -> Array[@contracts.DataClass] {
  [Public, Internal, Confidential, Restricted]
}

///|
pub fn data_class_name(classification : @contracts.DataClass) -> String {
  match classification {
    Public => "Public"
    Internal => "Internal"
    Confidential => "Confidential"
    Restricted => "Restricted"
  }
}

///|
pub fn parse_data_class(value : String) -> @contracts.DataClass {
  match value {
    "Public" => Public
    "Confidential" => Confidential
    "Restricted" => Restricted
    _ => Internal
  }
}

///|
pub fn data_class_label(
  locale : @i18n.Locale,
  classification : @contracts.DataClass,
) -> String {
  match classification {
    Public => localized(locale, "Public", "公开")
    Internal => localized(locale, "Internal", "内部")
    Confidential => localized(locale, "Confidential", "机密")
    Restricted => localized(locale, "Restricted", "受限")
  }
}

///|
/// One model-service template an operator registers with the control plane.
/// The control plane signs a catalog template itself, so `approval_receipt` and
/// `signature` have no field here: a caller that supplied them is refused.
/// Numeric fields are text because that is what an input carries, and the rules
/// that accept them live beside them.
pub(all) struct TemplateDraft {
  template_id : String
  version : String
  display_name : String
  description : String
  model_selector : String
  model_id : String
  model_version : String
  artifact_uri : String
  artifact_digest : String
  artifact_size_bytes : String
  artifact_signature_ref : String
  runtime_name : String
  runtime_version : String
  runtime_image_digest : String
  runtime_architectures : String
  runtime_multi_node : Bool
  capability : @contracts.Capability
  architecture : String
  accelerator_count : String
  accelerator_memory_mib : String
  cpu_millis : String
  memory_mib : String
  readiness_path : String
  health_interval_ms : String
  failure_threshold : String
  termination_grace_ms : String
  classification : @contracts.DataClass
  capture_for_evaluation : Bool
  evaluation_consent_receipt : String
  allow_cache : Bool
  allow_training_reuse : Bool
  secret_refs : String
  canary_replicas : String
  automatic_promotion : Bool
  automatic_rollback : Bool
  readiness_timeout_ms : String
} derive(Debug, Eq)

///|
pub extend TemplateDraft with Debug::{to_repr}

///|
pub extend TemplateDraft with Eq::{not_equal, equal}

///|
/// Every text control of the template form, addressed by name so one message
/// covers twenty-five fields instead of twenty-five messages.
pub(all) enum TemplateField {
  TemplateId
  TemplateVersion
  TemplateDisplayName
  TemplateDescription
  TemplateModelSelector
  TemplateArtifactUri
  TemplateArtifactDigest
  TemplateArtifactSizeBytes
  TemplateArtifactSignatureRef
  TemplateRuntimeName
  TemplateRuntimeVersion
  TemplateRuntimeImageDigest
  TemplateRuntimeArchitectures
  TemplateArchitecture
  TemplateAcceleratorCount
  TemplateAcceleratorMemoryMib
  TemplateCpuMillis
  TemplateMemoryMib
  TemplateReadinessPath
  TemplateHealthIntervalMs
  TemplateFailureThreshold
  TemplateTerminationGraceMs
  TemplateConsentReceipt
  TemplateSecretRefs
  TemplateCanaryReplicas
  TemplateReadinessTimeoutMs
} derive(Debug, Eq)

///|
pub extend TemplateField with Debug::{to_repr}

///|
pub extend TemplateField with Eq::{not_equal, equal}

///|
/// The switches a template carries. Multi-node support is what an admitted CX7
/// pair needs; the two capture switches only mean anything inside an evaluation
/// capture.
///
/// The retention itself is the capture switch: a template is immutable and
/// every workload created from it shares one policy, so the third retention the
/// contracts admit, an absolute `RetainUntil` expiry, has no stable meaning
/// here. Ephemeral and evaluation capture are the two a catalog entry can
/// carry, and there is no fourth.
pub(all) enum TemplateFlag {
  RuntimeMultiNode
  CaptureForEvaluation
  AllowCache
  AllowTrainingReuse
  AutomaticPromotion
  AutomaticRollback
} derive(Debug, Eq)

///|
pub extend TemplateFlag with Debug::{to_repr}

///|
pub extend TemplateFlag with Eq::{not_equal, equal}

///|
/// The defaults are the ones this deployment admits: one accelerator of the
/// admitted profile, the platform's own readiness probe, ephemeral payloads,
/// and the `runtime-token` every service assignment in this plane declares.
pub fn empty_template_draft() -> TemplateDraft {
  {
    template_id: "",
    version: "",
    display_name: "",
    description: "",
    model_selector: "",
    model_id: "",
    model_version: "",
    artifact_uri: "",
    artifact_digest: "",
    artifact_size_bytes: "",
    artifact_signature_ref: "",
    runtime_name: "",
    runtime_version: "",
    runtime_image_digest: "",
    runtime_architectures: "",
    runtime_multi_node: false,
    capability: TextGenerate,
    architecture: "",
    accelerator_count: "1",
    accelerator_memory_mib: "32768",
    cpu_millis: "4000",
    memory_mib: "65536",
    readiness_path: "/health",
    health_interval_ms: "5000",
    failure_threshold: "6",
    termination_grace_ms: "60000",
    classification: Internal,
    capture_for_evaluation: false,
    evaluation_consent_receipt: "",
    allow_cache: false,
    allow_training_reuse: false,
    secret_refs: "runtime-token",
    canary_replicas: "1",
    automatic_promotion: false,
    automatic_rollback: true,
    readiness_timeout_ms: "600000",
  }
}

///|
/// How one template field travels: free text, an `Int`, or an `Int64` that the
/// contracts marshal as a JSON string. The bound is the server's own inclusive
/// upper limit, so the control and the rule cannot drift apart.
priv enum TemplateFieldKind {
  FreeText
  Count(Int)
  ByteCount(Int64)
}

///|
/// The block a field is grouped under. The form renders one fieldset per block,
/// so a template with twenty-five inputs still reads as seven decisions.
priv enum TemplateSection {
  TemplateIdentity
  TemplateArtifact
  TemplateRuntime
  TemplateResources
  TemplateProbes
  TemplateDataPolicy
  TemplateRollout
} derive(Eq)

///|
/// One text control of the template form: what it is called, the bound the
/// control enforces, and the rule as help text.
priv struct TemplateFieldSpec {
  field : TemplateField
  section : TemplateSection
  label_en : String
  label_zh : String
  placeholder : String
  kind : TemplateFieldKind
  help_en : String
  help_zh : String
  optional : Bool
}

///|
fn template_field_spec(
  field : TemplateField,
  section : TemplateSection,
  label_en : String,
  label_zh : String,
  placeholder : String,
  kind : TemplateFieldKind,
  help_en : String,
  help_zh : String,
  optional? : Bool = false,
) -> TemplateFieldSpec {
  {
    field,
    section,
    label_en,
    label_zh,
    placeholder,
    kind,
    help_en,
    help_zh,
    optional,
  }
}

///|
/// The whole editable field set of `ModelServiceTemplate`, in the order
/// `@deployment.validate_template` reads it. `model_id` and `model_version` are
/// absent because the model picker owns them; `allowed_egress`, the two network
/// reachability flags, `approval_receipt` and `signature` are absent because the
/// deployment service admits exactly one value for each.
fn template_field_specs() -> Array[TemplateFieldSpec] {
  [
    template_field_spec(
      TemplateId,
      TemplateIdentity,
      "Template ID",
      "模板 ID",
      "text-small",
      FreeText,
      "Letters, numbers, dots, colons, hyphens, or underscores, up to 128 characters.",
      "使用字母、数字、点、冒号、连字符或下划线，最多 128 个字符。",
    ),
    template_field_spec(
      TemplateVersion,
      TemplateIdentity,
      "Template version",
      "模板版本",
      "v1",
      FreeText,
      "The immutable revision this template is registered as.",
      "该模板注册的不可变版本。",
    ),
    template_field_spec(
      TemplateDisplayName,
      TemplateIdentity,
      "Display name",
      "显示名称",
      "Approved text service",
      FreeText,
      "Shown in the template picker, up to 256 characters.",
      "显示在模板选择器中，最多 256 个字符。",
    ),
    template_field_spec(
      TemplateDescription,
      TemplateIdentity,
      "Description",
      "说明",
      "Digest-pinned text generation service",
      FreeText,
      "Optional operator note, up to 2048 characters.",
      "可选的运维说明，最多 2048 个字符。",
      optional=true,
    ),
    template_field_spec(
      TemplateModelSelector,
      TemplateArtifact,
      "Model selector",
      "模型选择器",
      "text.default",
      FreeText,
      "The routing name workloads address. A registered alias of this model is a safe choice.",
      "工作负载使用的路由名称。使用该模型已注册的别名是安全的选择。",
    ),
    template_field_spec(
      TemplateArtifactUri,
      TemplateArtifact,
      "Artifact URI",
      "制品 URI",
      "modelstore://owner/repo",
      FreeText,
      "An `s3://` object or this control plane's own `modelstore://` revision.",
      "`s3://` 对象，或本控制平面自有的 `modelstore://` 版本。",
    ),
    template_field_spec(
      TemplateArtifactDigest,
      TemplateArtifact,
      "Artifact digest",
      "制品摘要",
      "sha256:…",
      FreeText,
      "Exactly sha256: followed by 64 hexadecimal characters.",
      "必须为 sha256: 加 64 个十六进制字符。",
    ),
    template_field_spec(
      TemplateArtifactSizeBytes,
      TemplateArtifact,
      "Artifact size (bytes)",
      "制品大小（字节）",
      "16000000000",
      ByteCount(1099511627776L),
      "A positive byte count, at most 1 TiB. The control plane carries it as a JSON string.",
      "正整数字节数，最多 1 TiB。控制平面以 JSON 字符串传输该值。",
    ),
    template_field_spec(
      TemplateArtifactSignatureRef,
      TemplateArtifact,
      "Signature reference",
      "签名引用",
      "modelstore://owner/repo/lunanexa-source-manifest.json",
      FreeText,
      "A managed revision is signed by its own source manifest; an `s3://` object names its detached signature.",
      "受管版本由自身的来源清单签名；`s3://` 对象指向其分离签名。",
    ),
    template_field_spec(
      TemplateRuntimeName,
      TemplateRuntime,
      "Runtime name",
      "运行时名称",
      "text-runtime",
      FreeText,
      "A registered runtime profile, up to 256 characters with no '@' and no '..'.",
      "已注册的运行时配置，最多 256 个字符，不能包含 '@' 或 '..'。",
    ),
    template_field_spec(
      TemplateRuntimeVersion,
      TemplateRuntime,
      "Runtime version",
      "运行时版本",
      "runtime-v1",
      FreeText,
      "Must be the version the registry admitted for this runtime.",
      "必须是注册表为该运行时接纳的版本。",
    ),
    template_field_spec(
      TemplateRuntimeImageDigest,
      TemplateRuntime,
      "Runtime image digest",
      "运行时镜像摘要",
      "sha256:…",
      FreeText,
      "The verified image digest of the registered runtime.",
      "已注册运行时的、已验证的镜像摘要。",
    ),
    template_field_spec(
      TemplateRuntimeArchitectures,
      TemplateRuntime,
      "Runtime architectures",
      "运行时架构",
      "nvidia-gb10, nvidia-sm121",
      FreeText,
      "Comma-separated. Every entry must be a distinct architecture, and one of them must be this template's architecture.",
      "以逗号分隔。每个条目必须是不同的架构，且其中之一必须是本模板的架构。",
    ),
    template_field_spec(
      TemplateArchitecture,
      TemplateRuntime,
      "Accelerator architecture",
      "加速器架构",
      "nvidia-gb10",
      FreeText,
      "The architecture this template places on. It must appear in the runtime architectures above.",
      "本模板放置所用的架构。必须出现在上面的运行时架构中。",
    ),
    template_field_spec(
      TemplateAcceleratorCount,
      TemplateResources,
      "Accelerator count",
      "加速器数量",
      "1",
      Count(64),
      "Between 1 and 64 accelerators per replica.",
      "每个副本 1 至 64 个加速器。",
    ),
    template_field_spec(
      TemplateAcceleratorMemoryMib,
      TemplateResources,
      "Accelerator memory (MiB)",
      "加速器显存（MiB）",
      "32768",
      Count(1048576),
      "Between 1 and 1048576 MiB.",
      "1 至 1048576 MiB。",
    ),
    template_field_spec(
      TemplateCpuMillis,
      TemplateResources,
      "CPU millicores",
      "CPU 毫核",
      "4000",
      Count(1000000),
      "Between 1 and 1000000 millicores.",
      "1 至 1000000 毫核。",
    ),
    template_field_spec(
      TemplateMemoryMib,
      TemplateResources,
      "Host memory (MiB)",
      "主机内存（MiB）",
      "65536",
      Count(1048576),
      "Between 1 and 1048576 MiB.",
      "1 至 1048576 MiB。",
    ),
    template_field_spec(
      TemplateSecretRefs,
      TemplateResources,
      "Secret references",
      "密钥引用",
      "runtime-token",
      FreeText,
      "Comma-separated names of host secrets the deployment must already declare. Empty means the service needs none.",
      "以逗号分隔、部署必须已声明的主机密钥名称。留空表示该服务不需要密钥。",
      optional=true,
    ),
    template_field_spec(
      TemplateReadinessPath,
      TemplateProbes,
      "Readiness path",
      "就绪探针路径",
      "/health",
      FreeText,
      "An absolute path with no '..', up to 256 characters.",
      "绝对路径，不能包含 '..'，最多 256 个字符。",
    ),
    template_field_spec(
      TemplateHealthIntervalMs,
      TemplateProbes,
      "Probe interval (ms)",
      "探针间隔（毫秒）",
      "5000",
      Count(3600000),
      "Between 1 and 3600000 ms.",
      "1 至 3600000 毫秒。",
    ),
    template_field_spec(
      TemplateFailureThreshold,
      TemplateProbes,
      "Failure threshold",
      "失败阈值",
      "6",
      Count(100),
      "Consecutive failed probes between 1 and 100.",
      "连续失败探针数在 1 至 100 之间。",
    ),
    template_field_spec(
      TemplateTerminationGraceMs,
      TemplateProbes,
      "Termination grace (ms)",
      "终止宽限期（毫秒）",
      "60000",
      Count(3600000),
      "Between 1 and 3600000 ms.",
      "1 至 3600000 毫秒。",
    ),
    template_field_spec(
      TemplateConsentReceipt,
      TemplateDataPolicy,
      "Evaluation consent receipt",
      "评测同意凭据",
      "consent:evaluation:2026-01",
      FreeText,
      "Required by an evaluation capture, and only then: it is the receipt that permits holding payloads.",
      "仅在启用评测采集时必填：它是允许保留载荷的凭据。",
      optional=true,
    ),
    template_field_spec(
      TemplateCanaryReplicas,
      TemplateRollout,
      "Canary replicas",
      "金丝雀副本数",
      "1",
      Count(64),
      "Between 1 and 64 replicas carry the canary step.",
      "1 至 64 个副本承载金丝雀阶段。",
    ),
    template_field_spec(
      TemplateReadinessTimeoutMs,
      TemplateRollout,
      "Rollout readiness timeout (ms)",
      "发布就绪超时（毫秒）",
      "600000",
      ByteCount(86400000L),
      "Between 1 and 86400000 ms before the rollout is judged failed.",
      "在判定发布失败之前的 1 至 86400000 毫秒。",
    ),
  ]
}

///|
fn template_section_order() -> Array[TemplateSection] {
  [
    TemplateIdentity,
    TemplateArtifact,
    TemplateRuntime,
    TemplateResources,
    TemplateProbes,
    TemplateDataPolicy,
    TemplateRollout,
  ]
}

///|
fn template_section_legend(
  locale : @i18n.Locale,
  section : TemplateSection,
) -> String {
  match section {
    TemplateIdentity => localized(locale, "Template identity", "模板身份")
    TemplateArtifact =>
      localized(locale, "Model and artifact", "模型与制品")
    TemplateRuntime => localized(locale, "Runtime", "运行时")
    TemplateResources =>
      localized(locale, "Resources and secrets", "资源与密钥")
    TemplateProbes => localized(locale, "Health probes", "健康探针")
    TemplateDataPolicy => localized(locale, "Data policy", "数据策略")
    TemplateRollout => localized(locale, "Rollout", "发布策略")
  }
}

///|
/// The stable identifier of one template control, shared by the label, the help
/// text, and the render tests.
pub fn template_field_id(field : TemplateField) -> String {
  match field {
    TemplateId => "template-id"
    TemplateVersion => "template-version"
    TemplateDisplayName => "template-display-name"
    TemplateDescription => "template-description"
    TemplateModelSelector => "template-model-selector"
    TemplateArtifactUri => "template-artifact-uri"
    TemplateArtifactDigest => "template-artifact-digest"
    TemplateArtifactSizeBytes => "template-artifact-size"
    TemplateArtifactSignatureRef => "template-artifact-signature"
    TemplateRuntimeName => "template-runtime-name"
    TemplateRuntimeVersion => "template-runtime-version"
    TemplateRuntimeImageDigest => "template-runtime-image-digest"
    TemplateRuntimeArchitectures => "template-runtime-architectures"
    TemplateArchitecture => "template-architecture"
    TemplateAcceleratorCount => "template-accelerator-count"
    TemplateAcceleratorMemoryMib => "template-accelerator-memory"
    TemplateCpuMillis => "template-cpu-millis"
    TemplateMemoryMib => "template-memory"
    TemplateReadinessPath => "template-readiness-path"
    TemplateHealthIntervalMs => "template-health-interval"
    TemplateFailureThreshold => "template-failure-threshold"
    TemplateTerminationGraceMs => "template-termination-grace"
    TemplateConsentReceipt => "template-consent-receipt"
    TemplateSecretRefs => "template-secret-refs"
    TemplateCanaryReplicas => "template-canary-replicas"
    TemplateReadinessTimeoutMs => "template-readiness-timeout"
  }
}

///|
pub fn template_field_value(
  draft : TemplateDraft,
  field : TemplateField,
) -> String {
  match field {
    TemplateId => draft.template_id
    TemplateVersion => draft.version
    TemplateDisplayName => draft.display_name
    TemplateDescription => draft.description
    TemplateModelSelector => draft.model_selector
    TemplateArtifactUri => draft.artifact_uri
    TemplateArtifactDigest => draft.artifact_digest
    TemplateArtifactSizeBytes => draft.artifact_size_bytes
    TemplateArtifactSignatureRef => draft.artifact_signature_ref
    TemplateRuntimeName => draft.runtime_name
    TemplateRuntimeVersion => draft.runtime_version
    TemplateRuntimeImageDigest => draft.runtime_image_digest
    TemplateRuntimeArchitectures => draft.runtime_architectures
    TemplateArchitecture => draft.architecture
    TemplateAcceleratorCount => draft.accelerator_count
    TemplateAcceleratorMemoryMib => draft.accelerator_memory_mib
    TemplateCpuMillis => draft.cpu_millis
    TemplateMemoryMib => draft.memory_mib
    TemplateReadinessPath => draft.readiness_path
    TemplateHealthIntervalMs => draft.health_interval_ms
    TemplateFailureThreshold => draft.failure_threshold
    TemplateTerminationGraceMs => draft.termination_grace_ms
    TemplateConsentReceipt => draft.evaluation_consent_receipt
    TemplateSecretRefs => draft.secret_refs
    TemplateCanaryReplicas => draft.canary_replicas
    TemplateReadinessTimeoutMs => draft.readiness_timeout_ms
  }
}

///|
/// One `Int` field of a template as the operator typed it. Only the server's
/// own bound decides: the console never rounds or clamps a submitted number.
pub fn template_int_field(value : String, maximum~ : Int) -> Int? {
  let parsed = @string.parse_int(value.trim()) catch { _ => return None }
  if parsed < 1 || parsed > maximum {
    None
  } else {
    Some(parsed)
  }
}

///|
/// One `Int64` field. The contracts marshal it as a JSON string, so it is parsed
/// here and re-encoded by the type the request body is built from.
pub fn template_int64_field(value : String, maximum~ : Int64) -> Int64? {
  let parsed = @string.parse_int64(value.trim()) catch { _ => return None }
  if parsed < 1L || parsed > maximum {
    None
  } else {
    Some(parsed)
  }
}

///|
/// A comma-separated identifier list: the shape the runtime architectures and
/// the secret references both take. Empty is the empty list; a blank entry, a
/// repeated entry, or an identifier the planner would reject is not.
pub fn template_identifier_list(
  value : String,
  maximum~ : Int,
  identifier_length? : Int = 256,
) -> Array[String]? {
  if value.trim() == "" {
    return Some([])
  }
  let values : Array[String] = []
  for part in value.split(",") {
    let item = part.trim().to_owned()
    if !@contracts.valid_identifier(item, maximum_length=identifier_length) ||
      values.contains(item) {
      return None
    }
    values.push(item)
    if values.length() > maximum {
      return None
    }
  }
  Some(values)
}

///|
/// The same shape `deployment/planner.mbt` admits for an artifact: an upstream
/// object, or a revision inside this control plane's own verified model store.
/// The planner stays the authority; this only keeps an obviously doomed
/// submission off the wire.
pub fn template_artifact_reference_valid(value : String) -> Bool {
  template_object_reference_valid(value) || template_model_store_valid(value)
}

///|
/// A signature reference is either one of the two transports, or a short
/// identifier for a verifier the deployment already trusts.
pub fn template_signature_reference_valid(value : String) -> Bool {
  template_object_reference_valid(value) ||
  template_model_store_valid(value) ||
  @contracts.valid_identifier(value.trim().to_owned(), maximum_length=256)
}

///|
fn template_object_reference_valid(value : String) -> Bool {
  let object = value.trim().to_owned()
  guard object.has_prefix("s3://") else { return false }
  let remainder = object[5:].to_owned()
  remainder != "" &&
  remainder.length() <= 2048 &&
  remainder.contains_char('/') &&
  !remainder.has_prefix("/") &&
  !remainder.has_suffix("/") &&
  !remainder.contains("..") &&
  !remainder.contains("//") &&
  template_reference_characters(remainder)
}

///|
fn template_model_store_valid(value : String) -> Bool {
  let reference = value.trim().to_owned()
  guard reference.has_prefix(@contracts.model_store_scheme) else {
    return false
  }
  let directory = reference[@contracts.model_store_scheme.length():].to_owned()
  directory != "" &&
  directory.length() <= 2048 &&
  !directory.has_prefix("/") &&
  !directory.has_suffix("/") &&
  !directory.contains("..") &&
  !directory.contains("//") &&
  template_reference_characters(directory)
}

///|
fn template_reference_characters(value : String) -> Bool {
  value.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == '/'
  })
}

///|
pub fn template_runtime_name_valid(value : String) -> Bool {
  let name = value.trim().to_owned()
  name != "" &&
  name.length() <= 256 &&
  !name.contains("..") &&
  !name.contains_char('@') &&
  name.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.' ||
    character == ':' ||
    character == '/'
  })
}

///|
pub fn template_readiness_path_valid(value : String) -> Bool {
  let path = value.trim().to_owned()
  path.has_prefix("/") &&
  path.length() <= 256 &&
  !path.contains("..") &&
  template_reference_characters(path)
}

///|
/// The rule one free-text field must satisfy. A bounded numeric field is judged
/// by its bound instead, so it is not repeated here.
fn template_text_acceptable(field : TemplateField, value : String) -> Bool {
  match field {
    TemplateId =>
      @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
    TemplateVersion =>
      @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
    TemplateDisplayName => value.trim() != "" && value.length() <= 256
    TemplateDescription => value.length() <= 2048
    TemplateModelSelector =>
      @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
    TemplateArtifactUri => template_artifact_reference_valid(value)
    TemplateArtifactDigest =>
      @contracts.valid_sha256_digest(value.trim().to_owned())
    TemplateArtifactSignatureRef => template_signature_reference_valid(value)
    TemplateRuntimeName => template_runtime_name_valid(value)
    TemplateRuntimeVersion =>
      @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
    TemplateRuntimeImageDigest =>
      @contracts.valid_sha256_digest(value.trim().to_owned())
    TemplateRuntimeArchitectures =>
      template_identifier_list(value, maximum=64, identifier_length=128)
      is Some(_)
    TemplateArchitecture =>
      @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
    TemplateReadinessPath => template_readiness_path_valid(value)
    TemplateConsentReceipt => value.trim().length() <= 256
    TemplateSecretRefs => template_identifier_list(value, maximum=64) is Some(_)
    _ => true
  }
}

///|
/// Whether one field is acceptable, mirroring `@deployment.validate_template`.
fn template_field_acceptable(
  draft : TemplateDraft,
  spec : TemplateFieldSpec,
) -> Bool {
  let value = template_field_value(draft, spec.field)
  match spec.kind {
    FreeText => template_text_acceptable(spec.field, value)
    Count(maximum) => template_int_field(value, maximum~) is Some(_)
    ByteCount(maximum) => template_int64_field(value, maximum~) is Some(_)
  }
}

///|
/// Whether the draft is a template the deployment service can accept. The
/// planner's shape rules are mirrored here so an obviously invalid submission
/// is caught before it is sent; whether the model, the runtime, the licence and
/// the hardware actually admit this template stays the preflight's answer.
pub fn template_draft_valid(draft : TemplateDraft) -> Bool {
  if !@contracts.valid_identifier(
      draft.model_id.trim().to_owned(),
      maximum_length=128,
    ) ||
    !@contracts.valid_identifier(
      draft.model_version.trim().to_owned(),
      maximum_length=128,
    ) ||
    !@contracts.valid_identifier(
      draft.architecture.trim().to_owned(),
      maximum_length=128,
    ) {
    return false
  }
  for spec in template_field_specs() {
    if !template_field_acceptable(draft, spec) {
      return false
    }
  }
  let architectures = match
    template_identifier_list(
      draft.runtime_architectures,
      maximum=64,
      identifier_length=128,
    ) {
    Some(values) => values
    None => return false
  }
  if !architectures.contains(draft.architecture.trim().to_owned()) {
    return false
  }
  // An evaluation capture is the only non-ephemeral retention a template can
  // declare, and the two reuse switches only mean anything inside one.
  if draft.capture_for_evaluation {
    draft.evaluation_consent_receipt.trim() != ""
  } else {
    !draft.allow_cache && !draft.allow_training_reuse
  }
}

///|
/// The stable key of one registered runtime. A runtime image is immutable, so
/// its name and version identify it.
pub fn runtime_key(runtime : @contracts.RuntimeSpec) -> String {
  "\{runtime.name}@\{runtime.version}"
}

///|
/// Every runtime a template can name: the registry roster first, then any
/// runtime an already registered template carries that the roster did not list.
/// One runtime appears once.
pub fn known_runtimes(state : ConsoleState) -> Array[@contracts.RuntimeSpec] {
  let runtimes : Array[@contracts.RuntimeSpec] = []
  for candidate in state.registered_runtimes {
    if !runtimes.any(existing => runtime_key(existing) == runtime_key(candidate)) {
      runtimes.push(candidate)
    }
  }
  for template in state.catalog_templates {
    if !runtimes.any(existing => {
        runtime_key(existing) == runtime_key(template.runtime)
      }) {
      runtimes.push(template.runtime)
    }
  }
  runtimes
}

///|
pub(all) struct DeploymentRow {
  assignment_id : String
  deployment_id : String
  desired : @contracts.DeploymentState
  observed : @contracts.DeploymentState
  placement_reason : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DeploymentRow with Debug::{to_repr}

///|
pub extend DeploymentRow with Eq::{not_equal, equal}

///|
pub extend DeploymentRow with ToJson::{to_json}

///|
pub extend DeploymentRow with FromJson::{from_json}

///|
pub(all) struct RequestMetrics {
  count : Int
  p95_ms : Int
  throughput_per_second : Int
  errors : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RequestMetrics with Debug::{to_repr}

///|
pub extend RequestMetrics with Eq::{not_equal, equal}

///|
pub extend RequestMetrics with ToJson::{to_json}

///|
pub extend RequestMetrics with FromJson::{from_json}

///|
pub(all) struct RequestDetail {
  timestamp_unix_ms : Int64
  action : String
  model_selector : String
  result : String
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend RequestDetail with Debug::{to_repr}

///|
pub extend RequestDetail with Eq::{not_equal, equal}

///|
pub extend RequestDetail with ToJson::{to_json}

///|
pub extend RequestDetail with FromJson::{from_json}

///|
pub(all) struct StreamEventView {
  sequence : Int
  kind : String
  text : String
  receipt : String
} derive(Eq)

///|
pub extend StreamEventView with Eq::{not_equal, equal}

///|
pub(all) struct PolicySummary {
  quota_count : Int
  data_class_count : Int
  default_retention : @contracts.RetentionPolicy
  allowed_runtimes : Array[String]
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend PolicySummary with Debug::{to_repr}

///|
pub extend PolicySummary with Eq::{not_equal, equal}

///|
pub extend PolicySummary with ToJson::{to_json}

///|
pub extend PolicySummary with FromJson::{from_json}

///|
pub(all) struct AuditRow {
  actor : String
  decision : String
  evidence : String
  result : String
  receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AuditRow with Debug::{to_repr}

///|
pub extend AuditRow with Eq::{not_equal, equal}

///|
pub extend AuditRow with ToJson::{to_json}

///|
pub extend AuditRow with FromJson::{from_json}

///|
pub(all) struct NotificationRow {
  notification_id : String
  code : String
  severity : @notifications.NotificationSeverity
  lifecycle : @notifications.NotificationLifecycle
  topic : @notifications.NotificationTopic
  created_unix_ms : Int64
  generation : Int64
  node_ref : String
  assigned_to : String
  silenced_until_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationRow with Debug::{to_repr}

///|
pub extend NotificationRow with Eq::{not_equal, equal}

///|
pub extend NotificationRow with ToJson::{to_json}

///|
pub extend NotificationRow with FromJson::{from_json}

///|
pub(all) struct NotificationDeliveryRow {
  delivery_id : String
  notification_id : String
  channel : @notifications.NotificationChannel
  state : @notifications.DeliveryState
  attempt_count : Int
  updated_unix_ms : Int64
  last_error_code : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend NotificationDeliveryRow with Debug::{to_repr}

///|
pub extend NotificationDeliveryRow with Eq::{not_equal, equal}

///|
pub extend NotificationDeliveryRow with ToJson::{to_json}

///|
pub extend NotificationDeliveryRow with FromJson::{from_json}

///|
pub(all) struct UserAccessRow {
  user_id : String
  display_name : String
  email : String
  state : @workspace.WorkspaceUserState
  last_active : String
  grant_count : Int
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend UserAccessRow with Debug::{to_repr}

///|
pub extend UserAccessRow with Eq::{not_equal, equal}

///|
pub extend UserAccessRow with ToJson::{to_json}

///|
pub extend UserAccessRow with FromJson::{from_json}

///|
/// Portable browser projection of the account contract. These DTOs mirror the
/// public JSON vocabulary without importing the native durable account store.
pub(all) enum UiAccountRole {
  PlatformOperator
  AuditReader
  EnterpriseUser
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend UiAccountRole with Debug::{to_repr}

///|
pub extend UiAccountRole with Eq::{not_equal, equal}

///|
pub extend UiAccountRole with ToJson::{to_json}

///|
pub extend UiAccountRole with FromJson::{from_json}

///|
pub(all) enum UiAccountState {
  Invited
  Active
  Suspended
  Revoked
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend UiAccountState with Debug::{to_repr}

///|
pub extend UiAccountState with Eq::{not_equal, equal}

///|
pub extend UiAccountState with ToJson::{to_json}

///|
pub extend UiAccountState with FromJson::{from_json}

///|
pub(all) struct AccountView {
  account_id : String
  subject_ref : String
  identity_issuer : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[UiAccountRole]
  state : UiAccountState
  created_unix_ms : Int64
  updated_unix_ms : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccountView with Debug::{to_repr}

///|
pub extend AccountView with Eq::{not_equal, equal}

///|
pub extend AccountView with ToJson::{to_json}

///|
pub extend AccountView with FromJson::{from_json}

///|
pub(all) struct BrowserSessionView {
  session_id : String
  account_id : String
  created_unix_ms : Int64
  expires_unix_ms : Int64
  last_used_unix_ms : Int64
  revoked_unix_ms : Int64?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend BrowserSessionView with Debug::{to_repr}

///|
pub extend BrowserSessionView with Eq::{not_equal, equal}

///|
pub extend BrowserSessionView with ToJson::{to_json}

///|
pub extend BrowserSessionView with FromJson::{from_json}

///|
/// UI-owned draft for creating the LunaNexa mapping for an externally
/// authenticated human. The upstream subject is accepted only for submission;
/// it is never included in the account table or a public account view.
pub(all) struct AccountInviteDraft {
  account_id : String
  subject_ref : String
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  identity_receipt : String
  roles : Array[UiAccountRole]
} derive(Eq)

///|
pub extend AccountInviteDraft with Eq::{not_equal, equal}

///|
pub(all) struct AccessPackageDraft {
  identity_issuer : String
  identity_subject : String
  display_name : String
  email : String
  organization_id : String
  tenant_ref : String
  lifetime_days : Int
  identity_verified : Bool
} derive(Eq)

///|
pub extend AccessPackageDraft with Eq::{not_equal, equal}

///|
pub(all) struct AccessPackageView {
  package_id : String
  account_id : String
  subject_ref : String
  display_name : String
  email : String
  organization_id : String
  tenant_ref : String
  user_id : String?
  membership_id : String
  grant_id : String?
  lease_id : String?
  lease_state : @workspace.WorkspaceLeaseState?
  expires_unix_ms : Int64?
  approved_model_aliases : Array[String]
  account_ready : Bool
  membership_ready : Bool
  contract_required : Bool
  contract_ready : Bool
  workspace_ready : Bool
  models_ready : Bool
  ready : Bool
  can_enable : Bool
  state : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessPackageView with Debug::{to_repr}

///|
pub extend AccessPackageView with Eq::{not_equal, equal}

///|
pub extend AccessPackageView with ToJson::{to_json}

///|
pub extend AccessPackageView with FromJson::{from_json}

///|
pub(all) struct AccessGrantRow {
  grant_id : String
  user_id : String
  role : @workspace.WorkspaceAccess
  scope : String
  expires_at : String
  state : @workspace.WorkspaceAccessGrantState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AccessGrantRow with Debug::{to_repr}

///|
pub extend AccessGrantRow with Eq::{not_equal, equal}

///|
pub extend AccessGrantRow with ToJson::{to_json}

///|
pub extend AccessGrantRow with FromJson::{from_json}

///|
pub(all) struct ComputeLeaseRow {
  lease_id : String
  user_id : String
  /// The subject this lease belongs to. The guided-setup form matches on it so
  /// an operator can see which tenants a person already holds before typing a
  /// tenant of their own.
  subject_ref : String
  workspace : String
  resource : String
  started_at : String
  expires_at : String
  state : @workspace.WorkspaceLeaseState
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ComputeLeaseRow with Debug::{to_repr}

///|
pub extend ComputeLeaseRow with Eq::{not_equal, equal}

///|
pub extend ComputeLeaseRow with ToJson::{to_json}

///|
pub extend ComputeLeaseRow with FromJson::{from_json}

///|
pub(all) struct ExclusiveNodeLeaseRow {
  lease_id : String
  node_id : String
  subject_ref : String
  unix_username : String
  expires_at : String
  state : String
  generation : Int64
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ExclusiveNodeLeaseRow with Debug::{to_repr}

///|
pub extend ExclusiveNodeLeaseRow with Eq::{not_equal, equal}

///|
pub extend ExclusiveNodeLeaseRow with ToJson::{to_json}

///|
pub extend ExclusiveNodeLeaseRow with FromJson::{from_json}

///|
pub(all) struct CostCenterRow {
  cost_center_id : String
  organization_id : String
  display_name : String
  parent_cost_center_id : String
  project_count : Int
  provisional_spend : String
  budget_posture : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend CostCenterRow with Debug::{to_repr}

///|
pub extend CostCenterRow with Eq::{not_equal, equal}

///|
pub extend CostCenterRow with ToJson::{to_json}

///|
pub extend CostCenterRow with FromJson::{from_json}

///|
pub(all) struct AgreementRow {
  agreement_id : String
  agreement_type : String
  template_version : String
  organization_id : String
  state : String
  evidence_receipt : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AgreementRow with Debug::{to_repr}

///|
pub extend AgreementRow with Eq::{not_equal, equal}

///|
pub extend AgreementRow with ToJson::{to_json}

///|
pub extend AgreementRow with FromJson::{from_json}

///|
pub(all) struct EnterpriseLeaseRequestRow {
  request_id : String
  organization_id : String
  subject_ref : String
  project_id : String
  unix_username : String
  requested_models : String
  state : String
  generation : Int64
  assigned_node_id : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend EnterpriseLeaseRequestRow with Debug::{to_repr}

///|
pub extend EnterpriseLeaseRequestRow with Eq::{not_equal, equal}

///|
pub extend EnterpriseLeaseRequestRow with ToJson::{to_json}

///|
pub extend EnterpriseLeaseRequestRow with FromJson::{from_json}

///|
pub(all) struct QualifiedServiceRow {
  provider : String
  capability : String
  environment : String
  state : String
  evidence_policy : String
  production_ready : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend QualifiedServiceRow with Debug::{to_repr}

///|
pub extend QualifiedServiceRow with Eq::{not_equal, equal}

///|
pub extend QualifiedServiceRow with ToJson::{to_json}

///|
pub extend QualifiedServiceRow with FromJson::{from_json}

///|
pub(all) enum DestructiveAction {
  CordonNode(String)
  DrainNode(String)
  StopDeployment(String)
  RollbackAlias(String)
  RollbackServiceDeployment(String)
  DeleteServiceDeployment(String)
  SuspendUser(String)
  RevokeUser(String)
  RevokeAccessGrant(String)
  EndComputeLease(String)
  TerminateExclusiveNodeLease(String, Int64)
  RedriveNotificationDelivery(String, Int, Int64)
  ActivateAccount(String)
  SuspendAccount(String)
  RevokeAccount(String)
  SetAccountRoles(String, Array[UiAccountRole])
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend DestructiveAction with Debug::{to_repr}

///|
pub extend DestructiveAction with Eq::{not_equal, equal}

///|
pub extend DestructiveAction with ToJson::{to_json}

///|
pub extend DestructiveAction with FromJson::{from_json}

///|
pub(all) struct Confirmation {
  action : DestructiveAction
  scope : String
  receipt : String
  confirmed : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend Confirmation with Debug::{to_repr}

///|
pub extend Confirmation with Eq::{not_equal, equal}

///|
pub extend Confirmation with ToJson::{to_json}

///|
pub extend Confirmation with FromJson::{from_json}

///|
/// Authoritative production-acceptance projection from `/v1/readiness`.
pub(all) struct ProductionReadinessState {
  ready : Bool
  loading : Bool
  blocker_codes : Array[String]
  error : String?
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ProductionReadinessState with Debug::{to_repr}

///|
pub extend ProductionReadinessState with Eq::{not_equal, equal}

///|
pub extend ProductionReadinessState with ToJson::{to_json}

///|
pub extend ProductionReadinessState with FromJson::{from_json}

///|
/// Time window applied to the operator alert list. It narrows the
/// notifications already held in the typed state; it never triggers a
/// controller read.
pub(all) enum AlertsWindow {
  Today
  Last7Days
  Last30Days
  AllAlerts
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend AlertsWindow with Debug::{to_repr}

///|
pub extend AlertsWindow with Eq::{not_equal, equal}

///|
pub extend AlertsWindow with ToJson::{to_json}

///|
pub extend AlertsWindow with FromJson::{from_json}

///|
/// Stable storage value for the alert window picker, so the control survives
/// locale changes and the demo snapshot.
pub fn AlertsWindow::storage_value(self : AlertsWindow) -> String {
  match self {
    Today => "today"
    Last7Days => "last-7-days"
    Last30Days => "last-30-days"
    AllAlerts => "all"
  }
}

///|
pub fn parse_alerts_window(value : String) -> AlertsWindow {
  match value {
    "today" => Today
    "last-7-days" => Last7Days
    "last-30-days" => Last30Days
    _ => AllAlerts
  }
}

///|
pub fn AlertsWindow::label(
  self : AlertsWindow,
  locale : @i18n.Locale,
) -> String {
  match self {
    Today => @i18n.copy(locale, "Today", "今天")
    Last7Days => @i18n.copy(locale, "Last 7 days", "最近 7 天")
    Last30Days => @i18n.copy(locale, "Last 30 days", "最近 30 天")
    AllAlerts => @i18n.copy(locale, "All", "全部")
  }
}

///|
pub(all) struct ConsoleState {
  locale : @i18n.Locale
  route : OperatorRoute
  overview : OverviewMetrics
  nodes : Array[NodeRow]
  storage_nodes : Array[StorageNodeRow]
  models : Array[ModelRow]
  deployments : Array[DeploymentRow]
  catalog_templates : Array[@deployment.ModelServiceTemplate]
  service_deployments : Array[@deployment.DeploymentOperation]
  requests : RequestMetrics
  request_details : Array[RequestDetail]
  stream_events : Array[StreamEventView]
  benchmark_evidence : Array[String]
  policies : PolicySummary
  audit : Array[AuditRow]
  notifications : Array[NotificationRow]
  notification_deliveries : Array[NotificationDeliveryRow]
  accounts : Array[AccountView]
  trial_summary : TrialSummary?
  announcement_draft : AnnouncementDraft
  authenticated_account : AccountView?
  account_sessions : Array[BrowserSessionView]
  account_invite : AccountInviteDraft
  access_package_draft : AccessPackageDraft
  access_packages : Array[AccessPackageView]
  users : Array[UserAccessRow]
  access_grants : Array[AccessGrantRow]
  compute_leases : Array[ComputeLeaseRow]
  exclusive_node_leases : Array[ExclusiveNodeLeaseRow]
  resource_delivery : ResourceDeliveryPanel
  cost_centers : Array[CostCenterRow]
  agreements : Array[AgreementRow]
  enterprise_lease_requests : Array[EnterpriseLeaseRequestRow]
  portal_node_id : String
  qualified_services : Array[QualifiedServiceRow]
  offline_commerce : @offline_commerce.OfflineCommerceState
  contract_documents : @contract_documents.ContractDocumentsState
  production_readiness : ProductionReadinessState
  confirmation : Confirmation?
  error_message : String?
  success_message : String?
  loading : Bool
  operator_authenticated : Bool
  model_source_query : String
  model_source_results : Array[ModelSourceCatalogRow]
  model_source_total : Int64
  model_imports : Array[ModelImportRow]
  model_adoption_draft : ModelAdoptionDraft
  model_adopted_imports : Array[String]
  model_local_directories : Array[ModelLocalDirectoryRow]
  model_local_draft : ModelLocalRegistrationDraft
  model_license_draft : ModelLicenseDraft
  model_alias_draft : ModelAliasDraft
  runtime_draft : RuntimeProfileDraft
  template_draft : TemplateDraft
  /// The runtime images the registry admits, as the registry read reported
  /// them. The template form names one of these instead of retyping a digest.
  registered_runtimes : Array[@contracts.RuntimeSpec]
  operation_name : String
  operation_body : String
  quick_deployment_id : String
  quick_template : String
  quick_topology : QuickTopology
} derive(Eq)

///|
pub extend ConsoleState with Eq::{not_equal, equal}

///|
pub(all) enum ConsoleMessage {
  ResourceDelivery(ResourceDeliveryMessage)
  LocaleChanged(@i18n.Locale)
  Navigate(OperatorRoute)
  AlertsWindowChanged(AlertsWindow)
  BeginCordon(String)
  BeginDrain(String)
  BeginRollback(String)
  BeginStopDeployment(String)
  BeginRollbackServiceDeployment(String)
  BeginDeleteServiceDeployment(String)
  PromoteServiceDeployment(String)
  ActivateUser(String)
  BeginSuspendUser(String)
  BeginRevokeUser(String)
  BeginRevokeAccessGrant(String)
  ActivateComputeLease(String)
  BeginEndComputeLease(String)
  BeginTerminateExclusiveNodeLease(String, Int64)
  DismissConfirmation
  ConfirmAction(DestructiveAction)
  Refresh
  ModelSourceQueryChanged(String)
  SearchModelSource
  DownloadModelSource(String)
  CancelModelImport(String)
  RetryModelImport(String)
  RefreshModelImports
  BeginModelAdoption(String)
  DismissModelAdoption
  ModelAdoptionIdChanged(String)
  ModelAdoptionVersionChanged(String)
  ModelAdoptionLicenseChanged(String)
  ModelAdoptionArchitecturesChanged(String)
  ModelAdoptionMemoryChanged(String)
  SubmitModelAdoption
  RefreshModelLocalDirectories
  ModelLocalDirectoryChanged(String)
  ModelLocalRepositoryChanged(String)
  ModelLocalRevisionChanged(String)
  SubmitModelLocalRegistration
  BeginLicenseAcceptance(String, String)
  DismissLicenseAcceptance
  LicenseRecordIdChanged(String)
  LicenseEvidenceChanged(String)
  SubmitModelLicense
  VerifyModelArtifact(String, String)
  ApproveModelVersion(String, String)
  BeginAliasPromotion(String, String)
  DismissAliasPromotion
  AliasNameChanged(String)
  SubmitAliasPromotion
  RuntimeNameChanged(String)
  RuntimeVersionChanged(String)
  RuntimeImageDigestChanged(String)
  RuntimeArchitectureChanged(String)
  RuntimeCapabilityChanged(String)
  RuntimeBatchingToggled
  RuntimeMultiNodeToggled
  SubmitRuntimeRegistration
  TemplateTextChanged(TemplateField, String)
  TemplateFlagToggled(TemplateFlag)
  TemplateCapabilityChanged(String)
  TemplateClassificationChanged(String)
  /// The model picker: the value is `model_id@version`.
  TemplateModelSelected(String)
  /// The runtime picker: the value is `runtime_name@version`.
  TemplateRuntimeSelected(String)
  SubmitTemplateRegistration
  OperationChanged(String)
  OperationBodyChanged(String)
  SubmitOperation
  QuickDeploymentIdChanged(String)
  QuickTemplateChanged(String)
  QuickTopologyChanged(String)
  SubmitQuickDeployment
  PortalNodeChanged(String)
  ApproveEnterpriseLease(String, Int64)
  RejectEnterpriseLease(String, Int64)
  AcknowledgeAlert(String, Int64)
  AssignAlertToSelf(String, Int64)
  SilenceAlert(String, Int64)
  ResolveAlert(String, Int64)
  BeginRedriveNotificationDelivery(String, Int, Int64)
  AccountInviteIdChanged(String)
  AccountInviteSubjectRefChanged(String)
  AccountInviteIssuerChanged(String)
  AccountInviteProviderSubjectChanged(String)
  AccountInviteDisplayNameChanged(String)
  AccountInviteEmailChanged(String)
  AccountInviteReceiptChanged(String)
  AccountInviteRoleToggled(UiAccountRole)
  SubmitAccountInvite
  AnnouncementIdChanged(String)
  AnnouncementTenantChanged(String)
  AnnouncementTitleChanged(String)
  AnnouncementBodyChanged(String)
  AnnouncementExpiryChanged(String)
  AnnouncementLifetimeChosen(Int)
  SubmitAnnouncement
  AccessPackageIssuerChanged(String)
  AccessPackageSubjectChanged(String)
  AccessPackageDisplayNameChanged(String)
  AccessPackageEmailChanged(String)
  AccessPackageOrganizationChanged(String)
  AccessPackageTenantChanged(String)
  AccessPackageLifetimeChanged(Int)
  ToggleAccessPackageIdentityVerified
  SubmitAccessPackage
  EnableAccessPackage(String)
  BeginActivateAccount(String)
  BeginSuspendAccount(String)
  BeginRevokeAccount(String)
  BeginSetAccountRoles(String, Array[UiAccountRole])
  OfflineCommerce(@offline_commerce.OfflineCommerceMessage)
  ContractDocuments(@contract_documents.ContractDocumentsMessage)
} derive(Eq)

///|
pub extend ConsoleMessage with Eq::{not_equal, equal}

///|
pub fn confirmation_receipt(
  action : DestructiveAction,
  scope : String,
) -> Confirmation {
  {
    action,
    scope,
    receipt: "confirm:\{scope}:\{Repr(action)}",
    confirmed: false,
  }
}

///|
pub fn default_state() -> ConsoleState {
  {
    locale: @i18n.default_locale(),
    route: Overview,
    overview: {
      active_nodes: 0,
      total_nodes: 0,
      active_models: 0,
      queue_depth: 0,
      alerts: 0,
      recent_changes: 0,
    },
    nodes: [],
    storage_nodes: [],
    models: [],
    deployments: [],
    catalog_templates: [],
    service_deployments: [],
    requests: { count: 0, p95_ms: 0, throughput_per_second: 0, errors: 0, },
    request_details: [],
    stream_events: [],
    benchmark_evidence: [],
    policies: {
      quota_count: 0,
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: [],
    },
    audit: [],
    notifications: [],
    notification_deliveries: [],
    accounts: [],
    trial_summary: None,
    announcement_draft: empty_announcement_draft(),
    authenticated_account: None,
    account_sessions: [],
    account_invite: {
      account_id: "",
      subject_ref: "",
      identity_issuer: "",
      identity_subject: "",
      display_name: "",
      email: "",
      identity_receipt: "",
      roles: [EnterpriseUser],
    },
    access_package_draft: {
      identity_issuer: "",
      identity_subject: "",
      display_name: "",
      email: "",
      organization_id: "",
      tenant_ref: "",
      lifetime_days: 30,
      identity_verified: false,
    },
    access_packages: [],
    users: [],
    access_grants: [],
    compute_leases: [],
    exclusive_node_leases: [],
    resource_delivery: default_resource_delivery_panel(),
    cost_centers: [],
    agreements: [],
    enterprise_lease_requests: [],
    portal_node_id: "",
    qualified_services: [],
    offline_commerce: @offline_commerce.default_state(
      @i18n.default_locale(),
      OperatorCommerce,
    ),
    contract_documents: @contract_documents.default_state(
      @i18n.default_locale(),
      actor_owner=ManagerOperator,
    ),
    production_readiness: {
      ready: false,
      loading: true,
      blocker_codes: [],
      error: None,
    },
    confirmation: None,
    error_message: None,
    success_message: None,
    loading: false,
    operator_authenticated: false,
    model_source_query: "MiniCPM",
    model_source_results: [],
    model_source_total: 0L,
    model_imports: [],
    model_adoption_draft: {
      import_id: "",
      model_id: "",
      version: "",
      license_id: "",
      compatible_architectures: "",
      minimum_memory_mib: "",
    },
    model_adopted_imports: [],
    model_local_directories: [],
    model_local_draft: { directory: "", repository: "", revision: "master", },
    model_license_draft: empty_model_license_draft(),
    model_alias_draft: empty_model_alias_draft(),
    runtime_draft: default_runtime_draft(),
    template_draft: empty_template_draft(),
    registered_runtimes: [],
    operation_name: "register-model",
    operation_body: "",
    quick_deployment_id: "",
    quick_template: "",
    quick_topology: SingleMachine,
  }
}

///|
/// One approved demo artifact, with the licence record and managed-store
/// revision the per-row onboarding controls cite.
fn demo_model_row(
  model_id : String,
  version : String,
  alias_name : String,
  digest : String,
) -> ModelRow {
  {
    model_id,
    version,
    state: Approved,
    license_status: "accepted",
    evaluation_status: "passed",
    compatibility: "DGX Spark",
    alias_name,
    license_id: "license.\{alias_name}",
    artifact_uri: "modelstore://\{model_id}/\{version}",
    artifact_digest: digest,
  }
}

/// A deterministic, read-only snapshot for product demos and UI review.
/// It is never used by the live controller loading path.

///|
pub fn demo_state() -> ConsoleState {
  let contract_manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let contract_packet : @contractdoc.ContractPacket = {
    packet_id: "contract-packet-demo",
    idempotency_key: "contract-packet-demo-key",
    template_id: contract_manifest.template_id,
    template_version: contract_manifest.template_version,
    template_sha256: contract_manifest.sha256,
    tenant_ref: "tenant-demo",
    organization_id: "org-northstar",
    subject_ref: "subject-alice",
    order_ref: "order-demo-2026-001",
    preceding_packet_ref: None,
    active_forms: contract_manifest.forms.map(form => form.form),
    values: [{ field_id: "lessee.name", value: "Northstar Research", }],
    assignments: [
      {
        field_id: "lessee.name",
        value: "Northstar Research",
        owner: CustomerMessenger,
        source_ref: "customer-portal",
        updated_by: "subject-alice",
        updated_unix_ms: 1786521600000L,
      },
    ],
    values_sha256: None,
    confirmed_by: None,
    confirmed_unix_ms: None,
    artifacts: [],
    state: InformationDraft,
    execution: None,
    closure: None,
    supersession: None,
    generation_failure: None,
    revision: 2L,
    created_unix_ms: 1786521600000L,
    updated_unix_ms: 1786521600000L,
  }
  let effective_contract_packet : @contractdoc.ContractPacket = {
    ..contract_packet,
    packet_id: "contract-packet-effective-demo",
    idempotency_key: "contract-packet-effective-demo-key",
    order_ref: "order-demo-2026-000",
    values: [
      { field_id: "lessee.name", value: "Northstar Research", },
      { field_id: "lease.start_date", value: "2026-08-01", },
      { field_id: "lease.end_date", value: "2027-07-31", },
    ],
    values_sha256: Some(
      "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    ),
    confirmed_by: Some("subject-alice"),
    confirmed_unix_ms: Some(1786525200000L),
    state: Effective,
    execution: Some({
      evidence_sha256: "sha256:2222222222222222222222222222222222222222222222222222222222222222",
      signed_on: "2026-08-01",
      registered_by: "operator-a",
      registered_unix_ms: 1786528800000L,
    }),
    revision: 5L,
    updated_unix_ms: 1786528800000L,
  }
  let contract_approval : @contractdoc.ContractApproval = {
    approval_id: "contract-approval-demo",
    packet_id: effective_contract_packet.packet_id,
    action: "close:EarlyTermination",
    expected_revision: effective_contract_packet.revision,
    payload: {
      evidence_sha256: None,
      signed_on: None,
      kind: Some(EarlyTermination),
      reason: Some("operator review required"),
      amount_minor_units: Some(2880000L),
      packet_values_sha256: Some(
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
    },
    initiator: "operator-a",
    created_unix_ms: 1786529000000L,
    status: Pending,
    decided_by: None,
    decided_unix_ms: None,
    decision_reason: None,
  }
  let nodes : Array[NodeRow] = [
    {
      node_id: "dgx-spark-01",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 81920,
      used_memory_mib: 40960,
      memory_measured: true,
      utilization_per_mille: 420,
      cpu_per_mille: 340,
      cpu_measured: true,
      temperature_celsius: 46,
      power_watts: 76,
      workloads: 1,
      lease_holder: "org-northstar · alice",
      active_assignment: "deployment-qwen-eval",
      last_seen: "≤ 1 s",
    },
    {
      node_id: "dgx-spark-02",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 79872,
      used_memory_mib: 43008,
      memory_measured: true,
      utilization_per_mille: 610,
      cpu_per_mille: 520,
      cpu_measured: true,
      temperature_celsius: 51,
      power_watts: 89,
      workloads: 1,
      lease_holder: "org-acme · bob",
      active_assignment: "deployment-vision-review",
      last_seen: "≤ 1 s",
    },
    {
      node_id: "dgx-spark-03",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 80896,
      used_memory_mib: 41984,
      memory_measured: true,
      utilization_per_mille: 80,
      cpu_per_mille: 90,
      cpu_measured: true,
      temperature_celsius: 38,
      power_watts: 42,
      workloads: 0,
      lease_holder: "",
      active_assignment: "",
      last_seen: "3 s",
    },
    {
      node_id: "dgx-spark-04",
      state: Active,
      architecture: "nvidia-gb10",
      total_memory_mib: 122880,
      free_memory_mib: 79872,
      used_memory_mib: 43008,
      memory_measured: true,
      utilization_per_mille: 30,
      cpu_per_mille: 40,
      cpu_measured: true,
      temperature_celsius: 36,
      power_watts: 39,
      workloads: 0,
      lease_holder: "",
      active_assignment: "",
      last_seen: "5 s",
    },
  ]
  let models : Array[ModelRow] = [
    demo_model_row(
      "lunanexa.text.general", "v3", "text.default", "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    ),
    demo_model_row(
      "lunanexa.text.fast", "v2", "text.fast", "sha256:2222222222222222222222222222222222222222222222222222222222222222",
    ),
    demo_model_row(
      "lunanexa.text.reasoning", "v1", "text.reasoning", "sha256:3333333333333333333333333333333333333333333333333333333333333333",
    ),
    demo_model_row(
      "lunanexa.code.assist", "v4", "code.assist", "sha256:4444444444444444444444444444444444444444444444444444444444444444",
    ),
    demo_model_row(
      "lunanexa.embedding.multilingual", "v2", "embedding.multilingual", "sha256:5555555555555555555555555555555555555555555555555555555555555555",
    ),
    demo_model_row(
      "lunanexa.embedding.base", "v1", "embedding.default", "sha256:6666666666666666666666666666666666666666666666666666666666666666",
    ),
    demo_model_row(
      "lunanexa.vision.general", "v2", "vision.default", "sha256:7777777777777777777777777777777777777777777777777777777777777777",
    ),
    demo_model_row(
      "lunanexa.rerank.base", "v1", "rerank.default", "sha256:8888888888888888888888888888888888888888888888888888888888888888",
    ),
    demo_model_row(
      "lunanexa.speech.transcribe", "v2", "speech.transcribe", "sha256:9999999999999999999999999999999999999999999999999999999999999999",
    ),
  ]
  let templates : Array[@deployment.ModelServiceTemplate] = [
    {
      template_id: "text-small",
      version: "v1",
      display_name: "Text small",
      description: "Approved DGX Spark text service",
      model_selector: "text.default",
      model_id: "lunanexa.text.general",
      model_version: "v3",
      artifact: {
        digest: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        uri: "s3://models/lunanexa.text.general/v3",
        size_bytes: 16000000000L,
        signature_ref: "s3://models/lunanexa.text.general/v3.sig",
      },
      runtime: {
        name: "text-runtime",
        image_digest: "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        version: "runtime-v1",
        architectures: ["nvidia-gb10"],
        capabilities: [TextGenerate],
        supports_batching: false,
        supports_multi_node: false,
      },
      capability: TextGenerate,
      architecture: "nvidia-gb10",
      resources: {
        accelerator_count: 1,
        accelerator_memory_mib: 24000,
        cpu_millis: 4000,
        memory_mib: 32000,
      },
      network: {
        allow_controller: true,
        allow_artifact_store: true,
        allowed_egress: [],
      },
      health: {
        readiness_path: "/health",
        interval_ms: 1000,
        failure_threshold: 3,
        termination_grace_ms: 30000,
      },
      data_policy: {
        classification: Internal,
        retention: Ephemeral,
        allow_cache: false,
        allow_training_reuse: false,
      },
      secret_refs: ["runtime-token"],
      rollout: {
        canary_replicas: 1,
        automatic_promotion: false,
        automatic_rollback: true,
        readiness_timeout_ms: 60000L,
      },
      approval_receipt: "catalog:text-small:v1",
      signature: "demo-signed",
    },
  ]
  // The registry roster the template form names a runtime from. The text
  // runtime is the one `templates[0]` deploys; the other two are registered and
  // verified but not yet used by a template.
  let runtimes : Array[@contracts.RuntimeSpec] = [
    templates[0].runtime,
    {
      name: "embedding-runtime",
      image_digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      version: "runtime-v1",
      architectures: ["nvidia-gb10"],
      capabilities: [EmbeddingCreate],
      supports_batching: false,
      supports_multi_node: false,
    },
    {
      name: "vision-runtime",
      image_digest: "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      version: "runtime-v2",
      architectures: ["nvidia-gb10"],
      capabilities: [ImageGenerate, VideoGenerate],
      supports_batching: false,
      supports_multi_node: false,
    },
  ]
  let service_intent : @deployment.ModelServiceIntent = {
    version: @contracts.contract_version,
    idempotency_key: "demo:text-service:1",
    deployment_id: "text-service",
    template: { template_id: "text-small", version: "v1", },
    replicas: 1,
    data_class: Internal,
    lease_duration_ms: 86400000L,
    promote_when_ready: false,
    topology_profile: None,
  }
  let service_operation : @deployment.DeploymentOperation = {
    operation_id: "operation-text-service-01",
    deployment_id: "text-service",
    generation: 3L,
    state: Ready,
    plan: {
      plan_id: "plan:text-service:text-small:v1",
      intent: service_intent,
      template: Some(templates[0]),
      replicas: [
        {
          replica_id: "text-service-r1",
          node_id: "dgx-spark-03",
          devices: ["gpu-0"],
          group: None,
        },
      ],
      findings: [],
      executable: true,
      endpoint: Some({
        canonical_path: "/v1/workloads",
        model_selector: "text.default",
      }),
    },
    assignment_ids: ["assignment-text-service-r1"],
    endpoint: Some({
      canonical_path: "/v1/workloads",
      model_selector: "text.default",
    }),
    message: "Ready on one eligible DGX Spark node",
    audit_receipt: "demo:deployment:text-service:3",
    created_unix_ms: 1786500000000L,
    updated_unix_ms: 1786500300000L,
  }
  {
    ..default_state(),
    overview: {
      active_nodes: 4,
      total_nodes: 4,
      active_models: 9,
      queue_depth: 1,
      alerts: 0,
      recent_changes: 6,
    },
    nodes,
    storage_nodes: [],
    models,
    deployments: [
      {
        assignment_id: "assignment-qwen-eval-r1",
        deployment_id: "deployment-qwen-eval",
        desired: Ready,
        observed: Ready,
        placement_reason: "warm model · 80 GiB free · policy compatible",
      },
      {
        assignment_id: "assignment-vision-review-r1",
        deployment_id: "deployment-vision-review",
        desired: Ready,
        observed: Degraded,
        placement_reason: "vision runtime · tenant lease · retrying health probe",
      },
    ],
    catalog_templates: templates,
    registered_runtimes: runtimes,
    service_deployments: [service_operation],
    requests: {
      count: 1842,
      p95_ms: 142,
      throughput_per_second: 38,
      errors: 3,
    },
    request_details: [
      {
        timestamp_unix_ms: 1786500320000L,
        action: "workload.invoke",
        model_selector: "text.default",
        result: "accepted",
        receipt: "demo:workload:1842",
      },
      {
        timestamp_unix_ms: 1786500280000L,
        action: "workload.stream",
        model_selector: "code.assist",
        result: "accepted",
        receipt: "demo:workload:1841",
      },
    ],
    stream_events: [
      {
        sequence: 1,
        kind: "Chunk",
        text: "A bounded demo output chunk.",
        receipt: "",
      },
      {
        sequence: 2,
        kind: "Completed",
        text: "",
        receipt: "demo:workload:1841",
      },
    ],
    benchmark_evidence: [
      "demo-throughput · p95 142 ms · 38/s · failures 1‰ · demo-run-01",
    ],
    policies: {
      quota_count: 6,
      data_class_count: 4,
      default_retention: Ephemeral,
      allowed_runtimes: ["text-runtime", "embedding-runtime", "vision-runtime"],
    },
    audit: [
      {
        actor: "demo-operator",
        decision: "cluster.snapshot",
        evidence: "4-node demo fleet",
        result: "accepted",
        receipt: "demo:audit:01",
      },
    ],
    notifications: [],
    notification_deliveries: [],
    trial_summary: None,
    announcement_draft: empty_announcement_draft(),
    accounts: [
      {
        account_id: "account-alice",
        subject_ref: "subject-alice",
        identity_issuer: "https://identity.example.test",
        display_name: "Alice Chen",
        email: "alice@example.test",
        identity_receipt: "identity:demo:alice",
        roles: [PlatformOperator, AuditReader],
        state: Active,
        created_unix_ms: 1786500000000L,
        updated_unix_ms: 1786503600000L,
      },
      {
        account_id: "account-mina",
        subject_ref: "subject-mina",
        identity_issuer: "https://identity.example.test",
        display_name: "Mina Rao",
        email: "mina@example.test",
        identity_receipt: "identity:demo:mina",
        roles: [EnterpriseUser],
        state: Invited,
        created_unix_ms: 1786500000000L,
        updated_unix_ms: 1786500000000L,
      },
    ],
    authenticated_account: Some({
      account_id: "account-alice",
      subject_ref: "subject-alice",
      identity_issuer: "https://identity.example.test",
      display_name: "Alice Chen",
      email: "alice@example.test",
      identity_receipt: "identity:demo:alice",
      roles: [PlatformOperator, AuditReader],
      state: Active,
      created_unix_ms: 1786500000000L,
      updated_unix_ms: 1786503600000L,
    }),
    account_sessions: [
      {
        session_id: "session-demo-current",
        account_id: "account-alice",
        created_unix_ms: 1786500000000L,
        expires_unix_ms: 1786543200000L,
        last_used_unix_ms: 1786503600000L,
        revoked_unix_ms: None,
      },
    ],
    account_invite: {
      account_id: "",
      subject_ref: "",
      identity_issuer: "",
      identity_subject: "",
      display_name: "",
      email: "",
      identity_receipt: "",
      roles: [EnterpriseUser],
    },
    access_package_draft: {
      identity_issuer: "https://identity.example.test",
      identity_subject: "provider-subject-new-developer",
      display_name: "New WebIDE Developer",
      email: "developer@example.test",
      organization_id: "org-northstar",
      tenant_ref: "tenant-northstar",
      lifetime_days: 30,
      identity_verified: true,
    },
    access_packages: [
      {
        package_id: "access-account-alice",
        account_id: "account-alice",
        subject_ref: "subject-alice",
        display_name: "Alice Chen",
        email: "alice@example.test",
        organization_id: "org-northstar",
        tenant_ref: "tenant-northstar",
        user_id: Some("user-alice"),
        membership_id: "membership-alice",
        grant_id: Some("grant-alice-research"),
        lease_id: Some("workspace-lease-alice"),
        lease_state: Some(Active),
        expires_unix_ms: Some(1786557600000L),
        approved_model_aliases: ["text.default"],
        account_ready: true,
        membership_ready: true,
        contract_required: false,
        contract_ready: true,
        workspace_ready: true,
        models_ready: true,
        ready: true,
        can_enable: false,
        state: "Ready",
      },
    ],
    users: [
      {
        user_id: "user-alice",
        display_name: "Alice Chen",
        email: "alice@example.test",
        state: UserActive,
        last_active: "2 minutes ago",
        grant_count: 1,
      },
      {
        user_id: "user-mina",
        display_name: "Mina Rao",
        email: "mina@example.test",
        state: UserInvited,
        last_active: "Never",
        grant_count: 0,
      },
    ],
    access_grants: [
      {
        grant_id: "grant-alice-research",
        user_id: "user-alice",
        role: Developer,
        scope: "workspace/research-main",
        expires_at: "2026-08-13 02:00 北京时间",
        state: GrantActive,
      },
    ],
    compute_leases: [
      {
        lease_id: "workspace-lease-alice",
        user_id: "user-alice",
        subject_ref: "subject-alice",
        workspace: "research-main",
        resource: "Text generation · 2 concurrent",
        started_at: "2026-08-12 18:00 北京时间",
        expires_at: "2026-08-13 02:00 北京时间",
        state: Active,
      },
      {
        lease_id: "workspace-lease-mina",
        user_id: "user-mina",
        subject_ref: "subject-mina",
        workspace: "research-pending",
        resource: "Text generation · 1 concurrent",
        started_at: "2026-08-13 16:00 北京时间",
        expires_at: "2026-08-13 20:00 北京时间",
        state: Requested,
      },
    ],
    exclusive_node_leases: [
      {
        lease_id: "lease-northstar-alice",
        node_id: "dgx-spark-01",
        subject_ref: "subject-alice",
        unix_username: "alice",
        expires_at: "2026-08-12T18:00:00Z",
        state: "Active",
        generation: 4L,
      },
    ],
    cost_centers: [
      {
        cost_center_id: "cc-research",
        organization_id: "org-luna",
        display_name: "Research",
        parent_cost_center_id: "",
        project_count: 3,
        provisional_spend: "CNY 12,840.00",
        budget_posture: "Within budget",
      },
      {
        cost_center_id: "cc-platform",
        organization_id: "org-luna",
        display_name: "Platform",
        parent_cost_center_id: "",
        project_count: 2,
        provisional_spend: "CNY 8,120.00",
        budget_posture: "Approval at 80%",
      },
    ],
    agreements: [
      {
        agreement_id: "agreement-capacity-2026",
        agreement_type: "Reserved capacity",
        template_version: "capacity-v2",
        organization_id: "org-luna",
        state: "Executed",
        evidence_receipt: "evidence:agreement:2026:01",
      },
      {
        agreement_id: "agreement-dpa-2026",
        agreement_type: "Data processing",
        template_version: "dpa-v1",
        organization_id: "org-luna",
        state: "Awaiting signature",
        evidence_receipt: "evidence:agreement:2026:02",
      },
    ],
    enterprise_lease_requests: [
      {
        request_id: "request-eval-042",
        organization_id: "org-northstar",
        subject_ref: "subject-alice",
        project_id: "project-vision-lab",
        unix_username: "alice",
        requested_models: "qwen3-32b, bge-m3",
        state: "Submitted",
        generation: 1L,
        assigned_node_id: "—",
      },
    ],
    portal_node_id: "dgx-spark-04",
    qualified_services: [
      {
        provider: "LunaFide",
        capability: "Identity · signature · payment · invoice",
        environment: "TestOnly",
        state: "Available",
        evidence_policy: "Signed, sequenced, tenant-bound callbacks",
        production_ready: false,
      },
    ],
    offline_commerce: @offline_commerce.demo_state(
      @i18n.default_locale(),
      OperatorCommerce,
    ),
    contract_documents: {
      ..@contract_documents.default_state(
        @i18n.default_locale(),
        actor_owner=ManagerOperator,
      ),
      manifest: Some(contract_manifest),
      packets: [contract_packet, effective_contract_packet],
      events: [
        {
          event_id: "contract-event-operator-demo-created",
          packet_id: effective_contract_packet.packet_id,
          revision: 1L,
          kind: PacketCreated,
          actor_ref: "operator-a",
          changed_field_ids: [],
          values_sha256: None,
          artifact_sha256: None,
          occurred_unix_ms: effective_contract_packet.created_unix_ms,
        },
        {
          event_id: "contract-event-operator-demo-effective",
          packet_id: effective_contract_packet.packet_id,
          revision: effective_contract_packet.revision,
          kind: ExecutionRegisteredEvent,
          actor_ref: "operator-a",
          changed_field_ids: [],
          values_sha256: effective_contract_packet.values_sha256,
          artifact_sha256: effective_contract_packet.execution.map(value => {
            value.evidence_sha256
          }),
          occurred_unix_ms: effective_contract_packet.updated_unix_ms,
        },
      ],
      approvals: [contract_approval],
      obligations: [
        {
          obligation_id: "contract-obligation-overdue-demo",
          tenant_ref: effective_contract_packet.tenant_ref,
          packet_id: effective_contract_packet.packet_id,
          kind: PaymentMilestone,
          title: "August capacity payment",
          owner_ref: "subject-alice",
          due_unix_ms: 1786442400000L,
          amount_minor_units: Some(1280000L),
          state: Overdue,
          evidence_ref: None,
          completed_by: None,
          completed_unix_ms: None,
          created_by: Some("operator-a"),
          created_unix_ms: 1786356000000L,
          updated_unix_ms: 1786529000000L,
          revision: 2L,
        },
      ],
      governance_dashboard: Some({
        tenant_ref: "tenant-demo",
        effective_packets: 1,
        pending_approvals: 1,
        overdue_obligations: 1,
        open_closure_proposals: 0,
        total_amount_minor_units: 1280000L,
        next_expiry_unix_ms: Some(1786528800000L),
        generated_unix_ms: 1786529000000L,
      }),
      selected_packet_id: Some(contract_packet.packet_id),
      selected_form: Some(MasterLease),
      draft_values: contract_packet.values,
    },
    production_readiness: {
      ready: true,
      loading: false,
      blocker_codes: [],
      error: None,
    },
    operator_authenticated: true,
    quick_template: "text-small@v1",
  }
}

///|
fn localized(
  locale : @i18n.Locale,
  english : String,
  chinese : String,
) -> String {
  @i18n.copy(locale, english, chinese)
}

///|
fn generated_time_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "Never" | "从未" => "从未"
      "Unavailable" | "不可用" => "不可用"
      _ => value
    }
  } else {
    match value {
      "Never" | "从未" => "Never"
      "Unavailable" | "不可用" => "Unavailable"
      _ => value
    }
  }
}

///|
fn architecture_label(locale : @i18n.Locale, value : String) -> String {
  if value == "nvidia-sm121" || value == "nvidia-gb10" {
    "NVIDIA GB10 · DGX Spark"
  } else if locale.is_chinese() && value == "unreported" {
    "未上报"
  } else {
    value
  }
}

///|
fn license_evidence_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "accepted" => "已接受"
      "missing" => "未记录"
      _ => value
    }
  } else {
    value
  }
}

///|
fn evaluation_evidence_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "passed" => "已通过"
      "missing" => "未评测（不阻塞）"
      "failed" => "未通过"
      _ => value
    }
  } else {
    value
  }
}

///|
fn result_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() && value == "accepted" {
    "已接受"
  } else {
    value
  }
}

///|
fn stream_kind_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    match value {
      "Chunk" => "数据块"
      "Completed" => "已完成"
      "Failed" => "失败"
      "Cancelled" => "已取消"
      _ => value
    }
  } else {
    value
  }
}

///|
fn agreement_type_label(locale : @i18n.Locale, value : String) -> String {
  match value {
    "Reserved capacity" => localized(locale, value, "预留容量")
    "Data processing" => localized(locale, value, "数据处理")
    _ => value
  }
}

///|
fn agreement_state_label(locale : @i18n.Locale, value : String) -> String {
  match value {
    "Executed" => localized(locale, value, "已执行")
    "Awaiting signature" => localized(locale, value, "等待签署")
    "Review required" => localized(locale, value, "待审阅")
    "Declined" => localized(locale, value, "已拒绝")
    "Superseded" => localized(locale, value, "已替代")
    _ => value
  }
}

///|
fn enterprise_request_state_label(
  locale : @i18n.Locale,
  value : String,
) -> String {
  match value {
    "Submitted" => localized(locale, value, "待运维审核")
    "Approved" => localized(locale, value, "已批准")
    "Rejected" => localized(locale, value, "已拒绝")
    "Cancelled" => localized(locale, value, "已取消")
    _ => value
  }
}

///|
fn lease_resource_label(locale : @i18n.Locale, value : String) -> String {
  if locale.is_chinese() {
    value
    .replace_all(old="No inference capabilities", new="无推理能力")
    .replace_all(old="Text generation", new="文本生成")
    .replace_all(old="Embeddings", new="嵌入")
    .replace_all(old="Image generation", new="图像生成")
    .replace_all(old="Video generation", new="视频生成")
    .replace_all(old="Audio generation", new="音频生成")
    .replace_all(old=" concurrent", new=" 路并发")
  } else {
    value
    .replace_all(old="无推理能力", new="No inference capabilities")
    .replace_all(old="文本生成", new="Text generation")
    .replace_all(old="嵌入", new="Embeddings")
    .replace_all(old="图像生成", new="Image generation")
    .replace_all(old="视频生成", new="Video generation")
    .replace_all(old="音频生成", new="Audio generation")
    .replace_all(old=" 路并发", new=" concurrent")
  }
}

///|
fn route_label(locale : @i18n.Locale, route : OperatorRoute) -> String {
  match route {
    Overview => localized(locale, "Overview", "概览")
    Alerts => localized(locale, "Alerts", "告警")
    Users => localized(locale, "Users & access", "用户与访问权限")
    Leases => localized(locale, "Leases", "租约")
    CostCenters => localized(locale, "Cost centers", "成本中心")
    Agreements => localized(locale, "Agreements", "数字协议")
    OfflineCommerce => localized(locale, "Offline commerce", "线下商务")
    ContractDocuments => localized(locale, "Contract documents", "合同资料")
    QualifiedServices => localized(locale, "Qualified services", "资质服务")
    Nodes => localized(locale, "Nodes", "节点")
    Models => localized(locale, "Models", "模型")
    Catalog => localized(locale, "Catalog", "目录")
    Deployments => localized(locale, "Deployments", "部署")
    Requests => localized(locale, "Requests", "请求")
    Benchmarks => localized(locale, "Benchmarks", "基准测试")
    Policies => localized(locale, "Policies", "策略")
    Audit => localized(locale, "Audit", "审计")
    Blank => localized(locale, "Blank page", "空白页")
  }
}

///|
/// An intentionally empty page. It renders the page frame and nothing else, so
/// whatever is placed here later starts from a blank surface rather than from
/// someone else's layout.
fn blank_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("blank-title"), [
    @html.h2(id="blank-title", route_label(state.locale, Blank)),
  ])
}

///|
fn route_description(locale : @i18n.Locale, route : OperatorRoute) -> String {
  match route {
    Overview =>
      localized(
        locale, "Live capacity, service posture, and recent control-plane activity.",
        "查看实时容量、服务状态与近期控制平面活动。",
      )
    Alerts =>
      localized(
        locale, "Durable cluster incidents with acknowledgement, ownership, silence, and resolution.",
        "查看可确认、分派、静默和解决的持久化集群事件。",
      )
    Users =>
      localized(
        locale, "Identity lifecycle and scoped access to LunaNexa services.", "管理身份生命周期与 LunaNexa 服务的限定范围访问权限。",
      )
    Leases =>
      localized(
        locale, "Manage exclusive machine access and workspace capacity separately.",
        "分别管理独占机器访问与工作区容量授权。",
      )
    CostCenters =>
      localized(
        locale, "Tenant hierarchy, metered spend, budgets, quotas, and finance evidence.",
        "管理租户层级、计量支出、预算、配额与财务证据。",
      )
    Agreements =>
      localized(
        locale, "Versioned clickwrap and e-signature lifecycles with immutable evidence receipts.",
        "管理带不可变证据回执的版本化点击接受与电子签名生命周期。",
      )
    OfflineCommerce =>
      localized(
        locale, "Quote, generate, release, review, and fulfill hybrid offline orders with auditable evidence.",
        "通过可审计凭证完成线上线下协同订单的报价、生成、发布、审核与履约。",
      )
    ContractDocuments =>
      localized(
        locale, "Complete manager-owned contract fields and review the same live source preview as the customer.",
        "填写经理/运营方负责的合同字段，并与客户查看同一份源文件实时预览。",
      )
    QualifiedServices =>
      localized(
        locale, "Provider-neutral identity, signature, payment, and invoice integration posture.",
        "查看供应商中立的身份、签名、支付与发票集成状态。",
      )
    Nodes =>
      localized(
        locale, "Hardware inventory, workload pressure, and maintenance controls.",
        "查看硬件清单、工作负载压力与维护控制。",
      )
    Models =>
      localized(
        locale, "Approved artifacts, evaluation evidence, and serving aliases.",
        "查看已批准模型制品、评测证据与服务模型别名。",
      )
    Catalog =>
      localized(
        locale, "Approved templates, deterministic preflight, and one-click model services.",
        "管理已批准模板、确定性预检与一键模型服务。",
      )
    Deployments =>
      localized(
        locale, "Desired state, observed readiness, and placement decisions.", "对比期望状态、实际就绪状态与放置决策。",
      )
    Requests =>
      localized(
        locale, "Bounded request telemetry and payload-free workload receipts.",
        "查看有边界的请求遥测与不含载荷的工作负载回执。",
      )
    Benchmarks =>
      localized(
        locale, "Comparable performance evidence for approved runtime profiles.",
        "比较已批准运行时配置的性能证据。",
      )
    Policies =>
      localized(
        locale, "Quotas, retention, runtime policy, and typed operator operations.",
        "管理配额、保留策略、运行时策略与类型化运维操作。",
      )
    Audit =>
      localized(
        locale, "Immutable decisions, evidence, results, and correlation receipts.",
        "追踪不可变的决策、证据、结果与关联回执。",
      )
    Blank =>
      localized(
        locale, "Deliberately empty, for whatever is placed here next.", "刻意留空的页面，供后续放置内容。",
      )
  }
}

///|
fn command(
  emit : @rabbita.Emit[ConsoleMessage]?,
  message : ConsoleMessage,
) -> @rabbita.Cmd {
  match emit {
    Some(send) => send(message)
    None => @rabbita.none
  }
}

///|
fn text_command(
  emit : @rabbita.Emit[ConsoleMessage]?,
  wrap : (String) -> ConsoleMessage,
) -> @rabbita.Emit[String] {
  match emit {
    Some(send) => send.map(wrap)
    None => Emit(_ => @rabbita.none)
  }
}

///|
fn navigation(
  locale : @i18n.Locale,
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.nav(
    attrs=@html.Attrs::build().aria_label(
      localized(locale, "Primary", "主导航"),
    ),
    [
      @html.p(class="nav-group-label", localized(locale, "Monitor", "监控")),
      nav_link(locale, Overview, current, emit),
      nav_link(locale, Alerts, current, emit),
      nav_link(locale, Nodes, current, emit),
      nav_link(locale, Models, current, emit),
      nav_link(locale, Catalog, current, emit),
      nav_link(locale, Deployments, current, emit),
      nav_link(locale, Requests, current, emit),
      @html.p(class="nav-group-label", localized(locale, "Govern", "治理")),
      nav_link(locale, Users, current, emit),
      nav_link(locale, Leases, current, emit),
      nav_link(locale, CostCenters, current, emit),
      nav_link(locale, Agreements, current, emit),
      nav_link(locale, OfflineCommerce, current, emit),
      nav_link(locale, ContractDocuments, current, emit),
      nav_link(locale, Policies, current, emit),
      @html.p(class="nav-group-label", localized(locale, "Evidence", "证据")),
      nav_link(locale, QualifiedServices, current, emit),
      nav_link(locale, Benchmarks, current, emit),
      nav_link(locale, Audit, current, emit),
      nav_link(locale, Blank, current, emit),
    ],
  )
}

///|
fn nav_link(
  locale : @i18n.Locale,
  route : OperatorRoute,
  current : OperatorRoute,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let label = route_label(locale, route)
  @html.button(
    type_="button",
    class=if route == current { "nav-link active" } else { "nav-link" },
    on_click=command(emit, Navigate(route)),
    attrs=@html.Attrs::build().aria_current(
      if route == current {
        "page"
      } else {
        "false"
      },
    ),
    [@html.span(class="nav-indicator", ""), @html.span(label)],
  )
}

///|
fn stat(
  label : String,
  value : String,
  detail : String,
  tone : String,
) -> @rabbita.Html {
  @html.div(class="stat stat-\{tone}", [
    @html.dt(label),
    @html.dd(value),
    @html.span(class="stat-detail", detail),
  ])
}

///|
fn readiness_item(
  locale : @i18n.Locale,
  ready : Bool,
  label : String,
  detail : String,
) -> @rabbita.Html {
  @html.li(
    class=if ready { "readiness-item ready" } else { "readiness-item" },
    [
      @html.span(
        class="readiness-mark",
        attrs=@html.Attrs::build().aria_hidden("true"),
        if ready {
          "✓"
        } else {
          "!"
        },
      ),
      @html.div([
        @html.strong(label),
        @html.span(
          class="secondary",
          if ready {
            detail
          } else {
            localized(locale, "Action required · ", "需要操作 · ") +
            detail
          },
        ),
      ]),
    ],
  )
}

///|
fn readiness_blocker_label(locale : @i18n.Locale, code : String) -> String {
  match code {
    "NotificationDeliveryNotReady" =>
      localized(locale, "Notification delivery", "通知投递")
    "ExternalObservabilityNotReady" =>
      localized(
        locale, "External observability export", "外部可观测性导出",
      )
    "OfflineCommerceNotReady" =>
      localized(locale, "Offline commerce pipeline", "线下商务流水线")
    "CredentialBrokerUnavailable" =>
      localized(locale, "Credential broker", "凭据代理")
    "MachineHelperAdapterUnverified" =>
      localized(locale, "Machine cleanup helper", "机器清理助手")
    "ExclusiveMachineAuthorityUnavailable" =>
      localized(locale, "Exclusive-machine authority", "独占机器权限")
    "ArtifactSignatureVerifierUnavailable" =>
      localized(locale, "Artifact signature verifier", "制品签名验证器")
    "GuideDiagnosticsUnavailable" =>
      localized(locale, "Guide diagnostics", "指南诊断")
    "ExclusiveLeaseExpiryReconcilerUnavailable" =>
      localized(locale, "Lease expiry controller", "租约到期控制器")
    _ => localized(locale, "Blocked: \{code}", "阻塞：\{code}")
  }
}

///|
fn overview_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("overview-title"), [
    @html.div(class="overview-grid", [
      @html.div(
        class=if state.overview.total_nodes == 0 {
          "health-panel health-panel-unknown"
        } else if state.overview.alerts == 0 &&
          state.overview.active_nodes == state.overview.total_nodes {
          "health-panel health-panel-ok"
        } else {
          "health-panel health-panel-warning"
        },
        [
          @html.p(
            class="eyebrow",
            localized(state.locale, "Cluster posture", "集群状态"),
          ),
          @html.div(class="health-title", [
            @html.span(
              class="health-dot",
              attrs=@html.Attrs::build().aria_hidden("true"),
              "",
            ),
            @html.h2(
              id="overview-title",
              if state.overview.total_nodes == 0 {
                localized(
                  state.locale,
                  "Awaiting cluster telemetry",
                  "等待集群遥测",
                )
              } else if state.overview.alerts == 0 &&
                state.overview.active_nodes == state.overview.total_nodes {
                localized(
                  state.locale,
                  "Node heartbeats healthy",
                  "节点心跳正常",
                )
              } else {
                localized(
                  state.locale,
                  "Cluster needs attention",
                  "集群需要关注",
                )
              },
            ),
          ]),
          @html.p(
            class="health-copy",
            if state.overview.total_nodes == 0 {
              localized(
                state.locale,
                "Connect the controller and enroll a node to establish live cluster posture.",
                "连接控制器并注册节点，以建立实时集群状态。",
              )
            } else if state.overview.active_nodes < state.overview.total_nodes {
              localized(
                state.locale,
                "Some nodes are not active; inspect node heartbeat and maintenance status.",
                "部分节点未处于活跃状态，请检查心跳与维护状态。",
              )
            } else if state.overview.alerts == 0 {
              localized(
                state.locale,
                "Node heartbeat and reported alerts only; this does not verify model inference or service availability.",
                "此状态仅代表节点心跳和已上报告警，不代表模型推理与业务服务已验收。",
              )
            } else {
              localized(
                state.locale,
                "\{state.overview.alerts} alert signals require operator review before the next change window.",
                "下一个变更窗口前，需要运维人员检查 \{state.overview.alerts} 个告警信号。",
              )
            },
          ),
          @html.dl(class="health-facts", [
            @html.div([
              @html.dt(
                localized(state.locale, "Node availability", "节点可用性"),
              ),
              @html.dd(
                localized(
                  state.locale,
                  "\{state.overview.active_nodes} of \{state.overview.total_nodes}",
                  "\{state.overview.active_nodes} / \{state.overview.total_nodes}",
                ),
              ),
            ]),
            @html.div([
              @html.dt(
                localized(state.locale, "Approved models", "已批准模型"),
              ),
              @html.dd(state.overview.active_models.to_string()),
            ]),
            @html.div([
              @html.dt(
                localized(state.locale, "Pending queue", "待处理队列"),
              ),
              @html.dd(state.overview.queue_depth.to_string()),
            ]),
          ]),
        ],
      ),
      @html.aside(class="activity-panel", [
        @html.p(
          class="eyebrow",
          localized(state.locale, "Change activity", "变更活动"),
        ),
        @html.p(
          class="activity-value",
          if state.overview.recent_changes < 0 {
            localized(state.locale, "Not loaded", "尚未加载")
          } else {
            state.overview.recent_changes.to_string()
          },
        ),
        @html.p(
          class="activity-label",
          localized(
            state.locale,
            "Loaded audit records (up to 20); open Audit for history.",
            "已加载审计记录（最多 20 条）；完整记录请打开审计页。",
          ),
        ),
        @html.div(class="activity-divider", ""),
        @html.p(class="activity-note", [
          @html.strong(localized(state.locale, "Audit ready", "审计就绪")),
          @html.span(
            localized(
              state.locale,
              "Every consequential action produces a receipt.",
              "每项重要操作都会生成回执。",
            ),
          ),
        ]),
      ]),
    ]),
    @html.dl(class="stats", [
      stat(
        localized(state.locale, "Available nodes", "可用节点"),
        "\{state.overview.active_nodes}/\{state.overview.total_nodes}",
        if state.overview.total_nodes == 0 {
          localized(state.locale, "Telemetry unavailable", "遥测不可用")
        } else {
          localized(
            state.locale,
            "Active heartbeat · placement requires preflight",
            "心跳活跃 · 放置仍需预检",
          )
        },
        if state.overview.total_nodes == 0 {
          "neutral"
        } else if state.overview.active_nodes == state.overview.total_nodes {
          "ok"
        } else {
          "warning"
        },
      ),
      stat(
        localized(state.locale, "Approved models", "已批准模型"),
        state.overview.active_models.to_string(),
        localized(
          state.locale,
          "Registry approval · not running instances",
          "注册表批准数 · 并非运行实例数",
        ),
        "neutral",
      ),
      stat(
        localized(state.locale, "Queued requests", "排队请求"),
        state.overview.queue_depth.to_string(),
        localized(state.locale, "Awaiting admission", "等待准入"),
        if state.overview.queue_depth == 0 {
          "ok"
        } else {
          "neutral"
        },
      ),
      stat(
        localized(state.locale, "Open alerts", "未解决告警"),
        state.overview.alerts.to_string(),
        if state.overview.total_nodes == 0 {
          localized(state.locale, "Telemetry unavailable", "遥测不可用")
        } else if state.overview.alerts == 0 {
          localized(state.locale, "No active incidents", "无未解决事件")
        } else {
          localized(state.locale, "Review required", "需要检查")
        },
        if state.overview.total_nodes == 0 {
          "neutral"
        } else if state.overview.alerts == 0 {
          "ok"
        } else {
          "danger"
        },
      ),
    ]),
    @html.section(
      class="readiness-panel",
      attrs=@html.Attrs::build().aria_labelledby("deployment-readiness-title"),
      [
        @html.div(class="readiness-copy", [
          @html.p(
            class="eyebrow",
            localized(state.locale, "Deployment launchpad", "部署启动台"),
          ),
          @html.h2(
            id="deployment-readiness-title",
            localized(
              state.locale,
              "Choose a service template",
              "选择服务模板",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Browse the catalog and review a deployment plan. Opening the catalog does not start a service; the controller checks authorization and model/resource readiness before deployment.",
              "先浏览目录并查看部署计划。打开目录不会启动服务；实际部署前，控制器仍会检查授权、模型和资源条件。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button readiness-action",
            on_click=command(emit, Navigate(Catalog)),
            localized(
              state.locale,
              "Open service catalog",
              "打开服务目录",
            ),
          ),
        ]),
        @html.ul(class="readiness-list", [
          readiness_item(
            state.locale,
            state.production_readiness.ready &&
            state.production_readiness.blocker_codes.length() == 0 &&
            state.production_readiness.error is None &&
            !state.production_readiness.loading,
            localized(
              state.locale,
              "Platform-wide production acceptance (separate from catalog access)",
              "平台整体生产验收（不限制浏览目录）",
            ),
            if state.production_readiness.loading {
              localized(
                state.locale,
                "Loading controller readiness…",
                "正在加载控制器就绪状态…",
              )
            } else {
              match state.production_readiness.error {
                Some(_) =>
                  localized(
                    state.locale,
                    "Readiness check unavailable",
                    "就绪检查不可用",
                  )
                None if state.production_readiness.blocker_codes.length() > 0 =>
                  state.production_readiness.blocker_codes
                  .map(code => readiness_blocker_label(state.locale, code))
                  .join(" · ")
                None if state.production_readiness.ready =>
                  localized(
                    state.locale,
                    "All central blockers cleared",
                    "所有中央阻塞项均已清除",
                  )
                None =>
                  localized(
                    state.locale,
                    "Production acceptance not yet confirmed",
                    "尚未确认生产验收通过",
                  )
              }
            },
          ),
          readiness_item(
            state.locale,
            state.overview.total_nodes == 4,
            localized(
              state.locale,
              "Four DGX nodes enrolled",
              "已注册四台 DGX 节点",
            ),
            localized(
              state.locale,
              "\{state.overview.total_nodes} of 4 reporting telemetry",
              "4 台中有 \{state.overview.total_nodes} 台上报遥测",
            ),
          ),
          readiness_item(
            state.locale,
            state.overview.active_nodes == 4 && state.overview.alerts == 0,
            localized(state.locale, "Fleet healthy", "机群健康"),
            localized(
              state.locale,
              "\{state.overview.active_nodes} active · \{state.overview.alerts} alerts",
              "\{state.overview.active_nodes} 台活跃 · \{state.overview.alerts} 个告警",
            ),
          ),
          readiness_item(
            state.locale,
            state.overview.active_models > 0,
            localized(
              state.locale,
              "Approved model available",
              "已有批准模型",
            ),
            localized(
              state.locale,
              "\{state.overview.active_models} approved models",
              "\{state.overview.active_models} 个已批准模型",
            ),
          ),
          readiness_item(
            state.locale,
            state.catalog_templates.length() > 0,
            localized(
              state.locale,
              "Service template approved",
              "服务模板已批准",
            ),
            localized(
              state.locale,
              "\{state.catalog_templates.length()} immutable templates",
              "\{state.catalog_templates.length()} 个不可变模板",
            ),
          ),
        ]),
      ],
    ),
  ])
}

///|
fn status_badge(label : String, tone : String) -> @rabbita.Html {
  @html.span(class="status status-\{tone}", label)
}

///|
fn user_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceUserState,
) -> @rabbita.Html {
  match state {
    UserActive => status_badge(localized(locale, "Active", "已激活"), "ok")
    UserInvited =>
      status_badge(localized(locale, "Invited", "已邀请"), "pending")
    UserSuspended =>
      status_badge(localized(locale, "Suspended", "已暂停"), "muted")
    UserRevoked =>
      status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn grant_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceAccessGrantState,
) -> @rabbita.Html {
  match state {
    GrantActive => status_badge(localized(locale, "Active", "有效"), "ok")
    GrantExpired =>
      status_badge(localized(locale, "Expired", "已过期"), "warning")
    GrantRevoked =>
      status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn access_label(
  locale : @i18n.Locale,
  access : @workspace.WorkspaceAccess,
) -> String {
  match access {
    Administrator => localized(locale, "Administrator", "管理员")
    Developer => localized(locale, "Developer", "开发者")
    Observer => localized(locale, "Observer", "观察者")
  }
}

///|
fn lease_state_badge(
  locale : @i18n.Locale,
  state : @workspace.WorkspaceLeaseState,
) -> @rabbita.Html {
  match state {
    Requested =>
      status_badge(localized(locale, "Requested", "待审批"), "pending")
    Active => status_badge(localized(locale, "Active", "有效"), "ok")
    Suspended =>
      status_badge(localized(locale, "Suspended", "已暂停"), "warning")
    Expired => status_badge(localized(locale, "Expired", "已过期"), "muted")
    Revoked => status_badge(localized(locale, "Revoked", "已撤销"), "muted")
  }
}

///|
fn exclusive_lease_state_badge(
  locale : @i18n.Locale,
  state : String,
) -> @rabbita.Html {
  let (label, tone) = match state {
    "Active" => (localized(locale, "Active", "有效"), "ok")
    "Completed" => (localized(locale, "Sanitized", "已清理"), "ok")
    "Cancelled" => (localized(locale, "Cancelled", "已取消"), "neutral")
    "Quarantined" => (localized(locale, "Quarantined", "已隔离"), "danger")
    "Expiring" => (localized(locale, "Expiring", "正在到期"), "warning")
    "Draining" => (localized(locale, "Draining", "正在排空"), "warning")
    "RevokingAccess" =>
      (localized(locale, "Revoking access", "正在撤销访问"), "warning")
    "Sanitizing" => (localized(locale, "Sanitizing", "正在清理"), "warning")
    "Provisioning" =>
      (localized(locale, "Provisioning", "正在开通"), "pending")
    "Reserved" => (localized(locale, "Reserved", "已预留"), "pending")
    _ => (state, "neutral")
  }
  status_badge(label, tone)
}

///|
fn node_state_badge(
  locale : @i18n.Locale,
  state : @contracts.NodeState,
) -> @rabbita.Html {
  match state {
    Active => status_badge(localized(locale, "Active", "正常"), "ok")
    Enrolling =>
      status_badge(localized(locale, "Enrolling", "注册中"), "pending")
    Cordoned =>
      status_badge(localized(locale, "Cordoned", "已封锁调度"), "warning")
    Draining =>
      status_badge(localized(locale, "Draining", "正在排空"), "warning")
    Unreachable =>
      status_badge(localized(locale, "Unreachable", "无法访问"), "danger")
    Retired => status_badge(localized(locale, "Retired", "已退役"), "muted")
  }
}

///|
fn model_state_badge(
  locale : @i18n.Locale,
  state : @contracts.ModelState,
) -> @rabbita.Html {
  match state {
    Approved => status_badge(localized(locale, "Approved", "已批准"), "ok")
    Candidate =>
      status_badge(localized(locale, "Candidate", "候选"), "pending")
    Verified =>
      status_badge(localized(locale, "Verified", "已验证"), "pending")
    Evaluated =>
      status_badge(localized(locale, "Evaluated", "已评测"), "pending")
    Deprecated =>
      status_badge(localized(locale, "Deprecated", "已弃用"), "warning")
    Revoked => status_badge(localized(locale, "Revoked", "已撤销"), "danger")
  }
}

///|
fn deployment_state_badge(
  locale : @i18n.Locale,
  state : @contracts.DeploymentState,
) -> @rabbita.Html {
  match state {
    Ready => status_badge(localized(locale, "Ready", "就绪"), "ok")
    Pending =>
      status_badge(localized(locale, "Pending", "待处理"), "pending")
    Preparing =>
      status_badge(localized(locale, "Preparing", "准备中"), "pending")
    Starting =>
      status_badge(localized(locale, "Starting", "启动中"), "pending")
    Draining =>
      status_badge(localized(locale, "Draining", "正在排空"), "warning")
    Degraded =>
      status_badge(localized(locale, "Degraded", "已降级"), "warning")
    Failed => status_badge(localized(locale, "Failed", "失败"), "danger")
    Stopped => status_badge(localized(locale, "Stopped", "已停止"), "muted")
  }
}

///|
fn service_operation_state_badge(
  locale : @i18n.Locale,
  state : @deployment.DeploymentOperationState,
) -> @rabbita.Html {
  match state {
    Submitted =>
      status_badge(localized(locale, "Submitted", "已提交"), "pending")
    Blocked => status_badge(localized(locale, "Blocked", "已阻止"), "danger")
    Planned =>
      status_badge(localized(locale, "Planned", "已规划"), "pending")
    Reconciling =>
      status_badge(localized(locale, "Reconciling", "协调中"), "pending")
    Ready => status_badge(localized(locale, "Ready", "就绪"), "ok")
    Degraded =>
      status_badge(localized(locale, "Degraded", "已降级"), "warning")
    RollingBack =>
      status_badge(localized(locale, "Rolling back", "正在回滚"), "warning")
    RolledBack =>
      status_badge(localized(locale, "Rolled back", "已回滚"), "muted")
    Failed => status_badge(localized(locale, "Failed", "失败"), "danger")
    Deleted => status_badge(localized(locale, "Deleted", "已删除"), "muted")
  }
}

///|
fn account_state_badge(
  locale : @i18n.Locale,
  state : UiAccountState,
) -> @rabbita.Html {
  match state {
    Invited =>
      status_badge(localized(locale, "Invited", "已邀请"), "pending")
    Active => status_badge(localized(locale, "Active", "有效"), "ok")
    Suspended =>
      status_badge(localized(locale, "Suspended", "已暂停"), "warning")
    Revoked => status_badge(localized(locale, "Revoked", "已撤销"), "danger")
  }
}

///|
fn account_role_label(locale : @i18n.Locale, role : UiAccountRole) -> String {
  match role {
    PlatformOperator => localized(locale, "Platform operator", "平台运维")
    AuditReader => localized(locale, "Audit reader", "审计读取者")
    EnterpriseUser => localized(locale, "Enterprise user", "企业用户")
  }
}

///|
pub fn account_roles_after_toggle(
  roles : Array[UiAccountRole],
  role : UiAccountRole,
) -> Array[UiAccountRole] {
  if roles.contains(role) {
    if roles.length() == 1 {
      roles
    } else {
      roles.filter(value => value != role)
    }
  } else {
    roles + [role]
  }
}

///|
fn account_invite_ready(draft : AccountInviteDraft) -> Bool {
  draft.account_id.trim() != "" &&
  draft.subject_ref.trim() != "" &&
  draft.identity_issuer.trim() != "" &&
  draft.identity_subject.trim() != "" &&
  draft.display_name.trim() != "" &&
  draft.email.trim() != "" &&
  draft.identity_receipt.trim() != "" &&
  draft.roles.length() > 0
}

///|
fn account_role_controls(
  locale : @i18n.Locale,
  account_id : String,
  roles : Array[UiAccountRole],
  loading : Bool,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.div(
    class="account-role-controls",
    attrs=@html.Attrs::build().aria_label(
      localized(
        locale,
        "Roles for account \{account_id}",
        "账户 \{account_id} 的角色",
      ),
    ),
    [
      for role in [PlatformOperator, AuditReader, EnterpriseUser] => {
        let selected = roles.contains(role)
        @html.button(
          type_="button",
          class=if selected { "role-toggle selected" } else { "role-toggle" },
          disabled=loading || (selected && roles.length() == 1),
          attrs=@html.Attrs::build().aria_pressed(
            if selected {
              "true"
            } else {
              "false"
            },
          ),
          title=if selected && roles.length() == 1 {
            localized(
              locale, "Every account must retain at least one role", "每个账户必须至少保留一个角色",
            )
          } else {
            localized(
              locale,
              "Change \{account_role_label(locale, role)} role",
              "更改\{account_role_label(locale, role)}角色",
            )
          },
          on_click=command(
            emit,
            BeginSetAccountRoles(
              account_id,
              account_roles_after_toggle(roles, role),
            ),
          ),
          account_role_label(locale, role),
        )
      }
    ],
  )
}

///|
fn account_invite_role_controls(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.fieldset(class="account-role-fieldset", [
    @html.legend(localized(state.locale, "Initial roles", "初始角色")),
    @html.p(
      class="field-help",
      localized(
        state.locale,
        "Roles are assigned from LunaNexa's durable account record, never from identity headers.",
        "角色来自 LunaNexa 的持久账户记录，绝不来自身份标头。",
      ),
    ),
    @html.div(
      class="account-role-controls",
      [
        for role in [PlatformOperator, AuditReader, EnterpriseUser] => {
          let selected = state.account_invite.roles.contains(role)
          @html.button(
            type_="button",
            class=if selected { "role-toggle selected" } else { "role-toggle" },
            disabled=state.loading ||
              (selected && state.account_invite.roles.length() == 1),
            attrs=@html.Attrs::build().aria_pressed(
              if selected {
                "true"
              } else {
                "false"
              },
            ),
            on_click=command(emit, AccountInviteRoleToggled(role)),
            account_role_label(state.locale, role),
          )
        }
      ],
    ),
  ])
}

///|
fn access_package_draft_ready(draft : AccessPackageDraft) -> Bool {
  draft.identity_issuer.trim() != "" &&
  draft.identity_subject.trim() != "" &&
  draft.display_name.trim() != "" &&
  draft.email.trim() != "" &&
  draft.organization_id.trim() != "" &&
  draft.tenant_ref.trim() != "" &&
  draft.identity_verified
}

///|
fn access_package_milestone(
  locale : @i18n.Locale,
  label : String,
  ready : Bool,
  current : Bool,
) -> @rabbita.Html {
  @html.li(
    class=if ready {
      "complete"
    } else if current {
      "current"
    } else {
      "pending"
    },
    [
      @html.span(
        class="access-milestone-mark",
        if ready {
          "✓"
        } else {
          "·"
        },
      ),
      @html.span(label),
      @html.span(
        class="sr-only",
        if ready {
          localized(locale, "complete", "已完成")
        } else if current {
          localized(locale, "next", "下一步")
        } else {
          localized(locale, "pending", "待完成")
        },
      ),
    ],
  )
}

///|
fn access_package_card(
  state : ConsoleState,
  item : AccessPackageView,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let workspace_and_models_ready = item.workspace_ready && item.models_ready
  let user_id = item.user_id.unwrap_or("pending")
  let grant_id = item.grant_id.unwrap_or("pending")
  let lease_id = item.lease_id.unwrap_or("pending")
  @html.article(class="access-package-card", [
    @html.div(class="access-package-card-heading", [
      @html.div([
        @html.strong(item.display_name),
        @html.span(class="secondary", item.email),
        @html.span(
          class="secondary",
          "\{item.organization_id} · \{item.tenant_ref}",
        ),
      ]),
      status_badge(
        item.state,
        if item.ready {
          "ok"
        } else if item.can_enable {
          "pending"
        } else {
          "warning"
        },
      ),
    ]),
    @html.ol(class="access-package-milestones", [
      access_package_milestone(
        state.locale,
        localized(state.locale, "Identity", "身份"),
        item.account_ready,
        !item.account_ready,
      ),
      access_package_milestone(
        state.locale,
        localized(state.locale, "Organization", "组织"),
        item.membership_ready,
        item.account_ready && !item.membership_ready,
      ),
      access_package_milestone(
        state.locale,
        localized(state.locale, "MasterLease", "主租约"),
        item.contract_ready,
        item.membership_ready && !item.contract_ready,
      ),
      access_package_milestone(
        state.locale,
        localized(state.locale, "Workspace & models", "工作区与模型"),
        workspace_and_models_ready,
        item.contract_ready && !workspace_and_models_ready,
      ),
      access_package_milestone(
        state.locale,
        localized(state.locale, "WebIDE", "WebIDE"),
        item.ready,
        item.can_enable,
      ),
    ]),
    @html.div(class="access-package-next", [
      if item.can_enable {
        @html.button(
          type_="button",
          class="primary-button",
          disabled=state.loading,
          on_click=command(emit, EnableAccessPackage(item.account_id)),
          localized(state.locale, "Enable WebIDE", "启用 WebIDE"),
        )
      } else if !item.contract_ready {
        @html.button(
          type_="button",
          disabled=state.loading,
          on_click=command(emit, Navigate(ContractDocuments)),
          localized(state.locale, "Complete MasterLease", "完成主租约"),
        )
      } else if !item.models_ready {
        @html.button(
          type_="button",
          disabled=state.loading,
          on_click=command(emit, Navigate(Catalog)),
          localized(
            state.locale,
            "Deploy a serving model",
            "部署可调用模型",
          ),
        )
      } else if item.ready {
        @html.span(
          class="access-package-ready",
          localized(state.locale, "Ready for WebIDE", "WebIDE 已就绪"),
        )
      } else {
        @html.span(
          class="secondary",
          localized(
            state.locale,
            "Review the incomplete milestone above.",
            "请检查上方未完成的里程碑。",
          ),
        )
      },
      @html.details(class="access-package-evidence", [
        @html.summary(
          localized(state.locale, "Technical evidence", "技术证据"),
        ),
        @html.dl([
          @html.dt("Package"),
          @html.dd(class="mono", item.package_id),
          @html.dt("Account / subject"),
          @html.dd(class="mono", "\{item.account_id} / \{item.subject_ref}"),
          @html.dt("Membership"),
          @html.dd(class="mono", item.membership_id),
          @html.dt("Workspace user / grant / lease"),
          @html.dd(class="mono", "\{user_id} / \{grant_id} / \{lease_id}"),
          @html.dt(
            localized(
              state.locale,
              "Serving model aliases",
              "可用模型别名",
            ),
          ),
          @html.dd(
            class="mono",
            if item.approved_model_aliases.length() == 0 {
              localized(state.locale, "none", "无")
            } else {
              item.approved_model_aliases.join(", ")
            },
          ),
        ]),
        @html.button(
          type_="button",
          on_click=command(emit, Navigate(Audit)),
          localized(state.locale, "Open audit log", "打开审计日志"),
        ),
      ]),
    ]),
  ])
}

///|
/// The account reference an operator should see before pasting a raw provider
/// subject. LunaNexa never shows the raw subject anywhere -- every surface
/// (account rows, membership rows, the users table) shows only the derived
/// `subject-…` reference -- so without this preview the field is a blind paste
/// and the operator cannot tell whether the UUID they copied belongs to the
/// person whose row they were reading.
///
/// The hash is taken over the field exactly as it will be submitted, spaces
/// included, so a stray paste shows up as a reference that does not match the
/// account row instead of being silently normalised away here.
fn access_identity_reference(
  state : ConsoleState,
  issuer : String,
  subject : String,
  help_id : String,
) -> @rabbita.Html {
  if issuer.trim() == "" || subject.trim() == "" {
    return @html.p(
      id=help_id,
      class="field-help",
      localized(
        state.locale,
        "Paste the provider's own subject (the id the provider issued), not the derived reference. LunaNexa derives the account reference below; nothing leaves the browser until you submit.",
        "请粘贴提供商自己签发的原始主体，而不是派生引用。LunaNexa 会在下方派生账户引用；提交前不会发送任何内容。",
      ),
    )
  }
  let reference = @identity.subject_reference(issuer, subject)
  let account_id = @identity.account_identifier(issuer, subject)
  @html.p(
    id=help_id,
    class="field-help",
    localized(
      state.locale,
      "Derives \{reference} · \{account_id} — check it against the Subject column below before you submit.",
      "将派生为 \{reference} · \{account_id} —— 提交前请与下方「主体」列核对。",
    ),
  )
}

///|
/// What the platform already knows about the person whose subject was just
/// pasted, shown next to the organization and tenant the operator is about to
/// type.
///
/// Both of those fields are free text, and the customer's own session resolves
/// its tenant from the membership the self-registration path created
/// (`trial-tenant-…`), not from whatever is typed here. A package opened on a
/// different tenant still returns 200, still shows every milestone complete,
/// and is then invisible to the customer -- `api/client_handoff_http.mbt` checks
/// `portal_view.membership.tenant_ref`. Listing the tenants the subject already
/// holds is what makes that mismatch visible before submitting.
fn access_existing_authority(
  state : ConsoleState,
  issuer : String,
  subject : String,
  help_id : String,
) -> @rabbita.Html {
  if issuer.trim() == "" || subject.trim() == "" {
    return @html.p(
      id=help_id,
      class="field-help",
      localized(
        state.locale,
        "Fill in Identity provider details first; LunaNexa then lists the tenants this subject already holds, so you can reuse the customer's own tenant instead of inventing one.",
        "请先填写上方「身份提供商详情」；LunaNexa 随后会列出这个主体已有的租户，便于你沿用客户自己的租户，而不是另起一个。",
      ),
    )
  }
  let subject_ref = @identity.subject_reference(issuer, subject)
  let account_id = @identity.account_identifier(issuer, subject)
  let tenants : Array[String] = []
  for lease in state.compute_leases {
    if lease.subject_ref == subject_ref && !tenants.contains(lease.workspace) {
      tenants.push(lease.workspace)
    }
  }
  let account = state.accounts
    .iter()
    .find_first(value => value.account_id == account_id)
  let known = match (account, tenants.length()) {
    (None, 0) =>
      localized(
        state.locale,
        "LunaNexa holds no account or workspace lease for this subject yet. The organization and tenant below are the ones the package will create.",
        "LunaNexa 目前没有这个主体的账户或工作区租约。下面的组织与租户将由这个开通包创建。",
      )
    _ => {
      let existing = match account {
        Some(value) =>
          "\{value.display_name} · \{value.email} · \{value.subject_ref}"
        None => subject_ref
      }
      let held = if tenants.length() == 0 {
        localized(state.locale, "no workspace lease", "没有工作区租约")
      } else {
        tenants.join(", ")
      }
      localized(
        state.locale,
        "This subject already exists: \{existing}. Tenants it already holds: \{held}. The customer's own sign-in resolves its tenant from its existing membership, so a package opened on a different tenant will not be visible to them.",
        "这个主体已经存在：\{existing}。它已有的租户：\{held}。客户自己登录时会按既有会员解析租户，因此在别的租户上开通的包对他不可见。",
      )
    }
  }
  @html.p(id=help_id, class="field-help", known)
}

///|
fn users_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("users-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="users-title",
          localized(state.locale, "Users & access", "用户与访问权限"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Manage control-plane identities and time-bounded access grants. This view does not expose node credentials.",
            "管理控制平面身份和有时限的访问授权。此视图不会公开节点凭据。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.users.length()} users · \{state.access_grants.length()} grants",
          "\{state.users.length()} 位用户 · \{state.access_grants.length()} 项授权",
        ),
      ),
    ]),
    trial_summary_view(state),
    match state.authenticated_account {
      Some(account) =>
        @html.section(
          class="account-self",
          attrs=@html.Attrs::build().aria_labelledby("signed-in-account-title"),
          [
            @html.div([
              @html.p(
                class="eyebrow",
                localized(state.locale, "Current authority", "当前权限"),
              ),
              @html.h3(
                id="signed-in-account-title",
                localized(
                  state.locale,
                  "Signed-in account",
                  "当前登录账户",
                ),
              ),
              @html.p(class="section-copy", [
                @html.strong(account.display_name),
                @html.span(" · \{account.email}"),
                @html.span(class="mono secondary", " · \{account.account_id}"),
              ]),
            ]),
            @html.div(class="account-self-evidence", [
              account_state_badge(state.locale, account.state),
              @html.span(
                class="secondary",
                localized(
                  state.locale,
                  "\{account.roles.length()} roles · \{state.account_sessions.count_if(session => session.revoked_unix_ms is None)} active sessions",
                  "\{account.roles.length()} 个角色 · \{state.account_sessions.count_if(session => session.revoked_unix_ms is None)} 个有效会话",
                ),
              ),
            ]),
            @html.details(class="account-session-evidence", [
              @html.summary(
                localized(
                  state.locale,
                  "Session evidence (\{state.account_sessions.length()})",
                  "会话证据（\{state.account_sessions.length()}）",
                ),
              ),
              if state.account_sessions.length() == 0 {
                @html.p(
                  class="empty-state compact",
                  localized(
                    state.locale,
                    "No browser sessions are recorded.",
                    "没有已记录的浏览器会话。",
                  ),
                )
              } else {
                @html.div(class="table-scroll", [
                  @html.table(class="resource-table", [
                    @html.caption(
                      class="sr-only",
                      localized(
                        state.locale,
                        "Browser sessions",
                        "浏览器会话",
                      ),
                    ),
                    @html.thead(
                      @html.tr([
                        @html.th(
                          scope=Col,
                          localized(state.locale, "Session", "会话"),
                        ),
                        @html.th(
                          scope=Col,
                          localized(state.locale, "Last used", "最近使用"),
                        ),
                        @html.th(
                          scope=Col,
                          localized(state.locale, "Expires", "到期"),
                        ),
                        @html.th(
                          scope=Col,
                          localized(state.locale, "State", "状态"),
                        ),
                      ]),
                    ),
                    @html.tbody(
                      [
                        for session in state.account_sessions => {
                          @html.tr([
                            @html.td(class="mono", session.session_id),
                            @html.td(
                              @contractdoc.format_unix_ms_beijing(
                                session.last_used_unix_ms,
                              ),
                            ),
                            @html.td(
                              @contractdoc.format_unix_ms_beijing(
                                session.expires_unix_ms,
                              ),
                            ),
                            @html.td(
                              if session.revoked_unix_ms is Some(_) {
                                status_badge(
                                  localized(
                                    state.locale,
                                    "Revoked",
                                    "已撤销",
                                  ),
                                  "muted",
                                )
                              } else {
                                status_badge(
                                  localized(state.locale, "Active", "有效"),
                                  "ok",
                                )
                              },
                            ),
                          ])
                        }
                      ],
                    ),
                  ]),
                ])
              },
            ]),
          ],
        )
      None =>
        @html.p(
          class="account-self account-self-static",
          localized(
            state.locale,
            "This console is using the localhost development-token fallback. Sign in with an lnxs_ account session to inspect personal session evidence.",
            "此控制台正在使用本机开发令牌回退。请使用 lnxs_ 账户会话登录以查看个人会话证据。",
          ),
        )
    },
    @html.section(
      class="access-package-panel",
      attrs=@html.Attrs::build().aria_labelledby("access-package-title"),
      [
        @html.div(class="access-package-intro", [
          @html.p(
            class="eyebrow",
            localized(state.locale, "Guided setup", "引导式设置"),
          ),
          @html.h3(
            id="access-package-title",
            localized(
              state.locale,
              "Create WebIDE access",
              "创建 WebIDE 访问",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Enter the person and organization once. LunaNexa prepares the account, membership, workspace profile, Developer grant, and requested compute lease as one resumable package.",
              "只需输入一次人员与组织信息。LunaNexa 会将账户、成员关系、工作区档案、开发者授权和计算租约请求准备为一个可恢复的软件包。",
            ),
          ),
        ]),
        @html.ol(class="access-package-steps", [
          @html.li([
            @html.strong("1"),
            @html.span(
              localized(
                state.locale,
                "Person & organization",
                "人员与组织",
              ),
            ),
          ]),
          @html.li([
            @html.strong("2"),
            @html.span(localized(state.locale, "Review access", "检查权限")),
          ]),
          @html.li([
            @html.strong("3"),
            @html.span(localized(state.locale, "MasterLease", "主租约")),
          ]),
          @html.li([
            @html.strong("4"),
            @html.span(
              localized(state.locale, "Enable WebIDE", "启用 WebIDE"),
            ),
          ]),
        ]),
        @html.div(class="access-package-form-grid", [
          @html.div(class="field-group", [
            @html.label(
              for_="access-display-name",
              localized(state.locale, "Display name", "显示名称"),
            ),
            @html.input(
              id="access-display-name",
              value=state.access_package_draft.display_name,
              maxlength=128,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccessPackageDisplayNameChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="access-email",
              localized(state.locale, "Work email", "工作邮箱"),
            ),
            @html.input(
              id="access-email",
              input_type=Email,
              value=state.access_package_draft.email,
              maxlength=320,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccessPackageEmailChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="access-organization",
              localized(state.locale, "Organization", "组织"),
            ),
            @html.input(
              id="access-organization",
              value=state.access_package_draft.organization_id,
              maxlength=128,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccessPackageOrganizationChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="access-tenant",
              localized(state.locale, "Tenant", "租户"),
            ),
            @html.input(
              id="access-tenant",
              value=state.access_package_draft.tenant_ref,
              maxlength=128,
              auto_complete=Off,
              attrs=@html.Attrs::build().aria_describedby(
                "access-existing-authority",
              ),
              on_input=text_command(emit, value => {
                AccessPackageTenantChanged(value)
              }),
            ),
          ]),
        ]),
        access_existing_authority(
          state,
          state.access_package_draft.identity_issuer,
          state.access_package_draft.identity_subject,
          "access-existing-authority",
        ),
        @html.details(class="access-provider-details", [
          @html.summary(
            localized(
              state.locale,
              "Identity provider details",
              "身份提供商详情",
            ),
          ),
          @html.div(class="access-package-form-grid", [
            @html.div(class="field-group", [
              @html.label(
                for_="access-issuer",
                localized(state.locale, "Identity issuer", "身份签发方"),
              ),
              @html.input(
                id="access-issuer",
                value=state.access_package_draft.identity_issuer,
                maxlength=512,
                auto_complete=Off,
                placeholder="https://id.example.com",
                on_input=text_command(emit, value => {
                  AccessPackageIssuerChanged(value)
                }),
              ),
            ]),
            @html.div(class="field-group", [
              @html.label(
                for_="access-provider-subject",
                localized(state.locale, "Provider subject", "提供商主体"),
              ),
              @html.input(
                id="access-provider-subject",
                input_type=Password,
                value=state.access_package_draft.identity_subject,
                maxlength=1024,
                auto_complete=Off,
                attrs=@html.Attrs::build().aria_describedby(
                  "access-provider-subject-help",
                ),
                on_input=text_command(emit, value => {
                  AccessPackageSubjectChanged(value)
                }),
              ),
              access_identity_reference(
                state,
                state.access_package_draft.identity_issuer,
                state.access_package_draft.identity_subject,
                "access-provider-subject-help",
              ),
            ]),
          ]),
        ]),
        @html.div(class="access-package-review", [
          @html.div([
            @html.p(
              class="eyebrow",
              localized(state.locale, "Scope review", "范围检查"),
            ),
            @html.h4(
              localized(state.locale, "WebIDE developer", "WebIDE 开发者"),
            ),
            @html.p(
              class="section-copy",
              localized(
                state.locale,
                "Enterprise user + Developer · Text generation · 2 concurrent requests · 100 requests/hour",
                "企业用户 + 开发者 · 文本生成 · 2 个并发请求 · 每小时 100 个请求",
              ),
            ),
          ]),
          @html.div(class="access-lifetime", [
            @html.span(
              localized(state.locale, "Access duration", "访问期限"),
            ),
            @html.button(
              type_="button",
              class=if state.access_package_draft.lifetime_days == 0 {
                "role-toggle selected"
              } else {
                "role-toggle"
              },
              disabled=state.loading,
              attrs=@html.Attrs::build().aria_pressed(
                if state.access_package_draft.lifetime_days == 0 {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, AccessPackageLifetimeChanged(0)),
              localized(state.locale, "1h test", "1 小时测试"),
            ),
            @html.button(
              type_="button",
              class=if state.access_package_draft.lifetime_days == 7 {
                "role-toggle selected"
              } else {
                "role-toggle"
              },
              disabled=state.loading,
              attrs=@html.Attrs::build().aria_pressed(
                if state.access_package_draft.lifetime_days == 7 {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, AccessPackageLifetimeChanged(7)),
              "7d",
            ),
            @html.button(
              type_="button",
              class=if state.access_package_draft.lifetime_days == 30 {
                "role-toggle selected"
              } else {
                "role-toggle"
              },
              disabled=state.loading,
              attrs=@html.Attrs::build().aria_pressed(
                if state.access_package_draft.lifetime_days == 30 {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, AccessPackageLifetimeChanged(30)),
              "30d",
            ),
            @html.button(
              type_="button",
              class=if state.access_package_draft.lifetime_days == 90 {
                "role-toggle selected"
              } else {
                "role-toggle"
              },
              disabled=state.loading,
              attrs=@html.Attrs::build().aria_pressed(
                if state.access_package_draft.lifetime_days == 90 {
                  "true"
                } else {
                  "false"
                },
              ),
              on_click=command(emit, AccessPackageLifetimeChanged(90)),
              "90d",
            ),
          ]),
        ]),
        @html.div(class="access-package-submit", [
          @html.button(
            type_="button",
            class=if state.access_package_draft.identity_verified {
              "verification-toggle selected"
            } else {
              "verification-toggle"
            },
            disabled=state.loading,
            attrs=@html.Attrs::build().aria_pressed(
              if state.access_package_draft.identity_verified {
                "true"
              } else {
                "false"
              },
            ),
            on_click=command(emit, ToggleAccessPackageIdentityVerified),
            localized(state.locale, "Identity verified", "身份已验证"),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=state.loading ||
              !access_package_draft_ready(state.access_package_draft),
            on_click=command(emit, SubmitAccessPackage),
            localized(state.locale, "Prepare access", "准备访问"),
          ),
        ]),
        @html.div(class="access-package-list", [
          if state.access_packages.length() == 0 {
            @html.p(
              class="empty-state compact",
              localized(
                state.locale,
                "No WebIDE access packages yet.",
                "尚无 WebIDE 访问软件包。",
              ),
            )
          } else {
            @html.fragment(
              [
                for item in state.access_packages => {
                  access_package_card(state, item, emit)
                }
              ],
            )
          },
        ]),
      ],
    ),
    @html.details(class="account-invite-panel", [
      @html.summary(
        localized(
          state.locale,
          "Advanced: create account only",
          "高级：仅创建账户",
        ),
      ),
      @html.div(class="account-invite-content", [
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Map a verified identity-provider subject to a LunaNexa account. Passwords, MFA factors, and provider tokens remain with the external provider.",
            "将已验证的身份提供商主体映射到 LunaNexa 账户。密码、多因素认证和提供商令牌仍由外部提供商保管。",
          ),
        ),
        @html.div(class="account-invite-grid", [
          @html.div(class="field-group", [
            @html.label(
              for_="account-id",
              localized(state.locale, "Account ID", "账户 ID"),
            ),
            @html.input(
              id="account-id",
              value=state.account_invite.account_id,
              maxlength=128,
              auto_complete=Off,
              on_input=text_command(emit, value => AccountInviteIdChanged(value)),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-subject-ref",
              localized(
                state.locale,
                "Opaque subject reference",
                "不透明主体引用",
              ),
            ),
            @html.input(
              id="account-subject-ref",
              value=state.account_invite.subject_ref,
              maxlength=128,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccountInviteSubjectRefChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-issuer",
              localized(state.locale, "Identity issuer", "身份签发方"),
            ),
            @html.input(
              id="account-issuer",
              value=state.account_invite.identity_issuer,
              maxlength=512,
              auto_complete=Off,
              placeholder="https://id.example.com",
              on_input=text_command(emit, value => {
                AccountInviteIssuerChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-provider-subject",
              localized(state.locale, "Provider subject", "提供商主体"),
            ),
            @html.input(
              id="account-provider-subject",
              input_type=Password,
              value=state.account_invite.identity_subject,
              maxlength=1024,
              auto_complete=Off,
              attrs=@html.Attrs::build().aria_describedby(
                "account-provider-subject-help",
              ),
              on_input=text_command(emit, value => {
                AccountInviteProviderSubjectChanged(value)
              }),
            ),
            access_identity_reference(
              state,
              state.account_invite.identity_issuer,
              state.account_invite.identity_subject,
              "account-provider-subject-help",
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-display-name",
              localized(state.locale, "Display name", "显示名称"),
            ),
            @html.input(
              id="account-display-name",
              value=state.account_invite.display_name,
              maxlength=128,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccountInviteDisplayNameChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-email",
              localized(state.locale, "Email", "电子邮箱"),
            ),
            @html.input(
              id="account-email",
              input_type=Email,
              value=state.account_invite.email,
              maxlength=320,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccountInviteEmailChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="account-identity-receipt",
              localized(
                state.locale,
                "Identity evidence receipt",
                "身份凭证回执",
              ),
            ),
            @html.input(
              id="account-identity-receipt",
              value=state.account_invite.identity_receipt,
              maxlength=512,
              auto_complete=Off,
              on_input=text_command(emit, value => {
                AccountInviteReceiptChanged(value)
              }),
            ),
          ]),
        ]),
        account_invite_role_controls(state, emit),
        @html.div(class="account-invite-actions", [
          @html.span(
            class="secondary",
            localized(
              state.locale,
              "The new account starts Invited and cannot sign in until activated.",
              "新账户初始为“已邀请”，激活后才能登录。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            disabled=state.loading ||
              !account_invite_ready(state.account_invite),
            on_click=command(emit, SubmitAccountInvite),
            localized(state.locale, "Create invitation", "创建邀请"),
          ),
        ]),
      ]),
    ]),
    @html.div(class="subsection-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          localized(state.locale, "Application accounts", "应用账户"),
        ),
        @html.h3(
          localized(
            state.locale,
            "External identity mappings",
            "外部身份映射",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.accounts.length()} accounts",
          "\{state.accounts.length()} 个账户",
        ),
      ),
    ]),
    if state.accounts.length() == 0 {
      @html.p(
        class="empty-state compact",
        localized(
          state.locale,
          "No human accounts are registered. Create an invitation after the external identity provider is configured.",
          "尚未注册任何人员账户。请在配置外部身份提供商后创建邀请。",
        ),
      )
    } else {
      @html.div(class="table-scroll account-table", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(state.locale, "Human accounts", "人员账户"),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Account", "账户")),
              @html.th(
                scope=Col,
                localized(state.locale, "Identity mapping", "身份映射"),
              ),
              @html.th(scope=Col, localized(state.locale, "State", "状态")),
              @html.th(scope=Col, localized(state.locale, "Roles", "角色")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for account in state.accounts => {
                @html.tr([
                  @html.td([
                    @html.strong(account.display_name),
                    @html.span(class="secondary", account.email),
                    @html.span(class="mono secondary", account.account_id),
                  ]),
                  @html.td([
                    @html.strong(account.identity_issuer),
                    @html.span(class="mono secondary", account.subject_ref),
                    @html.span(class="mono secondary", account.identity_receipt),
                  ]),
                  @html.td(account_state_badge(state.locale, account.state)),
                  @html.td(
                    account_role_controls(
                      state.locale,
                      account.account_id,
                      account.roles,
                      state.loading || account.state == Revoked,
                      emit,
                    ),
                  ),
                  @html.td(class="row-actions", [
                    if account.state == Invited || account.state == Suspended {
                      @html.button(
                        type_="button",
                        disabled=state.loading,
                        on_click=command(
                          emit,
                          BeginActivateAccount(account.account_id),
                        ),
                        localized(state.locale, "Activate…", "激活…"),
                      )
                    } else {
                      @html.nothing
                    },
                    if account.state == Active {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        on_click=command(
                          emit,
                          BeginSuspendAccount(account.account_id),
                        ),
                        localized(state.locale, "Suspend…", "暂停…"),
                      )
                    } else {
                      @html.nothing
                    },
                    if account.state != Revoked {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        on_click=command(
                          emit,
                          BeginRevokeAccount(account.account_id),
                        ),
                        localized(state.locale, "Revoke…", "撤销…"),
                      )
                    } else {
                      @html.span(
                        class="secondary",
                        localized(state.locale, "Terminal", "已终止"),
                      )
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.h3(localized(state.locale, "Workspace profiles", "工作区档案")),
    if state.users.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No user identities are available. Use Policies → Invite user to create the first typed workspace record.",
          "暂无用户身份。请使用“策略 → 邀请用户”创建第一条类型化工作区记录。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(state.locale, "Cluster users", "集群用户"),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "User", "用户")),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Last active", "最近活动"),
              ),
              @html.th(scope=Col, localized(state.locale, "Grants", "授权")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for user in state.users => {
                @html.tr([
                  @html.td([
                    @html.strong(user.display_name),
                    @html.span(class="secondary", user.email),
                    @html.span(class="mono secondary", user.user_id),
                  ]),
                  @html.td(user_state_badge(state.locale, user.state)),
                  @html.td(generated_time_label(state.locale, user.last_active)),
                  @html.td(user.grant_count.to_string()),
                  @html.td(class="row-actions", [
                    if user.state == UserInvited || user.state == UserSuspended {
                      @html.button(
                        type_="button",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Activate user \{user.user_id}",
                          "激活用户 \{user.user_id}",
                        ),
                        on_click=command(emit, ActivateUser(user.user_id)),
                        localized(state.locale, "Activate", "激活"),
                      )
                    } else {
                      @html.nothing
                    },
                    if user.state == UserActive {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Suspend user \{user.user_id}",
                          "暂停用户 \{user.user_id}",
                        ),
                        on_click=command(emit, BeginSuspendUser(user.user_id)),
                        localized(state.locale, "Suspend…", "暂停…"),
                      )
                    } else {
                      @html.nothing
                    },
                    if user.state != UserRevoked {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Revoke user \{user.user_id}",
                          "撤销用户 \{user.user_id}",
                        ),
                        on_click=command(emit, BeginRevokeUser(user.user_id)),
                        localized(state.locale, "Revoke…", "撤销…"),
                      )
                    } else {
                      @html.span(
                        class="secondary",
                        localized(state.locale, "No actions", "无可用操作"),
                      )
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.h3(localized(state.locale, "Access grants", "访问授权")),
    if state.access_grants.length() == 0 {
      @html.p(
        class="empty-state compact",
        localized(
          state.locale,
          "No access grants are available.",
          "暂无访问授权。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Scoped access grants",
              "限定范围的访问授权",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Principal", "主体"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Role / scope", "角色 / 范围"),
              ),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Expires", "到期时间"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for grant in state.access_grants => {
                @html.tr([
                  @html.td([
                    @html.strong(grant.user_id),
                    @html.span(class="mono secondary", grant.grant_id),
                  ]),
                  @html.td([
                    @html.strong(access_label(state.locale, grant.role)),
                    @html.span(class="secondary", grant.scope),
                  ]),
                  @html.td(grant_state_badge(state.locale, grant.state)),
                  @html.td(generated_time_label(state.locale, grant.expires_at)),
                  @html.td(
                    @html.button(
                      type_="button",
                      class="danger-secondary",
                      disabled=grant.state != GrantActive,
                      title=localized(
                        state.locale,
                        "Revoke grant \{grant.grant_id}",
                        "撤销授权 \{grant.grant_id}",
                      ),
                      on_click=command(
                        emit,
                        BeginRevokeAccessGrant(grant.grant_id),
                      ),
                      localized(state.locale, "Revoke…", "撤销…"),
                    ),
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn leases_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("leases-title"), [
    resource_delivery_view(state, emit),
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="leases-title",
          localized(state.locale, "Lease operations", "租约运维"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Exclusive machine access and workspace capacity are separate authorities. Ending machine access always revokes credentials, stops tenant work, sanitizes the node, and verifies a clean baseline before placement resumes.",
            "独占机器访问与工作区容量属于不同权限。结束机器访问时，系统必须撤销凭据、停止租户工作、清理节点并验证干净基线，随后才能恢复调度。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.exclusive_node_leases.count_if(lease => lease.state == "Active")} machines leased · \{state.compute_leases.count_if(lease => lease.state == Active)} workspace leases",
          "\{state.exclusive_node_leases.count_if(lease => lease.state == "Active")} 台机器租用中 · \{state.compute_leases.count_if(lease => lease.state == Active)} 项工作区租约",
        ),
      ),
    ]),
    @html.div(class="lease-cleanup-policy", [
      @html.strong(
        localized(
          state.locale,
          "Fail-closed cleanup boundary",
          "故障关闭式清理边界",
        ),
      ),
      @html.p(
        localized(
          state.locale,
          "Natural expiry and early termination use the same generation-fenced path: revoke → sanitize → verify → release. Any failed or stale evidence quarantines the DGX.",
          "自然到期与提前终止使用同一条代际隔离路径：撤销 → 清理 → 验证 → 释放。任何失败或过期证据都会隔离该 DGX。",
        ),
      ),
    ]),
    if state.exclusive_node_leases.length() == 0 &&
      state.compute_leases.length() == 0 {
      @html.nothing
    } else {
      lease_lifecycle_graph(state)
    },
    @html.div(class="subsection-heading", [
      @html.div([
        @html.h3(
          localized(
            state.locale,
            "Exclusive machine leases",
            "独占机器租约",
          ),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "A node remains fenced until the cleanup helper returns generation-bound verification evidence.",
            "节点会保持隔离，直到清理助手返回绑定到对应代际的验证证据。",
          ),
        ),
      ]),
    ]),
    if state.exclusive_node_leases.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No exclusive machine leases are recorded.",
          "暂无独占机器租约。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Exclusive machine lease cleanup state",
              "独占机器租约清理状态",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                localized(state.locale, "Lease / user", "租约 / 用户"),
              ),
              @html.th(localized(state.locale, "Node", "节点")),
              @html.th(localized(state.locale, "State", "状态")),
              @html.th(localized(state.locale, "Expires", "到期时间")),
              @html.th(localized(state.locale, "Generation", "代际")),
              @html.th(localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for lease in state.exclusive_node_leases => {
                @html.tr([
                  @html.td([
                    @html.strong(lease.unix_username),
                    @html.span(class="mono secondary", lease.lease_id),
                    @html.span(class="mono secondary", lease.subject_ref),
                  ]),
                  @html.td(class="mono", lease.node_id),
                  @html.td(
                    exclusive_lease_state_badge(state.locale, lease.state),
                  ),
                  @html.td(generated_time_label(state.locale, lease.expires_at)),
                  @html.td(class="mono", lease.generation.to_string()),
                  @html.td(class="row-actions", [
                    if lease.state == "Requested" ||
                      lease.state == "Reserved" ||
                      lease.state == "Provisioning" ||
                      lease.state == "Active" ||
                      lease.state == "Quarantined" {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Terminate exclusive lease \{lease.lease_id}",
                          "终止独占租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          BeginTerminateExclusiveNodeLease(
                            lease.lease_id,
                            lease.generation,
                          ),
                        ),
                        localized(
                          state.locale,
                          "Terminate & clean…",
                          "终止并清理…",
                        ),
                      )
                    } else {
                      @html.span(
                        class="secondary",
                        localized(
                          state.locale,
                          if lease.state == "Completed" ||
                            lease.state == "Cancelled" {
                            "No actions"
                          } else {
                            "Cleanup in progress"
                          },
                          if lease.state == "Completed" ||
                            lease.state == "Cancelled" {
                            "无可用操作"
                          } else {
                            "清理进行中"
                          },
                        ),
                      )
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.div(class="subsection-heading", [
      @html.div([
        @html.h3(
          localized(
            state.locale,
            "Workspace capacity leases",
            "工作区容量租约",
          ),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "These grant control-plane capacity only and never grant direct DGX login access.",
            "这些租约只授予控制平面容量，绝不会直接授予 DGX 登录权限。",
          ),
        ),
      ]),
    ]),
    if state.compute_leases.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No compute or workspace leases are active. Use Policies → Create workspace lease after the user and access grant exist; it never grants direct node access.",
          "暂无有效的计算租约或工作区租约。用户和访问授权就绪后，请使用“策略 → 创建工作区租约”；租约绝不会授予节点直接访问权限。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Compute and workspace leases",
              "计算租约与工作区租约",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Lease / owner", "租约 / 所有者"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Workspace", "工作区"),
              ),
              @html.th(scope=Col, localized(state.locale, "Resource", "资源")),
              @html.th(scope=Col, localized(state.locale, "Status", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Window", "有效期"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for lease in state.compute_leases => {
                @html.tr([
                  @html.td([
                    @html.strong(lease.user_id),
                    @html.span(class="mono secondary", lease.lease_id),
                  ]),
                  @html.td(lease.workspace),
                  @html.td(lease_resource_label(state.locale, lease.resource)),
                  @html.td(lease_state_badge(state.locale, lease.state)),
                  @html.td([
                    @html.span(
                      localized(
                        state.locale,
                        "Starts \{generated_time_label(state.locale, lease.started_at)}",
                        "开始于 \{generated_time_label(state.locale, lease.started_at)}",
                      ),
                    ),
                    @html.span(
                      class="secondary",
                      localized(
                        state.locale,
                        "Expires \{generated_time_label(state.locale, lease.expires_at)}",
                        "到期于 \{generated_time_label(state.locale, lease.expires_at)}",
                      ),
                    ),
                  ]),
                  @html.td(class="row-actions", [
                    if lease.state == Requested {
                      @html.button(
                        type_="button",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "Activate lease \{lease.lease_id}",
                          "激活租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          ActivateComputeLease(lease.lease_id),
                        ),
                        localized(state.locale, "Activate", "激活"),
                      )
                    } else {
                      @html.nothing
                    },
                    if lease.state == Active {
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=state.loading,
                        title=localized(
                          state.locale,
                          "End lease \{lease.lease_id}",
                          "结束租约 \{lease.lease_id}",
                        ),
                        on_click=command(
                          emit,
                          BeginEndComputeLease(lease.lease_id),
                        ),
                        localized(
                          state.locale,
                          "End lease…",
                          "结束租约…",
                        ),
                      )
                    } else if lease.state != Requested {
                      @html.span(
                        class="secondary",
                        localized(state.locale, "No actions", "无可用操作"),
                      )
                    } else {
                      @html.nothing
                    },
                  ]),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn nodes_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("nodes-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(localized(state.locale, "Storage nodes", "存储节点")),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Measured capacity and inode headroom on the model-storage host. This is not GPU placement capacity.",
            "查看模型存储主机的实测容量与 inode 余量；此处不计入 GPU 放置容量。",
          ),
        ),
      ]),
    ]),
    if state.storage_nodes.is_empty() {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No storage monitor is configured. Configure the storage mount in the controller deployment.",
          "尚未配置存储监控。请在控制器部署中指定存储挂载卷。",
        ),
      )
    } else {
      @html.div(
        class="node-list",
        [
          for storage in state.storage_nodes => {
            storage_node_item(state.locale, storage)
          }
        ],
      )
    },
    @html.details(class="topology-disclosure", [
      @html.summary(
        localized(
          state.locale,
          "Cluster topology and trust boundaries",
          "集群拓扑与信任边界",
        ),
      ),
      cluster_topology(state),
    ]),
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="nodes-title",
          localized(state.locale, "Node inventory", "节点清单"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Inspect placement capacity and move nodes through controlled maintenance states.",
            "检查放置容量，并通过受控维护状态管理节点。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.nodes.length()} enrolled",
          "已注册 \{state.nodes.length()} 个",
        ),
      ),
    ]),
    if state.nodes.length() == 0 {
      @html.div(class="empty-state empty-state-action", [
        @html.strong(
          localized(state.locale, "No nodes enrolled", "尚未注册节点"),
        ),
        @html.p(
          localized(
            state.locale,
            "Create a short-lived enrollment token, start the node daemon, then refresh telemetry.",
            "请创建短期有效的注册令牌、启动节点守护进程，然后刷新遥测。",
          ),
        ),
        @html.button(
          type_="button",
          on_click=command(emit, Navigate(Policies)),
          localized(
            state.locale,
            "Open enrollment policy",
            "打开注册策略",
          ),
        ),
      ])
    } else {
      @html.div(
        class="node-list",
        [
          for node in state.nodes => node_item(state.locale, node, emit)
        ],
      )
    },
  ])
}

///|
fn storage_gib(bytes : Int64) -> String {
  let tenths = (bytes / 107374182L).max(0L)
  "\{tenths / 10L}.\{tenths % 10L} GiB"
}

///|
fn storage_node_item(
  locale : @i18n.Locale,
  storage : StorageNodeRow,
) -> @rabbita.Html {
  let healthy = storage.state == "healthy" &&
    storage.total_bytes is Some(_) &&
    storage.available_bytes is Some(_)
  let total = storage.total_bytes.unwrap_or(0L)
  let used = storage.used_bytes.unwrap_or(0L)
  let available = storage.available_bytes.unwrap_or(0L)
  let percent = if total > 0L {
    (used * 100L / total).clamp(min=0L, max=100L).to_int()
  } else {
    0
  }
  let inodes = storage.total_inodes.unwrap_or(0L)
  let available_inodes = storage.available_inodes.unwrap_or(0L)
  @html.article(class="node-record storage-node-record", [
    @html.div(class="node-summary", [
      @html.div(class="node-identity", [
        @html.strong(storage.node_id),
        @html.span(
          class="secondary",
          localized(
            locale, "Storage · model artifacts", "存储 · 模型制品",
          ),
        ),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "Status", "状态")),
        @html.strong(
          if healthy {
            localized(locale, "Measured", "已采集")
          } else {
            localized(locale, "Unavailable", "采集失败")
          },
        ),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(
          localized(
            locale, "Last sample (Beijing)", "最近采集（北京时间）",
          ),
        ),
        @html.strong(@contractdoc.format_unix_ms_beijing(storage.sampled_at_ms)),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "Available space", "可用空间")),
        @html.strong(
          if healthy {
            storage_gib(available)
          } else {
            localized(locale, "Not reported", "未上报")
          },
        ),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "Used / total", "已用／总量")),
        @html.strong(
          if healthy {
            "\{storage_gib(used)} / \{storage_gib(total)}"
          } else {
            localized(locale, "Not reported", "未上报")
          },
        ),
      ]),
    ]),
    if healthy {
      @html.div(class="node-detail", [
        @html.div(class="node-metrics", [
          @html.div(class="node-metric", [
            @html.span(localized(locale, "Capacity used", "容量已用")),
            @html.strong("\{percent}%"),
            @html.progress(value=percent, max=100, "\{percent}%"),
          ]),
          @html.div(class="node-metric", [
            @html.span(localized(locale, "Available inodes", "可用 inode")),
            @html.strong(
              if inodes > 0L {
                "\{available_inodes} / \{inodes}"
              } else {
                localized(locale, "Not reported", "未上报")
              },
            ),
          ]),
        ]),
      ])
    } else {
      @html.p(
        class="empty-state compact",
        localized(
          locale, "The configured storage mount could not be measured. Check its hostPath and controller mount.",
          "无法采集配置的存储挂载卷。请检查主机目录与控制器挂载。",
        ),
      )
    },
  ])
}

///|
fn cluster_topology(state : ConsoleState) -> @rabbita.Html {
  let active_nodes = state.nodes
    .iter()
    .filter(node => node.state == Active)
    .count()
  let management_label = if state.operator_authenticated {
    localized(state.locale, "Connected", "已连接")
  } else {
    localized(state.locale, "Authentication required", "需要认证")
  }
  let management_tone = if state.operator_authenticated {
    "ok"
  } else {
    "warning"
  }
  @html.section(
    class="cluster-topology",
    attrs=@html.Attrs::build().aria_labelledby("cluster-topology-title"),
    [
      @html.header(class="topology-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(state.locale, "Logical network", "逻辑网络"),
          ),
          @html.h2(
            id="cluster-topology-title",
            localized(state.locale, "Cluster topology", "集群拓扑"),
          ),
          @html.p(
            localized(
              state.locale,
              "Live roles and control paths derived from this console session and enrolled-node heartbeats.",
              "根据当前控制台会话和已注册节点心跳展示实时角色与控制链路。",
            ),
          ),
        ]),
        @html.div(class="topology-summary", [
          @html.span(class="topology-summary-item", [
            @html.strong("1"),
            @html.span(
              localized(state.locale, " management plane", " 个管理平面"),
            ),
          ]),
          @html.span(class="topology-summary-item", [
            @html.strong(state.nodes.length().to_string()),
            @html.span(
              localized(state.locale, " compute nodes", " 个计算节点"),
            ),
          ]),
          @html.span(class="topology-summary-item", [
            @html.strong(active_nodes.to_string()),
            @html.span(localized(state.locale, " active", " 个正常")),
          ]),
        ]),
      ]),
      @html.figure(class="topology-graph-frame", [
        @html.div(
          class="topology-graph",
          attrs=@html.Attrs::build()
            .role("img")
            .aria_label(
              localized(
                state.locale,
                "Network graph from operator access through the management plane to enrolled compute nodes, with metadata and model storage dependencies.",
                "从运维访问经管理平面连接到已注册计算节点，并包含元数据与模型存储依赖的网络图。",
              ),
            ),
          [
            @html.div(class="graph-node graph-access-node", [
              @html.span(
                class="graph-node-symbol",
                attrs=@html.Attrs::build().aria_hidden("true"),
                "OP",
              ),
              @html.div([
                @html.small(localized(state.locale, "Entry", "入口")),
                @html.h3(
                  localized(state.locale, "Operator access", "运维访问"),
                ),
                @html.span(
                  localized(
                    state.locale,
                    "Authorized management entry",
                    "已授权管理入口",
                  ),
                ),
              ]),
              status_badge(
                localized(state.locale, "Authenticated", "已认证"),
                if state.operator_authenticated {
                  "ok"
                } else {
                  "warning"
                },
              ),
            ]),
            @html.div(
              class="graph-edge graph-edge-https",
              attrs=@html.Attrs::build().aria_hidden("true"),
              @html.span("API"),
            ),
            @html.div(class="graph-management-stack", [
              @html.div(class="graph-node graph-control-node", [
                @html.span(
                  class="graph-node-symbol",
                  attrs=@html.Attrs::build().aria_hidden("true"),
                  "CP",
                ),
                @html.div([
                  @html.small(localized(state.locale, "Control", "控制")),
                  @html.h3(
                    localized(state.locale, "Management plane", "管理平面"),
                  ),
                  @html.span(
                    localized(
                      state.locale,
                      "API · Scheduler · Reconciler",
                      "API · 调度器 · 协调器",
                    ),
                  ),
                ]),
                status_badge(management_label, management_tone),
              ]),
              @html.div(class="graph-dependency-branch", [
                @html.div(class="graph-node graph-dependency-node", [
                  @html.span(
                    class="graph-node-symbol graph-node-symbol-data",
                    attrs=@html.Attrs::build().aria_hidden("true"),
                    "DB",
                  ),
                  @html.div([
                    @html.small(localized(state.locale, "State", "状态")),
                    @html.strong("PostgreSQL"),
                    @html.span(localized(state.locale, "Metadata", "元数据")),
                  ]),
                ]),
                @html.div(class="graph-node graph-dependency-node", [
                  @html.span(
                    class="graph-node-symbol graph-node-symbol-store",
                    attrs=@html.Attrs::build().aria_hidden("true"),
                    "MS",
                  ),
                  @html.div([
                    @html.small(localized(state.locale, "Artifacts", "制品")),
                    @html.strong(
                      localized(state.locale, "Model storage", "模型存储"),
                    ),
                    @html.span(
                      localized(
                        state.locale,
                        "Registry references",
                        "注册表引用",
                      ),
                    ),
                  ]),
                ]),
              ]),
            ]),
            @html.div(
              class="graph-edge graph-edge-mtls",
              attrs=@html.Attrs::build().aria_hidden("true"),
              [
                @html.span(
                  localized(state.locale, "mTLS + heartbeat", "mTLS + 心跳"),
                ),
              ],
            ),
            @html.div(class="graph-compute-cluster", [
              @html.div(class="graph-cluster-heading", [
                @html.div([
                  @html.small(localized(state.locale, "Execution", "执行")),
                  @html.h3(
                    localized(state.locale, "Compute plane", "计算平面"),
                  ),
                ]),
                @html.span(
                  localized(
                    state.locale,
                    "\{state.nodes.length()} enrolled",
                    "已注册 \{state.nodes.length()} 个",
                  ),
                ),
              ]),
              if state.nodes.length() == 0 {
                @html.div(class="topology-missing graph-compute-missing", [
                  status_badge(
                    localized(
                      state.locale,
                      "Enrollment required",
                      "等待注册",
                    ),
                    "warning",
                  ),
                  @html.strong(
                    localized(
                      state.locale,
                      "No compute link established",
                      "尚未建立计算链路",
                    ),
                  ),
                  @html.span(
                    localized(
                      state.locale,
                      "Enroll a node to establish desired-state and heartbeat channels.",
                      "注册节点后将建立期望状态与心跳通道。",
                    ),
                  ),
                ])
              } else {
                @html.ul(
                  class="graph-compute-list",
                  [
                    for node in state.nodes => {
                      @html.li(class="graph-node graph-compute-node", [
                        @html.span(
                          class="graph-node-symbol graph-node-symbol-compute",
                          attrs=@html.Attrs::build().aria_hidden("true"),
                          "GPU",
                        ),
                        @html.div([
                          @html.strong(class="mono", node.node_id),
                          @html.small(
                            class="mono",
                            architecture_label(state.locale, node.architecture),
                          ),
                        ]),
                        node_state_badge(state.locale, node.state),
                      ])
                    }
                  ],
                )
              },
            ]),
          ],
        ),
        @html.figcaption(
          localized(
            state.locale,
            "Arrows show authenticated control traffic; each compute branch represents an enrolled node-agent channel.",
            "箭头表示已认证的控制流量；每条计算分支代表一个已注册的节点代理通道。",
          ),
        ),
      ]),
      @html.details(class="topology-relationships", [
        @html.summary(
          localized(
            state.locale,
            "Connection inventory and trust boundaries",
            "连接清单与信任边界",
          ),
        ),
        @html.dl([
          @html.div([
            @html.dt(
              localized(
                state.locale,
                "Operator console → Management API",
                "运维控制台 → 管理 API",
              ),
            ),
            @html.dd(
              localized(
                state.locale,
                "Management API · transport security depends on the entry deployment",
                "管理 API · 传输安全取决于入口部署配置",
              ),
            ),
          ]),
          @html.div([
            @html.dt(
              localized(
                state.locale,
                "Management plane ↔ Compute nodes",
                "管理平面 ↔ 计算节点",
              ),
            ),
            @html.dd(
              localized(
                state.locale,
                "Mutual TLS · desired state, receipts, telemetry, and heartbeats",
                "双向 TLS · 期望状态、回执、遥测与心跳",
              ),
            ),
          ]),
          @html.div([
            @html.dt(
              localized(
                state.locale,
                "Management services → Persistent stores",
                "管理服务 → 持久化存储",
              ),
            ),
            @html.dd(
              localized(
                state.locale,
                "Metadata and model-artifact references · never exposed to tenants",
                "元数据与模型制品引用 · 不向租户暴露",
              ),
            ),
          ]),
        ]),
        @html.p(
          class="topology-scope-note",
          localized(
            state.locale,
            "Scope: LunaNexa logical roles. Optional bastions, VPNs, switches, physical NICs, and cabling are external infrastructure and are not inferred here.",
            "范围：LunaNexa 逻辑角色。可选堡垒机、VPN、交换机、物理网卡和线缆属于外部基础设施，此处不作推断。",
          ),
        ),
      ]),
    ],
  )
}

///|
fn memory_gib(mib : Int) -> String {
  let tenths = (mib.to_int64() * 10L + 512L) / 1024L
  "\{tenths / 10L}.\{tenths % 10L} GiB"
}

///|
fn node_item(
  locale : @i18n.Locale,
  node : NodeRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let lease_holder = if node.lease_holder == "" {
    localized(locale, "Unassigned", "未分配")
  } else {
    node.lease_holder
  }
  let active_assignment = if node.active_assignment == "" {
    localized(locale, "Idle", "空闲")
  } else {
    node.active_assignment
  }
  let utilization_percent = (node.utilization_per_mille / 10).clamp(
    min=0,
    max=100,
  )
  let cpu_percent = (node.cpu_per_mille / 10).clamp(min=0, max=100)
  let unified = node.architecture.contains("sm121") ||
    node.architecture.contains("gb10")
  let memory_label = if unified {
    localized(locale, "Unified memory", "统一内存")
  } else {
    localized(locale, "Memory", "内存")
  }
  let gpu_text = if node.utilization_per_mille < 0 {
    localized(locale, "Unavailable / stale", "未上报／已过期")
  } else {
    "\{node.utilization_per_mille / 10}.\{node.utilization_per_mille % 10}%"
  }
  let memory_percent = if node.total_memory_mib > 0 {
    (node.used_memory_mib * 100 / node.total_memory_mib).clamp(min=0, max=100)
  } else {
    0
  }
  @html.details(class="node-record", [
    @html.summary(class="node-summary", [
      @html.div(class="node-identity", [
        @html.strong(node.node_id),
        @html.span(
          class="mono secondary",
          architecture_label(locale, node.architecture),
        ),
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "State", "状态")),
        node_state_badge(locale, node.state),
      ]),
      @html.div(class="node-summary-cell node-memory-summary", [
        @html.span(memory_label),
        if node.memory_measured {
          @html.strong(memory_gib(node.free_memory_mib))
        } else {
          @html.strong(localized(locale, "Not reported", "未上报"))
        },
        if node.memory_measured {
          @html.small(
            localized(
              locale,
              "available · \{memory_gib(node.total_memory_mib)} total",
              "可用 · 总计 \{memory_gib(node.total_memory_mib)}",
            ),
          )
        } else {
          @html.small(
            localized(
              locale, "no memory sample reported", "未上报内存采样",
            ),
          )
        },
      ]),
      @html.div(class="node-summary-cell", [
        @html.span(localized(locale, "GPU utilization", "GPU 利用率")),
        @html.strong(gpu_text),
      ]),
      @html.div(class="node-summary-cell node-lease-summary", [
        @html.span(localized(locale, "Exclusive lease", "独占租约")),
        @html.strong(lease_holder),
      ]),
      @html.span(
        class="node-expand-cue",
        localized(locale, "Inspect", "查看详情"),
      ),
    ]),
    @html.div(class="node-detail", [
      @html.div(class="node-detail-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(locale, "Live node evidence", "节点实时证据"),
          ),
          @html.h3(localized(locale, "Resource telemetry", "资源遥测")),
        ]),
        @html.span(
          class="secondary",
          localized(
            locale,
            "Last heartbeat · \{node.last_seen}",
            "最近心跳 · \{node.last_seen}",
          ),
        ),
      ]),
      @html.div(class="node-metrics", [
        @html.div(class="node-metric", [
          @html.span(localized(locale, "GPU utilization", "GPU 利用率")),
          @html.strong(gpu_text),
          if node.utilization_per_mille >= 0 {
            @html.progress(
              value=utilization_percent,
              max=100,
              "\{utilization_percent}%",
            )
          } else {
            @html.nothing
          },
        ]),
        @html.div(class="node-metric", [
          @html.span(memory_label + localized(locale, " · used", " · 已用")),
          if node.memory_measured {
            @html.strong(memory_gib(node.used_memory_mib))
          } else {
            @html.strong(localized(locale, "Not reported", "未上报"))
          },
          if node.memory_measured {
            @html.progress(value=memory_percent, max=100, "\{memory_percent}%")
          } else {
            @html.nothing
          },
          if node.memory_measured {
            @html.small(
              localized(
                locale,
                "Total \{memory_gib(node.total_memory_mib)} · available \{memory_gib(node.free_memory_mib)}",
                "总计 \{memory_gib(node.total_memory_mib)} · 可用 \{memory_gib(node.free_memory_mib)}",
              ),
            )
          } else {
            @html.small(
              localized(
                locale, "no memory measurement reported", "未上报内存实测数据",
              ),
            )
          },
          if unified {
            @html.small(
              localized(
                locale, "CPU/GPU shared pool · system MemAvailable", "CPU/GPU 共享 · 系统 MemAvailable 实测",
              ),
            )
          } else {
            @html.nothing
          },
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "CPU utilization", "CPU 利用率")),
          if node.cpu_measured {
            @html.strong(
              "\{node.cpu_per_mille / 10}.\{node.cpu_per_mille % 10}%",
            )
          } else {
            @html.strong(localized(locale, "Not reported", "未上报"))
          },
          if node.cpu_measured {
            @html.progress(value=cpu_percent, max=100, "\{cpu_percent}%")
          } else {
            @html.nothing
          },
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "Temperature", "温度")),
          @html.strong(
            if node.temperature_celsius < 0 {
              localized(locale, "Unavailable / stale", "未上报／已过期")
            } else {
              "\{node.temperature_celsius} °C"
            },
          ),
          @html.small(
            localized(
              locale, "Maximum observed sensor", "已观测传感器最大值",
            ),
          ),
        ]),
        @html.div(class="node-metric", [
          @html.span(localized(locale, "Power draw", "功耗")),
          @html.strong(
            if node.power_watts < 0.0 {
              localized(locale, "Unavailable / stale", "未上报／已过期")
            } else {
              "\{node.power_watts} W"
            },
          ),
          @html.small(
            localized(
              locale, "Node-reported GPU aggregate", "节点上报 GPU 汇总",
            ),
          ),
        ]),
      ]),
      @html.dl(class="node-facts", [
        @html.div([
          @html.dt(localized(locale, "Lease holder", "租约持有者")),
          @html.dd(lease_holder),
        ]),
        @html.div([
          @html.dt(localized(locale, "Assignment", "当前分配")),
          @html.dd(class="mono", active_assignment),
        ]),
        @html.div([
          @html.dt(
            localized(
              locale, "Controller-managed deployments", "控制器托管部署",
            ),
          ),
          @html.dd(node.workloads.to_string()),
        ]),
      ]),
      @html.div(class="node-detail-actions", [
        @html.p(
          localized(
            locale, "Maintenance changes are confirmation-gated and recorded with an audit receipt.",
            "维护变更必须二次确认，并生成审计回执。",
          ),
        ),
        @html.div(class="row-actions", [
          @html.button(
            type_="button",
            title=localized(
              locale,
              "Cordon \{node.node_id}",
              "封锁调度 \{node.node_id}",
            ),
            on_click=command(emit, BeginCordon(node.node_id)),
            localized(locale, "Cordon…", "封锁调度…"),
          ),
          @html.button(
            type_="button",
            class="danger-secondary",
            title=localized(
              locale,
              "Drain \{node.node_id}",
              "排空 \{node.node_id}",
            ),
            on_click=command(emit, BeginDrain(node.node_id)),
            localized(locale, "Drain…", "排空…"),
          ),
        ]),
      ]),
    ]),
  ])
}

///|
fn model_source_size(value : Int64) -> String {
  if value >= 1073741824L {
    "\{value / 1073741824L}.\{(value % 1073741824L) * 10L / 1073741824L} GiB"
  } else {
    "\{value / 1048576L} MiB"
  }
}

///|
fn model_import_for(
  imports : Array[ModelImportRow],
  model_id : String,
) -> ModelImportRow? {
  let mut selected : ModelImportRow? = None
  for import_ in imports {
    if import_.model_id == model_id {
      match selected {
        Some(current) =>
          if import_.updated_unix_ms > current.updated_unix_ms {
            selected = Some(import_)
          }
        None => selected = Some(import_)
      }
    }
  }
  selected
}

///|
fn model_import_label(
  locale : @i18n.Locale,
  state : ModelImportState,
) -> String {
  match state {
    Queued => localized(locale, "Queued", "等待处理")
    Downloading => localized(locale, "Downloading", "下载中")
    Verifying =>
      localized(locale, "Verifying against ModelScope", "对照魔搭校验中")
    Verified => localized(locale, "Checksum verified", "校验和已验证")
    Failed => localized(locale, "Failed", "失败")
    Cancelled => localized(locale, "Cancelled", "已取消")
  }
}

///|
/// Where an import's bytes live, in the operator's words: an upstream
/// object, the model store the control plane serves, or nowhere yet.
fn model_import_transport_label(
  locale : @i18n.Locale,
  import_ : ModelImportRow,
) -> String {
  if import_.artifact_uri.has_prefix("s3://") {
    localized(locale, "Published to S3", "已发布到 S3")
  } else if import_.artifact_uri.has_prefix(@contracts.model_store_scheme) {
    localized(
      locale, "Servable from the model store", "可由模型库直接服务",
    )
  } else {
    localized(locale, "Awaiting artifact publication", "等待制品发布")
  }
}

///|
fn model_import_progress(import_ : ModelImportRow) -> Int {
  if import_.bytes_total <= 0L {
    0
  } else {
    (import_.bytes_completed * 100L / import_.bytes_total).min(100L).to_int()
  }
}

///|
/// Adoptability is decided in one place on purpose: the renderer that offers
/// the button and the handler that acts on it disagreed once, and the button
/// silently did nothing for every import the store had verified.
pub fn model_import_adoptable(import_ : ModelImportRow) -> Bool {
  import_.source == "modelscope" &&
  @contracts.valid_identifier(import_.import_id, maximum_length=128) &&
  import_.state == Verified &&
  import_.files_total > 0 &&
  import_.files_completed == import_.files_total &&
  import_.bytes_total > 0L &&
  import_.bytes_completed == import_.bytes_total &&
  (
    import_.artifact_uri.has_prefix("s3://") ||
    import_.artifact_uri.has_prefix(@contracts.model_store_scheme)
  ) &&
  @contracts.valid_sha256_digest(import_.manifest_digest) &&
  import_.license.trim() != ""
}

///|
/// Early ModelScope imports used a store URI that omitted the `models/`
/// directory. The immutable manifest digest and the rest of the path still
/// identify the same revision after the registry URI is corrected.
fn canonical_model_import_uri(uri : String) -> String {
  match uri.strip_prefix("modelstore://modelscope/") {
    Some(path) => "modelstore://models/modelscope/" + path.to_owned()
    None => uri
  }
}

///|
/// A verified download and a registry entry describe the same immutable
/// artifact only when their canonical transport URI and manifest digest agree.
fn registered_model_for_import(
  models : Array[ModelRow],
  import_ : ModelImportRow,
) -> ModelRow? {
  if import_.artifact_uri == "" || import_.manifest_digest == "" {
    return None
  }
  models
  .iter()
  .find_first(model => {
    canonical_model_import_uri(model.artifact_uri) ==
    canonical_model_import_uri(import_.artifact_uri) &&
    model.artifact_digest == import_.manifest_digest
  })
}

///|
pub fn model_import_needs_registration(
  import_ : ModelImportRow,
  models : Array[ModelRow],
) -> Bool {
  model_import_adoptable(import_) &&
  registered_model_for_import(models, import_) is None
}

///|
fn model_adoption_identifier_valid(value : String) -> Bool {
  @contracts.valid_identifier(value.trim().to_owned())
}

///|
fn model_adoption_architectures_valid(value : String) -> Bool {
  let mut count = 0
  for part in value.split(",") {
    let architecture = part.trim().to_owned()
    if !@contracts.valid_identifier(architecture, maximum_length=128) {
      return false
    }
    count += 1
    if count > 16 {
      return false
    }
  }
  count > 0
}

///|
fn model_adoption_memory_valid(value : String) -> Bool {
  let memory = @string.parse_int(value.trim()) catch { _ => return false }
  memory > 0
}

///|
fn model_adoption_draft_valid(draft : ModelAdoptionDraft) -> Bool {
  draft.import_id != "" &&
  model_adoption_identifier_valid(draft.model_id) &&
  model_adoption_identifier_valid(draft.version) &&
  model_adoption_identifier_valid(draft.license_id) &&
  model_adoption_architectures_valid(draft.compatible_architectures) &&
  model_adoption_memory_valid(draft.minimum_memory_mib)
}

///|
fn model_local_segment_valid(segment : String) -> Bool {
  let length = segment.length()
  length >= 1 &&
  length <= 90 &&
  segment.all(character => {
    (character >= 'a' && character <= 'z') ||
    (character >= 'A' && character <= 'Z') ||
    (character >= '0' && character <= '9') ||
    character == '-' ||
    character == '_' ||
    character == '.'
  })
}

///|
/// `owner/name` exactly: the same identity rule the model-source adapter and
/// the control plane enforce, so the console never offers a doomed submission.
fn model_local_repository_valid(value : String) -> Bool {
  let segments = value.trim().split("/").collect()
  segments.length() == 2 &&
  segments.all(segment => model_local_segment_valid(segment.to_owned()))
}

///|
fn model_local_directory_label(row : ModelLocalDirectoryRow) -> String {
  "\{row.directory} · \{row.files} files · \{row.bytes / 1073741824L} GiB"
}

///|
pub fn model_local_registration_valid(
  state : ConsoleState,
  draft : ModelLocalRegistrationDraft,
) -> Bool {
  draft.directory != "" &&
  state.model_local_directories.any(row => {
    row.directory == draft.directory && !row.registered
  }) &&
  model_local_repository_valid(draft.repository) &&
  model_local_segment_valid(draft.revision.trim().to_owned())
}

///|
/// Bring a directory that was populated outside LunaNexa into the same plane
/// as a download. The console only states intent; the adapter re-derives every
/// digest from the named ModelScope revision before the import is verified.
fn model_local_registration_form(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let draft = state.model_local_draft
  let directory_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=draft.directory == "",
      localized(state.locale, "Select a directory", "选择目录"),
    ),
  ]
  for row in state.model_local_directories {
    directory_options.push(
      @html.option(
        value=row.directory,
        selected=draft.directory == row.directory,
        if row.registered {
          "\{model_local_directory_label(row)} · \{localized(state.locale, "already registered", "已登记")}"
        } else {
          model_local_directory_label(row)
        },
      ),
    )
  }
  let repository_invalid = draft.repository != "" &&
    !model_local_repository_valid(draft.repository)
  @html.form(
    class="model-local-registration",
    on_submit=command(emit, SubmitModelLocalRegistration),
    [
      @html.fieldset(disabled=state.loading, [
        @html.legend(
          localized(
            state.locale,
            "Register a revision already in the managed store",
            "登记受管模型库中已有的版本",
          ),
        ),
        @html.p(
          class="field-help",
          localized(
            state.locale,
            "Choose the whole revision or a FL2VA / Ref2VA component directory. Each gets its own verified manifest and registry identity. The adapter checks every file against ModelScope before registration; license acceptance, artifact verification and operator approval follow. Evaluation is optional evidence.",
            "可选择完整版本，或单独选择 FL2VA／Ref2VA 组件目录。每个组件都有独立的校验清单和注册身份。适配器先按魔搭逐文件核对；后续仍需接受许可证、验证制品并由运维人员批准，评测可选。",
          ),
        ),
        @html.div(class="model-local-grid", [
          @html.div(class="field-group", [
            @html.label(
              for_="model-local-directory",
              localized(state.locale, "Directory", "目录"),
            ),
            @html.select(
              id="model-local-directory",
              on_change=text_command(emit, value => {
                ModelLocalDirectoryChanged(value)
              }),
              directory_options,
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-local-repository",
              localized(state.locale, "ModelScope repository", "魔搭仓库"),
            ),
            @html.input(
              id="model-local-repository",
              input_type=Text,
              maxlength=180,
              placeholder="MiniMax/MiniMax-H3",
              value=draft.repository,
              attrs=@html.Attrs::build().aria_invalid(
                if repository_invalid {
                  "true"
                } else {
                  "false"
                },
              ),
              on_input=text_command(emit, value => {
                ModelLocalRepositoryChanged(value)
              }),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-local-revision",
              localized(state.locale, "Revision", "版本"),
            ),
            @html.input(
              id="model-local-revision",
              input_type=Text,
              maxlength=96,
              placeholder="master",
              value=draft.revision,
              on_input=text_command(emit, value => {
                ModelLocalRevisionChanged(value)
              }),
            ),
          ]),
        ]),
        @html.div(class="operation-actions", [
          @html.button(
            type_="button",
            class="secondary-button",
            disabled=!state.operator_authenticated || state.loading,
            on_click=command(emit, RefreshModelLocalDirectories),
            localized(state.locale, "Scan the model store", "扫描模型库"),
          ),
          @html.button(
            type_="submit",
            class="primary-button",
            disabled=!state.operator_authenticated ||
              state.loading ||
              !model_local_registration_valid(state, draft),
            localized(state.locale, "Register & verify", "登记并校验"),
          ),
        ]),
      ]),
    ],
  )
}

///|
fn model_adoption_form(
  state : ConsoleState,
  import_ : ModelImportRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let adopted = state.model_adopted_imports.any(value => {
    value == import_.import_id
  })
  if adopted {
    return @html.div(
      class="model-adoption-complete",
      attrs=@html.Attrs::build().role("status").aria_live("polite"),
      [
        @html.strong(
          localized(
            state.locale,
            "Registered as a Candidate",
            "已登记为候选模型",
          ),
        ),
        @html.span(
          localized(
            state.locale,
            "License, artifact verification, operator approval, alias and deployment checks still apply. Evaluation is optional evidence.",
            "许可证、制品验证、运维批准、别名与部署检查仍然有效；评测是可选证据。",
          ),
        ),
      ],
    )
  }
  if !model_import_adoptable(import_) {
    return @html.div(class="model-adoption-blocked", [
      @html.strong(
        localized(
          state.locale,
          "Not ready for registry adoption",
          "尚不能登记到注册表",
        ),
      ),
      @html.span(
        localized(
          state.locale,
          "The import must be complete, checksum-verified, license-declared, and materialized on a transport LunaNexa itself serves: an immutable s3:// object, or a ModelScope-verified revision in the managed model store.",
          "导入必须完整、通过校验、声明许可证，并落在 LunaNexa 自身可服务的传输上：不可变的 s3:// 对象，或受管模型库中经魔搭校验的版本。",
        ),
      ),
    ])
  }
  if state.model_adoption_draft.import_id != import_.import_id {
    return @html.button(
      type_="button",
      class="primary-button",
      disabled=!state.operator_authenticated || state.loading,
      on_click=command(emit, BeginModelAdoption(import_.import_id)),
      localized(
        state.locale,
        "Adopt as Candidate…",
        "登记为候选模型…",
      ),
    )
  }
  let draft = state.model_adoption_draft
  let model_id_invalid = draft.model_id != "" &&
    !model_adoption_identifier_valid(draft.model_id)
  let version_invalid = draft.version != "" &&
    !model_adoption_identifier_valid(draft.version)
  let license_invalid = draft.license_id != "" &&
    !model_adoption_identifier_valid(draft.license_id)
  let architectures_invalid = draft.compatible_architectures != "" &&
    !model_adoption_architectures_valid(draft.compatible_architectures)
  let memory_invalid = draft.minimum_memory_mib != "" &&
    !model_adoption_memory_valid(draft.minimum_memory_mib)
  let valid = model_adoption_draft_valid(draft)
  @html.form(
    class="model-adoption-form",
    on_submit=command(emit, SubmitModelAdoption),
    attrs=@html.Attrs::build().aria_labelledby("model-adoption-title"),
    [
      @html.fieldset(disabled=state.loading, [
        @html.legend(
          id="model-adoption-title",
          localized(
            state.locale,
            "Register checksum-verified source as Candidate",
            "将校验通过的源登记为候选模型",
          ),
        ),
        @html.p(
          class="field-help model-adoption-intro",
          localized(
            state.locale,
            "Artifact URI, size, digest, upstream identity, and license evidence are locked to this verified import. Enter only registry identity and placement constraints that cannot be inferred safely.",
            "制品 URI、大小、摘要、上游身份与许可证证据均锁定到本次已验证导入。这里只填写无法安全推导的注册表身份与放置约束。",
          ),
        ),
        @html.div(class="model-adoption-grid", [
          @html.div(class="field-group", [
            @html.label(
              for_="model-adoption-id",
              localized(state.locale, "Model ID", "模型 ID"),
            ),
            @html.input(
              id="model-adoption-id",
              input_type=Text,
              required=true,
              maxlength=256,
              placeholder="model.minicpm5-1b",
              value=draft.model_id,
              attrs=@html.Attrs::build()
                .aria_describedby("model-adoption-id-help")
                .aria_invalid(if model_id_invalid { "true" } else { "false" }),
              on_input=text_command(emit, value => ModelAdoptionIdChanged(value)),
            ),
            @html.p(
              id="model-adoption-id-help",
              class=if model_id_invalid {
                "field-help field-error"
              } else {
                "field-help"
              },
              localized(
                state.locale,
                "Stable letters, numbers, dots, colons, hyphens, or underscores.",
                "使用稳定的字母、数字、点、冒号、连字符或下划线。",
              ),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-adoption-version",
              localized(state.locale, "Version", "版本"),
            ),
            @html.input(
              id="model-adoption-version",
              input_type=Text,
              required=true,
              maxlength=256,
              placeholder="modelscope-main",
              value=draft.version,
              attrs=@html.Attrs::build()
                .aria_describedby("model-adoption-version-help")
                .aria_invalid(if version_invalid { "true" } else { "false" }),
              on_input=text_command(emit, value => {
                ModelAdoptionVersionChanged(value)
              }),
            ),
            @html.p(
              id="model-adoption-version-help",
              class=if version_invalid {
                "field-help field-error"
              } else {
                "field-help"
              },
              localized(
                state.locale,
                "A stable registry version; source revision remains in provenance.",
                "稳定的注册表版本；源 revision 会保留在来源证据中。",
              ),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-adoption-license",
              localized(state.locale, "License record ID", "许可证记录 ID"),
            ),
            @html.input(
              id="model-adoption-license",
              input_type=Text,
              required=true,
              maxlength=256,
              placeholder="license.minicpm5-apache",
              value=draft.license_id,
              attrs=@html.Attrs::build()
                .aria_describedby("model-adoption-license-help")
                .aria_invalid(if license_invalid { "true" } else { "false" }),
              on_input=text_command(emit, value => {
                ModelAdoptionLicenseChanged(value)
              }),
            ),
            @html.p(
              id="model-adoption-license-help",
              class=if license_invalid {
                "field-help field-error"
              } else {
                "field-help"
              },
              localized(
                state.locale,
                "Creates a pending record; this does not accept the license.",
                "将创建待审核记录；此操作不会接受许可证。",
              ),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-adoption-architectures",
              localized(
                state.locale,
                "Compatible architectures",
                "兼容架构",
              ),
            ),
            @html.input(
              id="model-adoption-architectures",
              input_type=Text,
              required=true,
              maxlength=2048,
              placeholder="nvidia-gb10, nvidia-ampere",
              value=draft.compatible_architectures,
              attrs=@html.Attrs::build()
                .aria_describedby("model-adoption-architectures-help")
                .aria_invalid(
                  if architectures_invalid {
                    "true"
                  } else {
                    "false"
                  },
                ),
              on_input=text_command(emit, value => {
                ModelAdoptionArchitecturesChanged(value)
              }),
            ),
            @html.p(
              id="model-adoption-architectures-help",
              class=if architectures_invalid {
                "field-help field-error"
              } else {
                "field-help"
              },
              localized(
                state.locale,
                "Comma-separated; 1–16 validated architecture identifiers.",
                "用逗号分隔；填写 1–16 个经过验证的架构标识。",
              ),
            ),
          ]),
          @html.div(class="field-group", [
            @html.label(
              for_="model-adoption-memory",
              localized(
                state.locale,
                "Minimum accelerator memory (MiB)",
                "最低加速器显存（MiB）",
              ),
            ),
            @html.input(
              id="model-adoption-memory",
              input_type=Number,
              required=true,
              min=1,
              step=1,
              inputmode="numeric",
              placeholder="8192",
              value=draft.minimum_memory_mib,
              attrs=@html.Attrs::build()
                .aria_describedby("model-adoption-memory-help")
                .aria_invalid(if memory_invalid { "true" } else { "false" }),
              on_input=text_command(emit, value => {
                ModelAdoptionMemoryChanged(value)
              }),
            ),
            @html.p(
              id="model-adoption-memory-help",
              class=if memory_invalid {
                "field-help field-error"
              } else {
                "field-help"
              },
              localized(
                state.locale,
                "Measured placement floor, not a requested allocation.",
                "这是实测放置下限，不是申请分配量。",
              ),
            ),
          ]),
        ]),
        @html.div(class="model-adoption-actions", [
          @html.span(
            class="secondary",
            localized(
              state.locale,
              "Creates Candidate + pending license only. Three publication checks remain.",
              "仅创建候选模型与待审核许可证；仍需完成三项发布检查。",
            ),
          ),
          @html.div(class="row-actions", [
            @html.button(
              type_="button",
              class="secondary-button",
              disabled=state.loading,
              on_click=command(emit, DismissModelAdoption),
              localized(state.locale, "Cancel", "取消"),
            ),
            @html.button(
              type_="submit",
              class="primary-button",
              disabled=!valid || state.loading,
              localized(
                state.locale,
                if state.loading {
                  "Registering…"
                } else {
                  "Register Candidate"
                },
                if state.loading {
                  "正在登记…"
                } else {
                  "登记候选模型"
                },
              ),
            ),
          ]),
        ]),
      ]),
    ],
  )
}

///|
fn verified_import_gate(
  state : ConsoleState,
  import_ : ModelImportRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  if registered_model_for_import(state.models, import_) is Some(model) {
    return @html.div(class="verified-import-actions", [
      @html.strong(
        localized(
          state.locale,
          "Already registered in the model registry",
          "已登记到模型注册表",
        ),
      ),
      @html.span(class="mono", "\{model.model_id}@\{model.version}"),
      model_state_badge(state.locale, model.state),
    ])
  }
  @html.div(class="verified-import-actions", [
    @html.div(class="approval-gate-note", [
      @html.strong(
        localized(
          state.locale,
          "Checksum passed; three publication checks remain",
          "校验已通过；仍需完成三项发布检查",
        ),
      ),
      @html.span(
        localized(
          state.locale,
          "Adoption only creates a Candidate from the verified immutable artifact. It does not package the model or make it deployable.",
          "登记只会从已校验的不可变制品创建候选模型；不会打包模型，也不会使其可部署。",
        ),
      ),
      @html.ul(class="model-approval-checklist", [
        @html.li(
          localized(
            state.locale,
            "Pending · License acceptance",
            "待完成 · 许可证接受",
          ),
        ),
        @html.li(
          localized(
            state.locale,
            "Pending · Artifact integrity and provenance",
            "待完成 · 制品完整性与来源记录",
          ),
        ),
        @html.li(
          localized(
            state.locale,
            "Pending · Explicit operator approval",
            "待完成 · 运维人员明确批准",
          ),
        ),
      ]),
    ]),
    model_adoption_form(state, import_, emit),
  ])
}

///|
/// Registered artifacts grouped by model, in the order the controller reported
/// them. A model carries one artifact per qualification profile, so an
/// ungrouped table reads as many models when only a few exist.
pub fn group_models_by_model_id(
  rows : Array[ModelRow],
) -> Array[(String, Array[ModelRow])] {
  let groups : Array[(String, Array[ModelRow])] = []
  for row in rows {
    let mut bucket : Array[ModelRow]? = None
    for group in groups {
      if group.0 == row.model_id {
        bucket = Some(group.1)
      }
    }
    match bucket {
      Some(existing) => existing.push(row)
      None => groups.push((row.model_id, [row]))
    }
  }
  groups
}

///|
fn models_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let detached_imports = state.model_imports.filter(import_ => {
    registered_model_for_import(state.models, import_) is None &&
    !state.model_source_results.any(candidate => {
      match model_import_for(state.model_imports, candidate.id) {
        Some(visible) => visible.import_id == import_.import_id
        None => false
      }
    })
  })
  let registered_models = group_models_by_model_id(state.models)
  @html.section(attrs=@html.Attrs::build().aria_labelledby("models-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="models-title",
          localized(state.locale, "Model registry", "模型注册表"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Review serving eligibility, evaluation posture, and approved aliases.",
            "检查服务资格、评测状态和已批准的模型别名。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{registered_models.length()} models · \{state.models.length()} artifacts",
          "\{registered_models.length()} 个模型 · \{state.models.length()} 个制品",
        ),
      ),
    ]),
    @html.div(class="operation-panel model-onboarding-panel", [
      @html.div(class="operation-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(state.locale, "ModelScope catalog", "魔搭模型库"),
          ),
          @html.h3(
            localized(
              state.locale,
              "Find and import a model",
              "查找并导入模型",
            ),
          ),
        ]),
        @html.span(
          class="status status-pending",
          localized(state.locale, "Operator workflow", "运维工作流"),
        ),
      ]),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "Search ModelScope, download an exact revision into the governed model store, verify every declared SHA-256, then accept its license, verify the artifact and approve it. Evaluation can be recorded later without blocking publication.",
          "从魔搭搜索模型，将精确版本下载到受治理的模型库并验证每个文件的 SHA-256；接受许可证、验证制品并批准后即可发布。评测可随后记录，不阻塞发布。",
        ),
      ),
      @html.ol(class="deployment-steps model-onboarding-steps", [
        @html.li([
          @html.span("1"),
          @html.strong(
            localized(state.locale, "Search catalog", "搜索模型库"),
          ),
        ]),
        @html.li([
          @html.span("2"),
          @html.strong(
            localized(state.locale, "Download & checksum", "下载并校验"),
          ),
        ]),
        @html.li([
          @html.span("3"),
          @html.strong(
            localized(
              state.locale,
              "License & verification",
              "许可与制品验证",
            ),
          ),
        ]),
        @html.li([
          @html.span("4"),
          @html.strong(
            localized(
              state.locale,
              "Approve for users",
              "批准供用户使用",
            ),
          ),
        ]),
      ]),
      @html.div(class="model-source-search", [
        @html.label(
          for_="model-source-query",
          localized(state.locale, "Search ModelScope", "搜索魔搭模型"),
        ),
        @html.input(
          id="model-source-query",
          input_type=Text,
          maxlength=120,
          value=state.model_source_query,
          on_input=text_command(emit, value => ModelSourceQueryChanged(value)),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!state.operator_authenticated ||
            state.model_source_query.trim() == "" ||
            state.loading,
          on_click=command(emit, SearchModelSource),
          localized(state.locale, "Search", "搜索"),
        ),
      ]),
      model_local_registration_form(state, emit),
      @html.div(class="operation-actions", [
        @html.span(
          class="secondary",
          if state.operator_authenticated {
            localized(
              state.locale,
              "Downloads are durable; checksum verification is not signature approval.",
              "下载任务可持久恢复；校验和验证不等于签名批准。",
            )
          } else {
            localized(
              state.locale,
              "Sign in with operator authority to browse and import models.",
              "请使用运维权限登录后浏览并导入模型。",
            )
          },
        ),
        @html.button(
          type_="button",
          class="secondary-button",
          disabled=!state.operator_authenticated || state.loading,
          on_click=command(emit, RefreshModelImports),
          localized(state.locale, "Refresh downloads", "刷新下载任务"),
        ),
      ]),
      if state.model_source_results.length() == 0 {
        @html.div(class="model-source-hint", [
          @html.strong(
            localized(
              state.locale,
              "Search by model or organization",
              "按模型或组织搜索",
            ),
          ),
          @html.span(
            localized(
              state.locale,
              "Try MiniCPM, Qwen, embedding, or OpenBMB.",
              "可尝试 MiniCPM、Qwen、embedding 或 OpenBMB。",
            ),
          ),
        ])
      } else {
        @html.div(
          class="model-source-results",
          [
            for candidate in state.model_source_results => {
              let import_ = model_import_for(state.model_imports, candidate.id)
              @html.article(class="model-source-card", [
                @html.div(class="model-source-card-heading", [
                  @html.div([
                    @html.strong(candidate.display_name),
                    @html.span(class="mono secondary", candidate.id),
                  ]),
                  @html.span(
                    class="status status-neutral",
                    if candidate.license == "" {
                      localized(
                        state.locale,
                        "License unspecified",
                        "未声明许可证",
                      )
                    } else {
                      candidate.license
                    },
                  ),
                ]),
                @html.p(
                  class="section-copy",
                  if candidate.description == "" {
                    localized(
                      state.locale,
                      "No catalog description.",
                      "模型库未提供简介。",
                    )
                  } else {
                    candidate.description
                  },
                ),
                @html.div(class="model-source-facts", [
                  @html.span(model_source_size(candidate.file_size)),
                  @html.span("\{candidate.params / 1000000L}M params"),
                  @html.span("↓ \{candidate.downloads}"),
                  @html.span(candidate.tasks.join(", ")),
                ]),
                match import_ {
                  Some(value) =>
                    @html.div(class="model-import-status", [
                      @html.div([
                        @html.strong(
                          model_import_label(state.locale, value.state),
                        ),
                        @html.span(
                          class="secondary mono",
                          "\{model_import_progress(value)}% · \{value.files_completed}/\{value.files_total}",
                        ),
                      ]),
                      @html.div(class="model-import-track", [
                        @html.span(
                          class="model-import-fill",
                          style=["width: \{model_import_progress(value)}%"],
                          "",
                        ),
                      ]),
                      if value.state == Downloading || value.state == Queued {
                        @html.button(
                          type_="button",
                          class="secondary-button danger-button",
                          disabled=value.cancel_requested || state.loading,
                          on_click=command(
                            emit,
                            CancelModelImport(value.import_id),
                          ),
                          if value.cancel_requested {
                            localized(
                              state.locale,
                              "Cancelling…",
                              "正在取消…",
                            )
                          } else {
                            localized(state.locale, "Cancel", "取消")
                          },
                        )
                      } else if value.state == Verified {
                        verified_import_gate(state, value, emit)
                      } else {
                        @html.div(class="model-import-recovery", [
                          @html.span(class="danger-copy", value.error_code),
                          @html.button(
                            type_="button",
                            class="secondary-button",
                            disabled=state.loading,
                            on_click=command(
                              emit,
                              RetryModelImport(value.import_id),
                            ),
                            localized(state.locale, "Retry", "重试"),
                          ),
                        ])
                      },
                    ])
                  None =>
                    @html.button(
                      type_="button",
                      class="primary-button",
                      disabled=candidate.private ||
                        candidate.gated ||
                        state.loading,
                      on_click=command(emit, DownloadModelSource(candidate.id)),
                      localized(state.locale, "Download", "下载"),
                    )
                },
              ])
            }
          ],
        )
      },
      if detached_imports.length() == 0 {
        @html.nothing
      } else {
        @html.section(
          class="detached-imports",
          attrs=@html.Attrs::build().aria_labelledby("recent-imports-title"),
          [
            @html.div(class="detached-imports-heading", [
              @html.h4(
                id="recent-imports-title",
                localized(
                  state.locale,
                  "Imports awaiting a next action",
                  "等待后续操作的导入",
                ),
              ),
              @html.span(
                class="secondary",
                localized(
                  state.locale,
                  "Visible after refresh or sign-in without repeating a catalog search.",
                  "刷新或重新登录后无需再次搜索模型库即可查看。",
                ),
              ),
            ]),
            @html.div(
              class="detached-import-list",
              [
                for import_ in detached_imports => {
                  @html.article(class="detached-import-row", [
                    @html.div(class="model-source-card-heading", [
                      @html.div([
                        @html.strong(import_.model_id),
                        @html.span(
                          class="mono secondary",
                          "\{import_.revision} · \{import_.import_id}",
                        ),
                      ]),
                      @html.span(
                        class="status status-neutral",
                        model_import_label(state.locale, import_.state),
                      ),
                    ]),
                    @html.div(class="model-source-facts", [
                      @html.span(model_source_size(import_.bytes_total)),
                      @html.span(
                        if import_.license == "" {
                          localized(
                            state.locale,
                            "License unspecified",
                            "未声明许可证",
                          )
                        } else {
                          import_.license
                        },
                      ),
                      @html.span(
                        model_import_transport_label(state.locale, import_),
                      ),
                    ]),
                    @html.div(class="model-import-status", [
                      @html.div([
                        @html.strong(
                          localized(
                            state.locale,
                            "Import progress",
                            "导入进度",
                          ),
                        ),
                        @html.span(
                          class="secondary mono",
                          "\{model_import_progress(import_)}% · \{import_.files_completed}/\{import_.files_total}",
                        ),
                      ]),
                      @html.div(class="model-import-track", [
                        @html.span(
                          class="model-import-fill",
                          style=["width: \{model_import_progress(import_)}%"],
                          "",
                        ),
                      ]),
                      if import_.state == Downloading ||
                        import_.state == Queued ||
                        import_.state == Verifying {
                        @html.button(
                          type_="button",
                          class="secondary-button danger-button",
                          disabled=import_.cancel_requested || state.loading,
                          on_click=command(
                            emit,
                            CancelModelImport(import_.import_id),
                          ),
                          if import_.cancel_requested {
                            localized(
                              state.locale,
                              "Cancelling…",
                              "正在取消…",
                            )
                          } else {
                            localized(state.locale, "Cancel", "取消")
                          },
                        )
                      } else if import_.state == Verified {
                        verified_import_gate(state, import_, emit)
                      } else {
                        @html.div(class="model-import-recovery", [
                          @html.span(
                            class="danger-copy",
                            if import_.error_code == "" {
                              model_import_label(state.locale, import_.state)
                            } else {
                              import_.error_code
                            },
                          ),
                          @html.button(
                            type_="button",
                            class="secondary-button",
                            disabled=state.loading,
                            on_click=command(
                              emit,
                              RetryModelImport(import_.import_id),
                            ),
                            localized(state.locale, "Retry", "重试"),
                          ),
                        ])
                      },
                    ]),
                  ])
                }
              ],
            ),
          ],
        )
      },
    ]),
    if state.models.length() == 0 {
      @html.div(class="empty-state empty-state-action", [
        @html.strong(
          localized(
            state.locale,
            "No models registered yet",
            "尚未登记模型",
          ),
        ),
        @html.p(
          localized(
            state.locale,
            "Search ModelScope above and start a download. Licensed, verified and explicitly approved models can appear in the user catalog; evaluation is optional evidence.",
            "请在上方搜索魔搭并开始下载。接受许可、验证制品并明确批准后，模型即可进入用户目录；评测是可选证据。",
          ),
        ),
      ])
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Registered model artifacts",
              "已注册模型制品",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Model", "模型")),
              @html.th(
                scope=Col,
                localized(state.locale, "Lifecycle", "生命周期"),
              ),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(
                scope=Col,
                localized(state.locale, "Compatibility", "兼容性"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Serving alias", "服务模型别名"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
            ]),
          ),
          @html.tbody(model_artifact_rows(state, emit, registered_models)),
        ]),
      ])
    },
  ])
}

///|
/// Registry table body: one heading naming the model, then one row per
/// registered artifact of that model. Heading a model's artifacts keeps the
/// table readable when one model carries several qualification profiles.
fn model_artifact_rows(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  groups : Array[(String, Array[ModelRow])],
) -> Array[@rabbita.Html] {
  let body : Array[@rabbita.Html] = []
  for group in groups {
    let (model_id, artifacts) = group
    body.push(
      @html.tr(class="models-group-heading", [
        @html.th(scope=RowGroup, colspan=6, [
          @html.strong(model_id),
          @html.span(
            class="secondary",
            localized(
              state.locale,
              "\{artifacts.length()} registered artifacts",
              "\{artifacts.length()} 个已注册制品",
            ),
          ),
        ]),
      ]),
    )
    for model in artifacts {
      for row in model_item(state, model, emit) {
        body.push(row)
      }
    }
  }
  body
}

///|
fn model_item(
  state : ConsoleState,
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> Array[@rabbita.Html] {
  let locale = state.locale
  let rows : Array[@rabbita.Html] = [
    @html.tr([
      @html.td([
        @html.strong(model.model_id),
        @html.span(class="mono secondary", model.version),
      ]),
      @html.td(model_state_badge(locale, model.state)),
      @html.td([
        @html.span(
          localized(
            locale,
            "License · \{license_evidence_label(locale, model.license_status)}",
            "许可证 · \{license_evidence_label(locale, model.license_status)}",
          ),
        ),
        @html.span(
          class="secondary",
          localized(
            locale,
            "Optional evaluation · \{evaluation_evidence_label(locale, model.evaluation_status)}",
            "可选评测 · \{evaluation_evidence_label(locale, model.evaluation_status)}",
          ),
        ),
      ]),
      @html.td(model.compatibility),
      @html.td(class="mono", model.alias_name),
      @html.td(model_candidate_actions(state, model, emit)),
    ]),
  ]
  if state.model_license_draft.model_id == model.model_id &&
    state.model_license_draft.version == model.version {
    rows.push(model_license_form_row(state, model, emit))
  }
  if state.model_alias_draft.model_id == model.model_id &&
    state.model_alias_draft.version == model.version {
    rows.push(model_alias_form_row(state, model, emit))
  }
  rows
}

///|
/// The per-candidate actions the registry already exposes. None of them is
/// disabled for looking premature: the registry owns the order and answers an
/// early step with its own refusal, which the console reports verbatim.
fn model_candidate_actions(
  state : ConsoleState,
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  let offered = state.operator_authenticated && !state.loading
  @html.div(class="row-actions model-candidate-actions", [
    @html.button(
      type_="button",
      class="secondary-button",
      disabled=!offered,
      on_click=command(
        emit,
        BeginLicenseAcceptance(model.model_id, model.version),
      ),
      localized(locale, "Accept licence…", "接受许可证…"),
    ),
    @html.button(
      type_="button",
      class="secondary-button",
      disabled=!offered,
      on_click=command(emit, VerifyModelArtifact(model.model_id, model.version)),
      localized(locale, "Verify artifact", "验证制品"),
    ),
    @html.button(
      type_="button",
      class="secondary-button",
      disabled=!offered,
      on_click=command(emit, ApproveModelVersion(model.model_id, model.version)),
      localized(locale, "Approve", "批准"),
    ),
    @html.button(
      type_="button",
      class="secondary-button",
      disabled=!offered,
      on_click=command(emit, BeginAliasPromotion(model.model_id, model.version)),
      localized(locale, "Promote alias…", "提升别名…"),
    ),
    if model.alias_name == "—" {
      @html.span(
        class="secondary",
        localized(locale, "No alias", "无模型别名"),
      )
    } else {
      @html.button(
        type_="button",
        class="danger-secondary",
        on_click=command(emit, BeginRollback(model.alias_name)),
        localized(locale, "Roll back…", "回滚…"),
      )
    },
  ])
}

///|
/// The licence citation is operator text: the console prefills a
/// `modelscope-license:` reference derived from the model's declared licence
/// and never fabricates a path or digest.
fn model_license_form_row(
  state : ConsoleState,
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  let draft = state.model_license_draft
  let valid = model_license_draft_valid(draft)
  let license_invalid = draft.license_id != "" &&
    !@contracts.valid_identifier(
      draft.license_id.trim().to_owned(),
      maximum_length=128,
    )
  let evidence_missing = draft.evidence_ref.trim() == ""
  @html.tr(class="model-onboarding-form-row", [
    @html.td(colspan=6, [
      @html.form(
        class="model-onboarding-form",
        on_submit=command(emit, SubmitModelLicense),
        attrs=@html.Attrs::build().aria_labelledby("model-license-title"),
        [
          @html.fieldset(disabled=state.loading, [
            @html.legend(
              id="model-license-title",
              localized(
                locale,
                "Accept licence for \{model.model_id} · \{model.version}",
                "接受 \{model.model_id} · \{model.version} 的许可证",
              ),
            ),
            @html.p(
              class="field-help",
              localized(
                locale, "Records an accepted licence for this exact model version. Artifact verification and explicit approval remain separate checks; evaluation is optional.",
                "为这一精确模型版本记录已接受的许可证。制品验证与明确批准仍需分别完成；评测可选。",
              ),
            ),
            @html.div(class="model-onboarding-grid", [
              @html.div(class="field-group", [
                @html.label(
                  for_="model-license-id",
                  localized(locale, "Licence record ID", "许可证记录 ID"),
                ),
                @html.input(
                  id="model-license-id",
                  input_type=Text,
                  required=true,
                  maxlength=128,
                  placeholder="license.minicpm5-apache",
                  value=draft.license_id,
                  attrs=@html.Attrs::build()
                    .aria_describedby("model-license-id-help")
                    .aria_invalid(
                      if license_invalid {
                        "true"
                      } else {
                        "false"
                      },
                    ),
                  on_input=text_command(emit, value => {
                    LicenseRecordIdChanged(value)
                  }),
                ),
                @html.p(
                  id="model-license-id-help",
                  class=if license_invalid {
                    "field-help field-error"
                  } else {
                    "field-help"
                  },
                  localized(
                    locale, "Stable letters, numbers, dots, colons, hyphens, or underscores.",
                    "使用稳定的字母、数字、点、冒号、连字符或下划线。",
                  ),
                ),
              ]),
              @html.div(class="field-group", [
                @html.label(
                  for_="model-license-evidence",
                  localized(
                    locale, "Licence evidence citation", "许可证证据引用",
                  ),
                ),
                @html.input(
                  id="model-license-evidence",
                  input_type=Text,
                  required=true,
                  maxlength=256,
                  value=draft.evidence_ref,
                  attrs=@html.Attrs::build()
                    .aria_describedby("model-license-evidence-help")
                    .aria_invalid(
                      if evidence_missing {
                        "true"
                      } else {
                        "false"
                      },
                    ),
                  on_input=text_command(emit, value => {
                    LicenseEvidenceChanged(value)
                  }),
                ),
                @html.p(
                  id="model-license-evidence-help",
                  class=if evidence_missing {
                    "field-help field-error"
                  } else {
                    "field-help"
                  },
                  localized(
                    locale, "Free-form operator citation taken from the model's declared licence; no path or digest is invented here.",
                    "自由填写的运维引用，取自模型声明的许可证；此处不会虚构路径或摘要。",
                  ),
                ),
              ]),
            ]),
            @html.div(class="row-actions", [
              @html.button(
                type_="button",
                class="secondary-button",
                disabled=state.loading,
                on_click=command(emit, DismissLicenseAcceptance),
                localized(locale, "Cancel", "取消"),
              ),
              @html.button(
                type_="submit",
                class="primary-button",
                disabled=!valid || state.loading,
                localized(locale, "Accept licence", "接受许可证"),
              ),
            ]),
          ]),
        ],
      ),
    ]),
  ])
}

///|
fn model_alias_form_row(
  state : ConsoleState,
  model : ModelRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  let draft = state.model_alias_draft
  let valid = model_alias_draft_valid(draft)
  let alias_invalid = draft.alias_name != "" &&
    !@contracts.valid_identifier(
      draft.alias_name.trim().to_owned(),
      maximum_length=128,
    )
  @html.tr(class="model-onboarding-form-row", [
    @html.td(colspan=6, [
      @html.form(
        class="model-onboarding-form",
        on_submit=command(emit, SubmitAliasPromotion),
        attrs=@html.Attrs::build().aria_labelledby("model-alias-title"),
        [
          @html.fieldset(disabled=state.loading, [
            @html.legend(
              id="model-alias-title",
              localized(
                locale,
                "Promote \{model.model_id} · \{model.version} onto an alias",
                "将 \{model.model_id} · \{model.version} 提升到别名",
              ),
            ),
            @html.p(
              class="field-help",
              localized(
                locale, "Publishes a Canary alias for the approved version. A version the registry has not approved is refused, and that refusal is shown here.",
                "为已批准版本发布 Canary 别名。注册表尚未批准的版本会被拒绝，拒绝原因会显示在此处。",
              ),
            ),
            @html.div(class="model-onboarding-grid", [
              @html.div(class="field-group", [
                @html.label(
                  for_="model-alias-name",
                  localized(locale, "Serving alias", "服务别名"),
                ),
                @html.input(
                  id="model-alias-name",
                  input_type=Text,
                  required=true,
                  maxlength=128,
                  placeholder="text.default",
                  value=draft.alias_name,
                  attrs=@html.Attrs::build()
                    .aria_describedby("model-alias-name-help")
                    .aria_invalid(if alias_invalid { "true" } else { "false" }),
                  on_input=text_command(emit, value => AliasNameChanged(value)),
                ),
                @html.p(
                  id="model-alias-name-help",
                  class=if alias_invalid {
                    "field-help field-error"
                  } else {
                    "field-help"
                  },
                  localized(
                    locale, "Stable letters, numbers, dots, colons, hyphens, or underscores.",
                    "使用稳定的字母、数字、点、冒号、连字符或下划线。",
                  ),
                ),
              ]),
            ]),
            @html.div(class="row-actions", [
              @html.button(
                type_="button",
                class="secondary-button",
                disabled=state.loading,
                on_click=command(emit, DismissAliasPromotion),
                localized(locale, "Cancel", "取消"),
              ),
              @html.button(
                type_="submit",
                class="primary-button",
                disabled=!valid || state.loading,
                localized(locale, "Promote alias", "提升别名"),
              ),
            ]),
          ]),
        ],
      ),
    ]),
  ])
}

///|
fn quick_service_name_valid(value : String) -> Bool {
  @contracts.valid_identifier(value.trim().to_owned(), maximum_length=128)
}

///|
/// The machine geometry a one-click deployment asks for. LunaNexa admits
/// exactly two: one machine, or the validated CX7 pair.
pub(all) enum QuickTopology {
  SingleMachine
  Cx7Pair
} derive(Debug, Eq)

///|
pub extend QuickTopology with Debug::{to_repr}

///|
pub extend QuickTopology with Eq::{not_equal, equal}

///|
/// Stable storage value for the topology picker, so the control survives locale
/// changes and the demo snapshot.
pub fn QuickTopology::storage_value(self : QuickTopology) -> String {
  match self {
    SingleMachine => "single-machine"
    Cx7Pair => "cx7-pair"
  }
}

///|
pub fn parse_quick_topology(value : String) -> QuickTopology {
  match value {
    "cx7-pair" => Cx7Pair
    _ => SingleMachine
  }
}

///|
pub fn QuickTopology::label(
  self : QuickTopology,
  locale : @i18n.Locale,
) -> String {
  match self {
    SingleMachine => @i18n.copy(locale, "One machine", "单机")
    Cx7Pair =>
      @i18n.copy(
        locale, "CX7 pair (two machines)", "CX7 双机对（两台机器）",
      )
  }
}

///|
/// The intent field this choice maps to. `None` is one machine; the CX7 pair is
/// the only admitted multi-node profile.
pub fn QuickTopology::topology_profile(self : QuickTopology) -> String? {
  match self {
    SingleMachine => None
    Cx7Pair => Some(@contracts.cx7_pair_topology_profile)
  }
}

///|
pub fn template_flag_id(flag : TemplateFlag) -> String {
  match flag {
    RuntimeMultiNode => "template-runtime-multi-node"
    CaptureForEvaluation => "template-capture-for-evaluation"
    AllowCache => "template-allow-cache"
    AllowTrainingReuse => "template-allow-training-reuse"
    AutomaticPromotion => "template-automatic-promotion"
    AutomaticRollback => "template-automatic-rollback"
  }
}

///|
pub fn template_flag_value(draft : TemplateDraft, flag : TemplateFlag) -> Bool {
  match flag {
    RuntimeMultiNode => draft.runtime_multi_node
    CaptureForEvaluation => draft.capture_for_evaluation
    AllowCache => draft.allow_cache
    AllowTrainingReuse => draft.allow_training_reuse
    AutomaticPromotion => draft.automatic_promotion
    AutomaticRollback => draft.automatic_rollback
  }
}

///|
pub fn template_flag_label(
  locale : @i18n.Locale,
  flag : TemplateFlag,
) -> String {
  match flag {
    RuntimeMultiNode =>
      localized(locale, "Runtime supports multi-node", "运行时支持多机")
    CaptureForEvaluation =>
      localized(
        locale, "Capture payloads for evaluation", "为评测采集载荷",
      )
    AllowCache => localized(locale, "Allow cache", "允许缓存")
    AllowTrainingReuse =>
      localized(locale, "Allow training reuse", "允许训练复用")
    AutomaticPromotion =>
      localized(locale, "Automatic promotion", "自动提升")
    AutomaticRollback => localized(locale, "Automatic rollback", "自动回滚")
  }
}

///|
pub fn template_draft_with_text(
  draft : TemplateDraft,
  field : TemplateField,
  value : String,
) -> TemplateDraft {
  match field {
    TemplateId => { ..draft, template_id: value, }
    TemplateVersion => { ..draft, version: value, }
    TemplateDisplayName => { ..draft, display_name: value, }
    TemplateDescription => { ..draft, description: value, }
    TemplateModelSelector => { ..draft, model_selector: value, }
    TemplateArtifactUri => { ..draft, artifact_uri: value, }
    TemplateArtifactDigest => { ..draft, artifact_digest: value, }
    TemplateArtifactSizeBytes => { ..draft, artifact_size_bytes: value, }
    TemplateArtifactSignatureRef => { ..draft, artifact_signature_ref: value, }
    TemplateRuntimeName => { ..draft, runtime_name: value, }
    TemplateRuntimeVersion => { ..draft, runtime_version: value, }
    TemplateRuntimeImageDigest => { ..draft, runtime_image_digest: value, }
    TemplateRuntimeArchitectures => { ..draft, runtime_architectures: value, }
    TemplateArchitecture => { ..draft, architecture: value, }
    TemplateAcceleratorCount => { ..draft, accelerator_count: value, }
    TemplateAcceleratorMemoryMib => { ..draft, accelerator_memory_mib: value, }
    TemplateCpuMillis => { ..draft, cpu_millis: value, }
    TemplateMemoryMib => { ..draft, memory_mib: value, }
    TemplateReadinessPath => { ..draft, readiness_path: value, }
    TemplateHealthIntervalMs => { ..draft, health_interval_ms: value, }
    TemplateFailureThreshold => { ..draft, failure_threshold: value, }
    TemplateTerminationGraceMs => { ..draft, termination_grace_ms: value, }
    TemplateConsentReceipt => { ..draft, evaluation_consent_receipt: value, }
    TemplateSecretRefs => { ..draft, secret_refs: value, }
    TemplateCanaryReplicas => { ..draft, canary_replicas: value, }
    TemplateReadinessTimeoutMs => { ..draft, readiness_timeout_ms: value, }
  }
}

///|
/// Turn one switch on or off. Clearing an evaluation capture clears the two
/// reuse switches with it: an ephemeral template may neither cache a payload
/// nor reuse it for training, so leaving them set would only strand the form in
/// a state the planner refuses.
pub fn template_draft_with_flag(
  draft : TemplateDraft,
  flag : TemplateFlag,
  value : Bool,
) -> TemplateDraft {
  match flag {
    RuntimeMultiNode => { ..draft, runtime_multi_node: value, }
    CaptureForEvaluation =>
      if value {
        { ..draft, capture_for_evaluation: true, }
      } else {
        {
          ..draft,
          capture_for_evaluation: false,
          allow_cache: false,
          allow_training_reuse: false,
        }
      }
    AllowCache => { ..draft, allow_cache: value, }
    AllowTrainingReuse => { ..draft, allow_training_reuse: value, }
    AutomaticPromotion => { ..draft, automatic_promotion: value, }
    AutomaticRollback => { ..draft, automatic_rollback: value, }
  }
}

///|
/// The serving capabilities a template may declare. The console's own set is
/// narrowed to what the chosen runtime declares, so a template cannot name a
/// capability its runtime does not serve.
fn template_capability_choices(
  runtime : @contracts.RuntimeSpec?,
) -> Array[@contracts.Capability] {
  match runtime {
    None => runtime_capability_options()
    Some(spec) => {
      let declared = runtime_capability_options().filter(capability => {
        spec.capabilities.contains(capability)
      })
      if declared.length() == 0 {
        runtime_capability_options()
      } else {
        declared
      }
    }
  }
}

///|
/// One labelled select of the template form.
fn template_select_group(
  locale : @i18n.Locale,
  id : String,
  label_en : String,
  label_zh : String,
  help_en : String,
  help_zh : String,
  options : Array[@rabbita.Html],
  on_change : @rabbita.Emit[String],
) -> @rabbita.Html {
  @html.div(class="field-group", [
    @html.label(for_=id, localized(locale, label_en, label_zh)),
    @html.select(
      id~,
      on_change~,
      attrs=@html.Attrs::build().aria_describedby("\{id}-help"),
      options,
    ),
    @html.p(
      id="\{id}-help",
      class="field-help",
      localized(locale, help_en, help_zh),
    ),
  ])
}

///|
/// One text control of the template form. The rule it carries is the planner's
/// own, and the help text says the same thing in words, so a value that turns
/// red here is one the control plane would have refused.
fn template_field_group(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  draft : TemplateDraft,
  spec : TemplateFieldSpec,
) -> @rabbita.Html {
  let id = template_field_id(spec.field)
  let value = template_field_value(draft, spec.field)
  let invalid = (value != "" && !template_field_acceptable(draft, spec)) ||
    (
      spec.field == TemplateConsentReceipt &&
      draft.capture_for_evaluation &&
      value.trim() == ""
    )
  let attrs = @html.Attrs::build()
    .aria_describedby("\{id}-help")
    .aria_invalid(if invalid { "true" } else { "false" })
  let on_input = text_command(emit, text => {
    TemplateTextChanged(spec.field, text)
  })
  @html.div(class="field-group", [
    @html.label(for_=id, localized(state.locale, spec.label_en, spec.label_zh)),
    // A bounded field is a text control with a numeric keypad: the bound is the
    // planner's, so it is enforced by the rule below rather than by the
    // browser, which would answer in the wrong language.
    @html.input(
      id~,
      input_type=Text,
      inputmode=if spec.kind is FreeText { "text" } else { "numeric" },
      required=!spec.optional,
      placeholder=spec.placeholder,
      value~,
      attrs~,
      on_input~,
    ),
    @html.p(
      id="\{id}-help",
      class=if invalid { "field-help field-error" } else { "field-help" },
      localized(state.locale, spec.help_en, spec.help_zh),
    ),
  ])
}

///|
/// One row of switches. The two reuse switches only mean anything inside an
/// evaluation capture, so they are drawn disabled while the template keeps its
/// payloads ephemeral.
fn template_flag_row(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  draft : TemplateDraft,
  flags : Array[TemplateFlag],
) -> @rabbita.Html {
  @html.div(
    class="runtime-profile-flags",
    [
      for flag in flags => {
        let capture_only = flag == AllowCache || flag == AllowTrainingReuse
        @html.label(class="runtime-profile-flag", for_=template_flag_id(flag), [
          @html.input(
            input_type=Checkbox,
            id=template_flag_id(flag),
            checked=template_flag_value(draft, flag),
            attrs=@html.Attrs::build().disabled(
              capture_only && !draft.capture_for_evaluation,
            ),
            on_change=text_command(emit, _ => TemplateFlagToggled(flag)),
          ),
          @html.span(template_flag_label(state.locale, flag)),
        ])
      }
    ],
  )
}

///|
/// The operator-facing catalog-template registration the deployment service
/// already accepts. The client mirrors the planner's shape checks so the
/// console never offers a template the control plane would refuse as malformed;
/// whether the model, the runtime, the licence and the hardware admit it stays
/// the preflight's answer. The model and runtime pickers exist because both are
/// already in state: a model row carries the artifact the registry attested,
/// and the runtime roster carries the image digest it admitted.
fn template_registration_form(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  let draft = state.template_draft
  let valid = template_draft_valid(draft)
  let runtimes = known_runtimes(state)
  let selected_runtime = runtimes
    .iter()
    .find_first(runtime => {
      runtime_key(runtime) == "\{draft.runtime_name}@\{draft.runtime_version}"
    })
  let model_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=draft.model_id == "",
      localized(locale, "Select a registered model", "选择已注册模型"),
    ),
  ]
  for row in state.models {
    model_options.push(
      @html.option(
        value="\{row.model_id}@\{row.version}",
        selected=draft.model_id == row.model_id &&
          draft.model_version == row.version,
        "\{row.model_id} · \{row.version} · \{row.alias_name}",
      ),
    )
  }
  let runtime_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=draft.runtime_name == "",
      localized(
        locale, "Select a registered runtime", "选择已注册运行时",
      ),
    ),
  ]
  for runtime in runtimes {
    runtime_options.push(
      @html.option(
        value=runtime_key(runtime),
        selected=runtime_key(runtime) ==
          "\{draft.runtime_name}@\{draft.runtime_version}",
        "\{runtime.name} · \{runtime.version} · \{runtime.architectures.join(", ")}",
      ),
    )
  }
  let sections : Array[@rabbita.Html] = []
  for section in template_section_order() {
    let fields : Array[@rabbita.Html] = []
    if section == TemplateDataPolicy {
      fields.push(
        template_select_group(
          locale,
          "template-classification",
          "Data classification",
          "数据分类",
          "The class of the payloads this service will carry.",
          "该服务将承载的载荷类别。",
          [
            for classification in data_class_options() => {
              @html.option(
                value=data_class_name(classification),
                selected=classification == draft.classification,
                data_class_label(locale, classification),
              )
            }
          ],
          text_command(emit, value => TemplateClassificationChanged(value)),
        ),
      )
    }
    for spec in template_field_specs() {
      if spec.section == section {
        fields.push(template_field_group(state, emit, draft, spec))
      }
    }
    if section == TemplateRuntime {
      fields.push(
        template_select_group(
          locale,
          "template-capability",
          "Serving capability",
          "服务能力",
          "The capability this template serves. Only what the chosen runtime declares is offered.",
          "本模板提供的能力。仅提供所选运行时所声明的能力。",
          [
            for capability in template_capability_choices(selected_runtime) => {
              @html.option(
                value=runtime_capability_name(capability),
                selected=capability == draft.capability,
                runtime_capability_label(locale, capability),
              )
            }
          ],
          text_command(emit, value => TemplateCapabilityChanged(value)),
        ),
      )
    }
    let body : Array[@rabbita.Html] = [
      @html.legend(template_section_legend(locale, section)),
      @html.div(class="model-onboarding-grid", fields),
    ]
    match section {
      TemplateRuntime =>
        body.push(template_flag_row(state, emit, draft, [RuntimeMultiNode]))
      TemplateDataPolicy =>
        body.push(
          template_flag_row(state, emit, draft, [
            CaptureForEvaluation,
            AllowCache,
            AllowTrainingReuse,
          ]),
        )
      TemplateRollout =>
        body.push(
          template_flag_row(state, emit, draft, [
            AutomaticPromotion,
            AutomaticRollback,
          ]),
        )
      _ => ()
    }
    sections.push(@html.fieldset(class="template-registration-section", body))
  }
  // The pickers come first because both halves of the template are already in
  // state: a model row carries the artifact the registry attested, and the
  // runtime roster carries the image digest the registry admitted.
  let body : Array[@rabbita.Html] = [
    @html.legend(
      id="template-registration-title",
      localized(
        locale, "Start from a registered model and runtime", "从已注册的模型与运行时开始",
      ),
    ),
    @html.div(class="model-onboarding-grid", [
      template_select_group(
        locale,
        "template-model-picker",
        "Model",
        "模型",
        "Fills the model identity and the artifact the registry attested for it.",
        "填入模型身份以及注册表为其证明的制品。",
        model_options,
        text_command(emit, value => TemplateModelSelected(value)),
      ),
      template_select_group(
        locale,
        "template-runtime-picker",
        "Runtime",
        "运行时",
        "Fills the runtime image, its architectures and the capability it serves.",
        "填入运行时镜像、其架构以及它提供的能力。",
        runtime_options,
        text_command(emit, value => TemplateRuntimeSelected(value)),
      ),
    ]),
  ]
  body.push_iter(sections.iter())
  body.push(
    @html.div(class="operation-actions", [
      @html.span(
        class="secondary",
        if valid {
          localized(
            locale, "The receipt and signature are the control plane's own; the caller submits neither.",
            "回执与签名由控制平面生成；调用方两者都不提交。",
          )
        } else {
          localized(
            locale, "Submittable when every field matches its rule, the accelerator architecture appears in the runtime architectures, and the capability is one the runtime serves.",
            "当每个字段符合其规则、加速器架构出现在运行时架构中，且能力为运行时实际提供的能力时，方可提交。",
          )
        },
      ),
      @html.button(
        type_="submit",
        class="primary-button",
        disabled=!state.operator_authenticated || !valid || state.loading,
        localized(locale, "Register template", "注册模板"),
      ),
    ]),
  )
  @html.div(class="operation-panel template-registration-panel", [
    @html.div(class="operation-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          localized(locale, "Catalog templates", "目录模板"),
        ),
        @html.h3(
          localized(locale, "Register a catalog template", "注册目录模板"),
        ),
      ]),
      @html.span(
        class="status status-pending",
        localized(locale, "Preflight still applies", "仍需通过预检"),
      ),
    ]),
    @html.p(
      class="section-copy",
      localized(
        locale, "Registers one immutable model-service template. The control plane signs it, so registration alone deploys nothing: the model, the runtime, the licence and the hardware are still checked before any workload is placed.",
        "注册一个不可变的模型服务模板。控制平面会对其签名，因此仅注册不会部署任何内容：在放置任何工作负载之前，仍会检查模型、运行时、许可证与硬件。",
      ),
    ),
    @html.form(
      class="template-registration-form",
      on_submit=command(emit, SubmitTemplateRegistration),
      attrs=@html.Attrs::build().aria_labelledby("template-registration-title"),
      [@html.fieldset(disabled=state.loading, body)],
    ),
  ])
}

///|
fn catalog_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let template_options : Array[@rabbita.Html] = [
    @html.option(
      value="",
      selected=state.quick_template == "",
      localized(state.locale, "Select a template", "选择模板"),
    ),
  ]
  for template in state.catalog_templates {
    template_options.push(
      @html.option(
        value="\{template.template_id}@\{template.version}",
        selected=state.quick_template ==
          "\{template.template_id}@\{template.version}",
        "\{template.display_name} · \{template.version}",
      ),
    )
  }
  let service_name_present = state.quick_deployment_id.trim() != ""
  let service_name_valid = quick_service_name_valid(state.quick_deployment_id)
  @html.section(attrs=@html.Attrs::build().aria_labelledby("catalog-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="catalog-title",
          localized(state.locale, "Model service catalog", "模型服务目录"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Deploy an approved, immutable model-service template through one governed intent.",
            "通过一个受治理的意图部署已批准且不可变的模型服务模板。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.catalog_templates.length()} templates",
          "\{state.catalog_templates.length()} 个模板",
        ),
      ),
    ]),
    @html.div(class="operation-panel", [
      @html.div(class="operation-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(state.locale, "Governed deployment", "受治理的部署"),
          ),
          @html.h3(
            localized(
              state.locale,
              "One-click model service",
              "一键模型服务",
            ),
          ),
        ]),
        @html.span(
          class="status status-pending",
          localized(state.locale, "Preflight enforced", "强制预检"),
        ),
      ]),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "License, verification, alias, secret, data-class and capacity blockers are checked before any assignment is published. Optional evaluation does not block deployment.",
          "发布任何分配前都会检查许可证、验证、别名、密钥引用、数据分类与容量阻塞项；可选评测不阻塞部署。",
        ),
      ),
      @html.ol(class="deployment-steps", [
        @html.li([
          @html.span("1"),
          @html.strong(
            localized(
              state.locale,
              "Select approved template",
              "选择已批准模板",
            ),
          ),
        ]),
        @html.li([
          @html.span("2"),
          @html.strong(
            localized(state.locale, "Name the service", "命名服务"),
          ),
        ]),
        @html.li([
          @html.span("3"),
          @html.strong(
            localized(state.locale, "Preflight and deploy", "预检并部署"),
          ),
        ]),
      ]),
      @html.div(class="operation-form", [
        @html.div(class="field-group", [
          @html.label(
            for_="quick-deployment-id",
            localized(state.locale, "Service name", "服务名称"),
          ),
          @html.input(
            input_type=Text,
            id="quick-deployment-id",
            maxlength=128,
            attrs=@html.Attrs::build()
              .aria_describedby("quick-deployment-id-help")
              .aria_invalid(
                if service_name_present && !service_name_valid {
                  "true"
                } else {
                  "false"
                },
              ),
            placeholder="text-service",
            value=state.quick_deployment_id,
            on_input=text_command(emit, value => QuickDeploymentIdChanged(value)),
          ),
          @html.p(
            id="quick-deployment-id-help",
            class=if service_name_present && !service_name_valid {
              "field-help field-error"
            } else {
              "field-help"
            },
            localized(
              state.locale,
              "Use 1–128 letters, numbers, hyphens, underscores, dots, or colons.",
              "使用 1–128 个字母、数字、连字符、下划线、点或冒号。",
            ),
          ),
        ]),
        @html.div(class="field-group", [
          @html.label(
            for_="quick-template",
            localized(state.locale, "Approved template", "已批准模板"),
          ),
          @html.select(
            id="quick-template",
            on_change=text_command(emit, value => QuickTemplateChanged(value)),
            template_options,
          ),
        ]),
        @html.div(class="field-group", [
          @html.label(
            for_="quick-topology",
            localized(state.locale, "Topology", "拓扑"),
          ),
          @html.select(
            id="quick-topology",
            on_change=text_command(emit, value => QuickTopologyChanged(value)),
            [
              for choice in [SingleMachine, Cx7Pair] => {
                @html.option(
                  value=choice.storage_value(),
                  selected=choice == state.quick_topology,
                  choice.label(state.locale),
                )
              }
            ],
          ),
          @html.p(
            class="field-help",
            localized(
              state.locale,
              "A CX7 pair is placed only when both machines name each other over the private fabric, the runtime declares multi-node support, and the installed score policy lists the profile.",
              "仅当两台机器在私有互联上互相指认、运行时声明支持多机、且已安装的评分策略列出该拓扑时，才会按 CX7 对放置。",
            ),
          ),
        ]),
        @html.div(class="fixed-capacity", [
          @html.div(
            class="fixed-capacity-mark",
            if state.quick_topology == Cx7Pair {
              "2"
            } else {
              "1"
            },
          ),
          @html.div([
            @html.strong(
              if state.quick_topology == Cx7Pair {
                localized(
                  state.locale,
                  "One service · one validated CX7 pair",
                  "一个服务 · 一个已验证的 CX7 对",
                )
              } else {
                localized(
                  state.locale,
                  "One service · one assigned machine",
                  "一个服务 · 一台分配机器",
                )
              },
            ),
            @html.p(
              if state.quick_topology == Cx7Pair {
                localized(
                  state.locale,
                  "Capacity is fixed. LunaNexa selects one validated CX7 pair after preflight; replicas, batch scheduling, and autoscaling are unavailable.",
                  "容量固定。LunaNexa 在预检后选择一个已验证的 CX7 对；不提供副本、批处理调度或自动扩缩容。",
                )
              } else {
                localized(
                  state.locale,
                  "Capacity is fixed. LunaNexa selects one eligible DGX after preflight; replicas, batch scheduling, and autoscaling are unavailable.",
                  "容量固定。LunaNexa 在预检后选择一台符合条件的 DGX；不提供副本、批处理调度或自动扩缩容。",
                )
              },
            ),
          ]),
        ]),
      ]),
      @html.div(class="operation-actions", [
        @html.span(
          class="secondary",
          localized(
            state.locale,
            "Creates one durable idempotent operation",
            "创建一个持久且幂等的操作",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=!state.operator_authenticated ||
            state.loading ||
            !service_name_valid ||
            state.quick_template == "",
          on_click=command(emit, SubmitQuickDeployment),
          localized(state.locale, "Deploy model service", "部署模型服务"),
        ),
      ]),
    ]),
    if state.catalog_templates.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No approved model-service templates are registered.",
          "尚未注册已批准的模型服务模板。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Approved model-service templates",
              "已批准的模型服务模板",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Template", "模板")),
              @html.th(
                scope=Col,
                localized(state.locale, "Model selector", "模型选择器"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Runtime", "运行时"),
              ),
              @html.th(scope=Col, localized(state.locale, "Policy", "策略")),
            ]),
          ),
          @html.tbody(
            [
              for template in state.catalog_templates => {
                @html.tr([
                  @html.td([
                    @html.strong(template.display_name),
                    @html.span(
                      class="mono secondary",
                      "\{template.template_id}@\{template.version}",
                    ),
                  ]),
                  @html.td(class="mono", template.model_selector),
                  @html.td(
                    "\{template.runtime.name} · \{template.architecture}",
                  ),
                  @html.td(
                    if template.rollout.automatic_promotion {
                      localized(
                        state.locale,
                        "Auto-promote allowed",
                        "允许自动提升",
                      )
                    } else {
                      localized(
                        state.locale,
                        "Explicit promotion",
                        "显式提升",
                      )
                    },
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    template_registration_form(state, emit),
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(localized(state.locale, "Service operations", "服务操作")),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Restart-safe progress, endpoint and audit evidence for every model service.",
            "查看每个模型服务的重启安全进度、端点与审计证据。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.service_deployments.length()} operations",
          "\{state.service_deployments.length()} 个操作",
        ),
      ),
    ]),
    if state.service_deployments.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No model-service operations yet.",
          "尚无模型服务操作。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Model-service operations",
              "模型服务操作",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Service", "服务")),
              @html.th(scope=Col, localized(state.locale, "State", "状态")),
              @html.th(scope=Col, localized(state.locale, "Endpoint", "端点")),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for operation in state.service_deployments => {
                @html.tr([
                  @html.td([
                    @html.strong(operation.deployment_id),
                    @html.span(class="mono secondary", operation.operation_id),
                  ]),
                  @html.td(
                    service_operation_state_badge(state.locale, operation.state),
                  ),
                  @html.td(
                    class="mono",
                    operation.endpoint
                    .map(value => {
                      "\{value.canonical_path} · \{value.model_selector}"
                    })
                    .unwrap_or("—"),
                  ),
                  @html.td(class="mono secondary", operation.audit_receipt),
                  @html.td(
                    @html.div(class="row-actions", [
                      @html.button(
                        type_="button",
                        disabled=operation.state != Ready,
                        on_click=command(
                          emit,
                          PromoteServiceDeployment(operation.deployment_id),
                        ),
                        localized(state.locale, "Promote", "提升"),
                      ),
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=operation.state == Deleted ||
                          operation.state == RolledBack,
                        on_click=command(
                          emit,
                          BeginRollbackServiceDeployment(
                            operation.deployment_id,
                          ),
                        ),
                        localized(state.locale, "Roll back…", "回滚…"),
                      ),
                      @html.button(
                        type_="button",
                        class="danger-secondary",
                        disabled=operation.state == Deleted,
                        on_click=command(
                          emit,
                          BeginDeleteServiceDeployment(operation.deployment_id),
                        ),
                        localized(state.locale, "Delete…", "删除…"),
                      ),
                    ]),
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn deployments_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("deployments-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="deployments-title",
            localized(state.locale, "Deployments", "部署"),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Compare desired and observed runtime state with each placement decision.",
              "对比每项放置决策的期望状态与实际运行时状态。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.deployments.length()} assignments",
            "\{state.deployments.length()} 项分配",
          ),
        ),
      ]),
      if state.deployments.length() == 0 {
        @html.nothing
      } else {
        deployment_placement_graph(state)
      },
      if state.deployments.length() == 0 {
        @html.div(class="empty-state empty-state-action", [
          @html.strong(
            localized(
              state.locale,
              "No deployments are currently assigned",
              "当前没有已分配的部署",
            ),
          ),
          @html.p(
            localized(
              state.locale,
              "Choose an approved model-service template. Preflight will select exactly one eligible machine.",
              "请选择已批准的模型服务模板。预检将只选择一台符合条件的机器。",
            ),
          ),
          @html.button(
            type_="button",
            class="primary-button",
            on_click=command(emit, Navigate(Catalog)),
            localized(
              state.locale,
              "Open one-click deployment",
              "打开一键部署",
            ),
          ),
        ])
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(state.locale, "Model deployments", "模型部署"),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Deployment", "部署"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Desired", "期望状态"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Observed", "实际状态"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Placement rationale", "调度依据"),
                ),
                @html.th(scope=Col, localized(state.locale, "Action", "操作")),
              ]),
            ),
            @html.tbody(
              [
                for deployment in state.deployments => {
                  deployment_item(state.locale, deployment, emit)
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn deployment_item(
  locale : @i18n.Locale,
  deployment : DeploymentRow,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.tr([
    @html.td([
      @html.strong(deployment.deployment_id),
      @html.span(class="mono secondary", deployment.assignment_id),
    ]),
    @html.td(deployment_state_badge(locale, deployment.desired)),
    @html.td(deployment_state_badge(locale, deployment.observed)),
    @html.td(deployment.placement_reason),
    @html.td(
      @html.button(
        type_="button",
        class="danger-secondary",
        on_click=command(emit, BeginStopDeployment(deployment.assignment_id)),
        localized(locale, "Stop…", "停止…"),
      ),
    ),
  ])
}

///|
fn requests_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("requests-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="requests-title",
          localized(state.locale, "Request operations", "请求监控"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Observe throughput and failures without exposing prompt or output content.",
            "在不公开提示词或输出内容的前提下观察吞吐量和失败情况。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.requests.count} audited",
          "已审计 \{state.requests.count} 项",
        ),
      ),
    ]),
    request_telemetry_chart(state),
    @html.p(
      class="privacy-note",
      localized(
        state.locale,
        "Request detail is bounded and excludes raw payloads.",
        "请求详情受边界限制，且不包含原始载荷。",
      ),
    ),
    if state.request_details.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No request receipts are available yet.",
          "暂无请求回执。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Bounded workload request receipts",
              "有边界的工作负载请求回执",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(
                scope=Col,
                localized(state.locale, "Timestamp", "时间戳"),
              ),
              @html.th(scope=Col, localized(state.locale, "Action", "操作")),
              @html.th(
                scope=Col,
                localized(state.locale, "Model selector", "模型选择器"),
              ),
              @html.th(scope=Col, localized(state.locale, "Result", "结果")),
              @html.th(scope=Col, localized(state.locale, "Receipt", "回执")),
            ]),
          ),
          @html.tbody(
            [
              for detail in state.request_details => {
                @html.tr([
                  @html.td(
                    class="mono secondary",
                    @contractdoc.format_unix_ms_beijing(
                      detail.timestamp_unix_ms,
                    ),
                  ),
                  @html.td(detail.action),
                  @html.td(class="mono", detail.model_selector),
                  @html.td(
                    status_badge(
                      result_label(state.locale, detail.result),
                      "ok",
                    ),
                  ),
                  @html.td(class="mono secondary", detail.receipt),
                ])
              }
            ],
          ),
        ]),
      ])
    },
    @html.div(class="subsection-heading", [
      @html.h3(localized(state.locale, "Latest live stream", "最新实时流")),
      @html.span(
        class="resource-count",
        localized(state.locale, "Browser session", "浏览器会话"),
      ),
    ]),
    @html.div(class="stream-panel", [
      if state.stream_events.length() == 0 {
        @html.p(
          class="empty-state compact",
          localized(
            state.locale,
            "No live stream has been run in this browser session.",
            "此浏览器会话尚未运行实时流。",
          ),
        )
      } else {
        @html.ol(
          class="stream-list",
          [
            for event in state.stream_events => {
              @html.li([
                @html.div(class="stream-meta", [
                  @html.span(
                    class="stream-sequence",
                    event.sequence.to_string(),
                  ),
                  @html.strong(stream_kind_label(state.locale, event.kind)),
                  if event.receipt == "" {
                    @html.nothing
                  } else {
                    @html.span(class="mono secondary", event.receipt)
                  },
                ]),
                if event.text == "" {
                  @html.nothing
                } else {
                  @html.pre(class="stream-output", event.text)
                },
              ])
            }
          ],
        )
      },
    ]),
  ])
}

///|
fn alert_code_label(locale : @i18n.Locale, code : String) -> String {
  match code {
    "NodeUnreachable" =>
      localized(locale, "Node heartbeat is stale", "节点心跳已超时")
    "DeliveryAttemptLimit" =>
      localized(locale, "Notification delivery failed", "通知投递失败")
    "LeaseSanitizationFailed" =>
      localized(locale, "Machine sanitization failed", "机器清理失败")
    "ControllerRecoveryIncomplete" =>
      localized(
        locale, "Controller recovery is incomplete", "控制器恢复未完成",
      )
    "PostgresUnavailable" =>
      localized(
        locale, "Management database is unavailable", "管理数据库不可用",
      )
    "ArtifactVerificationFailed" =>
      localized(locale, "Artifact verification failed", "制品验证失败")
    "OfflineReviewOverdue" =>
      localized(locale, "Offline review is overdue", "线下审核已逾期")
    "OfflineReconciliationNeedsCorrection" =>
      localized(
        locale, "Offline reconciliation needs correction", "线下核对需要修正",
      )
    "PaymentInvoiceReconciliationFailed" =>
      localized(
        locale, "Payment or invoice reconciliation failed", "付款或发票核对失败",
      )
    "WorkloadAdmissionRejected" =>
      localized(
        locale, "Workload admission is repeatedly rejected", "工作负载准入被连续拒绝",
      )
    "GuideAdapterUnavailable" =>
      localized(
        locale, "Guide diagnostics are unavailable", "指南诊断不可用",
      )
    "KnowledgeRevisionStale" =>
      localized(
        locale, "Guide knowledge is stale", "指南知识版本已过期",
      )
    "ContractExpiring" =>
      localized(
        locale, "Contract is nearing its end date", "合同即将到期",
      )
    "AccessCredentialsRevoked" =>
      localized(
        locale, "Access credentials revoked on contract close", "合同关闭，访问凭据已撤销",
      )
    "ContractObligationOverdue" =>
      localized(
        locale, "Contract obligation is overdue", "合同履约义务已逾期",
      )
    "ContractApprovalRecoveryRequired" =>
      localized(
        locale, "Approved contract action needs recovery", "已批准的合同操作需要恢复执行",
      )
    "ContractApprovalNudged" =>
      localized(
        locale, "Customer requested an approval update", "客户发起了审批催办",
      )
    _ => code
  }
}

///|
fn alert_severity_label(
  locale : @i18n.Locale,
  severity : @notifications.NotificationSeverity,
) -> String {
  match severity {
    Information => localized(locale, "Information", "提示")
    Warning => localized(locale, "Warning", "警告")
    Critical => localized(locale, "Critical", "严重")
  }
}

///|
fn alert_lifecycle_label(
  locale : @i18n.Locale,
  lifecycle : @notifications.NotificationLifecycle,
) -> String {
  match lifecycle {
    Unread => localized(locale, "Open", "未处理")
    Read => localized(locale, "Read", "已读")
    Acknowledged => localized(locale, "Acknowledged", "已确认")
    Resolved => localized(locale, "Resolved", "已解决")
  }
}

///|
fn notification_channel_label(
  locale : @i18n.Locale,
  channel : @notifications.NotificationChannel,
) -> String {
  match channel {
    InApp => localized(locale, "In-app", "站内")
    Email => localized(locale, "Email", "电子邮件")
    Sms => localized(locale, "SMS", "短信")
    Webhook => localized(locale, "Webhook", "Webhook")
  }
}

///|
fn notification_delivery_state_label(
  locale : @i18n.Locale,
  delivery_state : @notifications.DeliveryState,
) -> String {
  match delivery_state {
    PendingDelivery => localized(locale, "Pending", "等待投递")
    Delivering => localized(locale, "Delivering", "投递中")
    Delivered => localized(locale, "Delivered", "已投递")
    RetryScheduled => localized(locale, "Retry scheduled", "已安排重试")
    DeadLetter => localized(locale, "Dead letter", "死信")
    DeliverySkipped => localized(locale, "Skipped", "已跳过")
  }
}

///|
fn notification_delivery_error_label(
  locale : @i18n.Locale,
  error_code : String,
) -> String {
  match error_code {
    "" => "—"
    "DeliveryAttemptLimit" =>
      localized(locale, "Attempt limit reached", "已达到尝试次数上限")
    "ProviderUnavailable" =>
      localized(locale, "Provider unavailable", "投递供应商不可用")
    _ => error_code
  }
}

///|
/// Whole Beijing calendar days since the Unix epoch. The fixed UTC+8 offset
/// keeps alert headings stable across operator browser timezones.
fn alert_day_index(unix_ms : Int64) -> Int64 {
  (unix_ms + 28800000L) / 86400000L
}

///|
/// First Beijing day included by a window, relative to `now_unix_ms`. `AllAlerts`
/// has no lower bound. The bound is inclusive upward so a clock that is behind
/// the controller never hides a freshly created alert.
fn alerts_window_lower_day(
  window : AlertsWindow,
  now_unix_ms : Int64,
) -> Int64? {
  let today = alert_day_index(now_unix_ms)
  match window {
    Today => Some(today)
    Last7Days => Some(today - 6L)
    Last30Days => Some(today - 29L)
    AllAlerts => None
  }
}

///|
/// Narrow the loaded notifications to one window. Pure projection: the
/// controller read set is unchanged.
pub fn filter_alerts(
  rows : Array[NotificationRow],
  window : AlertsWindow,
  now_unix_ms : Int64,
) -> Array[NotificationRow] {
  match alerts_window_lower_day(window, now_unix_ms) {
    None => rows.copy()
    Some(lower) =>
      rows.filter(row => alert_day_index(row.created_unix_ms) >= lower)
  }
}

///|
/// Open alerts in a set that the operator is looking at.
pub fn open_alert_count(rows : Array[NotificationRow]) -> Int {
  rows.count_if(row => row.lifecycle != Resolved)
}

///|
/// Beijing calendar day of an alert, for example `2026-09-19`.
pub fn alert_day_label(unix_ms : Int64) -> String {
  let stamp = @contractdoc.format_unix_ms_beijing(unix_ms)
  let mut day = stamp
  for part in stamp.split(" ") {
    day = part.to_owned()
    break
  }
  day
}

///|
/// Bucket alert rows by Beijing day, newest day first. Ordering inside one day is
/// the caller's ordering.
pub fn group_alerts_by_day(
  rows : Array[NotificationRow],
) -> Array[(String, Array[NotificationRow])] {
  let groups : Array[(String, Array[NotificationRow])] = []
  for row in rows {
    let day = alert_day_label(row.created_unix_ms)
    let mut bucket : Array[NotificationRow]? = None
    for group in groups {
      if group.0 == day {
        bucket = Some(group.1)
      }
    }
    match bucket {
      Some(bucket_rows) => bucket_rows.push(row)
      None => groups.push((day, [row]))
    }
  }
  groups.sort_by((left, right) => {
    if left.0 == right.0 {
      0
    } else if left.0 > right.0 {
      -1
    } else {
      1
    }
  })
  groups
}

///|
fn alert_row(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  row : NotificationRow,
) -> @rabbita.Html {
  @html.tr([
    @html.td([
      @html.strong(alert_code_label(state.locale, row.code)),
      @html.span(
        class="mono secondary",
        if row.node_ref == "" {
          row.notification_id
        } else {
          "\{row.node_ref} · \{row.notification_id}"
        },
      ),
    ]),
    @html.td(
      status_badge(
        alert_severity_label(state.locale, row.severity),
        if row.severity == Critical {
          "danger"
        } else {
          "warning"
        },
      ),
    ),
    @html.td(
      status_badge(
        alert_lifecycle_label(state.locale, row.lifecycle),
        if row.lifecycle == Resolved {
          "ok"
        } else {
          "warning"
        },
      ),
    ),
    @html.td(
      class="mono secondary",
      @contractdoc.format_unix_ms_beijing(row.created_unix_ms),
    ),
    @html.td(if row.assigned_to == "" { "—" } else { row.assigned_to }),
    @html.td(
      @html.div(class="table-actions", [
        @html.button(
          type_="button",
          disabled=row.lifecycle == Acknowledged || row.lifecycle == Resolved,
          on_click=command(
            emit,
            AcknowledgeAlert(row.notification_id, row.generation),
          ),
          localized(state.locale, "Acknowledge", "确认"),
        ),
        @html.button(
          type_="button",
          disabled=row.lifecycle == Resolved ||
            row.assigned_to == "platform-operator",
          on_click=command(
            emit,
            AssignAlertToSelf(row.notification_id, row.generation),
          ),
          localized(state.locale, "Assign to me", "分配给我"),
        ),
        @html.button(
          type_="button",
          disabled=row.lifecycle == Resolved,
          on_click=command(
            emit,
            SilenceAlert(row.notification_id, row.generation),
          ),
          localized(state.locale, "Silence 1h", "静默 1 小时"),
        ),
        @html.button(
          type_="button",
          disabled=row.lifecycle == Resolved,
          on_click=command(
            emit,
            ResolveAlert(row.notification_id, row.generation),
          ),
          localized(state.locale, "Resolve", "解决"),
        ),
      ]),
    ),
  ])
}

///|
/// Alert table body: one heading row per Beijing day, newest day first, then that
/// day's incidents in their existing order.
fn alert_rows_by_day(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  rows : Array[NotificationRow],
) -> Array[@rabbita.Html] {
  let body : Array[@rabbita.Html] = []
  for group in group_alerts_by_day(rows) {
    let (day, alerts) = group
    body.push(
      @html.tr(class="alerts-day-heading", [
        @html.th(
          scope=ColGroup,
          colspan=6,
          "\{day} · \{localized(state.locale, "\{alerts.length()} incidents", "\{alerts.length()} 个事件")}",
        ),
      ]),
    )
    for row in alerts {
      body.push(alert_row(state, emit, row))
    }
  }
  body
}

///|
fn alerts_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  window : AlertsWindow,
  now_unix_ms : Int64,
) -> @rabbita.Html {
  let visible = filter_alerts(state.notifications, window, now_unix_ms)
  let open_count = open_alert_count(visible)
  @html.section(attrs=@html.Attrs::build().aria_labelledby("alerts-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="alerts-title",
          localized(state.locale, "Operator alert center", "运维告警中心"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Incidents are durable and deduplicated. Resolution preserves their audit history.",
            "事件会持久化并去重；解决事件后仍保留其审计历史。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{open_count} open",
          "\{open_count} 个未解决",
        ),
      ),
    ]),
    @html.div(class="alerts-window-control", [
      @html.label(
        for_="alerts-window",
        localized(state.locale, "Time window", "时间范围"),
      ),
      @html.select(
        id="alerts-window",
        class="alerts-window-select",
        on_change=text_command(emit, value => {
          AlertsWindowChanged(parse_alerts_window(value))
        }),
        [
          for choice in [Today, Last7Days, Last30Days, AllAlerts] => {
            @html.option(
              value=choice.storage_value(),
              selected=choice == window,
              choice.label(state.locale),
            )
          }
        ],
      ),
      @html.span(
        class="alerts-window-summary",
        localized(
          state.locale,
          "\{visible.length()} of \{state.notifications.length()} incidents shown",
          "显示 \{visible.length()} / \{state.notifications.length()} 个事件",
        ),
      ),
    ]),
    alert_impact_graph(state),
    announcement_form(state, emit),
    if visible.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No incidents were created in this window.",
          "该时间范围内没有事件。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Durable operator alerts",
              "持久化运维告警",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Incident", "事件")),
              @html.th(scope=Col, localized(state.locale, "Severity", "级别")),
              @html.th(scope=Col, localized(state.locale, "State", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Created", "创建时间"),
              ),
              @html.th(scope=Col, localized(state.locale, "Owner", "负责人")),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(alert_rows_by_day(state, emit, visible)),
        ]),
      ])
    },
    @html.div(class="subsection-heading", [
      @html.div([
        @html.h3(
          localized(state.locale, "Delivery outbox", "通知投递队列"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Provider-neutral delivery records expose bounded state only. A dead letter must be confirmed against its current generation before redrive.",
            "投递记录仅显示受限的供应商中立状态。死信必须按当前代次确认后才能重新投递。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.notification_deliveries.count_if(row => row.state == DeadLetter)} dead letters",
          "\{state.notification_deliveries.count_if(row => row.state == DeadLetter)} 个死信",
        ),
      ),
    ]),
    if state.notification_deliveries.length() == 0 {
      @html.p(
        class="empty-state compact",
        localized(
          state.locale,
          "No outbound delivery records are available.",
          "暂无出站投递记录。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Outbound notification delivery records",
              "出站通知投递记录",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Delivery", "投递")),
              @html.th(scope=Col, localized(state.locale, "Channel", "渠道")),
              @html.th(scope=Col, localized(state.locale, "State", "状态")),
              @html.th(
                scope=Col,
                localized(state.locale, "Attempts", "尝试次数"),
              ),
              @html.th(
                scope=Col,
                localized(state.locale, "Last error", "最近错误"),
              ),
              @html.th(scope=Col, localized(state.locale, "Actions", "操作")),
            ]),
          ),
          @html.tbody(
            [
              for row in state.notification_deliveries => {
                @html.tr([
                  @html.td([
                    @html.strong(class="mono", row.delivery_id),
                    @html.span(class="mono secondary", row.notification_id),
                  ]),
                  @html.td(
                    notification_channel_label(state.locale, row.channel),
                  ),
                  @html.td(
                    status_badge(
                      notification_delivery_state_label(state.locale, row.state),
                      if row.state == DeadLetter {
                        "danger"
                      } else if row.state == Delivered {
                        "ok"
                      } else {
                        "warning"
                      },
                    ),
                  ),
                  @html.td(row.attempt_count.to_string()),
                  @html.td(
                    class="mono secondary",
                    notification_delivery_error_label(
                      state.locale,
                      row.last_error_code,
                    ),
                  ),
                  @html.td(
                    if row.state == DeadLetter {
                      @html.button(
                        type_="button",
                        on_click=command(
                          emit,
                          BeginRedriveNotificationDelivery(
                            row.delivery_id,
                            row.attempt_count,
                            row.updated_unix_ms,
                          ),
                        ),
                        localized(state.locale, "Redrive", "重新投递"),
                      )
                    } else {
                      @html.span(class="secondary", "—")
                    },
                  ),
                ])
              }
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn benchmarks_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("benchmarks-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="benchmarks-title",
            localized(state.locale, "Benchmark evidence", "基准测试证据"),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Versioned runtime measurements used for placement and promotion decisions.",
              "用于放置与提升决策的版本化运行时测量数据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.benchmark_evidence.length()} profiles",
            "\{state.benchmark_evidence.length()} 个配置",
          ),
        ),
      ]),
      if state.benchmark_evidence.length() == 0 {
        @html.nothing
      } else {
        benchmark_comparison_chart(state)
      },
      if state.benchmark_evidence.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No benchmark evidence has been recorded.",
            "尚未记录基准测试证据。",
          ),
        )
      } else {
        @html.nothing
      },
    ],
  )
}

///|
fn retention_label(
  locale : @i18n.Locale,
  retention : @contracts.RetentionPolicy,
) -> String {
  match retention {
    Ephemeral => localized(locale, "Ephemeral", "临时（不保留）")
    EvaluationCapture(consent_receipt=_) =>
      localized(locale, "Evaluation capture", "评测采集")
    RetainUntil(expiry) =>
      localized(locale, "Retain until \{expiry}", "保留至 \{expiry}")
  }
}

///|
fn runtime_capability_label(
  locale : @i18n.Locale,
  capability : @contracts.Capability,
) -> String {
  match capability {
    TextGenerate => localized(locale, "Text generation", "文本生成")
    EmbeddingCreate => localized(locale, "Embeddings", "嵌入")
    ImageGenerate => localized(locale, "Image generation", "图像生成")
    VideoGenerate => localized(locale, "Video generation", "视频生成")
    AudioGenerate => localized(locale, "Audio generation", "音频生成")
    ModelEvaluate => localized(locale, "Model evaluation", "模型评测")
    ModelTrain => localized(locale, "Model training", "模型训练")
  }
}

///|
/// The operator-facing runtime registration the registry already accepts. The
/// client mirrors the registry's own shape checks so the console never offers
/// a profile the control plane would reject as malformed; ordering and policy
/// decisions still come back from the server.
fn runtime_registration_form(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  let locale = state.locale
  let draft = state.runtime_draft
  let valid = runtime_profile_draft_valid(draft)
  let name_invalid = draft.name != "" && !runtime_profile_name_valid(draft.name)
  let version_invalid = draft.version != "" &&
    !@contracts.valid_identifier(
      draft.version.trim().to_owned(),
      maximum_length=128,
    )
  let digest_invalid = draft.image_digest != "" &&
    !@contracts.valid_sha256_digest(draft.image_digest.trim().to_owned())
  let architecture_invalid = draft.architecture != "" &&
    !@contracts.valid_identifier(
      draft.architecture.trim().to_owned(),
      maximum_length=128,
    )
  @html.div(class="operation-panel runtime-profile-panel", [
    @html.div(class="operation-heading", [
      @html.div([
        @html.p(
          class="eyebrow",
          localized(locale, "Runtime profiles", "运行时配置"),
        ),
        @html.h3(
          localized(
            locale, "Register a runtime profile", "注册运行时配置",
          ),
        ),
      ]),
      @html.span(
        class="status status-pending",
        localized(locale, "Registry validated", "注册表校验"),
      ),
    ]),
    @html.p(
      class="section-copy",
      localized(
        locale, "Registers one immutable runtime image for the registry to admit. A profile is deployable only after its image digest is verified, so registration alone grants no workload.",
        "登记一个供注册表接纳的不可变运行时镜像。只有在镜像摘要通过验证后配置才可部署，因此仅登记不会授予任何工作负载。",
      ),
    ),
    @html.form(
      class="operation-form runtime-profile-form",
      on_submit=command(emit, SubmitRuntimeRegistration),
      attrs=@html.Attrs::build().aria_labelledby("runtime-profile-title"),
      [
        @html.fieldset(disabled=state.loading, [
          @html.legend(
            id="runtime-profile-title",
            localized(
              locale, "Runtime identity and placement", "运行时身份与放置",
            ),
          ),
          @html.div(class="model-onboarding-grid", [
            @html.div(class="field-group", [
              @html.label(
                for_="runtime-name",
                localized(locale, "Runtime name", "运行时名称"),
              ),
              @html.input(
                id="runtime-name",
                input_type=Text,
                required=true,
                maxlength=256,
                placeholder="text-runtime-v2",
                value=draft.name,
                attrs=@html.Attrs::build()
                  .aria_describedby("runtime-name-help")
                  .aria_invalid(if name_invalid { "true" } else { "false" }),
                on_input=text_command(emit, value => RuntimeNameChanged(value)),
              ),
              @html.p(
                id="runtime-name-help",
                class=if name_invalid {
                  "field-help field-error"
                } else {
                  "field-help"
                },
                localized(
                  locale, "Up to 256 characters with no '@', no spaces, and no '..'.",
                  "最多 256 个字符，不能包含 '@'、空格或 '..'。",
                ),
              ),
            ]),
            @html.div(class="field-group", [
              @html.label(
                for_="runtime-version",
                localized(locale, "Runtime version", "运行时版本"),
              ),
              @html.input(
                id="runtime-version",
                input_type=Text,
                required=true,
                maxlength=128,
                placeholder="runtime-v2",
                value=draft.version,
                attrs=@html.Attrs::build()
                  .aria_describedby("runtime-version-help")
                  .aria_invalid(if version_invalid { "true" } else { "false" }),
                on_input=text_command(emit, value => {
                  RuntimeVersionChanged(value)
                }),
              ),
              @html.p(
                id="runtime-version-help",
                class=if version_invalid {
                  "field-help field-error"
                } else {
                  "field-help"
                },
                localized(
                  locale, "Stable letters, numbers, dots, colons, hyphens, or underscores.",
                  "使用稳定的字母、数字、点、冒号、连字符或下划线。",
                ),
              ),
            ]),
            @html.div(class="field-group", [
              @html.label(
                for_="runtime-image-digest",
                localized(
                  locale, "Runtime image digest", "运行时镜像摘要",
                ),
              ),
              @html.input(
                id="runtime-image-digest",
                input_type=Text,
                required=true,
                maxlength=71,
                placeholder="sha256:…",
                value=draft.image_digest,
                attrs=@html.Attrs::build()
                  .aria_describedby("runtime-image-digest-help")
                  .aria_invalid(if digest_invalid { "true" } else { "false" }),
                on_input=text_command(emit, value => {
                  RuntimeImageDigestChanged(value)
                }),
              ),
              @html.p(
                id="runtime-image-digest-help",
                class=if digest_invalid {
                  "field-help field-error"
                } else {
                  "field-help"
                },
                localized(
                  locale, "Exactly sha256: followed by 64 hexadecimal characters.",
                  "必须为 sha256: 加 64 个十六进制字符。",
                ),
              ),
            ]),
            @html.div(class="field-group", [
              @html.label(
                for_="runtime-architecture",
                localized(locale, "Accelerator architecture", "加速器架构"),
              ),
              @html.input(
                id="runtime-architecture",
                input_type=Text,
                required=true,
                maxlength=128,
                placeholder="nvidia-sm121",
                value=draft.architecture,
                attrs=@html.Attrs::build()
                  .aria_describedby("runtime-architecture-help")
                  .aria_invalid(
                    if architecture_invalid {
                      "true"
                    } else {
                      "false"
                    },
                  ),
                on_input=text_command(emit, value => {
                  RuntimeArchitectureChanged(value)
                }),
              ),
              @html.p(
                id="runtime-architecture-help",
                class=if architecture_invalid {
                  "field-help field-error"
                } else {
                  "field-help"
                },
                localized(
                  locale, "The deployment's admitted accelerator profile.", "部署所允许的加速器配置。",
                ),
              ),
            ]),
            @html.div(class="field-group", [
              @html.label(
                for_="runtime-capability",
                localized(locale, "Serving capability", "服务能力"),
              ),
              @html.select(
                id="runtime-capability",
                on_change=text_command(emit, value => {
                  RuntimeCapabilityChanged(value)
                }),
                [
                  for capability in runtime_capability_options() => {
                    @html.option(
                      value=runtime_capability_name(capability),
                      selected=capability == draft.capability,
                      runtime_capability_label(locale, capability),
                    )
                  }
                ],
              ),
            ]),
          ]),
          @html.div(class="runtime-profile-flags", [
            @html.label(class="runtime-profile-flag", for_="runtime-batching", [
              @html.input(
                input_type=Checkbox,
                id="runtime-batching",
                checked=draft.supports_batching,
                on_change=text_command(emit, _ => RuntimeBatchingToggled),
              ),
              @html.span(
                localized(locale, "Supports batching", "支持批处理"),
              ),
            ]),
            @html.label(
              class="runtime-profile-flag",
              for_="runtime-multi-node",
              [
                @html.input(
                  input_type=Checkbox,
                  id="runtime-multi-node",
                  checked=draft.supports_multi_node,
                  on_change=text_command(emit, _ => RuntimeMultiNodeToggled),
                ),
                @html.span(
                  localized(locale, "Supports multi-node", "支持多机"),
                ),
              ],
            ),
          ]),
          @html.div(class="operation-actions", [
            @html.span(
              class="secondary",
              localized(
                locale, "Registration does not verify the image; the registry records the digest an operator cited.",
                "登记不会验证镜像；注册表只记录运维人员引用的摘要。",
              ),
            ),
            @html.button(
              type_="submit",
              class="primary-button",
              disabled=!state.operator_authenticated || !valid || state.loading,
              localized(locale, "Register runtime", "注册运行时"),
            ),
          ]),
        ]),
      ],
    ),
  ])
}

///|
fn policies_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("policies-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="policies-title",
          localized(state.locale, "Policy & operations", "策略与运维"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Review effective controls and submit validated changes through the canonical API.",
            "检查生效的控制项，并通过规范 API 提交已验证的变更。",
          ),
        ),
      ]),
    ]),
    @html.dl(class="policy-summary", [
      @html.div([
        @html.dt(localized(state.locale, "Quotas", "配额")),
        @html.dd(state.policies.quota_count.to_string()),
      ]),
      @html.div([
        @html.dt(localized(state.locale, "Data classes", "数据分类")),
        @html.dd(state.policies.data_class_count.to_string()),
      ]),
      @html.div([
        @html.dt(
          localized(state.locale, "Default retention", "默认保留策略"),
        ),
        @html.dd(
          retention_label(state.locale, state.policies.default_retention),
        ),
      ]),
      @html.div([
        @html.dt(
          localized(state.locale, "Allowed runtimes", "允许的运行时"),
        ),
        @html.dd(
          if state.policies.allowed_runtimes.length() == 0 {
            localized(state.locale, "None configured", "未配置")
          } else {
            state.policies.allowed_runtimes.join(", ")
          },
        ),
      ]),
    ]),
    runtime_registration_form(state, emit),
    @html.div(class="operation-panel", [
      @html.div(class="operation-heading", [
        @html.div([
          @html.p(
            class="eyebrow",
            localized(
              state.locale,
              "Validated control path",
              "已验证的控制路径",
            ),
          ),
          @html.h3(
            localized(
              state.locale,
              "Typed operator operation",
              "类型化运维操作",
            ),
          ),
        ]),
        @html.span(
          class="status status-pending",
          localized(state.locale, "Canonical JSON", "规范 JSON"),
        ),
      ]),
      @html.p(
        class="section-copy",
        localized(
          state.locale,
          "Submit canonical JSON to the same validated API used by automation. Secret values remain in browser memory and must not be pasted into model or assignment metadata.",
          "向自动化所使用的同一已验证 API 提交规范 JSON。机密值仅保留在浏览器内存中，不得粘贴到模型或分配元数据中。",
        ),
      ),
      @html.div(class="operation-form", [
        @html.div(class="field-group", [
          @html.label(
            for_="operation-name",
            localized(state.locale, "Operation", "操作"),
          ),
          @html.select(
            id="operation-name",
            on_change=text_command(emit, value => OperationChanged(value)),
            [
              @html.option(
                value="issue-enrollment-token",
                selected=state.operation_name == "issue-enrollment-token",
                localized(
                  state.locale,
                  "Issue enrollment token",
                  "签发注册令牌",
                ),
              ),
              @html.option(
                value="register-runtime",
                selected=state.operation_name == "register-runtime",
                localized(state.locale, "Register runtime", "注册运行时"),
              ),
              @html.option(
                value="register-model",
                selected=state.operation_name == "register-model",
                localized(state.locale, "Register model", "注册模型"),
              ),
              @html.option(
                value="register-template",
                selected=state.operation_name == "register-template",
                localized(
                  state.locale,
                  "Register model-service template",
                  "注册模型服务模板",
                ),
              ),
              @html.option(
                value="plan-deployment",
                selected=state.operation_name == "plan-deployment",
                localized(
                  state.locale,
                  "Preflight deployment intent",
                  "预检部署意图",
                ),
              ),
              @html.option(
                value="deploy-service",
                selected=state.operation_name == "deploy-service",
                localized(
                  state.locale,
                  "Deploy model service",
                  "部署模型服务",
                ),
              ),
              @html.option(
                value="record-license",
                selected=state.operation_name == "record-license",
                localized(state.locale, "Record license", "记录许可证"),
              ),
              @html.option(
                value="record-verification",
                selected=state.operation_name == "record-verification",
                localized(state.locale, "Record verification", "记录验证"),
              ),
              @html.option(
                value="record-evaluation",
                selected=state.operation_name == "record-evaluation",
                localized(state.locale, "Record evaluation", "记录评测"),
              ),
              @html.option(
                value="approve-model",
                selected=state.operation_name == "approve-model",
                localized(state.locale, "Approve model", "批准模型"),
              ),
              @html.option(
                value="promote-alias",
                selected=state.operation_name == "promote-alias",
                localized(state.locale, "Promote alias", "提升模型别名"),
              ),
              @html.option(
                value="set-quota",
                selected=state.operation_name == "set-quota",
                localized(state.locale, "Set quota", "设置配额"),
              ),
              @html.option(
                value="create-organization",
                selected=state.operation_name == "create-organization",
                localized(state.locale, "Create organization", "创建组织"),
              ),
              @html.option(
                value="create-cost-center",
                selected=state.operation_name == "create-cost-center",
                localized(
                  state.locale,
                  "Create cost center",
                  "创建成本中心",
                ),
              ),
              @html.option(
                value="create-project",
                selected=state.operation_name == "create-project",
                localized(
                  state.locale,
                  "Create commercial project",
                  "创建商业项目",
                ),
              ),
              @html.option(
                value="record-commercial-usage",
                selected=state.operation_name == "record-commercial-usage",
                localized(
                  state.locale,
                  "Record commercial usage",
                  "记录商业用量",
                ),
              ),
              @html.option(
                value="rate-commercial-usage",
                selected=state.operation_name == "rate-commercial-usage",
                localized(
                  state.locale,
                  "Rate commercial usage",
                  "计费商业用量",
                ),
              ),
              @html.option(
                value="create-commercial-budget",
                selected=state.operation_name == "create-commercial-budget",
                localized(
                  state.locale,
                  "Create commercial budget",
                  "创建商业预算",
                ),
              ),
              @html.option(
                value="create-commercial-quota",
                selected=state.operation_name == "create-commercial-quota",
                localized(
                  state.locale,
                  "Create commercial quota",
                  "创建商业配额",
                ),
              ),
              @html.option(
                value="register-agreement-template",
                selected=state.operation_name == "register-agreement-template",
                localized(
                  state.locale,
                  "Register agreement template",
                  "注册协议模板",
                ),
              ),
              @html.option(
                value="create-agreement",
                selected=state.operation_name == "create-agreement",
                localized(
                  state.locale,
                  "Create digital agreement",
                  "创建数字协议",
                ),
              ),
              @html.option(
                value="create-enterprise-membership",
                selected=state.operation_name == "create-enterprise-membership",
                localized(
                  state.locale,
                  "Create enterprise membership",
                  "创建企业成员关系",
                ),
              ),
              @html.option(
                value="publish-portal-agreement",
                selected=state.operation_name == "publish-portal-agreement",
                localized(
                  state.locale,
                  "Publish portal agreement",
                  "发布企业门户协议",
                ),
              ),
              @html.option(
                value="register-external-record",
                selected=state.operation_name == "register-external-record",
                localized(
                  state.locale,
                  "Register external evidence",
                  "登记外部证据",
                ),
              ),
              @html.option(
                value="decide-backpressure",
                selected=state.operation_name == "decide-backpressure",
                localized(state.locale, "Evaluate backpressure", "评估背压"),
              ),
              @html.option(
                value="validate-transfer-grant",
                selected=state.operation_name == "validate-transfer-grant",
                localized(
                  state.locale,
                  "Validate transfer grant",
                  "验证传输授权",
                ),
              ),
              @html.option(
                value="invite-user",
                selected=state.operation_name == "invite-user",
                localized(state.locale, "Invite user", "邀请用户"),
              ),
              @html.option(
                value="grant-access",
                selected=state.operation_name == "grant-access",
                localized(
                  state.locale,
                  "Grant scoped access",
                  "授予限定范围的访问权限",
                ),
              ),
              @html.option(
                value="create-compute-lease",
                selected=state.operation_name == "create-compute-lease",
                localized(
                  state.locale,
                  "Create workspace lease",
                  "创建工作区租约",
                ),
              ),
              @html.option(
                value="publish-assignment",
                selected=state.operation_name == "publish-assignment",
                localized(
                  state.locale,
                  "Publish assignment for controller signing",
                  "发布分配以供控制器签名",
                ),
              ),
              @html.option(
                value="invoke-workload",
                selected=state.operation_name == "invoke-workload",
                localized(state.locale, "Invoke workload", "调用工作负载"),
              ),
              @html.option(
                value="record-benchmark",
                selected=state.operation_name == "record-benchmark",
                localized(
                  state.locale,
                  "Record benchmark evidence",
                  "记录基准测试证据",
                ),
              ),
            ],
          ),
        ]),
        @html.div(class="field-group operation-body", [
          @html.label(
            for_="operation-body",
            localized(state.locale, "Canonical JSON body", "规范 JSON 正文"),
          ),
          @html.textarea(
            id="operation-body",
            rows=12,
            maxlength=1048576,
            value=state.operation_body,
            on_input=text_command(emit, value => OperationBodyChanged(value)),
            "",
          ),
        ]),
      ]),
      @html.div(class="operation-actions", [
        @html.span(
          class="secondary",
          localized(
            state.locale,
            "Validated by the same contract used by automation",
            "使用与自动化相同的契约进行验证",
          ),
        ),
        @html.button(
          type_="button",
          class="primary-button",
          disabled=state.operation_body.trim() == "" || state.loading,
          on_click=command(emit, SubmitOperation),
          localized(state.locale, "Validate and submit", "验证并提交"),
        ),
      ]),
    ]),
  ])
}

///|
fn cost_centers_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("cost-centers-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="cost-centers-title",
            localized(
              state.locale,
              "Cost center governance",
              "成本中心治理",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Allocate metered model usage to a tenant hierarchy before rating, budget admission, and ledger finalization.",
              "在计费、预算准入和账本结算前，将模型用量分配至租户层级。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.cost_centers.length()} cost centers",
            "\{state.cost_centers.length()} 个成本中心",
          ),
        ),
      ]),
      @html.p(
        class="privacy-note",
        localized(
          state.locale,
          "Financial exports are tenant-scoped, formula-safe, and contain immutable ledger snapshots—not prompts or model payloads.",
          "财务导出限定租户范围、防公式注入，并仅包含不可变账本快照，不含提示词或模型载荷。",
        ),
      ),
      if state.cost_centers.length() == 0 {
        @html.nothing
      } else {
        cost_center_hierarchy_graph(state)
      },
      if state.cost_centers.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No cost centers are loaded. Create the organization hierarchy through the commercial API, then refresh.",
            "尚未加载成本中心。请通过商业管理 API 创建组织层级后刷新。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Cost center financial posture",
                "成本中心财务状态",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Cost center", "成本中心"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Organization", "组织"),
                ),
                @html.th(scope=Col, localized(state.locale, "Parent", "上级")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Projects", "项目"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Provisional spend", "暂计支出"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Budget posture", "预算状态"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for center in state.cost_centers => {
                  @html.tr([
                    @html.td([
                      @html.strong(center.display_name),
                      @html.span(class="mono secondary", center.cost_center_id),
                    ]),
                    @html.td(class="mono", center.organization_id),
                    @html.td(
                      class="mono secondary",
                      if center.parent_cost_center_id.trim() == "" {
                        "—"
                      } else {
                        center.parent_cost_center_id
                      },
                    ),
                    @html.td(center.project_count.to_string()),
                    @html.td(class="mono", center.provisional_spend),
                    @html.td(
                      status_badge(
                        center.budget_posture,
                        if center.budget_posture.contains("Within") {
                          "ok"
                        } else {
                          "warning"
                        },
                      ),
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn agreements_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("agreements-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="agreements-title",
            localized(
              state.locale,
              "Digital agreement lifecycle",
              "数字协议生命周期",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Track immutable template versions, clickwrap acceptance, signature callbacks, and separation-of-duties evidence.",
              "跟踪不可变模板版本、点击接受、签名回调与职责分离证据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.agreements.length()} agreements",
            "\{state.agreements.length()} 份协议",
          ),
        ),
      ]),
      if state.agreements.length() == 0 &&
        state.enterprise_lease_requests.length() == 0 {
        @html.nothing
      } else {
        agreement_lifecycle_graph(state)
      },
      if state.agreements.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No agreement evidence is loaded.",
            "尚未加载协议证据。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Digital agreement evidence",
                "数字协议证据",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Agreement", "协议"),
                ),
                @html.th(scope=Col, localized(state.locale, "Type", "类型")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Template", "模板"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Organization", "组织"),
                ),
                @html.th(scope=Col, localized(state.locale, "State", "状态")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Evidence receipt", "证据回执"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for agreement in state.agreements => {
                  @html.tr([
                    @html.td(class="mono", agreement.agreement_id),
                    @html.td(
                      agreement_type_label(
                        state.locale,
                        agreement.agreement_type,
                      ),
                    ),
                    @html.td(class="mono", agreement.template_version),
                    @html.td(class="mono", agreement.organization_id),
                    @html.td(
                      status_badge(
                        agreement_state_label(state.locale, agreement.state),
                        if agreement.state == "Executed" {
                          "ok"
                        } else {
                          "pending"
                        },
                      ),
                    ),
                    @html.td(class="mono secondary", agreement.evidence_receipt),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
      @html.div(class="section-heading enterprise-request-heading", [
        @html.div([
          @html.h2(
            localized(
              state.locale,
              "Enterprise lease requests",
              "企业租用申请",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Select one eligible node, then approve the tenant request into the exclusive-node lease authority.",
              "选择一个符合条件的节点，然后将租户申请批准到独占节点租约权限中。",
            ),
          ),
        ]),
        @html.div(class="portal-node-picker", [
          @html.label(
            for_="portal-node-id",
            localized(state.locale, "Assigned node", "分配节点"),
          ),
          @html.input(
            id="portal-node-id",
            value=state.portal_node_id,
            maxlength=128,
            placeholder="dgx-spark-01",
            on_input=text_command(emit, value => PortalNodeChanged(value)),
          ),
        ]),
      ]),
      if state.enterprise_lease_requests.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No enterprise lease requests are waiting.",
            "没有待处理的企业租用申请。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.thead(
              @html.tr([
                @html.th(localized(state.locale, "Request", "申请")),
                @html.th(localized(state.locale, "Organization", "组织")),
                @html.th(
                  localized(state.locale, "Project / user", "项目 / 用户"),
                ),
                @html.th(localized(state.locale, "Models", "模型")),
                @html.th(localized(state.locale, "State", "状态")),
                @html.th(localized(state.locale, "Decision", "决策")),
              ]),
            ),
            @html.tbody(
              [
                for request in state.enterprise_lease_requests => {
                  @html.tr([
                    @html.td(class="mono", request.request_id),
                    @html.td([
                      @html.strong(request.organization_id),
                      @html.span(class="mono secondary", request.subject_ref),
                    ]),
                    @html.td([
                      @html.strong(request.project_id),
                      @html.span(class="mono secondary", request.unix_username),
                    ]),
                    @html.td(request.requested_models),
                    @html.td(
                      status_badge(
                        enterprise_request_state_label(
                          state.locale,
                          request.state,
                        ),
                        if request.state == "Submitted" {
                          "pending"
                        } else {
                          "ok"
                        },
                      ),
                    ),
                    @html.td(
                      if request.state == "Submitted" {
                        @html.div(class="table-actions", [
                          @html.button(
                            type_="button",
                            class="action-button primary",
                            disabled=state.loading ||
                              state.portal_node_id.trim() == "",
                            on_click=command(
                              emit,
                              ApproveEnterpriseLease(
                                request.request_id,
                                request.generation,
                              ),
                            ),
                            localized(state.locale, "Approve", "批准"),
                          ),
                          @html.button(
                            type_="button",
                            class="action-button",
                            disabled=state.loading,
                            on_click=command(
                              emit,
                              RejectEnterpriseLease(
                                request.request_id,
                                request.generation,
                              ),
                            ),
                            localized(state.locale, "Reject", "拒绝"),
                          ),
                        ])
                      } else {
                        @html.span(
                          class="mono secondary",
                          request.assigned_node_id,
                        )
                      },
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn qualified_services_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(
    attrs=@html.Attrs::build().aria_labelledby("qualified-services-title"),
    [
      @html.div(class="section-heading", [
        @html.div([
          @html.h2(
            id="qualified-services-title",
            localized(
              state.locale,
              "Qualified service adapters",
              "资质服务适配器",
            ),
          ),
          @html.p(
            class="section-copy",
            localized(
              state.locale,
              "Inspect normalized provider capabilities and callback evidence without exposing provider references or credentials.",
              "查看规范化供应商能力与回调证据，不暴露供应商引用或凭据。",
            ),
          ),
        ]),
        @html.span(
          class="resource-count",
          localized(
            state.locale,
            "\{state.qualified_services.length()} adapters",
            "\{state.qualified_services.length()} 个适配器",
          ),
        ),
      ]),
      @html.p(
        class="privacy-note",
        localized(
          state.locale,
          "LunaFide is a deterministic test simulator only. It is not a qualified trust service, payment processor, tax platform, or production security boundary.",
          "LunaFide 仅为确定性测试模拟器，不是合格信任服务、支付处理器、税务平台或生产安全边界。",
        ),
      ),
      if state.qualified_services.length() == 0 {
        @html.p(
          class="empty-state",
          localized(
            state.locale,
            "No provider adapters are loaded.",
            "尚未加载供应商适配器。",
          ),
        )
      } else {
        @html.div(class="table-scroll", [
          @html.table(class="resource-table", [
            @html.caption(
              class="sr-only",
              localized(
                state.locale,
                "Qualified service adapter posture",
                "资质服务适配器状态",
              ),
            ),
            @html.thead(
              @html.tr([
                @html.th(
                  scope=Col,
                  localized(state.locale, "Provider", "供应商"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Capability", "能力"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Environment", "环境"),
                ),
                @html.th(scope=Col, localized(state.locale, "State", "状态")),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Evidence policy", "证据策略"),
                ),
                @html.th(
                  scope=Col,
                  localized(state.locale, "Production", "生产"),
                ),
              ]),
            ),
            @html.tbody(
              [
                for service in state.qualified_services => {
                  @html.tr([
                    @html.td(@html.strong(service.provider)),
                    @html.td(service.capability),
                    @html.td(status_badge(service.environment, "warning")),
                    @html.td(status_badge(service.state, "ok")),
                    @html.td(service.evidence_policy),
                    @html.td(
                      status_badge(
                        if service.production_ready {
                          localized(state.locale, "Ready", "就绪")
                        } else {
                          localized(state.locale, "Not ready", "未就绪")
                        },
                        if service.production_ready {
                          "ok"
                        } else {
                          "danger"
                        },
                      ),
                    ),
                  ])
                }
              ],
            ),
          ]),
        ])
      },
    ],
  )
}

///|
fn audit_view(state : ConsoleState) -> @rabbita.Html {
  @html.section(attrs=@html.Attrs::build().aria_labelledby("audit-title"), [
    @html.div(class="section-heading", [
      @html.div([
        @html.h2(
          id="audit-title",
          localized(state.locale, "Audit evidence", "审计证据"),
        ),
        @html.p(
          class="section-copy",
          localized(
            state.locale,
            "Trace consequential changes from actor and evidence through result and receipt.",
            "从操作者和证据追踪重要变更，直至结果与回执。",
          ),
        ),
      ]),
      @html.span(
        class="resource-count",
        localized(
          state.locale,
          "\{state.audit.length()} events",
          "\{state.audit.length()} 个事件",
        ),
      ),
    ]),
    if state.audit.length() == 0 {
      @html.nothing
    } else {
      audit_decision_graph(state)
    },
    if state.audit.length() == 0 {
      @html.p(
        class="empty-state",
        localized(
          state.locale,
          "No audit events are available.",
          "暂无审计事件。",
        ),
      )
    } else {
      @html.div(class="table-scroll", [
        @html.table(class="resource-table", [
          @html.caption(
            class="sr-only",
            localized(
              state.locale,
              "Immutable operator audit evidence",
              "不可变的运维审计证据",
            ),
          ),
          @html.thead(
            @html.tr([
              @html.th(scope=Col, localized(state.locale, "Actor", "操作者")),
              @html.th(scope=Col, localized(state.locale, "Decision", "决策")),
              @html.th(scope=Col, localized(state.locale, "Evidence", "证据")),
              @html.th(scope=Col, localized(state.locale, "Result", "结果")),
              @html.th(scope=Col, localized(state.locale, "Receipt", "回执")),
            ]),
          ),
          @html.tbody(
            [
              for event in state.audit => audit_item(state.locale, event)
            ],
          ),
        ]),
      ])
    },
  ])
}

///|
fn audit_item(locale : @i18n.Locale, event : AuditRow) -> @rabbita.Html {
  @html.tr([
    @html.td(event.actor),
    @html.td(event.decision),
    @html.td(event.evidence),
    @html.td(status_badge(result_label(locale, event.result), "ok")),
    @html.td(class="mono secondary", event.receipt),
  ])
}

///|
fn confirmation_copy(
  locale : @i18n.Locale,
  action : DestructiveAction,
) -> String {
  match action {
    ActivateAccount(_) =>
      localized(
        locale, "Activating this account allows its external identity to exchange a fresh browser session with the listed LunaNexa roles.",
        "激活此账户后，其外部身份可按列出的 LunaNexa 角色换取新的浏览器会话。",
      )
    SuspendAccount(_) =>
      localized(
        locale, "Suspending this account immediately revokes its browser sessions and blocks new account authorization until reactivated.",
        "暂停此账户会立即撤销其浏览器会话，并阻止新的账户授权，直至重新激活。",
      )
    RevokeAccount(_) =>
      localized(
        locale, "Revoking this account is terminal, revokes every browser session, and prevents this external identity from signing in again.",
        "撤销此账户是终止性操作，会撤销全部浏览器会话，并阻止此外部身份再次登录。",
      )
    SetAccountRoles(_, roles) =>
      localized(
        locale,
        "This replaces the account's LunaNexa roles with: \{roles.map(role => account_role_label(locale, role)).join(", ")}. Existing sessions are re-authorized against the new roles immediately.",
        "此操作会将账户的 LunaNexa 角色替换为：\{roles.map(role => account_role_label(locale, role)).join("、")}。现有会话会立即按新角色重新授权。",
      )
    SuspendUser(_) =>
      localized(
        locale, "Suspending this identity immediately blocks new workspace authorization. Existing records remain available for audit and later reactivation.",
        "暂停此身份会立即阻止新的工作区授权。现有记录仍可用于审计和后续重新激活。",
      )
    RevokeUser(_) =>
      localized(
        locale, "Revoking this identity is terminal and blocks new workspace authorization. Confirm the principal before continuing.",
        "撤销此身份是终止性操作，并会阻止新的工作区授权。继续前请确认主体。",
      )
    RevokeAccessGrant(_) =>
      localized(
        locale, "Revoking this grant removes its scoped access. Confirm only after checking the principal and scope.",
        "撤销此授权会移除其限定范围的访问权限。请在核对主体和范围后确认。",
      )
    EndComputeLease(_) =>
      localized(
        locale, "Ending this lease revokes its inference capacity and workspace access. Running work may be interrupted.",
        "结束此租约会撤销其推理容量和工作区访问权限，正在运行的工作可能中断。",
      )
    TerminateExclusiveNodeLease(_, _) =>
      localized(
        locale, "This immediately revokes the leased user's access and interrupts all tenant processes. The DGX stays unavailable until container, account, credential, process, volume and lease-data checks pass; any failure quarantines it.",
        "此操作会立即撤销租用用户的访问权限并中断全部租户进程。只有容器、账户、凭据、进程、卷和租约数据检查全部通过后，DGX 才会恢复可用；任何失败都会使其进入隔离状态。",
      )
    RedriveNotificationDelivery(_, attempt_count, updated_unix_ms) =>
      localized(
        locale,
        "Redrive requeues this dead letter only if it still has attempt count \{attempt_count} and update generation \{updated_unix_ms}. A newer delivery state is rejected; refresh before retrying.",
        "仅当此死信的尝试次数仍为 \{attempt_count} 且更新代次仍为 \{updated_unix_ms} 时才会重新入队。若投递状态已更新，请求将被拒绝；请刷新后重试。",
      )
    CordonNode(_) =>
      localized(
        locale, "Cordoning prevents new assignments on this node.", "封锁调度会阻止此节点接收新的分配。",
      )
    DrainNode(_) =>
      localized(
        locale, "Draining prevents new assignments and moves eligible subsequent work.",
        "排空会阻止新的分配，并将后续符合条件的工作迁移出去。",
      )
    StopDeployment(_) =>
      localized(
        locale, "Stopping ends the selected deployment assignment.", "停止操作会结束所选部署分配。",
      )
    RollbackAlias(_) =>
      localized(
        locale, "Rolling back changes the model version selected by this alias.",
        "回滚会更改此模型别名所选择的模型版本。",
      )
    RollbackServiceDeployment(_) =>
      localized(
        locale, "Rolling back removes only the signed assignments owned by this model service.",
        "回滚只会移除此模型服务拥有的已签名分配。",
      )
    DeleteServiceDeployment(_) =>
      localized(
        locale, "Deleting stops this model service and retains its immutable operation and audit evidence.",
        "删除会停止此模型服务，并保留其不可变操作与审计证据。",
      )
  }
}

///|
fn confirmation_view(
  locale : @i18n.Locale,
  confirmation : Confirmation?,
  emit : @rabbita.Emit[ConsoleMessage]?,
) -> @rabbita.Html {
  match confirmation {
    None => @html.nothing
    Some(value) => {
      let recovery = value.action is RedriveNotificationDelivery(_, _, _)
      let account_change = value.action is ActivateAccount(_) ||
        value.action is SetAccountRoles(_, _)
      @html.aside(
        class="confirmation-panel",
        attrs=@html.Attrs::build()
          .role("alertdialog")
          .aria_labelledby("confirmation-title")
          .aria_describedby("confirmation-description"),
        [
          @html.p(
            class="eyebrow danger-copy",
            if recovery {
              localized(locale, "Recovery operation", "恢复操作")
            } else if account_change {
              localized(
                locale, "Account authority change", "账户权限变更",
              )
            } else {
              localized(locale, "Destructive operation", "破坏性操作")
            },
          ),
          @html.h2(
            id="confirmation-title",
            if recovery {
              localized(
                locale, "Confirm delivery redrive", "确认重新投递",
              )
            } else if account_change {
              localized(locale, "Confirm account change", "确认账户变更")
            } else {
              localized(
                locale, "Confirm destructive operation", "确认破坏性操作",
              )
            },
          ),
          @html.p(
            id="confirmation-description",
            confirmation_copy(locale, value.action),
          ),
          @html.dl(class="confirmation-scope", [
            @html.div([
              @html.dt(localized(locale, "Scope", "范围")),
              @html.dd(value.scope),
            ]),
            @html.div([
              @html.dt(
                localized(locale, "Confirmation receipt", "确认回执"),
              ),
              @html.dd(class="mono", value.receipt),
            ]),
          ]),
          @html.div(class="confirmation-actions", [
            @html.button(
              type_="button",
              on_click=command(emit, DismissConfirmation),
              localized(locale, "Cancel", "取消"),
            ),
            @html.button(
              type_="button",
              class="danger-button",
              disabled=value.confirmed,
              on_click=command(emit, ConfirmAction(value.action)),
              if recovery {
                localized(locale, "Confirm redrive", "确认重新投递")
              } else if account_change {
                localized(locale, "Confirm change", "确认变更")
              } else {
                localized(locale, "Confirm operation", "确认操作")
              },
            ),
          ]),
        ],
      )
    }
  }
}

///|
fn console_styles() -> String {
  (
    #|:root {
    #|  color-scheme: light dark;
    #|  --bg: #f3f6fa;
    #|  --surface: #ffffff;
    #|  --surface-subtle: #f8fafc;
    #|  --surface-hover: #f1f5f9;
    #|  --ink: #101828;
    #|  --muted: #667085;
    #|  --muted-strong: #475467;
    #|  --line: #dce3ec;
    #|  --line-strong: #c8d2df;
    #|  --accent: #2f6fed;
    #|  --accent-hover: #245dcc;
    #|  --accent-soft: #edf4ff;
    #|  --success: #087a55;
    #|  --success-soft: #ecfdf3;
    #|  --warning: #a15c07;
    #|  --warning-soft: #fff8e7;
    #|  --danger: #b42318;
    #|  --danger-soft: #fff1f0;
    #|  --sidebar: #0b1220;
    #|  --sidebar-ink: #e8eef8;
    #|  --sidebar-muted: #91a0b8;
    #|  --sidebar-active: #16243a;
    #|  --shadow-sm: 0 1px 2px rgba(16, 24, 40, .05);
    #|  --shadow-lg: 0 18px 48px rgba(15, 23, 42, .18);
    #|}
    #|@media (prefers-color-scheme: dark) {
    #|  :root {
    #|    --bg: #0f1521;
    #|    --surface: #171e2b;
    #|    --surface-subtle: #1b2433;
    #|    --surface-hover: #202b3d;
    #|    --ink: #edf2f9;
    #|    --muted: #9aa9bd;
    #|    --muted-strong: #c1ccda;
    #|    --line: #2a3546;
    #|    --line-strong: #3a475b;
    #|    --accent: #79a7ff;
    #|    --accent-hover: #9abbff;
    #|    --accent-soft: #182a49;
    #|    --success: #6ce9b2;
    #|    --success-soft: #14372c;
    #|    --warning: #fec84b;
    #|    --warning-soft: #392d15;
    #|    --danger: #fda29b;
    #|    --danger-soft: #40201f;
    #|    --sidebar: #080d16;
    #|    --sidebar-active: #152238;
    #|    --shadow-lg: 0 18px 48px rgba(0, 0, 0, .38);
    #|  }
    #|}
    #|* { box-sizing: border-box; }
    #|html { min-width: 20rem; background: var(--bg); }
    #|body {
    #|  margin: 0;
    #|  background: var(--bg);
    #|  color: var(--ink);
    #|  font-family: Inter, "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    #|  font-size: .875rem;
    #|  line-height: 1.5;
    #|  text-rendering: optimizeLegibility;
    #|}
    #|html[lang^="zh"] body {
    #|  font-family: "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", Inter, ui-sans-serif, system-ui, sans-serif;
    #|}
    #|html[lang^="zh"] .page-eyebrow,
    #|html[lang^="zh"] .eyebrow,
    #|html[lang^="zh"] .nav-group-label,
    #|html[lang^="zh"] .resource-table th,
    #|html[lang^="zh"] .confirmation-scope dt {
    #|  letter-spacing: .02em;
    #|  text-transform: none;
    #|}
    #|button, input, select, textarea { font: inherit; }
    #|button, select, input { min-height: 2.75rem; }
    #|button {
    #|  margin: 0;
    #|  padding: .55rem .8rem;
    #|  border: 1px solid var(--line-strong);
    #|  border-radius: .45rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|  font-weight: 650;
    #|  cursor: pointer;
    #|  transition: background-color 120ms ease, border-color 120ms ease, color 120ms ease;
    #|}
    #|button:hover:not(:disabled) { background: var(--surface-hover); border-color: var(--muted); }
    #|button:disabled { cursor: not-allowed; opacity: .5; }
    #|button:focus-visible, input:focus-visible, select:focus-visible, textarea:focus-visible, summary:focus-visible, a:focus-visible {
    #|  outline: 3px solid var(--accent);
    #|  outline-offset: 2px;
    #|}
    #|.primary-button { border-color: var(--accent); background: var(--accent); color: #fff; }
    #|.primary-button:hover:not(:disabled) { border-color: var(--accent-hover); background: var(--accent-hover); }
    #|.danger-secondary { border-color: color-mix(in srgb, var(--danger) 55%, var(--line)); color: var(--danger); background: transparent; }
    #|.danger-secondary:hover:not(:disabled) { border-color: var(--danger); background: var(--danger-soft); }
    #|.danger-button { border-color: var(--danger); background: var(--danger); color: #fff; }
    #|.danger-button:hover:not(:disabled) { border-color: var(--danger); background: #8f1c13; }
    #|.console-root {
    #|  display: grid;
    #|  grid-template-columns: 14rem minmax(0, 1fr);
    #|  grid-template-rows: auto minmax(0, 1fr);
    #|  min-height: 100vh;
    #|  background: var(--bg);
    #|}
    #|.app-shell { display: contents; }
    #|.skip-link, .sr-only { position: absolute; left: -9999px; }
    #|.skip-link:focus {
    #|  left: 15rem;
    #|  top: .75rem;
    #|  z-index: 60;
    #|  padding: .65rem .9rem;
    #|  border-radius: .4rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|  box-shadow: var(--shadow-lg);
    #|}
    #|.sidebar {
    #|  grid-column: 1;
    #|  grid-row: 1 / 3;
    #|  position: sticky;
    #|  top: 0;
    #|  height: 100vh;
    #|  display: flex;
    #|  flex-direction: column;
    #|  overflow-y: auto;
    #|  padding: 1.15rem .75rem 1rem;
    #|  background: var(--sidebar);
    #|  color: var(--sidebar-ink);
    #|}
    #|.brand {
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .7rem;
    #|  min-height: 3.25rem;
    #|  margin: 0 .35rem 1.1rem;
    #|  padding-bottom: 1rem;
    #|  border-bottom: 1px solid rgba(255, 255, 255, .1);
    #|}
    #|.brand-mark {
    #|  display: grid;
    #|  place-items: center;
    #|  width: 2.1rem;
    #|  height: 2.1rem;
    #|  flex: none;
    #|  border: 1px solid rgba(255, 255, 255, .24);
    #|  border-radius: .55rem;
    #|  background: #f8fafc;
    #|  color: #0b1220;
    #|  font-size: .72rem;
    #|  font-weight: 800;
    #|  letter-spacing: .05em;
    #|}
    #|.brand-copy { min-width: 0; }
    #|.brand-name { display: block; font-size: .96rem; font-weight: 760; letter-spacing: -.01em; }
    #|.brand-product { display: block; color: var(--sidebar-muted); font-size: .72rem; }
    #|.sidebar nav { display: flex; flex-direction: column; gap: .15rem; }
    #|.nav-group-label {
    #|  margin: 1rem .65rem .35rem;
    #|  color: var(--sidebar-muted);
    #|  font-size: .65rem;
    #|  font-weight: 750;
    #|  letter-spacing: .11em;
    #|  text-transform: uppercase;
    #|}
    #|.nav-group-label:first-child { margin-top: 0; }
    #|.nav-link {
    #|  position: relative;
    #|  width: 100%;
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .65rem;
    #|  padding: .55rem .65rem;
    #|  border-color: transparent;
    #|  background: transparent;
    #|  color: var(--sidebar-muted);
    #|  text-align: left;
    #|  font-weight: 600;
    #|}
    #|.nav-link:hover:not(:disabled) { border-color: transparent; background: rgba(255, 255, 255, .055); color: var(--sidebar-ink); }
    #|.nav-link.active { background: var(--sidebar-active); color: #fff; }
    #|.nav-indicator { width: .3rem; height: .3rem; flex: none; border-radius: 999px; background: currentColor; opacity: .45; }
    #|.nav-link.active .nav-indicator { width: .38rem; height: 1.2rem; border-radius: .3rem; background: var(--accent); opacity: 1; }
    #|.sidebar-footer {
    #|  margin: auto .4rem 0;
    #|  padding-top: 1rem;
    #|  border-top: 1px solid rgba(255, 255, 255, .1);
    #|  color: var(--sidebar-muted);
    #|  font-size: .72rem;
    #|}
    #|.sidebar-footer strong { display: block; margin-bottom: .2rem; color: var(--sidebar-ink); font-size: .75rem; }
    #|.connection-panel {
    #|  grid-column: 2;
    #|  grid-row: 1;
    #|  position: sticky;
    #|  top: 0;
    #|  z-index: 30;
    #|  min-height: 3.65rem;
    #|  padding: .45rem 1.75rem;
    #|  border-bottom: 1px solid var(--line);
    #|  background: color-mix(in srgb, var(--surface) 94%, transparent);
    #|  box-shadow: var(--shadow-sm);
    #|  backdrop-filter: blur(12px);
    #|}
    #|.connection-panel summary {
    #|  min-height: 44px;
    #|  display: flex;
    #|  align-items: center;
    #|  justify-content: flex-end;
    #|  gap: .65rem;
    #|  color: var(--muted-strong);
    #|  cursor: pointer;
    #|  list-style: none;
    #|}
    #|.connection-panel summary::-webkit-details-marker { display: none; }
    #|.connection-panel summary::after { content: "+"; color: var(--muted); font-size: 1rem; }
    #|.connection-panel[open] summary::after { content: "–"; }
    #|.connection-summary-label { font-weight: 700; color: var(--ink); }
    #|.connection-endpoint { max-width: 22rem; overflow: hidden; color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .72rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.connection-state { display: inline-flex; align-items: center; gap: .4rem; font-size: .75rem; }
    #|.connection-state::before { width: .45rem; height: .45rem; border-radius: 999px; background: currentColor; content: ""; }
    #|.connection-state-ready { color: var(--success); }
    #|.connection-state-needed { color: var(--warning); }
    #|.demo-banner {
    #|  display: flex;
    #|  align-items: center;
    #|  gap: .6rem;
    #|  margin: 0 2rem;
    #|  padding: .65rem .8rem;
    #|  border: 1px solid color-mix(in srgb, var(--accent) 35%, var(--line));
    #|  border-radius: .55rem;
    #|  background: var(--accent-soft);
    #|  color: var(--muted-strong);
    #|  font-size: .76rem;
    #|}
    #|.demo-banner-mark {
    #|  padding: .2rem .38rem;
    #|  border-radius: .3rem;
    #|  background: var(--accent);
    #|  color: white;
    #|  font-size: .62rem;
    #|  font-weight: 800;
    #|  letter-spacing: .08em;
    #|}
    #|.demo-banner strong { color: var(--ink); }
    #|.connection-form {
    #|  display: grid;
    #|  grid-template-columns: repeat(2, minmax(13rem, 1fr));
    #|  gap: .8rem 1rem;
    #|  max-width: 60rem;
    #|  margin: .45rem 0 .85rem auto;
    #|  padding: 1rem;
    #|  border: 1px solid var(--line);
    #|  border-radius: .65rem;
    #|  background: var(--surface-subtle);
    #|}
    #|.connection-field label, .field-group label { display: block; margin-bottom: .35rem; color: var(--muted-strong); font-size: .75rem; font-weight: 700; }
    #|.connection-field input, .field-group input, .field-group select, .field-group textarea {
    #|  width: 100%;
    #|  border: 1px solid var(--line-strong);
    #|  border-radius: .4rem;
    #|  background: var(--surface);
    #|  color: var(--ink);
    #|}
    #|.connection-field input, .field-group input { padding: .55rem .65rem; }
    #|.field-group input[aria-invalid="true"] { border-color: var(--danger); box-shadow: 0 0 0 1px var(--danger-soft); }
    #|.field-help { margin: .35rem 0 0; color: var(--muted); font-size: .7rem; line-height: 1.4; }
    #|.field-error { color: var(--danger); }
    #|.connection-help { display: block; margin-top: .35rem; color: var(--muted); font-size: .7rem; line-height: 1.4; }
    #|.connection-actions { display: flex; align-items: end; justify-content: space-between; gap: 1rem; grid-column: 1 / -1; }
    #|.connection-actions .secondary { max-width: 34rem; }
    #|.workspace { grid-column: 2; grid-row: 2; min-width: 0; }
    #|.workspace-topbar {
    #|  display: flex;
    #|  align-items: flex-start;
    #|  justify-content: space-between;
    #|  gap: 1.5rem;
    #|  padding: 1.55rem 2rem 1.2rem;
    #|  border-bottom: 1px solid var(--line);
    #|}
    #|.page-eyebrow, .eyebrow { margin: 0 0 .25rem; color: var(--muted); font-size: .68rem; font-weight: 780; letter-spacing: .1em; text-transform: uppercase; }
    #|.page-heading h1 { margin: 0; font-size: 1.55rem; line-height: 1.2; letter-spacing: -.025em; }
    #|.page-description { max-width: 46rem; margin: .35rem 0 0; color: var(--muted); }
    #|.topbar-actions { display: flex; align-items: center; gap: .6rem; flex: none; }
    #|.locale-control { display: flex; align-items: center; gap: .4rem; min-height: 44px; }
    #|.locale-control label { color: var(--muted); font-size: .72rem; font-weight: 700; }
    #|.locale-select { min-width: 8rem; min-height: 44px; padding: .5rem 1.8rem .5rem .65rem; border: 1px solid var(--line-strong); border-radius: .45rem; background: var(--surface); color: var(--ink); font-weight: 650; }
    #|.alert-summary { display: inline-flex; align-items: center; gap: .45rem; min-height: 2.25rem; padding: .35rem .65rem; border: 1px solid var(--line); border-radius: 999px; background: var(--surface); color: var(--muted-strong); font-size: .75rem; font-weight: 650; }
    #|.alert-summary::before { width: .45rem; height: .45rem; border-radius: 999px; background: var(--success); content: ""; }
    #|.alert-summary.awaiting-telemetry::before { background: var(--muted); }
    #|.alert-summary.has-alerts { border-color: color-mix(in srgb, var(--warning) 40%, var(--line)); background: var(--warning-soft); color: var(--warning); }
    #|.alert-summary.has-alerts::before { background: var(--warning); }
    #|.workspace-main { width: 100%; max-width: 100rem; margin: 0 auto; padding: 1.45rem 2rem 3rem; }
    #|h2, h3 { letter-spacing: -.015em; }
    #|h2 { margin: 0; font-size: 1.16rem; line-height: 1.35; }
    #|h3 { margin: 1.5rem 0 .65rem; font-size: .96rem; }
    #|.overview-grid { display: grid; grid-template-columns: minmax(0, 2fr) minmax(15rem, 1fr); gap: 1rem; }
    #|.health-panel, .activity-panel, .stat, .operation-panel, .stream-panel, .evidence-list {
    #|  border: 1px solid var(--line);
    #|  border-radius: .65rem;
    #|  background: var(--surface);
    #|  box-shadow: var(--shadow-sm);
    #|}
    #|.health-panel { position: relative; overflow: hidden; padding: 1.4rem 1.5rem; }
    #|.health-panel::before { position: absolute; inset: 0 auto 0 0; width: .25rem; background: var(--success); content: ""; }
    #|.health-panel-unknown::before { background: var(--line-strong); }
    #|.health-panel-warning::before { background: var(--warning); }
    #|.health-title { display: flex; align-items: center; gap: .65rem; }
    #|.health-title h2 { font-size: 1.35rem; }
    #|.health-dot { width: .7rem; height: .7rem; flex: none; border: .18rem solid color-mix(in srgb, var(--success) 20%, transparent); border-radius: 999px; background: var(--success); box-shadow: 0 0 0 .2rem var(--success-soft); }
    #|.health-panel-unknown .health-dot { background: var(--muted); box-shadow: 0 0 0 .2rem var(--surface-hover); }
    #|.health-panel-warning .health-dot { background: var(--warning); box-shadow: 0 0 0 .2rem var(--warning-soft); }
    #|.health-copy { max-width: 43rem; margin: .55rem 0 1.15rem 1.35rem; color: var(--muted); }
    #|.health-facts { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .75rem; margin: 0; }
    #|.health-facts > div { padding: .7rem .8rem; border-left: 1px solid var(--line); }
    #|.health-facts dt { color: var(--muted); font-size: .7rem; }
    #|.health-facts dd { margin: .15rem 0 0; font-size: 1rem; font-weight: 750; }
    #|.activity-panel { padding: 1.25rem 1.35rem; background: linear-gradient(145deg, var(--surface), var(--surface-subtle)); }
    #|.activity-value { margin: .1rem 0 0; font-size: 2.6rem; font-weight: 780; line-height: 1; letter-spacing: -.05em; }
    #|.activity-label { margin: .35rem 0 0; color: var(--muted); }
    #|.activity-divider { height: 1px; margin: 1.15rem 0; background: var(--line); }
    #|.activity-note { display: grid; gap: .15rem; margin: 0; }
    #|.activity-note span { color: var(--muted); font-size: .75rem; }
    #|.stats { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .75rem; margin: .8rem 0 0; }
    #|.stat { position: relative; min-height: 7rem; padding: .95rem 1rem; overflow: hidden; }
    #|.stat::before { position: absolute; inset: 0 0 auto; height: .16rem; background: var(--line-strong); content: ""; }
    #|.stat-ok::before { background: var(--success); }
    #|.stat-warning::before { background: var(--warning); }
    #|.stat-danger::before { background: var(--danger); }
    #|.stat dt { color: var(--muted); font-size: .72rem; font-weight: 650; }
    #|.stat dd { margin: .3rem 0 .15rem; font-size: 1.6rem; font-weight: 780; line-height: 1.15; letter-spacing: -.035em; }
    #|.stat-detail { color: var(--muted); font-size: .7rem; }
    #|.readiness-panel { display: grid; grid-template-columns: minmax(18rem, .85fr) minmax(24rem, 1.15fr); gap: 1.5rem; margin-top: 1rem; padding: 1.25rem 1.35rem; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.readiness-copy h2 { margin-bottom: .35rem; }
    #|.readiness-action { margin-top: 1rem; }
    #|.readiness-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .6rem; margin: 0; padding: 0; list-style: none; }
    #|.readiness-item { display: flex; align-items: flex-start; gap: .65rem; min-width: 0; padding: .75rem; border: 1px solid color-mix(in srgb, var(--warning) 35%, var(--line)); border-radius: .5rem; background: var(--warning-soft); }
    #|.readiness-item.ready { border-color: color-mix(in srgb, var(--success) 28%, var(--line)); background: var(--success-soft); }
    #|.readiness-mark { display: grid; place-items: center; width: 1.35rem; height: 1.35rem; flex: none; border-radius: 999px; background: var(--warning); color: white; font-size: .72rem; font-weight: 800; }
    #|.readiness-item.ready .readiness-mark { background: var(--success); }
    #|.readiness-item div { display: grid; gap: .15rem; min-width: 0; }
    #|.section-heading, .subsection-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; margin-bottom: 1rem; }
    #|.section-heading h2 { margin-bottom: .2rem; }
    #|.enterprise-request-heading { margin-top: 2rem; padding-top: 1.5rem; border-top: 1px solid var(--line); }
    #|.portal-node-picker { min-width: 16rem; }
    #|.portal-node-picker label { display: block; margin-bottom: .3rem; color: var(--muted); font-size: .68rem; font-weight: 700; }
    #|.portal-node-picker input { width: 100%; min-height: 2.5rem; padding: .55rem .65rem; border: 1px solid var(--line-strong); border-radius: .45rem; background: var(--panel-strong); color: var(--text); }
    #|.table-actions { display: flex; flex-wrap: wrap; gap: .4rem; }
    #|.action-button { min-height: 2.25rem; padding: .4rem .65rem; border: 1px solid var(--line-strong); border-radius: .4rem; background: var(--panel-strong); color: var(--text); font: inherit; font-weight: 750; cursor: pointer; }
    #|.action-button.primary { border-color: var(--accent); color: var(--accent); }
    #|.action-button:disabled { opacity: .45; cursor: not-allowed; }
    #|.section-copy { max-width: 52rem; margin: 0; color: var(--muted); }
    #|.resource-count { flex: none; margin-top: .15rem; color: var(--muted); font-size: .75rem; }
    #|.alerts-window-control { display: flex; align-items: center; flex-wrap: wrap; gap: .55rem; margin: 0 0 1rem; }
    #|.alerts-window-control label { color: var(--muted); font-size: .72rem; font-weight: 700; }
    #|.alerts-window-select { min-height: 44px; padding: .45rem 1.9rem .45rem .6rem; border: 1px solid var(--line-strong); border-radius: .5rem; background: var(--surface); color: var(--text); font: inherit; }
    #|.alerts-window-summary { color: var(--muted); font-size: .75rem; }
    #|.alerts-day-heading th { text-transform: none; letter-spacing: .02em; font-size: .74rem; font-weight: 760; color: var(--muted-strong); }
    #|.models-group-heading th { padding-top: 1.15rem; border-bottom: 1px solid var(--line); text-transform: none; letter-spacing: 0; font-size: .85rem; font-weight: 760; color: var(--text); background: none; }
    #|.models-group-heading th strong { margin-right: .5rem; }
    #|.subsection-heading { align-items: center; margin: 1.6rem 0 .65rem; }
    #|.subsection-heading h3 { margin: 0; }
    #|.lease-cleanup-policy { margin: .9rem 0 1.15rem; padding: .85rem 1rem; border: 1px solid color-mix(in srgb, var(--warning) 38%, var(--line)); border-left: 4px solid var(--warning); border-radius: .55rem; background: color-mix(in srgb, var(--warning-soft) 68%, var(--surface)); }
    #|.lease-cleanup-policy p { margin: .25rem 0 0; color: var(--muted); font-size: .78rem; }
    #|.table-scroll { max-width: 100%; overflow-x: auto; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.resource-table { width: 100%; min-width: 48rem; border-collapse: collapse; font-size: .8rem; }
    #|.resource-table th, .resource-table td { padding: .65rem .8rem; text-align: left; vertical-align: middle; border-bottom: 1px solid var(--line); }
    #|.resource-table th { height: 2.4rem; background: var(--surface-subtle); color: var(--muted); font-size: .66rem; font-weight: 760; letter-spacing: .07em; text-transform: uppercase; }
    #|.resource-table tbody tr:last-child td { border-bottom: 0; }
    #|.resource-table tbody tr:hover { background: var(--surface-hover); }
    #|.resource-table td > span, .resource-table td > strong { display: block; }
    #|.row-actions { white-space: nowrap; }
    #|.row-actions button { min-width: 5rem; margin-right: .35rem; }
    #|.row-actions button:last-child { margin-right: 0; }
    #|.row-actions .secondary { padding: .65rem 0; }
    #|.secondary { color: var(--muted); font-size: .74rem; }
    #|.mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; overflow-wrap: anywhere; }
    #|.account-self { display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 1rem; margin: 0 0 1rem; padding: .9rem 1rem; border: 1px solid color-mix(in srgb, var(--accent) 28%, var(--line)); border-radius: .65rem; background: var(--accent-soft); }
    #|.account-self h3 { margin: 0; }
    #|.account-self .section-copy { margin-top: .2rem; }
    #|.account-self-static { display: block; color: var(--muted-strong); }
    #|.account-self-evidence { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: .55rem; }
    #|.account-session-evidence { width: 100%; border-top: 1px solid color-mix(in srgb, var(--accent) 20%, var(--line)); }
    #|.account-session-evidence summary { min-height: 44px; padding: .65rem 0; cursor: pointer; color: var(--muted-strong); font-weight: 700; }
    #|.account-session-evidence .resource-table { min-width: 38rem; }
    #|.access-package-panel { margin-bottom: 1.2rem; padding: 1.1rem; border: 1px solid color-mix(in srgb, var(--accent) 35%, var(--line)); border-radius: .8rem; background: linear-gradient(145deg, var(--surface), var(--accent-soft)); box-shadow: var(--shadow-sm); }
    #|.access-package-intro h3 { margin: 0; font-size: 1.15rem; }
    #|.access-package-intro .section-copy { max-width: 55rem; }
    #|.access-package-steps { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: .5rem; margin: 1rem 0; padding: 0; list-style: none; }
    #|.access-package-steps li { display: flex; align-items: center; gap: .5rem; min-height: 3rem; padding: .55rem .7rem; border: 1px solid var(--line); border-radius: .55rem; background: var(--surface); color: var(--muted-strong); }
    #|.access-package-steps strong { display: grid; place-items: center; width: 1.45rem; height: 1.45rem; flex: none; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-size: .72rem; }
    #|.access-package-form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .8rem 1rem; }
    #|.access-provider-details { margin-top: .75rem; border: 1px solid var(--line); border-radius: .55rem; background: var(--surface); }
    #|.access-provider-details summary { min-height: 44px; padding: .65rem .8rem; cursor: pointer; color: var(--muted-strong); font-weight: 700; }
    #|.access-provider-details .access-package-form-grid { padding: 0 .8rem .8rem; }
    #|.access-package-review { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: .85rem; padding: .85rem; border: 1px solid var(--line); border-radius: .55rem; background: var(--surface); }
    #|.access-package-review h4 { margin: 0; }
    #|.access-package-review .section-copy { margin-top: .2rem; }
    #|.access-lifetime { display: flex; align-items: center; justify-content: flex-end; flex-wrap: wrap; gap: .35rem; }
    #|.access-lifetime > span { width: 100%; color: var(--muted); font-size: .7rem; font-weight: 700; text-align: right; }
    #|.access-package-submit { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: .55rem; margin-top: .85rem; }
    #|.verification-toggle.selected { border-color: var(--success); background: var(--success-soft); color: var(--success); }
    #|.access-package-list { display: grid; gap: .75rem; margin-top: 1rem; padding-top: 1rem; border-top: 1px solid var(--line); }
    #|.access-package-card { padding: .9rem; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); }
    #|.access-package-card-heading, .access-package-next { display: flex; align-items: center; justify-content: space-between; gap: .75rem; }
    #|.access-package-card-heading > div > span { display: block; }
    #|.access-package-milestones { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: .35rem; margin: .8rem 0; padding: 0; list-style: none; }
    #|.access-package-milestones li { display: flex; align-items: center; gap: .35rem; min-height: 2.4rem; padding: .4rem .5rem; border: 1px solid var(--line); border-radius: .45rem; color: var(--muted); font-size: .72rem; }
    #|.access-package-milestones li.complete { border-color: color-mix(in srgb, var(--success) 32%, var(--line)); background: var(--success-soft); color: var(--success); }
    #|.access-package-milestones li.current { border-color: color-mix(in srgb, var(--accent) 35%, var(--line)); background: var(--accent-soft); color: var(--accent); font-weight: 700; }
    #|.access-milestone-mark { font-weight: 800; }
    #|.access-package-ready { color: var(--success); font-weight: 750; }
    #|.access-package-evidence { max-width: 34rem; }
    #|.access-package-evidence summary { min-height: 44px; padding: .55rem 0; cursor: pointer; color: var(--muted-strong); font-weight: 700; }
    #|.access-package-evidence dl { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: .35rem .7rem; margin: 0 0 .7rem; }
    #|.access-package-evidence dt { color: var(--muted); font-size: .68rem; font-weight: 700; }
    #|.access-package-evidence dd { margin: 0; overflow-wrap: anywhere; }
    #|.account-invite-panel { margin-bottom: 1.2rem; overflow: hidden; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.account-invite-panel summary { min-height: 44px; padding: .8rem 1rem; cursor: pointer; color: var(--ink); font-weight: 760; }
    #|.account-invite-panel[open] summary { border-bottom: 1px solid var(--line); background: var(--surface-subtle); }
    #|.account-invite-content { padding: 1rem; }
    #|.account-invite-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .8rem 1rem; margin-top: 1rem; }
    #|.account-role-fieldset { margin: 1rem 0 0; padding: .8rem; border: 1px solid var(--line); border-radius: .5rem; }
    #|.account-role-fieldset legend { padding: 0 .35rem; font-weight: 730; }
    #|.account-role-controls { display: flex; flex-wrap: wrap; gap: .35rem; }
    #|.role-toggle { min-height: 44px; padding: .45rem .65rem; font-size: .7rem; }
    #|.role-toggle.selected { border-color: var(--accent); background: var(--accent-soft); color: var(--accent); }
    #|.account-invite-actions { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: 1rem; padding-top: .8rem; border-top: 1px solid var(--line); }
    #|.account-table .resource-table { min-width: 66rem; }
    #|.status { display: inline-flex !important; align-items: center; gap: .35rem; width: max-content; padding: .2rem .5rem; border: 1px solid var(--line); border-radius: 999px; background: var(--surface-subtle); color: var(--muted-strong); font-size: .7rem; font-weight: 720; line-height: 1.2; }
    #|.status::before { width: .38rem; height: .38rem; border-radius: 999px; background: currentColor; content: ""; }
    #|.status-ok { border-color: color-mix(in srgb, var(--success) 30%, var(--line)); background: var(--success-soft); color: var(--success); }
    #|.status-pending { border-color: color-mix(in srgb, var(--accent) 30%, var(--line)); background: var(--accent-soft); color: var(--accent); }
    #|.status-warning { border-color: color-mix(in srgb, var(--warning) 35%, var(--line)); background: var(--warning-soft); color: var(--warning); }
    #|.status-danger { border-color: color-mix(in srgb, var(--danger) 35%, var(--line)); background: var(--danger-soft); color: var(--danger); }
    #|.status-muted { color: var(--muted); }
    #|.loading-state, .error-state, .success-state { margin: 0 0 1rem; padding: .8rem 1rem; border: 1px solid var(--line); border-left-width: .25rem; border-radius: .45rem; background: var(--surface); }
    #|.loading-state { border-left-color: var(--accent); }
    #|.error-state { border-left-color: var(--danger); background: var(--danger-soft); }
    #|.success-state { border-left-color: var(--success); background: var(--success-soft); }
    #|.empty-state { margin: 0; padding: 2.2rem; border: 1px dashed var(--line-strong); border-radius: .6rem; background: var(--surface-subtle); color: var(--muted); text-align: center; }
    #|.empty-state.compact { padding: 1rem; }
    #|.empty-state-action { display: grid; justify-items: center; gap: .55rem; }
    #|.empty-state-action strong { color: var(--ink); font-size: .95rem; }
    #|.empty-state-action p { max-width: 36rem; margin: 0; }
    #|.cluster-topology { margin-bottom: 1.5rem; overflow: hidden; border: 1px solid var(--line); border-radius: .8rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.topology-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1.5rem; padding: 1.2rem 1.3rem; border-bottom: 1px solid var(--line); background: linear-gradient(135deg, var(--surface), var(--surface-subtle)); }
    #|.topology-heading h2 { font-size: 1.3rem; }
    #|.topology-heading p:last-child { max-width: 48rem; margin: .35rem 0 0; color: var(--muted); }
    #|.topology-summary { display: flex; flex-wrap: wrap; justify-content: flex-end; gap: .4rem; }
    #|.topology-summary-item { padding: .35rem .55rem; border: 1px solid var(--line); border-radius: 999px; background: var(--surface); color: var(--muted); font-size: .7rem; white-space: nowrap; }
    #|.topology-summary-item strong { color: var(--ink); }
    #|.topology-graph-frame { margin: 0; overflow-x: auto; background-image: linear-gradient(rgba(86, 104, 117, .05) 1px, transparent 1px), linear-gradient(90deg, rgba(86, 104, 117, .05) 1px, transparent 1px); background-size: 24px 24px; }
    #|.topology-graph { display: grid; grid-template-columns: minmax(8rem, .72fr) minmax(3rem, .28fr) minmax(15rem, 1.15fr) minmax(3.5rem, .34fr) minmax(15rem, 1.3fr); align-items: center; min-width: 44rem; min-height: 24rem; padding: 1.5rem; }
    #|.topology-graph-frame figcaption { padding: .65rem 1.25rem; border-top: 1px solid var(--line); background: color-mix(in srgb, var(--surface) 92%, transparent); color: var(--muted); font-size: .68rem; }
    #|.graph-node { position: relative; z-index: 2; display: flex; align-items: center; gap: .65rem; min-width: 0; padding: .75rem; border: 1px solid var(--line); border-radius: .58rem; background: var(--surface); box-shadow: 0 .25rem .75rem rgba(15, 23, 42, .07); }
    #|.graph-node > div { display: grid; min-width: 0; flex: 1; }
    #|.graph-node h3, .graph-cluster-heading h3 { margin: .05rem 0; font-size: .85rem; }
    #|.graph-node small, .graph-cluster-heading small { color: var(--muted); font-size: .58rem; font-weight: 760; letter-spacing: .08em; text-transform: uppercase; }
    #|.graph-node > div > span { color: var(--muted); font-size: .64rem; }
    #|.graph-node-symbol { display: grid; place-items: center; width: 2.25rem; height: 2.25rem; flex: none; border: 1px solid color-mix(in srgb, var(--accent) 42%, var(--line)); border-radius: 999px; background: var(--accent-soft); color: var(--accent); font: 800 .66rem ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.graph-access-node { align-items: flex-start; flex-direction: column; border-color: color-mix(in srgb, var(--muted) 30%, var(--line)); }
    #|.graph-control-node { border-color: color-mix(in srgb, var(--accent) 52%, var(--line)); box-shadow: 0 0 0 .22rem var(--accent-soft), 0 .4rem 1rem rgba(15, 23, 42, .08); }
    #|.graph-management-stack { position: relative; display: grid; gap: 3.1rem; }
    #|.graph-management-stack::after { position: absolute; z-index: 0; top: 4rem; bottom: 4.4rem; left: 50%; width: 2px; background: color-mix(in srgb, var(--accent) 50%, var(--line)); content: ""; }
    #|.graph-dependency-branch { position: relative; z-index: 1; display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .55rem; }
    #|.graph-dependency-branch::before { position: absolute; top: -1.55rem; left: 25%; right: 25%; height: 1.55rem; border-top: 2px solid color-mix(in srgb, var(--accent) 50%, var(--line)); border-left: 2px solid color-mix(in srgb, var(--accent) 50%, var(--line)); border-right: 2px solid color-mix(in srgb, var(--accent) 50%, var(--line)); border-radius: .35rem .35rem 0 0; content: ""; }
    #|.graph-dependency-node { padding: .55rem; box-shadow: none; }
    #|.graph-dependency-node strong { overflow: hidden; font-size: .68rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.graph-node-symbol-data { border-radius: .4rem; background: var(--surface-subtle); color: var(--muted-strong); }
    #|.graph-node-symbol-store { border-color: color-mix(in srgb, var(--warning) 40%, var(--line)); border-radius: .4rem; background: var(--warning-soft); color: var(--warning); }
    #|.graph-edge { position: relative; z-index: 1; height: 2px; background: color-mix(in srgb, var(--muted) 58%, var(--line)); }
    #|.graph-edge::before { position: absolute; right: -.05rem; top: 50%; width: .55rem; height: .55rem; border-top: 2px solid var(--muted); border-right: 2px solid var(--muted); content: ""; transform: translateY(-50%) rotate(45deg); }
    #|.graph-edge::after { position: absolute; left: 50%; top: 50%; width: .45rem; height: .45rem; border: 2px solid var(--surface); border-radius: 999px; background: var(--accent); content: ""; transform: translate(-50%, -50%); }
    #|.graph-edge span { position: absolute; left: 50%; bottom: .65rem; padding: .16rem .32rem; border: 1px solid var(--line); border-radius: .3rem; background: var(--surface); color: var(--muted-strong); font: 700 .58rem ui-monospace, SFMono-Regular, Menlo, monospace; white-space: nowrap; transform: translateX(-50%); }
    #|.graph-compute-cluster { position: relative; z-index: 2; padding: .8rem .8rem .8rem 1rem; border: 1px dashed color-mix(in srgb, var(--success) 42%, var(--line)); border-radius: .65rem; background: color-mix(in srgb, var(--success-soft) 42%, var(--surface)); }
    #|.graph-cluster-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: .7rem; padding: 0 0 .6rem .35rem; }
    #|.graph-cluster-heading > div { display: grid; }
    #|.graph-cluster-heading > span { color: var(--muted); font-size: .64rem; white-space: nowrap; }
    #|.graph-compute-list { position: relative; display: grid; gap: .45rem; margin: 0; padding: 0 0 0 1.25rem; list-style: none; }
    #|.graph-compute-list::before { position: absolute; top: 1.5rem; bottom: 1.5rem; left: .28rem; width: 2px; background: color-mix(in srgb, var(--success) 45%, var(--line)); content: ""; }
    #|.graph-compute-node { min-height: 3.3rem; padding: .5rem .55rem; box-shadow: none; }
    #|.graph-compute-node::before { position: absolute; top: 50%; right: 100%; width: 1rem; height: 2px; background: color-mix(in srgb, var(--success) 45%, var(--line)); content: ""; }
    #|.graph-compute-node::after { position: absolute; top: 50%; right: calc(100% + .9rem); width: .45rem; height: .45rem; border: 2px solid var(--surface); border-radius: 999px; background: var(--success); content: ""; transform: translateY(-50%); }
    #|.graph-compute-node strong { overflow: hidden; font-size: .7rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.graph-compute-node small { color: var(--muted); font-size: .58rem; }
    #|.graph-node-symbol-compute { width: 1.8rem; height: 1.8rem; border-color: color-mix(in srgb, var(--success) 42%, var(--line)); border-radius: .4rem; background: var(--success-soft); color: var(--success); font-size: .56rem; }
    #|.graph-compute-missing { margin: .4rem 0 0 1.1rem; }
    #|.topology-missing { display: grid; gap: .45rem; margin-top: .8rem; padding: .8rem; border: 1px dashed color-mix(in srgb, var(--warning) 50%, var(--line)); border-radius: .48rem; background: var(--warning-soft); }
    #|.topology-missing strong { font-size: .76rem; }
    #|.topology-missing span:last-child { color: var(--muted-strong); font-size: .68rem; }
    #|.topology-relationships { border-top: 1px solid var(--line); background: var(--surface-subtle); }
    #|.topology-relationships summary { min-height: 44px; padding: .75rem 1.25rem; color: var(--muted-strong); cursor: pointer; font-size: .75rem; font-weight: 720; }
    #|.topology-relationships dl { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .7rem; margin: 0; padding: 0 1.25rem 1rem; }
    #|.topology-relationships dl > div { min-width: 0; padding: .75rem; border: 1px solid var(--line); border-radius: .45rem; background: var(--surface); }
    #|.topology-relationships dt { color: var(--ink); font-size: .7rem; font-weight: 720; }
    #|.topology-relationships dd { margin: .3rem 0 0; color: var(--muted); font-size: .67rem; }
    #|.topology-scope-note { margin: 0; padding: 0 1.25rem 1rem; color: var(--muted); font-size: .68rem; }
    #|.node-list { display: grid; gap: .65rem; }
    #|.node-record { overflow: hidden; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.node-record[open] { border-color: color-mix(in srgb, var(--accent) 32%, var(--line)); }
    #|.node-summary { display: grid; grid-template-columns: minmax(11rem, 1.25fr) minmax(7rem, .65fr) minmax(8rem, .75fr) minmax(7rem, .65fr) minmax(11rem, 1fr) auto; align-items: center; gap: 1rem; min-height: 4.6rem; padding: .75rem 1rem; cursor: pointer; list-style: none; }
    #|.node-summary::-webkit-details-marker { display: none; }
    #|.node-summary:hover { background: var(--surface-hover); }
    #|.node-identity, .node-summary-cell { display: grid; gap: .2rem; min-width: 0; }
    #|.node-identity > strong { font-size: .86rem; }
    #|.node-summary-cell > span { color: var(--muted); font-size: .67rem; font-weight: 680; }
    #|.node-summary-cell > strong { overflow: hidden; color: var(--ink); font-size: .78rem; text-overflow: ellipsis; white-space: nowrap; }
    #|.node-summary-cell > small { color: var(--muted); font-size: .66rem; }
    #|.node-expand-cue { display: inline-flex; align-items: center; gap: .35rem; color: var(--accent); font-size: .72rem; font-weight: 750; }
    #|.node-expand-cue::after { content: "⌄"; font-size: .9rem; transition: transform .16s ease; }
    #|.node-record[open] .node-expand-cue::after { transform: rotate(180deg); }
    #|.node-detail { padding: 1rem; border-top: 1px solid var(--line); background: var(--surface-subtle); }
    #|.node-detail-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 1rem; margin-bottom: .75rem; }
    #|.node-detail-heading h3 { margin: 0; }
    #|.node-metrics { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: .65rem; }
    #|.node-identity > strong { overflow-wrap: anywhere; }
    #|.node-metric { min-width: 0; overflow-wrap: anywhere; }
    #|.node-summary-cell > small { overflow-wrap: anywhere; }
    #|.topology-disclosure { margin-bottom: 1rem; }
    #|.topology-disclosure > summary { min-height: 44px; padding: .7rem 1rem; cursor: pointer; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); font-weight: 650; }
    #|.readiness-item { overflow-wrap: anywhere; }
    #|.node-metric { display: grid; gap: .35rem; min-height: 7.2rem; padding: .8rem; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); }
    #|.node-metric > span { color: var(--muted); font-size: .68rem; font-weight: 680; }
    #|.node-metric > strong { font-size: 1.35rem; letter-spacing: -.035em; }
    #|.node-metric > small { color: var(--muted); font-size: .66rem; }
    #|.node-metric progress { width: 100%; height: .4rem; overflow: hidden; border: 0; border-radius: 999px; background: var(--line); accent-color: var(--accent); }
    #|.node-metric progress::-webkit-progress-bar { border-radius: 999px; background: var(--line); }
    #|.node-metric progress::-webkit-progress-value { border-radius: 999px; background: var(--accent); }
    #|.node-facts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: .7rem 0 0; border: 1px solid var(--line); border-radius: .5rem; background: var(--surface); }
    #|.node-facts > div { min-width: 0; padding: .7rem .8rem; border-right: 1px solid var(--line); }
    #|.node-facts > div:last-child { border-right: 0; }
    #|.node-facts dt { color: var(--muted); font-size: .66rem; font-weight: 680; }
    #|.node-facts dd { margin: .2rem 0 0; overflow-wrap: anywhere; font-size: .76rem; font-weight: 680; }
    #|.node-detail-actions { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: .7rem; }
    #|.node-detail-actions p { max-width: 44rem; margin: 0; color: var(--muted); font-size: .7rem; }
    #|.privacy-note { margin: .8rem 0; padding: .55rem .75rem; border-left: .2rem solid var(--accent); background: var(--accent-soft); color: var(--muted-strong); font-size: .75rem; }
    #|.request-stats { margin-bottom: 1rem; }
    #|.stream-panel { padding: .7rem; }
    #|.stream-list { display: grid; gap: .5rem; margin: 0; padding: 0; list-style: none; }
    #|.stream-list li { padding: .75rem; border: 1px solid var(--line); border-radius: .45rem; background: var(--surface-subtle); }
    #|.stream-meta { display: flex; align-items: center; gap: .55rem; }
    #|.stream-sequence { display: grid; place-items: center; width: 1.5rem; height: 1.5rem; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-size: .68rem; font-weight: 760; }
    #|.stream-output { margin: .6rem 0 0 2.05rem; padding: .65rem; overflow: auto; border-radius: .35rem; background: var(--sidebar); color: var(--sidebar-ink); font: .76rem/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; }
    #|.evidence-list { display: grid; gap: 0; margin: 0; padding: 0; list-style: none; }
    #|.evidence-list li { display: flex; align-items: center; gap: .75rem; min-height: 3.75rem; padding: .65rem 1rem; border-bottom: 1px solid var(--line); }
    #|.evidence-list li:last-child { border-bottom: 0; }
    #|.evidence-list li span { display: block; }
    #|.evidence-mark { width: .55rem; height: .55rem; flex: none; border: .15rem solid var(--accent-soft); border-radius: 999px; background: var(--accent); }
    #|.policy-summary { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); margin: 0 0 1rem; border: 1px solid var(--line); border-radius: .65rem; background: var(--surface); box-shadow: var(--shadow-sm); }
    #|.policy-summary > div { min-width: 0; padding: .8rem 1rem; border-right: 1px solid var(--line); }
    #|.policy-summary > div:last-child { border-right: 0; }
    #|.policy-summary dt { color: var(--muted); font-size: .7rem; }
    #|.policy-summary dd { margin: .2rem 0 0; font-weight: 720; overflow-wrap: anywhere; }
    #|.operation-panel { padding: 1.1rem; }
    #|.operation-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }
    #|.operation-heading h3 { margin: 0; font-size: 1.05rem; }
    #|.operation-form { display: grid; grid-template-columns: minmax(13rem, .72fr) minmax(20rem, 1.6fr); gap: 1rem; margin-top: 1rem; }
    #|.fixed-capacity { display: flex; align-items: center; gap: .75rem; grid-column: 1 / -1; min-height: 4.5rem; padding: .75rem .85rem; border: 1px solid color-mix(in srgb, var(--success) 28%, var(--line)); border-radius: .5rem; background: var(--success-soft); }
    #|.fixed-capacity-mark { display: grid; place-items: center; width: 2.25rem; height: 2.25rem; flex: none; border-radius: .5rem; background: var(--success); color: white; font-weight: 850; }
    #|.fixed-capacity strong { display: block; color: var(--ink); font-size: .78rem; }
    #|.fixed-capacity p { margin: .22rem 0 0; color: var(--muted-strong); font-size: .7rem; line-height: 1.45; }
    #|.deployment-steps { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: .6rem; margin: 1rem 0 0; padding: 0; list-style: none; }
    #|.deployment-steps li { display: flex; align-items: center; gap: .5rem; color: var(--muted-strong); font-size: .74rem; }
    #|.deployment-steps li > span { display: grid; place-items: center; width: 1.45rem; height: 1.45rem; flex: none; border-radius: 999px; background: var(--accent-soft); color: var(--accent); font-weight: 800; }
    #|.model-onboarding-steps { grid-template-columns: repeat(4, minmax(0, 1fr)); }
    #|.model-source-search { display: grid; grid-template-columns: minmax(12rem, 1fr) auto; gap: .45rem .65rem; align-items: end; margin-top: 1rem; }
    #|.model-source-search label { grid-column: 1 / -1; color: var(--muted-strong); font-size: .75rem; font-weight: 700; }
    #|.model-source-search input { width: 100%; min-height: 2.65rem; padding: .55rem .7rem; border: 1px solid var(--line-strong); border-radius: .45rem; background: var(--surface); color: var(--ink); }
    #|.model-source-hint { display: grid; gap: .25rem; margin-top: 1rem; padding: 1rem; border: 1px dashed var(--line-strong); border-radius: .55rem; background: var(--surface-subtle); }
    #|.model-source-hint span { color: var(--muted); font-size: .75rem; }
    #|.model-source-results { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .75rem; margin-top: 1rem; }
    #|.model-source-card { display: grid; align-content: start; gap: .75rem; min-width: 0; padding: 1rem; border: 1px solid var(--line); border-radius: .6rem; background: var(--surface-subtle); }
    #|.model-source-card-heading { display: flex; align-items: flex-start; justify-content: space-between; gap: .75rem; }
    #|.model-source-card-heading > div { display: grid; gap: .2rem; min-width: 0; }
    #|.model-source-card-heading strong { font-size: .94rem; }
    #|.model-source-facts { display: flex; flex-wrap: wrap; gap: .35rem; }
    #|.model-source-facts span { padding: .24rem .45rem; border-radius: .35rem; background: var(--surface); color: var(--muted-strong); font-size: .68rem; }
    #|.model-import-recovery { display: flex; align-items: center; justify-content: space-between; gap: .65rem; }
    #|.model-approval-checklist { display: grid; gap: .28rem; margin: .25rem 0; padding-left: 1.15rem; color: var(--muted-strong); font-size: .72rem; }
    #|.model-import-status { display: grid; gap: .5rem; padding-top: .7rem; border-top: 1px solid var(--line); }
    #|.model-import-status > div:first-child { display: flex; justify-content: space-between; gap: .6rem; }
    #|.model-import-track { height: .42rem; overflow: hidden; border-radius: 999px; background: var(--line); }
    #|.model-import-fill { display: block; height: 100%; border-radius: inherit; background: var(--accent); transition: width .18s ease; }
    #|.verified-import-actions { display: grid; gap: .7rem; }
    #|.approval-gate-note { display: grid; gap: .2rem; padding: .65rem; border-left: .2rem solid var(--warning); border-radius: .35rem; background: var(--warning-soft); }
    #|.approval-gate-note span { color: var(--muted-strong); font-size: .7rem; line-height: 1.45; }
    #|.model-adoption-form { padding-top: .75rem; border-top: 1px solid var(--line); }
    #|.model-adoption-form fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
    #|.model-adoption-form legend { padding: 0; color: var(--ink); font-size: .82rem; font-weight: 760; }
    #|.model-adoption-intro { max-width: 58rem; }
    #|.model-adoption-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .7rem .85rem; margin-top: .75rem; }
    #|.model-adoption-grid .field-group:last-child { grid-column: 1 / -1; max-width: 24rem; }
    #|.model-adoption-actions { display: flex; align-items: center; justify-content: space-between; gap: .75rem; margin-top: .85rem; }
    #|.model-adoption-actions .row-actions { display: flex; justify-content: flex-end; gap: .5rem; }
    #|.model-candidate-actions { display: flex; flex-wrap: wrap; align-items: center; gap: .35rem; white-space: normal; }
    #|.model-onboarding-form-row td { padding: .55rem .7rem 1rem; background: var(--surface-subtle); }
    #|.model-onboarding-form { padding-top: .5rem; border-top: 1px solid var(--line); }
    #|.model-onboarding-form fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
    #|.model-onboarding-form legend { padding: 0; color: var(--ink); font-size: .82rem; font-weight: 760; }
    #|.model-onboarding-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .7rem .85rem; margin-top: .75rem; }
    #|.model-onboarding-form .row-actions, .runtime-profile-form .operation-actions, .template-registration-form .operation-actions { display: flex; justify-content: flex-end; align-items: center; gap: .5rem; margin-top: .85rem; }
    #|.template-registration-form fieldset { min-width: 0; margin: 0; padding: 0; border: 0; }
    #|.template-registration-form legend { padding: 0; color: var(--ink); font-size: .82rem; font-weight: 760; }
    #|.template-registration-form .template-registration-section { margin-top: 1rem; padding-top: .85rem; border-top: 1px solid var(--line); }
    #|.runtime-profile-flags { display: flex; flex-wrap: wrap; gap: 1.1rem; margin-top: .9rem; }
    #|.runtime-profile-flag { display: inline-flex; align-items: center; gap: .45rem; min-height: 44px; color: var(--muted-strong); font-size: .78rem; font-weight: 650; }
    #|.runtime-profile-flag input { width: 1.05rem; height: 1.05rem; }
    #|.model-adoption-complete, .model-adoption-blocked { display: grid; gap: .25rem; padding: .65rem; border-left: .2rem solid var(--success); border-radius: .35rem; background: var(--success-soft); }
    #|.model-adoption-blocked { border-left-color: var(--warning); background: var(--warning-soft); }
    #|.model-adoption-complete span, .model-adoption-blocked span { color: var(--muted-strong); font-size: .7rem; line-height: 1.45; }
    #|.detached-imports { margin-top: 1rem; padding-top: 1rem; border-top: 1px solid var(--line); }
    #|.detached-imports-heading { display: flex; align-items: baseline; justify-content: space-between; gap: .75rem; }
    #|.detached-imports-heading h4 { margin: 0; font-size: .9rem; }
    #|.detached-import-list { display: grid; gap: .65rem; margin-top: .7rem; }
    #|.detached-import-row { display: grid; gap: .7rem; min-width: 0; padding: .85rem; border: 1px solid var(--line); border-radius: .55rem; background: var(--surface-subtle); }
    #|.field-group select { padding: .55rem .65rem; }
    #|.field-group textarea { display: block; min-height: 15rem; padding: .7rem; resize: vertical; font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; line-height: 1.55; }
    #|.operation-actions { display: flex; align-items: center; justify-content: space-between; gap: 1rem; margin-top: .8rem; padding-top: .8rem; border-top: 1px solid var(--line); }
    #|.confirmation-panel { position: fixed; right: 1.5rem; bottom: 1.5rem; z-index: 50; width: min(31rem, calc(100vw - 3rem)); padding: 1.25rem; border: 1px solid color-mix(in srgb, var(--danger) 40%, var(--line)); border-top: .25rem solid var(--danger); border-radius: .7rem; background: var(--surface); box-shadow: var(--shadow-lg); }
    #|.confirmation-panel h2 { margin-bottom: .45rem; }
    #|.confirmation-panel > p:not(.eyebrow) { margin: 0 0 1rem; color: var(--muted-strong); }
    #|.danger-copy { color: var(--danger); }
    #|.confirmation-scope { display: grid; gap: .55rem; margin: 0; padding: .75rem; border-radius: .45rem; background: var(--surface-subtle); }
    #|.confirmation-scope dt { color: var(--muted); font-size: .68rem; font-weight: 700; text-transform: uppercase; }
    #|.confirmation-scope dd { margin: .1rem 0 0; overflow-wrap: anywhere; }
    #|.confirmation-actions { display: flex; justify-content: flex-end; gap: .5rem; margin-top: 1rem; }
    #|@media (max-width: 72rem) {
    #|  .stats { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .operation-form { grid-template-columns: 1fr; }
    #|  .policy-summary { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .readiness-panel { grid-template-columns: 1fr; }
    #|  .topology-relationships dl { grid-template-columns: 1fr; }
    #|  .node-summary { grid-template-columns: minmax(11rem, 1.3fr) repeat(3, minmax(7rem, .7fr)) auto; }
    #|  .node-lease-summary { display: none; }
    #|  .node-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .node-facts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|  .node-facts > div:nth-child(2) { border-right: 0; }
    #|  .node-facts > div:nth-child(-n+2) { border-bottom: 1px solid var(--line); }
    #|  .policy-summary > div:nth-child(2) { border-right: 0; }
    #|  .policy-summary > div:nth-child(-n+2) { border-bottom: 1px solid var(--line); }
    #|  .model-source-results { grid-template-columns: 1fr; }
    #|  .model-adoption-grid { grid-template-columns: 1fr; }
    #|  .model-adoption-grid .field-group:last-child { grid-column: auto; max-width: none; }
    #|}
    #|@media (max-width: 56rem) {
    #|  .console-root { display: flex; flex-direction: column; }
    #|  .connection-panel { order: 2; position: sticky; width: 100%; padding-inline: 1rem; }
    #|  .connection-panel summary { justify-content: flex-start; }
    #|  .sidebar { order: 1; position: static; width: 100%; height: auto; overflow: visible; padding: .75rem; }
    #|  .brand { margin-bottom: .65rem; padding-bottom: .65rem; }
    #|  .sidebar nav { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .25rem; }
    #|  .nav-group-label { grid-column: 1 / -1; margin-top: .65rem; }
    #|  .sidebar-footer { display: none; }
    #|  .workspace { order: 3; width: 100%; }
    #|  .workspace-topbar { padding: 1.25rem 1rem 1rem; }
    #|  .workspace-main { padding: 1rem 1rem 2.5rem; }
    #|  .topology-heading { flex-direction: column; }
    #|  .topology-summary { justify-content: flex-start; }
    #|  .skip-link:focus { left: 1rem; }
    #|  .overview-grid { grid-template-columns: 1fr; }
    #|  .connection-form { grid-template-columns: 1fr; margin-left: 0; }
    #|  .connection-actions { display: grid; }
    #|  .node-summary { grid-template-columns: minmax(10rem, 1.4fr) minmax(7rem, .7fr) minmax(7rem, .7fr) auto; }
    #|  .node-memory-summary { display: none; }
    #|  .account-invite-grid { grid-template-columns: 1fr; }
    #|  .access-package-steps, .access-package-milestones { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    #|}
    #|@media (max-width: 40rem) {
    #|  .connection-endpoint { display: none; }
    #|  .demo-banner { align-items: flex-start; flex-direction: column; margin: 0 .75rem; }
    #|  .nav-group-label { display: none; }
    #|  .workspace-topbar, .section-heading, .operation-heading { flex-direction: column; }
    #|  .topbar-actions { width: 100%; flex-wrap: wrap; justify-content: space-between; }
    #|  .locale-control { flex: 1; }
    #|  .locale-select { width: 100%; }
    #|  .health-facts { grid-template-columns: 1fr; }
    #|  .health-facts > div { border-left: 0; border-top: 1px solid var(--line); }
    #|  .stats, .policy-summary { grid-template-columns: 1fr; }
    #|  .readiness-list, .deployment-steps { grid-template-columns: 1fr; }
    #|  .policy-summary > div { border-right: 0; border-bottom: 1px solid var(--line); }
    #|  .policy-summary > div:last-child { border-bottom: 0; }
    #|  .operation-actions { align-items: stretch; flex-direction: column; }
    #|  .operation-actions button { width: 100%; }
    #|  .account-self, .account-invite-actions { align-items: stretch; flex-direction: column; }
    #|  .account-self-evidence { justify-content: flex-start; }
    #|  .account-invite-actions button { width: 100%; }
    #|  .access-package-form-grid, .access-package-steps, .access-package-milestones { grid-template-columns: 1fr; }
    #|  .access-package-review, .access-package-card-heading, .access-package-next { align-items: stretch; flex-direction: column; }
    #|  .access-lifetime { justify-content: flex-start; }
    #|  .access-lifetime > span { text-align: left; }
    #|  .access-package-submit { display: grid; }
    #|  .access-package-evidence { max-width: none; }
    #|  .model-onboarding-steps { grid-template-columns: 1fr; }
    #|  .model-source-search { grid-template-columns: 1fr; }
    #|  .model-adoption-actions, .detached-imports-heading { align-items: stretch; flex-direction: column; }
    #|  .model-adoption-actions .row-actions { display: grid; grid-template-columns: 1fr; }
    #|  .model-adoption-actions button { width: 100%; }
    #|  .model-onboarding-grid { grid-template-columns: 1fr; }
    #|  .model-onboarding-form .row-actions, .runtime-profile-form .operation-actions, .template-registration-form .operation-actions { display: grid; grid-template-columns: 1fr; }
    #|  .model-onboarding-form button, .runtime-profile-form .operation-actions button, .template-registration-form .operation-actions button { width: 100%; }
    #|  .topology-graph { min-width: 44rem; padding: 1rem; }
    #|  .node-summary { grid-template-columns: minmax(0, 1fr) auto; gap: .65rem; }
    #|  .node-summary-cell { display: none; }
    #|  .node-detail-heading, .node-detail-actions { align-items: stretch; flex-direction: column; }
    #|  .node-metrics, .node-facts { grid-template-columns: 1fr; }
    #|  .node-facts > div { border-right: 0; border-bottom: 1px solid var(--line); }
    #|  .node-facts > div:last-child { border-bottom: 0; }
    #|  .confirmation-panel { right: .75rem; bottom: .75rem; width: calc(100vw - 1.5rem); }
    #|}
    #|@media (prefers-reduced-motion: reduce) {
    #|  * { scroll-behavior: auto !important; transition: none !important; }
    #|}
  )
}

///|
fn console_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage]?,
  alerts_window : AlertsWindow,
  now_unix_ms : Int64,
  page_read_state : PageReadState,
) -> @rabbita.Html {
  let content = match state.route {
    Overview => overview_view(state, emit)
    Alerts => alerts_view(state, emit, alerts_window, now_unix_ms)
    Users => users_view(state, emit)
    Leases => leases_view(state, emit)
    CostCenters => cost_centers_view(state)
    Agreements => agreements_view(state, emit)
    OfflineCommerce => {
      let commerce = { ..state.offline_commerce, locale: state.locale, }
      let page = match emit {
        Some(send) =>
          @offline_commerce.interactive_view(
            commerce,
            send.map(message => OfflineCommerce(message)),
          )
        None => @offline_commerce.view(commerce)
      }
      @html.div([offline_commerce_lifecycle_graph(state), page])
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
    QualifiedServices => qualified_services_view(state)
    Nodes => nodes_view(state, emit)
    Models => models_view(state, emit)
    Catalog => catalog_view(state, emit)
    Deployments => deployments_view(state, emit)
    Requests => requests_view(state)
    Benchmarks => benchmarks_view(state)
    Policies => policies_view(state, emit)
    Audit => audit_view(state)
    Blank => blank_view(state)
  }
  @html.div(class="app-shell", [
    @html.style_tag(
      console_styles() +
      placement_visual_styles() +
      observability_visual_styles() +
      governance_visual_styles() +
      offline_commerce_visual_styles(),
    ),
    @html.a(
      href="#main",
      class="skip-link",
      localized(state.locale, "Skip to content", "跳转到主要内容"),
    ),
    @html.aside(class="sidebar", [
      @html.div(
        class="brand",
        attrs=@html.Attrs::build().aria_label(
          localized(
            state.locale,
            "能源谷“创未来”街区算力平台 Cluster Operations",
            "能源谷“创未来”街区算力平台 集群运维",
          ),
        ),
        [
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
          @html.div(class="brand-copy", [
            @html.span(
              class="brand-name",
              "能源谷“创未来”街区算力平台",
            ),
            @html.span(
              class="brand-product",
              localized(state.locale, "Cluster operations", "集群运维"),
            ),
          ]),
        ],
      ),
      navigation(state.locale, state.route, emit),
      @html.p(class="sidebar-footer", [
        @html.strong(localized(state.locale, "Control plane", "控制平面")),
        @html.span(
          localized(
            state.locale,
            "Managed nodes remain isolated from application state.",
            "受管节点始终与应用状态隔离。",
          ),
        ),
      ]),
    ]),
    @html.div(class="workspace", [
      @html.header(class="workspace-topbar", [
        @html.div(class="page-heading", [
          @html.p(
            class="page-eyebrow",
            localized(state.locale, "Private DGX cluster", "私有 DGX 集群"),
          ),
          @html.h1(route_label(state.locale, state.route)),
          @html.p(
            class="page-description",
            route_description(state.locale, state.route),
          ),
        ]),
        @html.div(class="topbar-actions", [
          @html.div(class="locale-control", [
            @html.label(
              for_="console-locale",
              localized(state.locale, "Language", "语言"),
            ),
            @html.select(
              id="console-locale",
              class="locale-select",
              on_change=text_command(emit, value => {
                LocaleChanged(@i18n.parse_locale(value))
              }),
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
          @html.span(
            class=if state.overview.total_nodes == 0 {
              "alert-summary awaiting-telemetry"
            } else if state.overview.alerts == 0 {
              "alert-summary"
            } else {
              "alert-summary has-alerts"
            },
            if state.overview.total_nodes == 0 {
              localized(state.locale, "Awaiting telemetry", "等待遥测")
            } else if state.overview.alerts == 0 {
              localized(state.locale, "No open alerts", "无未解决告警")
            } else {
              localized(
                state.locale,
                "\{state.overview.alerts} open alerts",
                "\{state.overview.alerts} 个未解决告警",
              )
            },
          ),
          @html.button(
            type_="button",
            disabled=state.loading,
            on_click=command(emit, Refresh),
            localized(state.locale, "Refresh", "刷新"),
          ),
        ]),
      ]),
      @html.main_(id="main", class="workspace-main", [
        if state.loading {
          @html.p(
            class="loading-state",
            attrs=@html.Attrs::build()
              .role("status")
              .aria_live("polite")
              .aria_busy("true"),
            localized(
              state.locale,
              "Loading current cluster state…",
              "正在加载当前集群状态…",
            ),
          )
        } else {
          @html.nothing
        },
        match state.error_message {
          Some(message) =>
            @html.div(
              attrs=@html.Attrs::build().role("alert"),
              class="error-state",
              localized(
                state.locale,
                "Unable to complete the operation: \{message}",
                "无法完成此操作：\{message}",
              ),
            )
          None => @html.nothing
        },
        match state.success_message {
          Some(message) =>
            @html.div(
              attrs=@html.Attrs::build().role("status").aria_live("polite"),
              class="success-state",
              message,
            )
          None => @html.nothing
        },
        match page_read_state {
          Ready => content
          Loading =>
            @html.p(
              class="loading-state",
              attrs=@html.Attrs::build()
                .role("status")
                .aria_live("polite")
                .aria_busy("true"),
              localized(
                state.locale,
                "Loading this page’s records…",
                "正在加载此页面的数据…",
              ),
            )
          Failed =>
            @html.div(
              class="error-state",
              attrs=@html.Attrs::build().role("alert"),
              [
                @html.p(
                  localized(
                    state.locale,
                    "This page’s records could not be loaded. This does not mean there are no records.",
                    "此页面的数据未能加载，不代表没有记录。",
                  ),
                ),
                @html.button(
                  type_="button",
                  disabled=state.loading,
                  on_click=command(emit, Refresh),
                  localized(state.locale, "Retry loading", "重新加载"),
                ),
              ],
            )
        },
        confirmation_view(state.locale, state.confirmation, emit),
      ]),
    ]),
  ])
}

///|
pub fn view(state : ConsoleState) -> @rabbita.Html {
  console_view(state, None, AllAlerts, 0L, Ready)
}

///|
pub(all) enum PageReadState {
  Ready
  Loading
  Failed
}

///|
pub fn interactive_view(
  state : ConsoleState,
  emit : @rabbita.Emit[ConsoleMessage],
  alerts_window? : AlertsWindow = AllAlerts,
  now_unix_ms? : Int64 = 0L,
  page_read_state? : PageReadState = Ready,
) -> @rabbita.Html {
  console_view(state, Some(emit), alerts_window, now_unix_ms, page_read_state)
}

///|
#warnings("-alert_unstable")
pub fn render(state : ConsoleState) -> String {
  @rabbita.render_to_string(() => @rabbita.Val::constant(view(state)))
}
