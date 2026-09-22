///| The independently versioned open-font edition preserves all legal text and

///|
/// slots. It explicitly adopts Noto Sans SC rather than impersonating the v1 faces.
pub fn undertaking_ofl_manifest() -> ContractTemplateManifest {
  {
    ..undertaking_manifest(),
    template_id: "youthpolicy-device-undertaking-ofl-v2",
    template_version: "v2",
    filename: "device-use-undertaking.ofl-v2.docx",
    sha256: "sha256:bae42968028bc491455dca0463f4ce16018134bb9a06e90b3b05e88fd8aae117",
    fillable_filename: "device-use-undertaking.ofl-v2.fillable.docx",
    fillable_sha256: "sha256:92f0041e2752d684ced68dd09f793ed0aafd795dc92c2f9522ca25c0af4542f7",
    byte_count: 16014L,
    page_count: 4,
  }
}
