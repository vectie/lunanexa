# MoonLeaf offline renderer

Executable `cmd/offline-pdf-renderer` consumes the same staged job JSON as
`offline-artifact-worker`. Run after worker `prepare`, before worker `finalize`.

Required environment:

- `LUNANEXA_OFFLINE_ARTIFACT_STAGING_ROOT`: isolated per-job directory.
- `LUNANEXA_OFFLINE_ARTIFACT_JOB_FILENAME`: basename, not a path.
- `LUNANEXA_OFFLINE_FONT_ROOT`: read-only approved static TrueType font directory.
- `LUNANEXA_OFFLINE_FONT_CONFIG_FILENAME`: deployment-controlled configuration path.
- `LUNANEXA_RENDER_EVIDENCE_SECRET`: shared verification secret, 32+ characters.
- Optional `LUNANEXA_OFFLINE_PDFTOPPM_BIN`: Poppler binary; default `pdftoppm`.

Font configuration schema (digests and license reference must be real):

```json
{
  "default_family": "仿宋_GB2312",
  "fonts": [
    {
      "family": "仿宋_GB2312",
      "filename": "FangSong_GB2312.ttf",
      "sha256": "sha256:<actual digest>",
      "license_reference": "<deployment license evidence reference>"
    }
  ]
}
```

Supply **every** family requested by the template, including title/heading fonts.
The renderer checks the font's internal family name and embedding flags. It never
renames Noto/other fonts into proprietary family slots. The font manifest and
license reference are operator inputs, not a substitute for a genuine license.

For the new open-font undertaking `youthpolicy-device-undertaking-ofl-v2`, use
`assets/fonts/open/noto-sans-sc/font-config.json`. Its reproducible official
OFL installation and four-page template acceptance are documented in
`assets/contracts/youthpolicy/undertaking-ofl-v2/README.md`. This version needs
no proprietary CJK font purchase. Original v1 continues to require its original
font families and is never silently substituted.

Outputs: requested PDF (or original DOCX/XLSX plus a PDF proof), per-page raster
PNGs and HMAC v3 manifest binding source bytes, artifact bytes, font bundle,
layout profile and every PNG digest. Worker finalization verifies the same
manifest. Poppler renders MoonLeaf's PDF only; it does not lay out DOCX/XLSX.

`passed` records successful supported-profile rendering and rasterization, **not**
human/legal approval or Word fidelity. Read MoonLeaf `render/README.mbt.md` for
scope. Unsupported semantics fail closed. Deployment readiness must additionally
be grounded in exact-template/exact-font visual acceptance.

Supported kinds: editable DOCX, print-ready PDF and bounded normalized XLSX
cell-value proofs. XLSX proof pages do not claim Excel styling/print fidelity.
Original workbook bytes remain the downloadable output.

Use read-only font mounts, a non-root runtime, per-job writable staging, bounded
job timeouts and CPU/memory limits. Do not mount controller or transfer credentials
into the renderer. See the shared offline-runtime image and dispatcher manifest.
