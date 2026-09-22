# Offline document evidence, 2026-09-22

This is retained technical evidence, not a signed production readiness document.
No legal owner's name, third-party certification, qualified signature or real customer order is
invented by these files. The capability switches remain a separate reviewed
deployment decision.

## Scope and results

| Capability | Observed evidence | Not proved by this package |
|---|---|---|
| ApprovedLegalTemplates | Exact v2 source/fillable hashes; old v1 retained; parsed wording/fields unchanged; four-page technical review; platform owner's explicit removal of the bilingual prerequisite | Third-party legal certification; jurisdictional enforceability; approval of every legacy template |
| CjkFonts | Official Noto Sans SC source at fixed upstream commit; OFL license retained; deterministic static weight-400 font; real family/embedding checks; production font PVC verified | Proprietary v1 font licenses or deployment-wide font coverage beyond this named v2 profile |
| PdfRenderer | MoonLeaf native PDF; exact source/font/page binding; four pages rasterized; actual Linux prepare/render/finalize/scanned-S3 roundtrip/callback-recovery; macOS/Linux PDF byte identity | Actual production controller order/Job acceptance, final immutable production image digest, operator signoff of every supported template |
| SpreadsheetFormulaEngine | Current MoonLeaf XLSX native strict suite 38/38; worker suites 14/14; synthetic stale-cache 999 replaced by `49*7=343`, rendered and visually checked | An actual production quote template/order rehearsal; full Excel compatibility; approval of financial/tax policy |

`probe-summary.json` and `render-test-only.json` came from the real isolated
Linux run `test-only-1790069913499`. Its controller plan/callback endpoint was
a test HTTP service; storage, scanner, worker, renderer and rasterizer were real.
The first callback deliberately returned 503; recovery used the persisted
artifact and succeeded on the second callback without rerendering. The HMAC
receipt uses an explicitly test-only authority and is **not** a production key.
The isolated namespace was subsequently removed; these non-secret receipts and
images are retained here.

## Exact inputs

- Template `youthpolicy-device-undertaking-ofl-v2`, version `v2`, locale `zh-CN`.
- Source DOCX SHA256: `bae42968028bc491455dca0463f4ce16018134bb9a06e90b3b05e88fd8aae117`.
- Fillable DOCX SHA256: `92f0041e2752d684ced68dd09f793ed0aafd795dc92c2f9522ca25c0af4542f7`.
- Filled sample: organization `示例使用单位`, date `2026-09-22`; not a customer order.
- Prepared DOCX SHA256: `bd539681004440f7f1417fcb8781b0a663f56bfce9467bad1bd2818b33e1f5e2`.
- Four-page PDF SHA256: `7f47f4fec8dba952bc9dc700e7a5bebb7c42946b2780364c26a3529162740b19`, 10,824,742 bytes.
- Noto Sans SC Regular static TTF SHA256: `c7763f454946833081cc90e73186615f8e1189de9c5e5a5a8752871fd79fddbc`.
- OFL file SHA256: `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2`.
- Runtime font manifest SHA256: `9a022142b3e7a7aa078ced948b81c95ac9cc133cd54a1cb658840ede4711db71`.

Font provenance and deterministic generation are in
`assets/contracts/youthpolicy/undertaking-ofl-v2/README.md` and
`scripts/install-open-contract-fonts.mbtx`. The large TTF and PDF are not put in
Git. The DOCX sources are retained with the template; the visual baselines are
the four small PNGs whose hashes are bound by the retained render receipt.

## Visual inspection

All four pages were individually inspected: title and clauses readable; Chinese
glyphs present; no clipping/overlap; rental table includes all five periods and
prices; filled organization/date and signature label fit. The final v2 signature
paragraph is right aligned with zero first-line indent to avoid wrapping the
last character of the seal label. Independent LibreOffice rendering of the DOCX
was also inspected on all four pages. Line/page breaks differ because MoonLeaf
keeps paragraphs together; no pixel equivalence to Word or LibreOffice is claimed.

The formula image is deliberately a **separate synthetic fixture**. Its one-page
grid has Price=49, Days=7, Total=343 after replacing a stale 999 cache. PDF SHA256
is `6cb4fdf99f6d62f0f40f72ffc84ab04347c41b507afecd0f8b0b7c5be0130090`.
The engine supports bounded same-sheet arithmetic/references, percentages,
SUM/MIN/MAX ranges and ROUND; unsupported functions, external/cross-sheet,
shared/array formulas, cycles and arithmetic errors fail closed. The proof is a
normalized value grid, not Excel print-layout fidelity.

## Remaining release decisions

### Subsequent production runtime qualification (2026-09-22)

Two genuine Kubernetes Jobs in namespace `lunanexa` subsequently completed
prepare, MoonLeaf render, per-page raster evidence, and finalize with the actual
read-only approved-font PVC, production render-evidence authority, admission
policy and the AF_UNIX-only worker seccomp profile:

