# Hosted applications and trial media — 2026-10-15

## Supported sites and observed scope

Acceptance used the deployed customer `/user/` portal, management `/mana/`
portal and `/docs/` site at `suanli.kechuangfuwu.com:8443`. No local demo was
used. Browser launch checks used the signed-in customer account. This is not
evidence that every customer account or physical robot has been exercised.

The four PaaS cards show their product logos, ready states and one launch action.
Workspace settings remain collapsed. Switching applications clears incompatible
model and rental-order intent before a new handoff.

| Application | Observed result |
| --- | --- |
| ComfyUI | Isolated editor opens; text-to-video on `.176` and reference-image video on `.177` both complete and display saved videos. |
| MoonDesk | Desktop opens and its code assistant reports running. |
| MoonRobo | Cockpit opens with the existing RoboBook; its scoped model proxy returns HTTP 200 from GLM. Physical operations remain read-only. |
| MoonTown | Interactive town map opens after the optional character setup is skipped. |

## Trial media and reserved inference

ComfyUI inference is restricted to the existing shared H3 providers on trial
machines `.176` and `.177`. The FL2VA and Ref2VA aliases are separate from the
company's reserved GLM service. A hosted ComfyUI profile never falls back to a
reserved GPU delivery, including when a shared provider is unavailable.

Applications run in isolated CPU workspaces on the management workspace host.
The trial GPU nodes retain their existing opaque model-serving runtimes; no
MoonSuite application or application repository was installed on a managed
GPU node. Reserved GLM placement and its model-serving workloads were preserved.

External media providers use a generic native contract: approved artifact,
tenant, node attribution, generation, loopback origin and mounted credential
reference. Readiness requires authenticated health and exact served-model
identity. Jobs reuse durable ownership, bounded admission, reconciliation,
termination and usage settlement. Paid dedicated jobs cannot consume these
shared providers. Private-workspace video usage does not become a payable
GPU reservation or token charge.

Client model policies expose only the approved H3 aliases to ComfyUI and only
GLM to the text applications. Supplemental video-only workspace authority was
bounded by the existing company authority; registration does not synthesize
trial organizations or machine reservations.

## Integration repairs

- Hosted model requests use the controller's authenticated TLS contract.
  The former application route pointed at a legacy model gateway.
- The native adapter handles both URL-encoded text jobs and binary multipart
  reference jobs. It accepts either valid MIME header order and Python's
  neutral boolean sampler defaults. Unsupported effective overrides still fail.
- Qualified reference profiles accept bounded embedded PNG and PCM WAV data;
  arbitrary URLs, host paths, duplicate fields and unknown overrides fail.
- The pinned CPU ComfyUI adapter reuses the existing reviewed Ref2VA silent
  audio-condition support. The bounded transport and cleanup logic are retained.
- Workspace initialization uses atomic POSIX link publication on NFS, preserving
  existing regular files and rejecting symlink targets.
- Existing RoboBook files were copied to the isolated workspace and compared
  byte-for-byte. Originals remain intact. The incorrectly generated GLM video
  template was archived under the workspace's hidden bootstrap directory.
- Temporary migration and inspection Jobs and their network policies were removed.

## Validation

- `moon info`, `moon fmt`, strict native check and `git diff --check` pass.
- Full native runner: 1,820 passed, zero failed, including contract fixtures,
  public-response checks and durable restart/reconciliation tests.
- Customer UI and command packages: 137 JS tests passed with warnings denied.
- Dependency/public-response scan passed; all 30 isolation scan fixtures passed.
- The live customer JavaScript matches the built artifact:
  `5c2d2c5d6f25fa06427f904a6810910b41ba28f5d251cd25f97df2149e6b07de`.
- Four card logos were decoded in the live browser. Successful text and reference
  video outputs were visible in ComfyUI, not merely accepted by HTTP endpoints.
  Reference validation used a frame from the public synthetic text-video check;
  no private customer image was uploaded. Both browser jobs completed their
  bounded transport cleanup, and the separate diagnostic job was deleted.

Production credentials, account snapshots, request payloads and deployment
backups remain private host references and are not included in this evidence.

## Release identities

The customer portal image is `sha256:e2b824c63b2166793597108f1b76ec0bd2ddadf6ce1e579ecf368b1af30f8c20`.
The controller image is `sha256:94335e3f4f7a5acd26816002c90e686f5a03cea54e99fad1745fe76eb967ac7d`.
The ComfyUI model proxy is `sha256:6859204df27c39084ddb8f2044a447eb41a3d8f2eb76aa9b8156e46868f2ed17`.
The pinned CPU ComfyUI image is `sha256:946009509adc8c4390fa7e58d6b64d2b2217c580d8a4cf413e460316717b3bc5`.

The Linux controller build retained release semantics with a private build-only
`-O1` compiler option for the monolithic control executable. This did not change
the repository manifest or runtime configuration. The native C test runner used
the repository's strict runner with an unlimited shell stack and bounded jobs.

## Follow-up authenticated acceptance

The existing customer session was renewed with the existing sign-in reference.
The MaaS status, endpoint copy and model copy were checked in the signed-in
portal. The exact published HTTPS `/user/v1/chat/completions` endpoint returned
complete answers for arithmetic (`323`), Chinese streaming (`早上好`, including
the terminal SSE marker) and structured JSON (`{"sum":42,"ok":true}`). Each
response ended normally with nonempty final content; HTTP 200 alone was not
treated as success. Existing scoped customer authority was reused without
issuing a key. An unauthenticated request remained HTTP 401.

A fresh ComfyUI card launch generated another playable 512×512 reference video.
MoonDesk's actual code assistant answered the arithmetic verification request,
and MoonTown's Guide answered a question about its work/result interface.
MoonTown's character creation remains a separate first-use action.

MoonDesk initially failed its handoff because a legacy client-side manager
co-owned its network policy. The two affected workspace policies were backed
up, adopted by their normal workspace reconciler using resource-version guards,
and checked to preserve their exact rules during adoption. The subsequent
signed-in handoff applied the intended controller route and launched MoonDesk.

MoonRobo's inspection request revealed a retired automatic browser-side call to
an agent gateway on the browser's loopback address. The cockpit now refreshes
MoonRobo-owned evidence after acceptance and removes the retired routine action.
Agent work requires the installed MoonRobo adapter through MoonDesk / MoonFlow;
no replacement agent runtime or physical authority was added to LunaNexa.
The source-aligned native runtime and cockpit were packaged together as
`sha256:987fe39774e2e1fa1318ed1bd0d418931114aff0c2d2123084f9b85a20e4de0a`.
The existing RoboBook was archived privately before the upgrade.

MoonRobo verification: 76 cockpit JS tests and 21 native inspection tests pass.
The native application builds with the current source. Its pre-existing compiler
migration warnings still prevent a warning-free strict MoonRobo UI gate; this
is separate from the successful LunaNexa strict native gate above. The robot
bridge, calibration and named physical-runtime evidence are absent, so physical
operation and unrestricted robot-agent work are not claimed as verified.

A final fresh card launch exposed an additional crash in MoonRobo's older
workspace gateway. Its deployment was privately backed up and its image was
aligned, with a resource-version guard, to the gateway already serving the
other hosted applications:
`sha256:5835a215c580dd795b00092332336f1d8d48e509387f24e22ac5f9c1e90a8eb2`.
Two subsequent authenticated card launches reached the current cockpit and
existing RoboBook. The harmless status inspection was accepted without the
retired external routine call. The gateway remained ready with zero restarts
during these checks. This is a bounded acceptance check, not a long-duration
availability claim.
