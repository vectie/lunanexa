///|
/// Generate the checked browser demo scene from the authoritative DOCX.
async fn main {
  let args = @env.args()
  guard args is [_, template_path, output_path] else {
    raise Failure::Failure(
      "usage: contract-preview-scene TEMPLATE.docx OUTPUT.json",
    )
  }
  let manifest = @contractdoc.youthpolicy_remote_lease_manifest()
  let source = @fs.read_file(template_path).binary().to_fixedarray()
  let preview = @preview.template(source, manifest)
  @fs.write_file(
    output_path,
    preview.to_json().stringify(),
    create_mode=CreateOrTruncate,
    permission=0o644,
    sync=Full,
  )
}
