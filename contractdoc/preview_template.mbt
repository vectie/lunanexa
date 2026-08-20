///|
/// Materialize authenticated role-owned values into a build-time MoonLeaf
/// scene. This pure path is used only by the read-only browser demo.
pub fn materialize_preview_template(
  template : ContractPreviewTemplate,
  manifest : ContractTemplateManifest,
  packet : ContractPacket,
  actor : ContractFieldOwner,
  form : ContractFormKind,
  changes : Array[ContractFieldValue],
) -> ContractPreviewDocument raise ContractDocumentError {
  if template.template_id != manifest.template_id ||
    template.template_version != manifest.template_version ||
    template.template_sha256 != manifest.fillable_sha256 ||
    !packet.active_forms.contains(form) ||
    template.page_forms.length() != template.scene.pages.length() {
    raise TemplateMismatch
  }
  // Signed/closed packets are immutable, but their exact recorded values must
  // remain previewable. Ignore browser draft changes for those states instead
  // of routing a read-only preview through the edit transition.
  let read_only = packet.state == Generated ||
    packet.state == Effective ||
    packet.state == Closed ||
    packet.state == Superseded
  let draft = if changes.length() == 0 || read_only {
    packet
  } else {
    packet.update_information(
      manifest,
      packet.revision,
      changes,
      actor,
      if actor == ManagerOperator {
        "preview-operator"
      } else {
        "preview-customer"
      },
      "moonleaf-demo-preview",
      packet.updated_unix_ms + 1L,
    )
  }
  let values = template.marker_defaults.map(item => {
    (item.marker, draft.marker_value(item.marker))
  })
  fn replace_markers(
    text : String,
    values : Array[(String, String)],
  ) -> String {
    let mut output = text
    for pair in values {
      output = output.replace_all(old=pair.0, new=pair.1)
    }
    output
  }
  fn replace_block(
    block : ContractPreviewBlock,
    values : Array[(String, String)],
  ) -> ContractPreviewBlock {
    {
      ..block,
      runs: block.runs.map(run => {
        ..run,
        text: replace_markers(run.text, values),
      }),
      rows: block.rows.map(row => {
        ..row,
        cells: row.cells.map(cell => {
          ..cell,
          text: replace_markers(cell.text, values),
          paragraphs: cell.paragraphs.map(paragraph => {
            ..paragraph,
            runs: paragraph.runs.map(run => {
              ..run,
              text: replace_markers(run.text, values),
            }),
          }),
        }),
      }),
    }
  }
  let pages : Array[Array[ContractPreviewBlock]] = []
  for index, page in template.scene.pages {
    if template.page_forms.get(index) == Some(form) {
      pages.push(page.map(block => replace_block(block, values)))
    }
  }
  if pages.length() == 0 {
    raise TemplateMismatch
  }
  let blocks : Array[ContractPreviewBlock] = []
  for page in pages {
    for block in page {
      blocks.push(block)
    }
  }
  {
    ..template.scene,
    packet_id: packet.packet_id,
    packet_revision: draft.revision,
    form,
    blocks,
    pages,
  }
}
