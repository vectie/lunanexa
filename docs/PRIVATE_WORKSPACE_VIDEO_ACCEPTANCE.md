# Private workspace video acceptance — 2026-09-15

This record proves a bounded private-cloud workflow, not production launch,
Spark compatibility, actual model inference or commercial-provider acceptance.

## Observed end-to-end path

An administrator-authorized disposable account launched its isolated ComfyUI
workspace without a rental contract. Kubernetes created the workspace in the
management namespace, with a persistent per-user/project volume. Managed model
execution remained on the separately enrolled compute node with truthful RTX
inventory; no Spark hardware identity was fabricated.

The browser's saved `PrivateBrowserAcceptance-20260915` workflow was restored
after workspace replacement. Its stored SHA256 remained
`f712b4265757843ab974d1a901169800e7f6909d4ead55c5157813ea19a6aa38`.

Clicking Run completed this actual path:

`ComfyUI → pod-local model proxy → configured provider gateway → LunaNexa → Kubernetes TEST ONLY video provider`.

The browser displayed a two-second video visibly marked `TEST ONLY / NO GPU
MODEL`. ComfyUI saved `video/LunaNexa_00001_.mp4` (14,093 bytes), including its
workflow metadata. After reopening the browser, the asset remained available.
The asset-panel Download action produced a local file whose SHA256 exactly
matched the workspace file:
`72b478e30d4c080282e949a6dac29b195bdbba7f8cd1f0e358c5cfb4f2f76782`.
This differs intentionally from the raw provider fixture because SaveVideo
writes the final file with metadata.

The browser job was
`video-53ea458533a0a9faf386eaa51dfd14438a67b80f0c009cd59e0b701ca85ad841`.
The commercial snapshot contained one `private-workspace-video-job` observation
for it, quantity 1, with no payable ledger entry. The bounded operator pending
media-job endpoint returned an empty, non-truncated list afterward.

After the durable-list fix, a second actual browser run created
`video/LunaNexa_00002_.mp4` (14,045 bytes). It appeared beside the old output
without a page refresh; the active-job count returned to zero. The native video
element reported duration 2 seconds, ready state 4, advancing playback time and
no media error. The downloaded file matched SHA256
`8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.
Job `video-8aea5332b3bb6419f09e0b540de260ca62dd89d0ce0a73cd9ec6c9f1a1e6896c`
had one private-workspace job-meter observation, quantity 1.

The modified workflow was saved through the UI (unsaved marker cleared). Its
new intentional SHA256 was
`0b3461688811b3abf5f6b9ba40c1d8d31b8685432c15416ab251ead9b299cee5`.
A further container replacement retained that workflow and both output hashes;
the SQLite seeder recognized both existing indexed assets without duplicates.
The real browser reopened the saved prompt with no unsaved marker and listed
both videos after this final replacement.

## Security and recovery checks

- Fresh private handoff: connect 204, authenticated page 200, WebSocket 101.
- Explicit revocation closed an established socket with policy code 1008 in
  4,987 ms; later HTTP and WebSocket attempts returned 401.
- Cross-site WebSocket request: 403. Forged session cookie: 401.
- Regression tests distinguish authorization outage from explicit denial:
  requests fail closed with 503, existing sockets close, but unexpired sessions
  and running workspace resources are preserved. After authority recovery the
  same cookie reconnects. Local expiry still denies access during an outage.
- Text-only multipart forms are normalized into the provider JSON contract;
  duplicate fields, file parts, ambiguous framing and excessive bodies fail
  closed. Controller profile/allowlist checks remain authoritative.

Local bridge/host/provider tests passed 20/20, targeted native checks passed,
and staged Linux bridge/host tests passed 15/15. Native interfaces were
regenerated. The acceptance gateway image is
`sha256:6704cb19c9aec356f233f2ecda9c4f88e4c50bfc4d36697c6efb12ce5cfe40f7`;
the unchanged pod-local proxy uses
`sha256:60facfe1c2703c676834b697a6038a0f169c858e17acf44a35b93bd609046048`.
These are binary overlays on an existing acceptance image, not a production image
security qualification. No model weights were packaged.

## Failures found and remaining limits

- The old boolean authorization probe treated transport failure as revocation,
  clearing sessions and scaling workspaces down. This is now distinguished and
  covered by regression tests; live outage injection remains a separate check.
- A text multipart form passed the old local model-name check but could not be
  consumed by the downstream JSON/form contract. The local adapter now
  normalizes that supported text-only input; file/reference profiles remain
  separately qualified work.
- The cluster-to-gateway acceptance reverse SSH tunnel had exited. Its missing
  loopback listener was verified and restored before the successful browser
  run. The SSH tunnel remains a lab dependency, not production availability.
- Opening the embedded browser's native video overflow menu crashed its page.
  A fresh page recovered the workflow and the ComfyUI asset-panel download
  passed. The native menu crash is not considered resolved.
- Container replacement initially retained both files with exactly the hashes
  above, but the output panel became empty. Enabling the SQLite-backed asset
  seeder alone did not fix the community frontend's transient-history binding.
  The pinned frontend adapter in `images/COMFYUI_ASSETS.md`, plus the authenticated
  read-only asset-list gateway route, restored the visible output after replacement.
  At 21:09 CST the browser downloaded `video_LunaNexa_00001_.mp4` (14,093 bytes)
  with exactly the original output SHA256 above. Unauthenticated asset listing
  returned 401. Administrative asset mutations remain denied.
  ComfyUI acceptance image:
  `sha256:c0c4a38d2c169e6b55f4dd844ee4033c46ce3d960a6159d7b413ad65b617d74b`.
  The patch verifies the exact original bundle hash and JavaScript syntax;
  attempting to apply it again was rejected without a second mutation.
- Initial frontend loading remained slow and logged a graph-initialization
  warning. Responsive/accessibility acceptance and the simplified administrator
  resource-selection UI are not proved by this record.
- Real Spark ARM64/CUDA/SM121, models, quality/performance/memory and dual-node
  tests remain pending. So do the full non-model failure campaign and repository
  release gate; targeted green tests do not waive those requirements. The full
  local `moon check --target native --deny-warn` was attempted and failed with
  95 errors, including the existing MoonLeaf `strconv.from_str` incompatibility
  and warning-92 failures in other packages. The scoped checks do not claim to
  resolve those repository-wide failures.
