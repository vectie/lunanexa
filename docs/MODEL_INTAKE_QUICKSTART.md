# Turn a model catalog spreadsheet into reviewable registration drafts

Have a local artifact but no measured digest or size? Use the
[local artifact intake workflow](LOCAL_ARTIFACT_INTAKE_QUICKSTART.md) to generate
the same Candidate draft directly from one selected file.

`cmd/model-intake` fills the gap between an operator's ordinary asset spreadsheet
and LunaNexa's existing per-model `register-model FILE` contract. It imports a
mapped CSV, keeps every model in `Candidate`, compares it with a saved registry,
and extracts one exact registration-request body. You can edit the spreadsheet
and repeat the same workflow without hand-authoring nested model JSON.

This is entirely offline. It does not download artifacts, query model providers,
contact a controller, write registry state, accept licenses, verify signatures,
approve models, create deployments, grant access or run inference. ModelScope
discovery and managed-store registration remain separate existing workflows.

To start from existing registered metadata instead of a blank spreadsheet, use
the [saved catalog editing workflow](MODEL_CATALOG_EDIT_QUICKSTART.md): export
the saved registry as mapped CSV, edit a successor version, then reuse the
import, review and request commands below.

## Run the included synthetic example

Build in the existing LunaNexa workspace, retaining its exact MoonLeaf companion
and frozen dependencies. Keep generated targets outside the source tree:

```text
moon build --frozen --target native --strip -j1 --target-dir /absolute/private/build cmd/model-intake --deny-warn
```

Set `INTAKE` to
`/absolute/private/build/native/debug/build/vectie/lunanexa/cmd/model-intake/model-intake.exe`.
Set `EXAMPLES` to this repository's `tests/fixtures` directory, or the supplied
kit's `examples` directory. Use a separate writable working directory:

```text
$INTAKE import "$EXAMPLES/model-catalog.synthetic.csv" "$EXAMPLES/model-catalog-mapping.v1.json" > draft.json
$INTAKE review draft.json "$EXAMPLES/model-registry.synthetic.json" > review.json
$INTAKE request draft.json "$EXAMPLES/model-registry.synthetic.json" model-new v1 > register-model.json
```

The three invented source rows produce:

- `model-new / v1`: absent from the saved registry, so a Candidate request can
  be extracted. Its intentionally artificial `9007199254740993` byte count is
  preserved exactly as an Int64 JSON string, and its quoted multiline Unicode
  provenance is retained.
- `model-existing / v1`: metadata already registered with recorded `Approved`
  state. Request extraction is blocked, even though the draft is Candidate.
- `model-conflict / v1`: the saved record is `Revoked`, with different provenance
  and memory. Review lists both old and proposed values. Extraction is blocked.

The fixture contains no real model, artifact, license or verification evidence.
The kit's `outputs` are actual executions of these examples, including an edited
CSV and reimported draft with the new model's memory changed to 65536 MiB.

## Bring an ordinary CSV

1. Export one model/version per row as UTF-8 comma-delimited CSV. Keep the byte
   size column as text in spreadsheets when it exceeds their integer precision;
   this tool cannot recover digits already rounded by spreadsheet software.
2. Run `$INTAKE mapping > mapping.json` to get all ten field mappings. Change the
   header names to the exact names in your sheet, or copy the synthetic mapping.
   Every field must map to a distinct existing header. Column order is arbitrary.
3. Supply all of the following without guessing missing metadata:
   - model ID and version, matching LunaNexa contract identifiers;
   - complete `sha256:` artifact digest with 64 hexadecimal digits;
   - `s3://`, `oci://` or `modelstore://` artifact reference and positive byte size;
   - detached-signature/evidence reference, license ID and provenance text;
   - explicit compatible architectures, separated by semicolons;
   - positive minimum memory in whole MiB.
4. Import the CSV using the mapping. All rows must pass before any JSON is
   written. Edit the original CSV and rerun to revise the draft. Preserve the
   original CSV, mapping, saved registry and each desired draft revision.
5. Use an already-authorized saved JSON body of operator `GET /v1/registry`
   (`schema_version: "lunanexa.registry.v1"`) for review. Acquisition is outside
   this tool. It reads only `models`; it does not validate other registry domains.
   A model list, OpenAI `/v1/models` response and durable-store wrapper are not
   substitutes for this input format.
6. Inspect `review.json`, then extract the desired exact model ID and version.
   The request has exactly the existing `contracts.ModelRecord` shape accepted
   by `cmd/cli register-model FILE`. Its state is always Candidate. Sending it is
   a separate authorized operator action, not part of this workflow.

