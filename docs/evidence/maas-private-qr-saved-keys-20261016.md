# MaaS private QR and saved API keys — 2026-10-16

Acceptance target: `https://suanli.kechuangfuwu.com:8443/user/` and `/docs/`.
Verified as guojiaan in the signed-in customer portal. No demo was used.

## Observed customer behavior

- Existing active keys are masked as `********`, with eye and copy icons.
- Revealing, hiding, reloading the entire page, and revealing again returned
  the same actual `lnx_…` secret. The secret was withheld from tool output.
- Copy completed with the success toast. The automation clipboard cannot
  provide OS clipboard readback; transport and clipboard binding are also
  covered by the portal tests.
- Revoked and expired records have disabled reveal/copy controls. Active keys
  appear first, newest first, ahead of archived records.
- MaaS → Connection QR opens a key selector. Selecting an active key shows
  its QR directly in that dialog. There is no password input, paste field,
  docs redirect, or extra create-key action in this flow.
- The descriptor is versioned `openai.connection.v1`, containing the HTTPS
  base URL, Chat Completions format, model, actual secret and recommended
  output budget. Closing clears the private dialog state.
- A synthetic QR image rendered by live MaaS was decoded by live MoonDesk
  into the correct URL, `glm-5.3.flash`, output `16384`, and a masked key.
- An authorized small request using the existing real key returned HTTP 200,
  assistant text `OK`, and `finish_reason=stop`.
- Live bilingual documentation describes repeat reveal/copy and the short
  QR flow, with the correct URL, model, TRAE settings and copyable examples.
  It has no `qr-entry` link or credential-bearing QR asset.

## Authorization and persistence

`POST /v1/portal/self/api-keys/{key_id}:secret` uses the existing authenticated
subject and active selected organization. Only a matching owner and tenant can
retrieve an unexpired, unrevoked credential. Recreated values must match the
durable digest. Ordinary lists and snapshots contain no raw secret. The HTTP
transport sends `Cache-Control: no-store`. Stale UI replies are fenced by
session and request generations; navigation, organization changes and closing
the view clear revealed values. Tests cover restart, wrong tenant/subject,
expiry, revocation and a changed issuer secret.

## Validation

- Strict native check passed; complete native runner: **1829/1829**.
- Strict customer portal JS check and tests: **141/141**.
- Bilingual docs and gateway tests: **52/52**.
- Release dependency, contract, image, secret and response scans passed.
- Production fault simulation passed, including process recovery and
  four-node disruption. These are simulation results, not live fault injection.
- Browser bundle source/build/HTML digest verification passed.

## Immutable live release

- Customer portal image: `sha256:30f0ae3631e5d389f7ac25a6fbede34e3653f014ea0ec197807e06faf1cf721c`.
- Customer JS: `cb9c0b4ec5beb812a20679d5bd38376c2d8767a1a03b77764ab217a79239953e`.
- Docs image: `sha256:08c12840651c6f8daeaafe793410c54f4fe294859183835d97df311cac07b1bc`.
- Controller image: `sha256:01a5af039fe585210b5299dbe37daefbc677a119c0eefba75b5a1d0ea459e116`.

Only reviewed containers were changed, using image/resource-version guards.
Private rollback snapshots remain on the management host. No secret or private
QR is included in this evidence.
