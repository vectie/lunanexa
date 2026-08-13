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
    line_rule: None,
    left_indent_twips: None,
    right_indent_twips: None,
    first_line_twips: None,
    hanging_twips: None,
    grid_widths_twips: [],
  }
}

///|
fn preview_run(run : @docx.RunMetadata) -> @contractdoc.ContractPreviewRun {
  {
    text: run.text,
    bold: run.bold,
    italic: run.italic,
    underline: run.underline,
    font_size_half_points: run.font_size_half_points,
    color: run.color,
    font_ascii: run.font_ascii,
    font_east_asia: run.font_east_asia,
    font_complex_script: run.font_complex_script,
  }
}

///|
fn preview_paragraph(
  paragraph : @docx.ParagraphInfo,
) -> @contractdoc.ContractPreviewParagraph {
  {
    runs: paragraph.runs.map(preview_run),
    alignment: paragraph.metadata.alignment,
    spacing_before_twips: paragraph.metadata.spacing_before_twips,
    spacing_after_twips: paragraph.metadata.spacing_after_twips,
    line_twips: paragraph.metadata.line_twips,
    line_rule: paragraph.metadata.line_rule,
    left_indent_twips: paragraph.metadata.left_indent_twips,
    right_indent_twips: paragraph.metadata.right_indent_twips,
    first_line_twips: paragraph.metadata.first_line_twips,
    hanging_twips: paragraph.metadata.hanging_twips,
  }
}

///|
fn preview_row(row : @docx.TableRowInfo) -> @contractdoc.ContractPreviewRow {
  {
    cells: row.cells.map(cell => {
      text: cell.text,
      paragraphs: cell.paragraphs.map(preview_paragraph),
      grid_span: cell.grid_span,
      vertical_merge: cell.vertical_merge,
      width_twips: cell.width_twips,
      margin_top_twips: cell.margin_top_twips,
      margin_right_twips: cell.margin_right_twips,
      margin_bottom_twips: cell.margin_bottom_twips,
      margin_left_twips: cell.margin_left_twips,
      vertical_alignment: cell.vertical_alignment,
    }),
    height_twips: row.height_twips,
    height_rule: row.height_rule,
  }
}

///|
fn preview_flow_block(
  block : @docx.DocxFlowBlock,
) -> @contractdoc.ContractPreviewBlock? {
  match block {
    FlowParagraph(paragraph) => {
      let runs = paragraph.runs.map(preview_run)
      Some({
        ..empty_block("paragraph", runs),
        level: paragraph.outline_level.unwrap_or(0),
        alignment: paragraph.metadata.alignment,
        spacing_before_twips: paragraph.metadata.spacing_before_twips,
        spacing_after_twips: paragraph.metadata.spacing_after_twips,
        line_twips: paragraph.metadata.line_twips,
        line_rule: paragraph.metadata.line_rule,
        left_indent_twips: paragraph.metadata.left_indent_twips,
        right_indent_twips: paragraph.metadata.right_indent_twips,
        first_line_twips: paragraph.metadata.first_line_twips,
        hanging_twips: paragraph.metadata.hanging_twips,
      })
    }
    FlowTable(table) =>
      Some({
        ..empty_block("table", []),
        rows: table.rows.map(preview_row),
        grid_widths_twips: table.grid_widths_twips,
      })
    FlowPageBreak | FlowSection(_) => None
  }
}

///| Apply MoonLeaf's physical page boundaries from a materialized copy to the

///| marker-preserving scene used by the browser demo. Paragraphs remain in

