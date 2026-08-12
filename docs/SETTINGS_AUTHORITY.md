# Settings authority

LunaNexa separates configuration by who owns the decision. A browser
preference must never become cluster policy, and an enterprise request must
never weaken a management-node or node-agent safety boundary.

## The four authorities

| Authority | Stored where | Examples | Can a lease user change it? |
| --- | --- | --- | --- |
| Global administrator | `lunanexa-admin-settings` ConfigMap, mounted read-only into the controller and every node agent | admission capacity, runtime concurrency, retry count, heartbeat/replay windows, retention counts, certificate lifetime, artifact I/O chunk, container PID limit | No |
| Enterprise user | Per request or enterprise workspace record, bounded by the active global generation | model alias, request deadline, maximum output units, workspace quota requests | Yes, within the advertised limit |
| User local | Browser `localStorage` or editor settings on that user's workstation | locale, remembered model, result display length, editor layout/theme | Yes; these values are not stored in the management database and are not sent to a DGX node |
| Fixed safety boundary | Compiled LunaNexa validation | maximum configurable replay window, maximum request/body/event size, maximum configured retention, identifier/path rules, digest and signature requirements | No; not even an administrator can raise it without a reviewed release |

The public MoonBit types and validation live in `settings/`. The API returns
the authority catalog with the effective enterprise-visible limits so both the
enterprise portal and Web IDE can render the same policy without copying
constants.

## Deployment and change control

The administrator edits `deploy/admin-settings.example.json`, increments
`generation`, reviews the change, and updates the `lunanexa-admin-settings`
ConfigMap. The controller and node daemon validate the complete document at
startup and fail closed on unknown schema versions, missing fields, negative
values, or values beyond hard ceilings.

Settings are startup configuration, not a mutable public API. Roll the
controller and all four node agents after changing the ConfigMap. Use one
generation across them; do not run nodes with a different policy document.
The legacy `LUNANEXA_ADMISSION_CAPACITY` and
`LUNANEXA_RUNTIME_CONCURRENCY` variables are accepted only when
`LUNANEXA_ADMIN_SETTINGS_PATH` is absent, for migration of older deployments.

## Read APIs

- `GET /v1/settings/effective` accepts enterprise inference authority or
  operator authority. It returns request budgets, timing information,
  authority descriptors and the global generation. It omits node safety and
  internal scheduling policy.
- `GET /v1/settings/admin` requires operator authority and returns the complete
  active document.
- There is intentionally no settings write endpoint. Cluster policy changes
  use reviewed deployment configuration and a controlled rollout.

Clients resolve `UserRequestPreferences` through `resolve_user_request` before
submission. Values above the global maximum are rejected rather than silently
expanded. `UserLocalPreferences` has a separate validator and is never part of
the controller snapshot, PostgreSQL schema, assignment, heartbeat, or lease.

## Important ownership examples

- A user may request a shorter deadline; the administrator defines the maximum
  and default.
- A user may choose a model alias they are entitled to; the administrator owns
  catalog approval, node assignment and model transfer policy.
- A user may change language and output display truncation locally; neither
  affects inference output limits or billing records.
- The administrator may lower request and telemetry bounds but cannot raise
  them above compiled safety ceilings.
- Lease start/end and early termination cleanup are state-machine decisions,
  not user-local settings. A user may request termination; the management plane
  and node helper own revocation, sanitization and quarantine evidence.

## Verification checklist

1. Confirm the same ConfigMap generation is mounted in the controller and all
   node pods.
2. Call `/v1/settings/admin` as the operator and compare its generation with
   the reviewed deployment artifact.
3. Call `/v1/settings/effective` as an enterprise user and confirm internal
   node/telemetry policy is absent.
4. Submit a request at the advertised limit, then one unit above it; the latter
   must be rejected.
5. Corrupt a copy of the settings document or exceed a hard ceiling; startup
   must fail before the listener or reconciliation loop begins.
