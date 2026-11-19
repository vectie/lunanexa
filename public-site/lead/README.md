# /lead exhibition display

Three content-only raster crops from the user-approved collage. No regenerated
text, photography or branding. Blank wall, doors, fire equipment and measurement
labels are excluded. Slide 1 joins two adjacent source crops to remove the
measurement strip; slides 2 and 3 are contiguous crops.

- Source: `/Users/kq/Documents/Codex/2026-11-13/an-z/outputs/02-lively-collage-fullsize-repaired-v3.png`
- Preparation: `scripts/prepare-lead-display.mbtx` (explicit source coordinates).
- Lossless crops: `output/lead-20261114/slide-01.png` through `slide-03.png`.
- Browser assets: local WebP, approximately 3 MiB combined; no CDN or framework.
- Display: 3840 × 2160 verified, object-fit contain, user-requested subtle
  horizontal stretch of 5% (`scaleX(1.05)`), height unchanged, full content visible.
- Controls: arrows, dots, pause/play, fullscreen; keyboard arrows, Space, F.
- Playback order: right → middle → left (slide-03 → slide-02 → slide-01).
- Autoplay: 15 seconds; hidden tabs suspend it; reduced-motion starts paused.

Published 2026-11-14 on management node .173 only. Isolated deployment/service
`lunanexa/nexai-lead-display`, exact `/lead` and prefix `/lead/` IngressRoute,
existing qualified homepage NGINX image pinned by digest. No GPU changes,
homepage replacement, account changes or model dependencies.

Remote immutable release directory and deployment receipt:
`/home/HwHiAiUser/lead-display-20261114-r1/`.
Current content update: `/home/HwHiAiUser/lead-display-20261114-r4/`;
previous releases are retained for rollback.
`manifest.json` records the complete isolated resources. Rollback/removal is
limited to that named IngressRoute, Service and Deployment; preserve source
assets and other platform routes. Do not rerun the publication helper against
existing resources; it intentionally refuses overwriting them.

External: https://suanli.kechuangfuwu.com:8443/lead/

Internal: https://suanli.kechuangfuwu.com/lead/

443 is verified on the management host with host/SNI resolution. External 443
is not reachable from this Mac; external users should use the 8443 address.
The `/lead` redirect uses a relative Location to preserve the active port.