The license ID, provenance, digest, size and signature reference are operator
declarations. Neither their presence nor successful parsing establishes license
acceptance, authenticity, artifact possession, compatibility or measured memory.
Existing license, verification and approval gates remain required. Never put
raw credentials or access tokens into these references or files.

## What review means

An identity is the exact, case-sensitive pair `(model_id, version)`. Different
versions are distinct. Duplicate pairs reject the entire draft or saved models
projection rather than overwrite a row. Whitespace around CSV identifiers,
references and integers is trimmed; provenance is preserved verbatim.
Architecture items are trimmed, checked for duplicates and ordered. Their order
is ignored when comparing metadata; no architecture is inferred or discarded.
All other metadata compares exactly, including digest spelling and URI spelling.

- `new`: no matching pair in this saved registry.
- `already-registered`: matching pair and equal metadata. Recorded registry
  state is shown separately, so this status says nothing about readiness.
- `conflict`: matching pair with different metadata. Each difference includes
  the field name, candidate value and registered value. There is no overwrite
  or force option.

Both kinds of existing identity block request extraction, including Candidate,
Approved and Revoked records. A conflict elsewhere does not prevent extracting
an unrelated new model, but all source rows still must validate. Rows are ordered
lexically by model ID then version, and output is deterministic for equivalent
row order. No input arrays or files are modified.

The registry snapshot is supplied evidence, not a live lock or completeness
guarantee. A stale or incomplete snapshot may omit an identity that now exists.
Re-read the authoritative registry before any later registration: the existing
registration endpoint can replace an existing model/version. This tool cannot
make a later write conditional or prevent that race. A generated request does
not reserve the identity and is not proof of registration or approval.

## Supported data and failures

- CSV: up to 2 Mi UTF-16 characters / 8 MiB file bytes, 1–1000 model records,
  256 columns and 100000 total cells (including headers). Optional BOM,
  LF/CRLF/CR, quoted commas/newlines and doubled quotes are supported by the
  unchanged MoonLeaf CSV parser. Nonempty unique trimmed headers are required.
  Blank data records, ragged records, malformed quotes and missing mapped fields
  reject the complete import. Unmapped columns are ignored, never used as state
  or authority. They are not included in the output.
- Mapping: version 1, up to 16 Ki characters / 64 KiB bytes, no unknown fields.
  Header names are 1–256 characters without surrounding whitespace.
- Draft and saved registry: at most 1000 models, 8 Mi characters / 16 MiB bytes.
  Draft version and all draft/model fields are strict; unknown model fields fail.
  Other saved-registry domains and root fields are intentionally ignored.
  Empty draft/saved model arrays are supported; empty CSV intake is rejected.
- IDs and architecture names follow the existing 1–128-character ASCII contract
  (`A–Z`, `a–z`, digits, `-`, `_`, `.`, `:`). There must be 1–32 distinct
  architectures. Bytes are positive exact Int64; memory is positive Int32 MiB.
  Scientific notation, fractional units, signs and overflow are rejected.
- Artifact URI and signature reference are at most 2048 characters. URI scheme
  needs a nonempty resource, and ASCII spaces, traversal and ASCII control bytes
  (U+0000–U+001F and DEL U+007F) are rejected. Signature references cannot contain
  those ASCII control bytes. Provenance
  needs nonblank text of at most 4096 characters, with no NUL.
- The shared registry-registration predicate remains unchanged. Intake adds its
  bounded spreadsheet profile above, so some historically accepted but
  under-specified registry records cannot be reviewed by this tool.
- All files decode strict UTF-8. Each output is bounded to 8 Mi characters before
  stdout is written. Failed input/selection/command exits nonzero with a
  diagnostic on stderr and empty stdout. Shell redirection can still truncate
  the chosen output path before the program starts: always use a new output
  filename, never redirect onto an input. Same-size concurrent file replacement
  is not detected; keep source files stable during acquisition.

Reports and drafts retain private artifact references and provenance. They are
not sanitized for public sharing. Neither JSON output nor CSV intake is an
invoice, verification receipt, provisioning action or production qualification.

## Focused verification

Portable intake and shared-contract tests run on native and JavaScript. The
native CLI test actually imports, saves/reopens, reviews, edits/reimports and
extracts a request, then decodes it as `contracts.ModelRecord` and passes the
same registration predicate used by `ModelRegistry::register_model`. It checks
duplicate/conflict refusal, exact large integers, unchanged source files and
nonzero/empty-stdout failures. It requires `MODEL_INTAKE_EXE`,
`MODEL_INTAKE_FIXTURES` and an existing writable `MODEL_INTAKE_EVIDENCE` directory.

This does not run the full native registry, HTTP/authentication stack, database,
operator browser, model provider, artifact verification or physical GPU. The
infrastructure and commercial acceptance requirements remain open.
