///|
pub(all) suberror WorkerVerificationError {
  InvalidInput(String)
  UnsupportedKind(@offline.DocumentArtifactKind)
  MoonLeafRejected(String)
  FormulaErrors(Int)
} derive(Debug, Eq)

///|
pub(all) struct OoxmlVerification {
  moonleaf_verified : Bool
  diagnostic_codes : Array[String]
  formula_error_count : Int
  active_content_detected : Bool
  reopened_byte_count : Int
} derive(Debug, Eq)

///|
pub(all) struct TextReplacement {
  placeholder : String
  value : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CellReplacement {
  sheet_name : String
  row : Int
  column : Int
  value : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub(all) struct CustomizedOoxml {
  bytes : FixedArray[Byte]
  replacement_count : Int
  verification : OoxmlVerification
} derive(Debug, Eq)

///|
fn active_part(name : String) -> Bool {
  let lower = name.to_lower()
  lower.has_suffix("vbaproject.bin") ||
  lower.contains("activex") ||
  lower.contains("embeddings/") ||
  lower.contains("oleobject") ||
  lower.has_suffix(".exe") ||
  lower.has_suffix(".js")
}

///|
fn formula_error(value : String) -> Bool {
  value == "#REF!" ||
  value == "#DIV/0!" ||
  value == "#VALUE!" ||
  value == "#NAME?" ||
  value == "#N/A" ||
  value == "#NUM!" ||
  value == "#NULL!"
}

///|
pub fn verify_ooxml(
  filename : String,
  kind : @offline.DocumentArtifactKind,
  bytes : FixedArray[Byte],
) -> OoxmlVerification raise WorkerVerificationError {
  if filename.trim() == "" || bytes.length() == 0 || bytes.length() > 100000000 {
    raise InvalidInput("invalid OOXML worker input")
  }
  let expected_format = match kind {
    EditableContractDocx => @moonleaf.DocumentFormat::Docx
    QuoteScheduleXlsx => Xlsx
    _ => raise UnsupportedKind(kind)
  }
  let session = @moonleaf.open_session(filename, bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  if session.format() != expected_format {
    raise MoonLeafRejected("extension and requested artifact kind disagree")
  }
  let capabilities = session.capabilities()
  if !capabilities.render_scene || !capabilities.save_as_copy {
    raise MoonLeafRejected("required MoonLeaf capabilities are unavailable")
  }
  let archive = @opc.open(bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let active_content_detected = archive.parts.any(part => active_part(part.name))
  let mut formula_error_count = 0
  if kind == QuoteScheduleXlsx {
    let cells = @xlsx.inspect(archive) catch {
      error => raise MoonLeafRejected("\{Repr(error)}")
    }
    for cell in cells {
      if cell.cached_value.map_or(false, formula_error) ||
        cell.resolved_text.map_or(false, formula_error) {
        formula_error_count += 1
      }
    }
  }
  if formula_error_count > 0 {
    raise FormulaErrors(formula_error_count)
  }
  let copy = session.save_as_copy() catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let reopened_bytes = copy.bytes()
  let reopened = copy.session()
  if reopened.format() != session.format() ||
    reopened.scene() != session.scene() ||
    reopened_bytes.length() == 0 {
    raise MoonLeafRejected(
      "MoonLeaf verified copy did not preserve the semantic scene",
    )
  }
  {
    moonleaf_verified: true,
    diagnostic_codes: session.diagnostics().map(diagnostic => diagnostic.code),
    formula_error_count,
    active_content_detected,
    reopened_byte_count: reopened_bytes.length(),
  }
}

///|
fn safe_replacement_text(value : String, maximum : Int) -> Bool {
  value.length() <= maximum &&
  value.all(character => character.is_printable() && character != '\u{0000}')
}

///|
fn replace_docx_text_element(
  element : @xml.Element,
  find : String,
  replacement : String,
) -> @xml.Element {
  let is_word_text = element.name == "w:t"
  let children = []
  for child in element.children {
    match child {
      Text(text) if is_word_text =>
        children.push(@xml.Text(text.replace_all(old=find, new=replacement)))
      Text(_) => children.push(child)
      Element(nested) =>
        children.push(
          Element(replace_docx_text_element(nested, find, replacement)),
        )
    }
  }
  { name: element.name, attributes: element.attributes, children }
}

///|
fn docx_header_or_footer(name : String) -> Bool {
  (name.has_prefix("word/header") && name.has_suffix(".xml")) ||
  (name.has_prefix("word/footer") && name.has_suffix(".xml"))
}

///|
/// MoonLeaf's current document-session edit covers the main document part.
/// Legal templates also place order references in related headers and footers,
/// so apply the same prefix-specific `w:t` rule to those bounded OOXML parts.
fn replace_docx_headers_and_footers(
  bytes : FixedArray[Byte],
  replacements : Array[TextReplacement],
) -> FixedArray[Byte] raise WorkerVerificationError {
  let mut archive = @opc.open(bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  for part in archive.parts {
    if docx_header_or_footer(part.name) {
      let source = archive.text(part.name) catch {
        error => raise MoonLeafRejected("\{Repr(error)}")
      }
      let mut root = @xml.parse(source) catch {
        error => raise MoonLeafRejected("\{Repr(error)}")
      }
      for replacement in replacements {
        root = replace_docx_text_element(
          root,
          replacement.placeholder,
          replacement.value,
        )
      }
      archive = archive.replace_text(part.name, @xml.serialize(root))
    }
  }
  @opc.save(archive) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
}

///|
pub fn customize_docx_template(
  bytes : FixedArray[Byte],
  replacements : Array[TextReplacement],
) -> CustomizedOoxml raise WorkerVerificationError {
  if replacements.length() == 0 || replacements.length() > 256 {
    raise InvalidInput("DOCX replacements are empty or exceed the bound")
  }
  let mut session = @moonleaf.open_session("contract.docx", bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let keys : Map[String, Unit] = Map([])
  for replacement in replacements {
    if replacement.placeholder.length() < 3 ||
      replacement.placeholder.length() > 160 ||
      !replacement.placeholder.has_prefix("{{") ||
      !replacement.placeholder.has_suffix("}}") ||
      !safe_replacement_text(replacement.value, 4000) ||
      keys.contains(replacement.placeholder) {
      raise InvalidInput("invalid or duplicate DOCX replacement")
    }
    keys[replacement.placeholder] = ()
    session = session.replace_text(replacement.placeholder, replacement.value) catch {
      error => raise MoonLeafRejected("\{Repr(error)}")
    }
  }
  let copy = session.save_as_copy() catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let customized = replace_docx_headers_and_footers(copy.bytes(), replacements)
  {
    bytes: customized,
    replacement_count: replacements.length(),
    verification: verify_ooxml(
      "contract.docx",
      EditableContractDocx,
      customized,
    ),
  }
}

///| Exact-format legal templates use one verified marker per physical slot.

///| This path requires the caller to account for every marker. Missing or

///|
/// unknown values fail instead of leaking markers or inventing contract text.
pub fn customize_exact_docx_template(
  bytes : FixedArray[Byte],
  replacements : Array[TextReplacement],
) -> CustomizedOoxml raise WorkerVerificationError {
  if replacements.length() == 0 || replacements.length() > 512 {
    raise InvalidInput("exact DOCX replacements are empty or exceed the bound")
  }
  let expected = exact_docx_markers(bytes)
  if expected.length() == 0 || expected.length() != replacements.length() {
    raise InvalidInput("exact DOCX replacement set is incomplete")
  }
  let expected_set : Map[String, Unit] = Map([])
  for marker in expected {
    expected_set[marker] = ()
  }
  let provided : Map[String, Unit] = Map([])
  for replacement in replacements {
    if !expected_set.contains(replacement.placeholder) ||
      provided.contains(replacement.placeholder) ||
      !safe_replacement_text(replacement.value, 4000) {
      raise InvalidInput("exact DOCX replacement is unknown or invalid")
    }
    provided[replacement.placeholder] = ()
  }
  let result = customize_docx_template(bytes, replacements)
  let reopened = @opc.open(result.bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let completed = reopened.text("word/document.xml") catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  if completed.contains("{{") || completed.contains("}}") {
    raise InvalidInput("exact DOCX output retains a marker")
  }
  result
}

///|
/// Returns each distinct physical marker in deterministic lexical order.
pub fn exact_docx_markers(
  bytes : FixedArray[Byte],
) -> Array[String] raise WorkerVerificationError {
  let archive = @opc.open(bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let source = archive.text("word/document.xml") catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let mut cursor = 0
  let expected : Map[String, Unit] = Map([])
  while cursor < source.length() {
    guard source[cursor:].find("{{") is Some(relative_start) else { break }
    let start = cursor + relative_start
    guard source[start + 2:].find("}}") is Some(relative_end) else {
      raise InvalidInput("exact DOCX template contains an open marker")
    }
    let end = start + 2 + relative_end + 2
    let marker = source[start:end].to_owned()
    if marker.length() < 5 || marker.length() > 180 {
      raise InvalidInput("exact DOCX marker is invalid")
    }
    expected[marker] = ()
    cursor = end
  }
  let markers = expected.to_array().map(pair => pair.0)
  markers.sort()
  markers
}

///|
pub fn customize_xlsx_template(
  bytes : FixedArray[Byte],
  replacements : Array[CellReplacement],
) -> CustomizedOoxml raise WorkerVerificationError {
  if replacements.length() == 0 || replacements.length() > 1024 {
    raise InvalidInput("XLSX replacements are empty or exceed the bound")
  }
  let mut session = @moonleaf.open_session("quote.xlsx", bytes) catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let coordinates : Map[String, Unit] = Map([])
  for replacement in replacements {
    let key = "\{replacement.sheet_name}:\{replacement.row}:\{replacement.column}"
    if replacement.sheet_name.trim() == "" ||
      replacement.sheet_name.length() > 160 ||
      replacement.row <= 0 ||
      replacement.column <= 0 ||
      !safe_replacement_text(replacement.value, 4000) ||
      coordinates.contains(key) {
      raise InvalidInput("invalid or duplicate XLSX replacement")
    }
    coordinates[key] = ()
    session = session.set_cell_text(
      replacement.sheet_name,
      replacement.row,
      replacement.column,
      replacement.value,
    ) catch {
      error => raise MoonLeafRejected("\{Repr(error)}")
    }
  }
  let copy = session.save_as_copy() catch {
    error => raise MoonLeafRejected("\{Repr(error)}")
  }
  let customized = copy.bytes()
  {
    bytes: customized,
    replacement_count: replacements.length(),
    verification: verify_ooxml("quote.xlsx", QuoteScheduleXlsx, customized),
  }
}
