# Youthpolicy DGX Spark remote-lease template v1

This file is the execution contract for the retained source template at
`assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.docx`.
The retained DOCX is the design and legal-text authority. LunaNexa must never
rewrite, summarize, translate, or extend its clauses.

## Reference

- Original filename: `NVIDIA DGX Spark算力设备远程租赁合同（修订版）.docx`
- Retained path: `assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.docx`
- Internal marker copy: `assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.fillable.docx`
- Internal marker-copy SHA-256: `d4445ad5566d5dc1d3d24c9ecd77090e03d1eb8fa7d25c575b012b4d2e6f573a`
- SHA-256: `9edba327848cd84a6b9e64bb7d0d7896c844468c64749ec4bb96b60c7f4c2d48`
- Size: 419136 bytes
- Source package: 14 OOXML parts, no active content, no drawings, no fields,
  no content controls, no footnotes, and no endnotes.
- Rendered page count: 14
- Section count: 1

The source digest is checked before every fill. A different digest is a new
template version and requires a fresh slot and visual audit.

## Page system and typography

- One portrait A4 section: 11905 x 16840 DXA.
- One column; the source does not explicitly store page-margin elements, so
  inherited application behavior is part of the reference-render evidence and
  is unresolved rather than guessed.
- Default linked header/footer parts are present but empty.
- The body is predominantly `仿宋_GB2312` at 16 pt; tables use
  `仿宋_GB2312` at 12 pt. Section headings use `黑体` at 16 pt. The title uses
  `方正小标宋简体` at 26 pt.
- The document uses extensive direct formatting. The generator must preserve
  it rather than normalizing styles.

## Packet structure

The one source contains seven long-horizon forms:

1. master equipment lease;
2. compute lease reservation application and operator review;
3. access opening/closure confirmation;
4. violation notice;
5. damage assessment and compensation notice;
6. lease settlement confirmation;
7. early termination application and operator review.

The authoritative typed field inventory and OOXML locators are exported by
`contractdoc.youthpolicy_remote_lease_manifest()`. A packet activates only the
forms required for its current lifecycle task. A later form creates a new
confirmed packet revision; it does not rewrite an earlier generated artifact.

## Collection and no-invention rules

- Every filled value must come from an authenticated user or operator input.
- Missing required values block confirmation and generation.
- Choices accept only options printed in the source document.
- Money-in-words fields are collected explicitly; LunaNexa does not invent or
  calculate their legal wording.
- Signatures, seals, and the access initial password are completed offline.
  They are never stored in contract packet state.
- Audit events record field identifiers and document/value digests only. They
  do not repeat names, addresses, telephone numbers, business-purpose prose,
  passwords, or signatures.
- The original DOCX remains byte-for-byte unchanged.

## Package preservation

Only `word/document.xml` is editable, and only at a locator declared in the
versioned manifest. These parts are preserve-only and must retain their source
SHA-256 exactly:

| Part | SHA-256 |
|---|---|
| `[Content_Types].xml` | `e90ca394d9f5bf4d62ea461ae2b1953616a435bf0096644dfa863c89d3b0f293` |
| `_rels/.rels` | `514e1846381cb6bcfff105a4b0a17d666cf0ed1f0c120bff73b82226ab7ed977` |
| `docProps/app.xml` | `23b26ddf3465bfa49150ed00b4bec6a3c02ccc0b66f0891db44a86649f477fb7` |
| `docProps/core.xml` | `6708515596783c049a405d689cfbfd924b16dedf1136c2095002129a238d4de0` |
| `docProps/custom.xml` | `dd93741f0b908e7649c8f1f5f3336d3d50ce87b047ae5b4b14e16371f35cf874` |
| `word/_rels/document.xml.rels` | `4e015530d0dc70fe8279c2684b2ccc6a2f7759977753206559307c03f3633768` |
| `word/fontTable.xml` | `4ec2c3e3affae1ca3e4e65fae6770399ea6fc3d3b3ed6a6eae622d1ed8742d23` |
| `word/footer1.xml` | `8c1e7e11538572f56b2604e23623090913095518afefa463d0c7e1366ae876fe` |
| `word/header1.xml` | `c459a0e3c2356479313c79000380dbcdb0779a377e58cd10d64682ca6e64739a` |
| `word/numbering.xml` | `5c5d3a14fa0aae31788908ff8c08e2424968f17a31c3dc74c5738a65878a5791` |
| `word/settings.xml` | `13b7869dcbf8fa36b7ad3e262b0875b1544e04800dfabb5b8e5e04f652e6e33a` |
| `word/styles.xml` | `2776aa1c04d340bef3fcd98afe4f423493898828658affb1da761c6d19369e68` |
| `word/theme/theme1.xml` | `bea0a0590dea0ed9e97fa4391c1b7980640249387153014388eaaa628837b32c` |

## Fidelity gates

Before a DOCX/PDF pair is released:

1. verify source digest and all declared locator preconditions;
2. verify the internal marker-copy digest, replace every marker, reject any
   remaining marker, and preserve all package parts above byte-for-byte;
3. reopen the result with MoonLeaf and reject active content or structural loss;
4. render the DOCX to PDF and all 14 page images with the approved production
   Chinese font set;
5. compare reference/final page geometry and inspect every final page at 100%;
6. reject missing glyphs, unexpected page-count change, clipping, overflow,
   moved tables, modified recurring furniture, or unexplained pixel changes;
7. bind DOCX, PDF, page images, source digest, value digest, and renderer
   receipt into one generation result.

The current local LibreOffice environment does not resolve the source's three
named Chinese fonts and therefore renders Chinese characters as missing. This
is a hard PDF release blocker, not permission to substitute fonts or ship a
visually different contract. The DOCX source and its Chinese text remain
intact.

The marker copy is never a customer artifact and must never be sent to the
renderer before every marker has been replaced. Its visible markers expand the
source to 18 pages; a completed contract that does not return to the source's
14-page count fails the release gate.
