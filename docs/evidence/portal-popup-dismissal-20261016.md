# Portal popup dismissal — 2026-10-16

Verified on the signed-in live `/user/` site as guojiaan.

- Clicking the backdrop closes the connection QR popup and restores focus to
  its trigger. Clicking its heading keeps the popup open.
- Escape and the visible header Close button both dismiss the popup.
- Selecting an existing key still displays the private connection QR directly.
  Clicking outside clears it; reopening shows the empty key selector.
- Closing invalidates an in-flight secret request, preventing late replies from
  filling a reopened dialog. The unit test checks request and generation state.
- The shared dismissal handler uses the existing cancel controls for API key
  creation, revocation and secret dialogs, respecting their disabled state.
- UI and shell regression tests: **142/142 passed**. The handler test covers
  outside click, inside click, Escape, focus restoration and disabled controls.
- Strict native check and browser source/bundle/HTML verification passed.

Published customer portal image:
`sha256:8a5f6e2597014fefbb69d69aae45565c3f2c6452d3bcf3c5d884058db57f5bd7`.
Customer JS:
`4fc0a5825ab2086ab8c489e4d35d8a73c27287e716451f9635fc97aee8b57a24`.

The rollout tested the prior image and resource version before changing the
customer container. Private rollback material remains on the management host.
No credential or credential-bearing QR screenshot is included here.
