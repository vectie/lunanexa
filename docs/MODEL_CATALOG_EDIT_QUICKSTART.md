# Edit a saved model catalog into a successor-version draft

Start from the model metadata already in an authorized saved registry rather
than copying nested artifact JSON into a new spreadsheet by hand. The native
`model-intake export` command writes the same mapped CSV accepted by the
existing importer. Edit the desired version, reimport, review against the
saved registry, then extract one Candidate registration-request body.

This is an offline editing workflow. It does not fetch a registry, submit a
request, overwrite a model, verify an artifact, accept a license, approve a
version, change an alias, download weights, deploy a runtime or run inference.
Changing a version label never proves that its model or signature is valid.

## Export, edit, review, extract

Build `cmd/model-intake` with the pinned toolchain, frozen graph, exact MoonLeaf
R58 companion and an absolute external target. Set `INTAKE` to the resulting
native `model-intake.exe`. Use separate output files in a working directory:

```sh
$INTAKE mapping > mapping.json
$INTAKE export registry.json mapping.json > catalog.csv
$INTAKE import catalog.csv mapping.json > unchanged-draft.json
$INTAKE review unchanged-draft.json registry.json > unchanged-review.json
```

`registry.json` is an already-authorized saved `GET /v1/registry` response with
`schema_version: "lunanexa.registry.v1"`. Only its model records are read and
validated; other registry domains are ignored. Do not include credentials in
the snapshot. `mapping` produces the existing version-1 ten-field mapping.
An existing custom mapping can also be used for both export and reimport.

1. Keep the saved registry and the exported original. Open a copy of the CSV
   in a UTF-8 text/CSV editor. If using a spreadsheet, import every column as
   **text**, including byte size, version and identifiers. Opening CSV directly
   can silently turn version strings into dates or round large integers. Quoting
   does not prevent spreadsheet type inference. This command cannot recover
   data your editor has already changed.
2. Rows are sorted by exact model ID, then version. The last column,
   `lunanexa_registered_state`, shows the saved state, including Revoked and
   Deprecated. It is informational and deliberately not part of the mapping.
   Do not rename another mapped header to that reserved name.
3. Edit or copy the intended model row. Supply the actual successor version,
   artifact digest, location, exact size, signature reference, license,
   provenance, architectures and required memory. Nothing is inferred. Update
   only the fields that genuinely changed; a new version does not imply new
   bytes, and reused bytes do not establish license or signature eligibility.
4. Save the edited CSV as a new file. Unchanged rows can remain; the review
   distinguishes them from the new version. An unchanged exact identity remains
   blocked for request extraction, even if its recorded state was Candidate.

```sh
$INTAKE import edited-catalog.csv mapping.json > successor-draft.json
$INTAKE review successor-draft.json registry.json > successor-review.json
$INTAKE request successor-draft.json registry.json MODEL_ID NEW_VERSION > register-model.json
```

All imported rows are Candidate. The informational state column cannot import
an approval, and editing it does not change the resulting draft. A changed
record retaining its existing identity is a conflict, not a registry update.
Review preserves the saved recorded state and lists each differing metadata
field. Request extraction remains the existing `contracts.ModelRecord` shape.

If a later authorized operator intends to send the request, refresh and review
against the authoritative registry first. A saved registry is not a lock or a
completeness guarantee; this workflow does not make the existing registration
endpoint conditional. Sending is a separate action with its existing authority,
artifact-verification and approval requirements.

## Exact data and export limits

- Every field is quoted, quotes are doubled, and CSV records use CRLF. Embedded
  commas, quotes, Unicode and line breaks in provenance or header names survive.
  The original provenance string is preserved, including surrounding spaces.
- Byte size is emitted directly from Int64 as a decimal string. No floating
  point conversion is used, including values above spreadsheet precision.
  Required memory remains a positive Int32 MiB value.
- Architecture names are exported in canonical lexical order separated by
  semicolons. Their input order is not metadata identity in the existing review.
  Source arrays and files are never modified.
- Export validates every model and the mapping before writing stdout. Duplicate
  model/version pairs, unsupported metadata and invalid mappings reject the
  whole export. Existing intake/profile limits still apply.
- The output must fit the existing 2 Mi UTF-16-character CSV intake limit and
  contains at most 1000 model rows plus the header. Empty registries produce a
  header-only CSV; add a complete row before importing it because the importer
  requires at least one model.
- Common spreadsheet-formula prefixes (`=`, `+`, `-`, `@`, including after
  surrounding whitespace) and an initial tab/CR/LF reject the export. This
  includes mapping headers. The exporter does not silently prefix an apostrophe
  that would change model metadata on reimport. A signature reference with
  surrounding whitespace is also rejected because the existing importer trims
  that field. Retain and inspect the original JSON for such records; JSON review
  behavior is unchanged. These export restrictions do not change registry
  admission or retroactively invalidate records.
- The registry file is bounded to 16 MiB / 8 Mi characters; mapping to 64 KiB /
  16 Ki characters. Strict UTF-8 is required. Output or selection failure returns
  nonzero, a diagnostic on stderr and empty stdout. Shell redirection can still
  truncate an output file before the program starts. Always use a new output
  filename, never an input path, and keep inputs stable while reading.

The CSV is an editable projection, not a registry backup: it omits unrelated
domains and cannot restore lifecycle authority. Retain the original snapshot
and mapping alongside edits. References and provenance can be private; these
files are not sanitized for public sharing.

## Included synthetic workflow

`tests/fixtures/model-registry-edit.synthetic.json` contains two invented saved
models: `model-existing / v1` Approved and `model-conflict / v1` Revoked. Export
it with `tests/fixtures/model-catalog-mapping.v1.json`. An unchanged import/review
reports two already-registered records with no conflicts. The Approved record's
byte size `9007199254740993` and multiline Unicode provenance remain exact.

The native CLI test edits that record to `v2`, changes its digest, artifact
reference, signature reference, provenance and memory, then saves and reimports
the CSV. Review reports one new model/version and one unchanged existing record;
the extracted request remains Candidate and passes the existing shared
registration predicate. It also checks repeatable export, untouched source
files, empty catalogs and nonzero/empty-stdout failures. The fixture is not
evidence of real models, verification, approval or hardware performance.

This focused workflow has portable core and native CLI tests. No live registry,
API/authentication stack, UI, spreadsheet application, provider, database,
physical cluster, payment or model execution is qualified by these tests.
