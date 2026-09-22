# Device undertaking — open-font edition v2

Template ID: `youthpolicy-device-undertaking-ofl-v2`; version: `v2`.
This is a new typography edition, not a renamed or certified reproduction of
the proprietary-font v1. Both original v1 files remain unchanged. Legal prose,
prices, table cells and the four editable fields are unchanged; regression tests
compare parsed source and fillable text, markers and page geometry. All text now
uses genuine **Noto Sans SC Regular**. The signature paragraph is right aligned
with no first-line indent so an entered organization name has usable space.

## Reproduce and install

Run from the repository with the sibling MoonLeaf workspace available:

```sh
moon run scripts/build-open-font-undertaking.mbtx -- /absolute/repo
moon run scripts/install-open-contract-fonts.mbtx -- /absolute/repo /absolute/fonttools
```

FontTools must be version `4.60.2`. The installer downloads the official
[Noto CJK source](https://github.com/notofonts/noto-cjk) at commit
`f8d157532fbfaeda587e826d4cd5b21a49186f7c`, verifies the variable TrueType source
and [SIL OFL 1.1 license](https://github.com/notofonts/noto-cjk/blob/f8d157532fbfaeda587e826d4cd5b21a49186f7c/Sans/LICENSE),
then instantiates weight 400 with deterministic timestamps. This is a lawful
static instance retaining its genuine family identity, not a SimHei/FangSong alias.
The installer verifies the resulting bytes before replacing the runtime asset.
Font binaries are ignored by Git; the small license and configuration are tracked.

Set renderer font root to `assets/fonts/open/noto-sans-sc` and font config filename
to that directory's `font-config.json` (absolute paths in deployed containers).
Browser bundle packaging copies the same verified font and license. Install the
font before building the browser bundle; missing or altered bytes fail packaging.
The default build includes only OFL font binaries. Private fonts are never copied
merely because they exist on the build machine. An old output directory containing
private font binaries is rejected; use a fresh output directory for an OFL-only
release. Legacy proprietary-font packaging requires explicit
`LUNANEXA_INCLUDE_PRIVATE_CONTRACT_FONTS=1` and
`LUNANEXA_PRIVATE_FONT_LICENSE_EVIDENCE=/absolute/license-evidence-file`.
That opt-in is an operator attestation of redistribution rights, not an automated
license determination. The evidence file itself is not published to the browser.
The controller catalog selects this version for new undertakings; old packets
retain v1. Registration/object upload must use the exact selected manifest and
must not silently rewrite an existing signed document.

## Validation and limits

Native MoonLeaf renders source and a filled sample to **four pages** with the
exact pinned font, including the full rental table and signature area. Both
outputs were rasterized and all pages visually checked. An independent
LibreOffice render of the DOCX also has four readable pages, but line/page breaks
differ: MoonLeaf keeps paragraphs together. This is not pixel equivalence to Word
or LibreOffice. Raster HMAC evidence proves byte binding, not legal approval.

An isolated Linux Kubernetes integration probe also completed the actual
prepare → MoonLeaf render → finalize → scanned S3 write/readback pipeline and
recovered a deliberately failed first callback. Only the controller plan/callback
endpoint was a fixture. The filled PDF is byte-identical on macOS and Linux:
`sha256:7f47f4fec8dba952bc9dc700e7a5bebb7c42946b2780364c26a3529162740b19`,
10,824,742 bytes, four pages. This is an integration result, not a production
rollout attestation or a real commercial order.

Run the opt-in real-font regression with `MOONLEAF_OFL_TEMPLATE_FONT`,
`MOONLEAF_OFL_TEMPLATE_ROOT` and `MOONLEAF_OFL_OUTPUT` set, then
`moon test --target native --deny-warn cmd/offline-pdf-renderer`.
The legal production deployment still requires its actual worker/dispatcher
configuration, object storage and exact-template acceptance evidence; these
files do not themselves assert that a cluster rollout occurred.
