# Equipment use undertaking source

This collection contains only Attachment 2, `设备使用承诺函`, from the
user-supplied rental-scheme request. The request narrative, Attachment 1,
reviewer comments and personal document properties are not published.

The supplied original has SHA-256
`3bb56d66ae9d36519df9a25de1dd80eda7880865960780227da03f08172f9de5`.
`scripts/build-undertaking-template.mbtx` checks that exact digest before
extracting the reviewed attachment. The original is deliberately not committed.

## Fidelity contract

- All six sections, the fixed addressee, all five price tiers and the sole
  undertaking-party signature/stamp line are retained without rewriting.
- The source itself contains the equal-effect wording. Preserving that wording
  is not a platform certification of enforceability.
- Original section geometry is retained: 11906 × 16838 twips, top/bottom
  margins 1440, left/right margins 1800, single column, line grid 312.
- Original run fonts, sizes, paragraph spacing, first-line indents, numbering
  definitions, table widths, row rules and package relationships are retained.
- Only `word/document.xml` differs between source and fillable templates.
  The fillable copy replaces the organization blank and the date blanks with
  four declared markers. There is no added legal prose or operator signature.
- `lessee.name` maps to paragraph `w14:paraId="0E84CC24"`.
  `undertaking.signed_date` maps to paragraph `w14:paraId="694B4DD1"`, with
  year/month/day markers retaining the original Chinese date separators.
- `lease.start_date`, `lease.end_date` and `lease.total_rent` are platform
  admission metadata. They are not inserted into the undertaking's text.

The browser scene is generated with the same MoonLeaf parser/paginator used
for authenticated previews:

```sh
moon run cmd/contract-preview-scene --target native -- \
  assets/contracts/youthpolicy/undertaking-v1/device-use-undertaking.fillable.docx \
  assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json \
  youthpolicy-device-undertaking-v1
```

## Verification

The source and fillable digests are pinned in `contractdoc/undertaking.mbt`.
Native tests verify both byte digests, package-part fidelity, four exact
markers, fixed clauses/prices, absence of the request/Attachment 1, and actual
MoonLeaf substitution plus a four-page preview. The three admission fields
remain outside the legal document.

On 2026-09-16, bundled LibreOffice 26.8 was used only for independent visual
inspection of the extracted source, not as the platform rendering backend.
All four extracted pages were inspected. An isolated fontconfig included the
locally licensed `FangSong_GB2312` face and system CJK fallbacks; without that
font configuration the bundled renderer omitted Chinese glyphs. No substitute
font was renamed or packaged as an original face. Exact production typography
continues to require the approved font deployment in `assets/fonts/private`.

An online preview is not a generated document artifact or completed rental.
The authenticated renderer worker still must materialize the selected template,
publish its verified DOCX/PDF and report results through the existing worker
API before customer submission and approval may proceed.