Runtime image: `moon/offline-runtime@sha256:49e6cadff1be5ed2cac0193f5e275d1ac34ce55c4f3cc57c65e6524b34aaa1c8`
from the deployment's private registry. This exact image was read back from the
production Job specification.

- Chinese OFL v2: `offline-artifact-9e6800d95e087c99e2829a816b5ad3a704b0d4ed`;
  four-page PDF SHA256 `65e70f452ad7dd7029acaf6edde0fad1b4175741209a82c168d3f45d8cf7b543`.
  All four retained `production-docx-page-*.png` pages were visually inspected;
  text, all five tariff rows and signature area are readable without clipping.
  The sample explicitly states “技术验收样例（非商业订单，未签署）”.
- Original quote-v1 XLSX:
  `offline-artifact-7b836a8609006da2af5b8a7bb68787c49dd13cc6`;
  output XLSX SHA256 `c044202b042e94ad0ee4cb7b87a1ebedb3ecc9c46e68e70d08bbdf8453f4c6eb`.
  Actual worksheet XML retains B8 `SUM(B6:B7)` with cached value 76320,
  B6=72000 and B7=4320; the one-page normalized visual proof was inspected.

The production receipts and PNGs are retained by
`scripts/retain-production-document-qualification.mbtx`. These Jobs are
explicit technical qualifications, not paid/signed customer orders. They close
the production **runtime** part of items 2 and 3 below, but do not manufacture a
controller business callback, legal approval or financial fulfillment receipt.
The earlier isolated probe and its `production_ready=false` remain unchanged.

1. Retain attributable platform approval for exact template ID/version/hash and
   supported locale. On 2026-09-22 the platform owner explicitly said that the
   bilingual evidence condition was erroneous and must be removed. This `zh-CN`
   profile does not require an English counterpart. The current conversation's
   deployment approval may be retained as its actual source; no personal name,
   professional qualification or third-party certification may be invented.
2. Bind production evidence to the actual runtime image digest, read-only font
   and template mounts, authenticated controller callback and retained order.
3. Run the real quote-v1 XLSX path through that production worker; verify B8
   `SUM(B6:B7)` equals the authoritative integer-money quote total. The existing
   workbook declares `Noto Sans CJK SC`; the normalized proof uses the explicit
   runtime default font, and does not attest to workbook-font fidelity.
4. Require separate evidence before permitting legacy proprietary-font templates
   or additional locales. Technical publication on a PVC is not legal approval.

The evidence-retention helper verifies source/PDF/page digests before copying:
`scripts/retain-open-font-evidence.mbtx`. The contract-PVC inventory is generated
by `scripts/contract-asset-manifest.mbtx`; `contract-assets-sha256.txt` covers all
14 published source/preview/documentation files, not just the new template.

## Real MoonEdit production bridge acceptance

The subsequent `moonedit-production-bridge.json` records the real authenticated
MoonEdit API path on the deployed controller, not a directly submitted worker
qualification Job. The agent used an authenticated purchaser session to create
and fill the technical packet, an operator supplied its assigned fields, and the
purchaser session confirmed and requested
generation. No operator artifact-generation request was inserted manually.

The controller automatically queued exactly one frozen DOCX/PDF pair. An exact
repeat of the generate click retained revision 5. Actual dispatcher callbacks
published both scanned objects and advanced the packet to `Generated`, revision
6, with **four actual pages in each artifact** and matching visual evidence
`sha256:2e1012e44af3f571b49894bd2385b9d17465f4100a9e20d155f6c07dbe06ecea`.
The private frozen plans are absent from the operator snapshot projection.

Controller image: `sha256:ec18ed94a93176b41b8de1e2b0f8920ee4ef98a12434cb9a9d6fb4abf8eb01df`.
Worker image: `sha256:ec1d28986b5ee034ec7125f88ecb82ad4b9b96580ae6cac8763183a6a16aaff4`.
`scripts/retain-moonedit-bridge-evidence.mbtx` validates the captured responses
before retaining this scoped evidence, without tokens or unrelated tenant data.

This packet explicitly says “技术验收样例（非商业订单，未签署）”. Generated does
not mean signed, paid, legally executed or entitled. The earlier isolated and
direct-Job evidence above retains its original, narrower claims.

Both actual Kubernetes Jobs completed (`Succeeded=1`), as checked by the
dispatcher deployment workstream:

- `offline-artifact-e332d55952485c819a00bd57dc3178f2044407a2`, UID
  `8eef4bbc-f26f-4259-b4a1-e4e0bf095fb2`;
- `offline-artifact-eaf0799473ba6a47a43752138fdfc8465330d71a`, UID
  `d8c12f35-dc17-4047-bc49-c0757f6df5c2`.