///|
/// source order; split tables retain the corresponding source row slice.
fn marker_preserving_pages(
  source : @docx.DocxPreviewDocument,
  layout : @docx.PagedDocxDocument,
) -> Array[Array[@contractdoc.ContractPreviewBlock]] {
  let source_index = Ref(0)
  let source_table_row = Ref(0)
  fn skip_non_content(
    blocks : Array[@docx.DocxFlowBlock],
    source_index : Ref[Int],
  ) -> Unit {
    while source_index.val < blocks.length() {
      match blocks[source_index.val] {
        FlowPageBreak | FlowSection(_) =>
          source_index.val = source_index.val + 1
        _ => break
      }
    }
  }
  layout.pages.map(page => {
    let output : Array[@contractdoc.ContractPreviewBlock] = []
    for layout_block in page.blocks {
      skip_non_content(source.blocks, source_index)
      match layout_block {
        FlowParagraph(_) =>
          if source_index.val < source.blocks.length() {
            match source.blocks[source_index.val] {
              FlowParagraph(paragraph) => {
                match preview_flow_block(FlowParagraph(paragraph)) {
                  Some(block) => output.push(block)
                  None => ()
                }
                source_index.val = source_index.val + 1
              }
              _ => ()
            }
          }
        FlowTable(fragment) =>
          if source_index.val < source.blocks.length() {
            match source.blocks[source_index.val] {
              FlowTable(table) => {
                let rows : Array[@docx.TableRowInfo] = []
                let row_end = (source_table_row.val + fragment.rows.length()).min(
                  table.rows.length(),
                )
                for row_index = source_table_row.val
                    row_index < row_end
                    row_index = row_index + 1 {
                  rows.push(table.rows[row_index])
                }
                match preview_flow_block(FlowTable({ ..table, rows, })) {
                  Some(block) => output.push(block)
                  None => ()
                }
                source_table_row.val = row_end
                if source_table_row.val >= table.rows.length() {
                  source_index.val = source_index.val + 1
                  source_table_row.val = 0
                }
              }
              _ => ()
            }
          }
        FlowPageBreak | FlowSection(_) => ()
      }
    }
    output
  })
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
  let paged = @docx.paginate_document(archive) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let blocks : Array[@contractdoc.ContractPreviewBlock] = []
  let mut section : @docx.SectionInfo? = None
  for block in rich.blocks {
    match block {
      FlowParagraph(paragraph) => {
        let runs = paragraph.runs.map(preview_run)
        blocks.push({
          ..empty_block("paragraph", runs),
          level: paragraph.outline_level.unwrap_or(0),
          alignment: paragraph.metadata.alignment,
          spacing_before_twips: paragraph.metadata.spacing_before_twips,
          spacing_after_twips: paragraph.metadata.spacing_after_twips,
          line_twips: paragraph.metadata.line_twips,
          line_rule: paragraph.metadata.line_rule,
          left_indent_twips: paragraph.metadata.left_indent_twips,
          right_indent_twips: paragraph.metadata.right_indent_twips,
          first_line_twips: paragraph.metadata.first_line_twips,
          hanging_twips: paragraph.metadata.hanging_twips,
        })
      }
      FlowTable(table) =>
        blocks.push({
          ..empty_block("table", []),
          rows: table.rows.map(preview_row),
          grid_widths_twips: table.grid_widths_twips,
        })
      FlowPageBreak => blocks.push(empty_block("page-break", []))
      FlowSection(value) => section = Some(value)
    }
  }
  let pages : Array[Array[@contractdoc.ContractPreviewBlock]] = paged.pages.map(page => {
      page.blocks.filter_map(preview_flow_block)
    },
  )
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
    pages,
    diagnostic_codes: session.diagnostics().map(item => item.code),
    page_width_twips,
    page_height_twips,
    margin_top_twips,
    margin_right_twips,
    margin_bottom_twips,
    margin_left_twips,
  }
}

///|
/// Build a marker-preserving MoonLeaf scene for the read-only browser demo.
/// It contains no customer or operator values and is never used for release.
pub fn template(
  source : FixedArray[Byte],
  manifest : @contractdoc.ContractTemplateManifest,
) -> @contractdoc.ContractPreviewTemplate raise ContractPreviewError {
  let markers = @worker.exact_docx_markers(source) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let marker_defaults = markers.map(marker => @contractdoc.ContractPreviewMarker::{
    marker,
    value: if marker.has_suffix(".mark}}") {
      "□"
    } else {
      ""
    },
  })
  let archive = @opc.open(source) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let rich = @docx.preview_document(archive) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let layout_copy = @worker.customize_exact_docx_template(
    source,
    marker_defaults.map(item => { placeholder: item.marker, value: item.value }),
  ) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let layout_archive = @opc.open(layout_copy.bytes) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let paged = @docx.paginate_document(layout_archive) catch {
    error => raise MoonLeafPreviewFailed("\{Repr(error)}")
  }
  let blocks : Array[@contractdoc.ContractPreviewBlock] = []
  let mut section : @docx.SectionInfo? = None
  for block in rich.blocks {
    match block {
      FlowParagraph(paragraph) =>
        blocks.push({
          ..empty_block("paragraph", paragraph.runs.map(preview_run)),
          level: paragraph.outline_level.unwrap_or(0),
          alignment: paragraph.metadata.alignment,
          spacing_before_twips: paragraph.metadata.spacing_before_twips,
          spacing_after_twips: paragraph.metadata.spacing_after_twips,
          line_twips: paragraph.metadata.line_twips,
          line_rule: paragraph.metadata.line_rule,
          left_indent_twips: paragraph.metadata.left_indent_twips,
          right_indent_twips: paragraph.metadata.right_indent_twips,
          first_line_twips: paragraph.metadata.first_line_twips,
          hanging_twips: paragraph.metadata.hanging_twips,
        })
      FlowTable(table) =>
        blocks.push({
          ..empty_block("table", []),
          rows: table.rows.map(preview_row),
          grid_widths_twips: table.grid_widths_twips,
        })
      FlowPageBreak => blocks.push(empty_block("page-break", []))
      FlowSection(value) => section = Some(value)
    }
  }
  let pages = marker_preserving_pages(rich, paged)
  let (width, height, top, right, bottom, left) = match section {
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
    template_id: manifest.template_id,
    template_version: manifest.template_version,
    template_sha256: manifest.fillable_sha256,
    scene: {
      engine: "moonleaf",
      packet_id: "demo-template",
      packet_revision: 0L,
      form: MasterLease,
      blocks,
      pages,
      diagnostic_codes: rich.warnings.map(warning => warning.code),
      page_width_twips: width,
      page_height_twips: height,
      margin_top_twips: top,
      margin_right_twips: right,
      margin_bottom_twips: bottom,
      margin_left_twips: left,
    },
    marker_defaults,
  }
}
