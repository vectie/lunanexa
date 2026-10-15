# Live application cards — 2026-10-15

This records the initial card release. The later hosted application and shared
trial-provider rollout is recorded in [Hosted applications and trial media](hosted-apps-trial-media-20261015.md).

The supported `/user/` PaaS page now presents four cards, in order:
ComfyUI, MoonDesk, MoonRobo and MoonTown. Each card uses its product logo,
an availability state and one primary action. Static logos are bundled with
the customer portal; they introduce no application code dependency.

Ready application cards reuse the existing authorized one-click handoff.
ComfyUI opens its GPU workspace setup unless an authorized, unexpired delivery
is already ready. Missing launch profiles stay visible and unavailable rather
than acquiring a fabricated configuration. The live MoonRobo profile is not
configured, so its card is disabled. This release does not grant new access or
deploy a robot runtime. Workspace settings are collapsed for a ready app and
open for a selected app that needs setup.

Validation:

- Strict native check and full native runner: 1,813 tests passed, zero failed.
- Customer UI and command packages: 134 JS tests passed with `--deny-warn`.
- Live portal: exactly four cards; all four SVG images decoded successfully.
- ComfyUI configuration selects the app and opens the relevant setup panel
  without starting a workload.
- At 390px, all four cards stack in one column without document overflow.
  The browser's default viewport was restored afterward.
- The temporary GLM key approved during this task was created, copied and
  revoked. Detailed API-test limits and the corrected example budget are in
  `rental-glm-ux-20261015.md`.

Final customer image:
`sha256:42ba1f2e14d126edb5a8eeaf76c0f89210fa6bdb436c18d791d59ef91bdafb9c`.

Public JavaScript matches the built artifact:
`6252dc7fa7620b6a40e9076e8fc9f4b5a3a44f2ba4148a45e30d297027f84e50`.
The management portal and controller images were not changed by this release.
