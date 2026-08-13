///|
pub(all) suberror ContractPreviewError {
  InvalidDraft(String)
  MoonLeafPreviewFailed(String)
} derive(Debug, Eq)

///|
fn empty_block(
  kind : String,
  runs : Array[@contractdoc.ContractPreviewRun],
) -> @contractdoc.ContractPreviewBlock {
  {
    kind,
    level: 0,
    ordered: false,
    runs,
    rows: [],
    alignment: None,
    spacing_before_twips: None,
    spacing_after_twips: None,
    line_twips: None,
    left_indent_twips: None,
    right_indent_twips: None,
    first_line_twips: None,
    hanging_twips: None,
    grid_widths_twips: [],
    cell_widths_twips: [],
  }
}

///|
/// Apply a role-scoped, non-persistent draft to a packet for preview only.
fn preview_packet(
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
  actor : @contractdoc.ContractFieldOwner,
  changes : Array[@contractdoc.ContractFieldValue],
) -> @contractdoc.ContractPacket raise ContractPreviewError {
  if changes.length() == 0 {
    return packet
  }
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
    "moonleaf-preview",
    packet.updated_unix_ms + 1L,
  ) catch {
    error => raise InvalidDraft("\{Repr(error)}")
  }
}

///| Build a live preview exclusively through MoonLeaf: exact declared markers

///| are replaced in a verified copy, then the copy is reopened through

///|
/// MoonLeaf's rich ordered DOCX preview model for Rabbita rendering.
pub fn render(
  template : FixedArray[Byte],
  manifest : @contractdoc.ContractTemplateManifest,
  packet : @contractdoc.ContractPacket,
  actor : @contractdoc.ContractFieldOwner,
  form : @contractdoc.ContractFormKind,
  changes : Array[@contractdoc.ContractFieldValue],
) -> @contractdoc.ContractPreviewDocument raise ContractPreviewError {
  if !packet.active_forms.contains(form) || template.length() == 0 {
    raise InvalidDraft("preview form or template is unavailable")
  }
  let draft = preview_packet(manifest, packet, actor, changes)
  let markers = @worker.exact_docx_markers(template) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let replacements = markers.map(marker => @worker.TextReplacement::{
    placeholder: marker,
    value: draft.marker_value(marker) catch {
      error => raise MoonLeafPreviewFailed("\{Repr(error)}")
    },
  })
  let customized = @worker.customize_exact_docx_template(template, replacements) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let session = @moonleaf.open_session(
    manifest.fillable_filename,
    customized.bytes,
  ) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let archive = @opc.open(customized.bytes) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let rich = @docx.preview_document(archive) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let blocks : Array[@contractdoc.ContractPreviewBlock] = []
  let mut section : @docx.SectionInfo? = None
  for block in rich.blocks {
    match block {
      FlowParagraph(paragraph) => {
        let runs = paragraph.runs.map(run => @contractdoc.ContractPreviewRun::{
          text: run.text,
          bold: run.bold,
          italic: run.italic,
          underline: run.underline,
          font_size_half_points: run.font_size_half_points,
          color: run.color,
          font_ascii: run.font_ascii,
          font_east_asia: run.font_east_asia,
          font_complex_script: run.font_complex_script,
        })
        blocks.push({
          ..empty_block("paragraph", runs),
          level: paragraph.outline_level.unwrap_or(0),
          alignment: paragraph.metadata.alignment,
          spacing_before_twips: paragraph.metadata.spacing_before_twips,
          spacing_after_twips: paragraph.metadata.spacing_after_twips,
          line_twips: paragraph.metadata.line_twips,
          left_indent_twips: paragraph.metadata.left_indent_twips,
          right_indent_twips: paragraph.metadata.right_indent_twips,
          first_line_twips: paragraph.metadata.first_line_twips,
          hanging_twips: paragraph.metadata.hanging_twips,
        })
      }
      FlowTable(table) =>
        blocks.push({
          ..empty_block("table", []),
          rows: table.rows.map(row => row.map(cell => cell.text)),
          grid_widths_twips: table.grid_widths_twips,
          cell_widths_twips: table.rows.map(row => {
            row.map(cell => cell.width_twips)
          }),
        })
      FlowSection(value) => section = Some(value)
    }
  }
  let (
    page_width_twips,
    page_height_twips,
    margin_top_twips,
    margin_right_twips,
    margin_bottom_twips,
    margin_left_twips,
  ) = match section {
    Some(value) =>
      (
        value.page_width_twips,
        value.page_height_twips,
        value.margin_top_twips,
        value.margin_right_twips,
        value.margin_bottom_twips,
        value.margin_left_twips,
      )
    None => (None, None, None, None, None, None)
  }
  {
    engine: "moonleaf",
    packet_id: packet.packet_id,
    packet_revision: packet.revision,
    form,
    blocks,
    diagnostic_codes: session.diagnostics().map(item => item.code),
    page_width_twips,
    page_height_twips,
    margin_top_twips,
    margin_right_twips,
    margin_bottom_twips,
    margin_left_twips,
  }
}
