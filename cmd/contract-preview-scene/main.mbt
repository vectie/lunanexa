///|
/// Generate the checked browser demo scene from the authoritative DOCX.
async fn main {
  let args = @env.args()
  guard args.length() == 3 || args.length() == 4 else {
    raise Failure::Failure(
      "usage: contract-preview-scene TEMPLATE.docx OUTPUT.json [TEMPLATE_ID]",
    )
  }
  let template_path = args[1]
  let output_path = args[2]
  let manifest = if args.length() == 4 {
    let selected = @contractdoc.manifest_for_template_id(args[3])
    guard selected.template_id == args[3] else {
      raise Failure::Failure("unknown template id")
    }
    selected
  } else {
    @contractdoc.youthpolicy_remote_lease_manifest()
  }
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
