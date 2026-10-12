# Turn one local artifact into a model draft

Use `model-intake local-artifact` when you already have a model artifact file
and want to prepare its registry metadata without transcribing a digest or file
size. The command streams the selected bytes into SHA-256, measures their exact
size, and emits the existing Candidate draft. Save it, review it against an
authorized saved registry, and extract the existing registration-request body.

This is a local file workflow. It does not contact ModelScope, an artifact URI,
a controller, or a node; upload or move bytes; register or approve a model;
verify a signature or license; run inference; or accept a purchase or agreement.
The artifact can be a single model file or a previously prepared archive. A
shard, index, directory, or manifest is not automatically expanded into weights.
The computed digest identifies exactly the one file read, not its dependencies.

## Prepare declarations and read the artifact

Build `cmd/model-intake` with the retained pinned graph and Leaf R58 companion,
using an absolute external target. Set `INTAKE` to the resulting native
`model-intake.exe`. The full synthetic workflow, from the source directory:

```sh
$INTAKE local-artifact tests/fixtures/local-artifact.synthetic.bin \
  tests/fixtures/local-artifact-metadata.synthetic.json > local-draft.json
$INTAKE review local-draft.json tests/fixtures/model-registry.synthetic.json \
  > local-review.json
$INTAKE request local-draft.json tests/fixtures/model-registry.synthetic.json \
  local-model v1 > register-model.json
```

The invented binary is 131335 bytes, deliberately crosses two 64 KiB read
boundaries, and includes arbitrary binary bytes. Its digest is
`sha256:f9bee7fdb821357e6b4a03658df896a5bb056360b1e6645dfbeacc1018130056`.
It is not a real model. The metadata's license, signature, architectures and
memory requirement are invented declarations.

For your own file, copy and edit the metadata fixture. All fields are required:

```json
{
  "schema_version": "lunanexa.local-artifact.v1",
  "model_id": "my-model",
  "version": "v1",
  "artifact_uri": "modelstore://my-model/model.bin",
  "signature_ref": "operator-supplied-signature-reference",
  "license_id": "operator-supplied-license-id",
  "provenance": "Where these bytes came from; declarations still require verification",
  "compatible_architectures": ["aarch64"],
  "minimum_memory_mib": 32768,
  "maximum_artifact_bytes": "68719476736"
}
```

- Choose the model identity, actual license/signature references, provenance,
  supported architectures and memory requirement yourself. None is derived from
  the filename or guessed from content. SHA-256 and byte size are computed and
  must not be supplied in the metadata. State and other unknown fields reject.
- `artifact_uri` is the intended managed reference using `s3://`, `oci://` or
  `modelstore://`. It is preserved exactly. Reading a local file does not prove
  that the URI contains those bytes or that a runtime can use them. Uploading,
  signing, verifying and registering remain separately authorized workflows.
- `maximum_artifact_bytes` is your positive decimal-string read ceiling, at most
  1099511627776 bytes (1 TiB). The command refuses a file above it before hashing.
  The ceiling is not an expected size and is omitted from the resulting draft.
- Declarations use existing intake/registration bounds: 1–128-character ASCII
  identifiers, 1–32 distinct architectures, positive Int32 memory MiB, bounded
  URI and signature references, and nonblank provenance up to 4096 characters.
  Provenance and metadata strings retain their exact contents; architectures
  are canonically sorted in the draft without modifying the input array.

Keep your source file stable while reading. The command opens it read-only,
requires an ordinary nonempty file, and reads in 65536-byte chunks. A symlink
may name a regular file; directories, pipes, devices and sockets are unsupported.
It uses the opened file's exact size, checks for extra bytes, and compares size,
modification time and change time after reading. Growth, truncation and observed
metadata changes fail. These checks are not an atomic filesystem snapshot and
cannot prove the absence of every concurrent same-size edit or path replacement.
Use a stable, already-authorized copy. Renaming/replacing the path cannot make
the output describe the new path's content: the digest belongs to the opened
file. The local path and filesystem timestamps are not placed in the draft.

## Review, change and reuse

The result is schema-version-1 `model_intake.Draft`, with one Candidate model.
The existing importer can reopen it and the existing review shows `new`,
`already-registered`, or `conflict`. It does not restore or modify a registry.
A changed artifact with the same model/version produces a digest/size conflict
against a saved record. For a genuine successor, edit the version and any
changed declarations in a new metadata file, rerun acquisition and review again.
The same unchanged inputs produce the same output.

Existing identities remain blocked for request extraction, even if they were
Candidate, Approved or Revoked. Refresh the authorized registry before a later
registration: a saved snapshot is not a lock, and the existing endpoint can
replace an identity. Extracting JSON neither sends the request nor reserves its
identity. Nothing here validates a runtime, registers a node or grants access.

## Bounds, failures and privacy

The metadata file is at most 64 KiB of strict UTF-8 bytes and 16 Ki UTF-16
characters. The artifact is arbitrary binary; it is not decoded as text, parsed,
decompressed or executed. Hashing uses bounded memory but time grows with file
size. The 1 TiB ceiling is a supported integer bound, not a performance or
large-model qualification. Focused tests use small synthetic files.

All checks complete before stdout is written. Missing files, invalid metadata,
empty/nonregular artifacts, read-limit violations and observed file changes exit
nonzero with a diagnostic on stderr and empty stdout. Use new output filenames:
shell redirection can truncate an existing input before the program starts.
Original files are never written by the executable; ordinary filesystem access
times may change. Metadata paths can appear in error messages from the OS.

Keep artifacts, declarations, drafts and saved registries in approved private
storage. A digest is content identity, not signature authenticity, provenance,
model safety, licensing, remote availability or production qualification.
The pure `import_artifact_metadata` and `artifact_draft` APIs share the same
metadata validation on JS/native; only the native command actually reads and
hashes the selected file. No browser, database, provider, GPU or paid service is
qualified by this workflow.
