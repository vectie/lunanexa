///|
/// Opaque LunaNexa-side capability for one exactly approved LunaFlux rollout.
///
/// This is not a serialized deployment template. It can only be derived from
/// `LunaFluxAdapterAuthority`, whose production constructor remains private
/// until a controller-authenticated approval verifier exists.
pub struct LunaFluxOpaqueAdapter {
  priv authority : LunaFluxAdapterAuthority
  priv contract_digest : String
}

///|
fn lunaflux_adapter_contract_digest(
  authority : LunaFluxAdapterAuthority,
) -> String {
  lunaflux_promotion_sha256(
    "lunanexa.lunaflux.opaque-adapter.v1",
    "\{authority.candidate_manifest_digest}|\{authority.runtime.image_digest}|\{authority.model_artifact_digest}|\{authority.launch_manifest_digest}|\{authority.control_contract_digest}|\{authority.invocation_contract_digest}|\{authority.approval_catalog_digest}",
  )
}

///|
/// Narrows verifier-issued rollout authority into the LunaNexa runtime adapter
/// capability. There is deliberately no constructor from a candidate,
/// caller-supplied approval claim, JSON document, or digest list.
pub fn LunaFluxAdapterAuthority::opaque_adapter(
  self : LunaFluxAdapterAuthority,
) -> LunaFluxOpaqueAdapter {
  { authority: self, contract_digest: lunaflux_adapter_contract_digest(self) }
}

///|
/// Stable identity of the exact candidate, control, invocation, and approval
/// catalog joined by this adapter capability.
pub fn LunaFluxOpaqueAdapter::contract_digest(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.contract_digest
}

///|
pub fn LunaFluxOpaqueAdapter::runtime(
  self : LunaFluxOpaqueAdapter,
) -> @contracts.RuntimeSpec {
  self.authority.runtime
}

///|
pub fn LunaFluxOpaqueAdapter::model_artifact_digest(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.model_artifact_digest
}

///|
/// The exact launch manifest retained by deployment ownership. It is never
/// inferred from an image tag, model identifier, or filesystem path.
pub fn LunaFluxOpaqueAdapter::launch_manifest_digest(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.launch_manifest_digest
}

///|
pub fn LunaFluxOpaqueAdapter::target_profile_digest(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.target_profile_digest
}

///|
pub fn LunaFluxOpaqueAdapter::health_url(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.listener_origin + self.authority.health_path
}

///|
pub fn LunaFluxOpaqueAdapter::readiness_url(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.listener_origin + self.authority.readiness_path
}

///|
/// Returns only the approved inherited-drain contract path. It is not joined
/// to the HTTPS listener because LunaFlux exposes no HTTP drain route.
pub fn LunaFluxOpaqueAdapter::inherited_drain_path(
  self : LunaFluxOpaqueAdapter,
) -> String {
  self.authority.drain_path
}

///|
/// Creates the generic Responses adapter while keeping deployment bearer
/// credentials out of the opaque integration capability and all evidence.
pub fn LunaFluxOpaqueAdapter::openai_text_runtime(
  self : LunaFluxOpaqueAdapter,
  credential_value : String,
) -> OpenAiTextRuntime raise RemoteRuntimeError {
  self.authority.openai_text_runtime(credential_value)
}
