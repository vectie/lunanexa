# Enterprise contract UI acceptance — 2026-09-22

Technical test only. This record does not assert a signed legal agreement,
payment, invoice, business approval, or delivery of commercial capacity.
The platform owner separately waived those real-world steps for offline testing.

## Code and release

- Fixed contract generation status refresh: a selected `GenerationRequested`
  packet is refreshed at two-second intervals, up to 150 attempts. Each GET has
  a ten-second abort deadline. A terminal state, missing packet, failed request,
  or exhausted attempt budget stops the loop. Navigation, organization changes,
  logout, and packet selection fence stale results. Background updates retain
  local draft values and selected form. Duplicate generation is rejected while
  submitting or already generating.
- Replaced implicit public derive-method promotion in `ui/enterprise` with
  explicit public extensions. No warning was disabled.
- Fixed release packaging of stale standalone JavaScript after enabling
  `moon.work`: browser builds now use a dedicated output directory and select
  the workspace-qualified or standalone path explicitly, never by stale-file
  presence. The verification script checks all four emitted assets against the
  copied bytes and their HTML cache-busting SHA-256 references.
- Fixed verified downloads over the approved outer HTTP website: the existing
  MoonBit SHA-256 implementation now checks bytes instead of assuming
  secure-context-only `crypto.subtle`. Integrity checking was not removed.

Release `web-v5` enterprise JavaScript SHA-256:
`bd680d3a3881f3604c4acbd789d05b0915b7ea593705be9c402e92713b0f8d8d`.
This exact asset was checked through the public identity edge at
`http://106.39.18.146:5003/enterprise/`.

## Automated regression

`moon test cmd/enterprise ui/enterprise --target js --deny-warn`
with an isolated target directory: **70 passed, 0 failed**.

Coverage added: generated/failed/timeout/error results; stale navigation,
organization, logout and selection results; draft preservation; duplicate
generation rejection; empty/`abc` SHA-256 known vectors; the actual JavaScript
`Uint8Array` → MoonBit `Bytes` digest callback representation.

`moon info --target js`, `moon fmt`, and scoped `git diff --check` completed.
Unrelated existing console FFI and installer import warnings were not hidden.
Workspace and standalone path selection are regression-asserted; this record
does not claim a separate full standalone-module build.

## Actual browser observations

Using the existing temporary OIDC technical-acceptance account and organization,
without creating another order or packet:

1. Opened the public enterprise portal, selected the technical organization,
   and opened **Contract forms**.
2. Observed the existing packet at **DOCX and PDF generated**, **Revision 6**,
   correctly identified as **Attachment 2 · equipment undertaking**, with the
   open-font edition selected and its real generation event timeline visible.
3. Clicked **Download verified PDF**. The page reported **Verified document
   downloaded** for the PDF artifact, which occurs only after the browser's
   size/digest checks and download trigger succeed.
4. Clicked **Download verified DOCX** and observed the equivalent verified DOCX
   completion message. No legal submission, payment or approval was performed.

The renderer/dispatcher production records separately prove that both generated
documents contain four pages. Browser generation polling itself was tested by
the state-machine regressions above, not by creating a second live order or by
pretending this already-generated packet was newly generated in the browser.

## Live preview recheck — passed

The same real browser exposed a backend preview bug: viewing a `Generated`
packet sent unchanged role-scoped field values, and the backend incorrectly
treated those as an edit to a read-only record. The renderer agent fixed and
tested exact-no-op previews while still rejecting actual edits.

After controller `v4` became Ready, the same real browser session was reloaded
and **Contract forms** reopened without changing fields or regenerating the
packet. The page changed from **Updating preview…** to **Preview is
synchronized**, reported **4 physical pages**, and exposed **Contract page 1 of
4** through **Contract page 4 of 4**. The earlier HTTP 400 message was absent.
Visual inspection confirmed Chinese body text on the first page and, after
scrolling the embedded preview to the final page, the unchanged technical-test
organization and date alongside the unsigned signature/stamp placeholder.
The captured browser error log contained no entries. No approval/submit or
regeneration button was clicked. This is actual live preview evidence, separate
from the earlier successful DOCX/PDF downloads.

## Traditional-contract boundary

The flag `traditional_contract_route_available = false` predates this frontend
finish: `git blame HEAD` attributes it to commit `8019f6db` on 2026-09-22.
It is not a new removal of bilateral-contract delivery in this change. The
existing creation menu retains a disabled **Traditional rental contract ·
bilateral execution (temporarily unavailable)** entry. Existing packets remain
in the packet selector and resolve manifests by their immutable template ID;
this frontend change does not delete or rewrite them.

The deployed approval scope in `offline-ofl-v2-20260922/operator-approval.md`
covers only the exact Chinese OFL undertaking v2 and technical quote v1 bytes.
It explicitly excludes legacy proprietary-font templates. Neither the UI flag
nor the passing OFL production renderer tests establish approved fonts,
rendering, or rollout of the original traditional-contract templates. This
release therefore does **not** claim the traditional bilateral-contract entry
is fully live. Re-enabling it requires a separately approved template/font
scope and corresponding rendering/browser acceptance, not merely flipping the
menu flag.
