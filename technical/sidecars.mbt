///|
pub(all) enum ReviewedSidecar {
  InferenceGateway
  TelemetryExporter
  CertificateReloader
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SidecarEgress {
  ControllerOnly
  TelemetrySinkOnly
  Disabled
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SidecarProfile {
  name : ReviewedSidecar
  profile_version : String
  catalog_image_key : String
  image_must_be_digest_pinned : Bool
  configuration_schema : String
  egress : SidecarEgress
  read_only_root : Bool
  drops_all_capabilities : Bool
  host_network : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct SidecarRequest {
  profile : ReviewedSidecar
  configuration_ref : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SidecarRejection {
  ProfileNotAllowed
  DuplicateProfile
  InvalidConfigurationReference
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) enum SidecarDecision {
  Accepted(Array[SidecarProfile])
  Rejected(SidecarRejection)
} derive(Debug, Eq, ToJson, FromJson)

///|
pub fn reviewed_sidecar_profile(name : ReviewedSidecar) -> SidecarProfile {
  match name {
    InferenceGateway =>
      {
        name,
        profile_version: "v1",
        catalog_image_key: "sidecar.inference-gateway",
        image_must_be_digest_pinned: true,
        configuration_schema: "lunanexa.sidecar.inference-gateway/v1",
        egress: ControllerOnly,
        read_only_root: true,
        drops_all_capabilities: true,
        host_network: false,
      }
    TelemetryExporter =>
      {
        name,
        profile_version: "v1",
        catalog_image_key: "sidecar.telemetry-exporter",
        image_must_be_digest_pinned: true,
        configuration_schema: "lunanexa.sidecar.telemetry-exporter/v1",
        egress: TelemetrySinkOnly,
        read_only_root: true,
        drops_all_capabilities: true,
        host_network: false,
      }
    CertificateReloader =>
      {
        name,
        profile_version: "v1",
        catalog_image_key: "sidecar.certificate-reloader",
        image_must_be_digest_pinned: true,
        configuration_schema: "lunanexa.sidecar.certificate-reloader/v1",
        egress: Disabled,
        read_only_root: true,
        drops_all_capabilities: true,
        host_network: false,
      }
  }
}

///|
fn valid_configuration_reference(value : String) -> Bool {
  value.has_prefix("config://") &&
  value.length() > "config://".length() &&
  value.length() <= 256 &&
  !value.contains("..") &&
  value.all(char => {
    match char {
      'a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '_' | '-' | '/' | ':' => true
      _ => false
    }
  })
}

///|
pub fn select_sidecar_profiles(
  requests : Array[SidecarRequest],
  allowed : Array[ReviewedSidecar],
) -> SidecarDecision {
  let selected : Array[SidecarProfile] = []
  let seen : Array[ReviewedSidecar] = []
  for request in requests {
    if !allowed.contains(request.profile) {
      return Rejected(ProfileNotAllowed)
    }
    if seen.contains(request.profile) {
      return Rejected(DuplicateProfile)
    }
    if !valid_configuration_reference(request.configuration_ref) {
      return Rejected(InvalidConfigurationReference)
    }
    seen.push(request.profile)
    selected.push(reviewed_sidecar_profile(request.profile))
  }
  Accepted(selected)
}
