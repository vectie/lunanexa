# LunaNexa coursebook site

This is a separate, source-grounded documentation site generated with
MoonBook's `wiki-course` repository-coursebook skill and reusable site asset.
It opens with 24 bilingual classroom lessons: LLMs, harnesses and agents,
learning and feedback, infrastructure, real work, and industry. **Start presentation** opens 46 content
slides, a break and questions, with a 120-minute speaking plan. It begins
directly with text inputs and outputs. Each screen separates its animated
figure and conclusion from expandable speaker notes. Animations support play,
pause, steps and restart; playback finishes the current step and holds its
explanation until the learner advances. Future objects stay hidden. Arrow keys navigate, Space
advances the figure, and Escape returns to the book. A 25-minute route remains
in technical notes.
The introduction omits engineering hardening and repeated workbook templates
at the user's explicit request.
The user's seven source photographs now form the main curriculum: all 186
identifiable entries are integrated as 47 sections within normal chapters and
linked to the main presentation. Their explanations occupy 78 of 105 content
minutes; supporting examples occupy 27. No separate board route remains.
Numerical SVG controls include neurons, probability loss, rewards, scaling,
expert routing and quantization. Model/harness comparison is a regular chapter.
All 48 presentation screens also have a complete Chinese speaking manuscript,
including the break and discussion. The **讲稿** panel separates spoken prose
from directions and provides a button for each of the 149 animation stages;
that button restores the example's initial values before showing the stage.
The **逐页讲稿** link opens `ai-speaker-script.html`, with a 48-item directory,
print layout and an editable Markdown download. English teaching notes remain
available; the complete new manuscript is Chinese. Sources live in
`docs/ai-speaking/`; `scripts/build-ai-speaker.mbtx` runs as the final build
step. Timing is estimated at 220 Chinese characters/minute, with separate
allowances for controls, observation and questions, rather than an audience trial.
Read `docs/AI_WHITEBOARD_COVERAGE_20261114.md` for the point-by-point crosswalk
and explicitly unresolved handwriting. Build with `moon run
scripts/build-ai-whiteboard.mbtx`, then run `scripts/sync-ai-coursebook.mbtx`
with the actual review timestamp. Original photos stay local and are not shipped.
The remaining 41 pages teach LunaNexa's features, architecture, data flows,
use, operation, and debugging. The repository documents and typed
contracts referenced by `coursebook-evidence.json` remain authoritative.

The Operations section also publishes a 50-scenario production UI validation
page. Its atomic source ledger is
`docs/UI_PRODUCTION_VALIDATION_50_SCENARIOS.md`; demo-scoped checks and blocked
external dependencies remain visibly distinct from real production evidence.

The published default begins with the AI landscape, followed by platform overview, quickstart, concepts,
deployment, operations, troubleshooting, and public reference. Implementation
status, readiness judgment, repository revision, source provenance, and the
generation process appear only after the reader explicitly selects **Show
technical notes** or follows a direct advanced-page link. This is progressive
disclosure, not a security boundary.

The advanced **P0/P1/P2 expansion and offering launch plan** explains why a
deployable four-node repository is not yet the same as a managed-inference or
dedicated-workspace product. It publishes separate physical and external gates,
code-size ranges, and the recommended order from internal pilot to focused
private-cloud capabilities.

The normal **Operations** navigation begins with one bilingual daily runbook
for both sides of the platform. It explains durable operator alerts and tenant
notifications, the event/metric/typed-trigger model, hybrid offline commercial
reconciliation, exclusive-machine access through termination and sanitization,
and the role-safe public/admin guide boundary. Its copyable recipes are
read-only by default, and its prerequisite table keeps external identity,
delivery, observability, document, finance, SSH, and diagnostics dependencies
explicit without exposing implementation process or release judgment.

English is the canonical content in `coursebook.json`; the complete Simplified
Chinese overlay lives in `coursebook.zh-CN.json`. The native language selector
uses the same `lunanexa.locale` browser preference as the console and
workbench. It translates explanations and labels while preserving commands,
paths, protocol IDs, model names, and other copy-sensitive technical values.
Real product screenshots live below `images/` and state exactly which live UI
condition was captured.

The 2026-11-10 platform content review covers the original 41 pages and both
language projections. The [AI foundations guide](../docs/AI_FOUNDATIONS.md)
records the classroom rewrite, narrative examples and primary references.
The combined coursebook contains 66 pages in both languages: 24 AI chapters,
a searchable course directory, and 41 platform pages. Open
`?page=ai-course-map` for all 60 concepts grouped by topic. Each
entry links to its explanation and exact presentation slide; related concepts
can share one worked scene. The same directory
is available inside the classroom. Search matches Chinese and English names
and related concepts without an external service.
The exact inspected revision, dirty snapshot, per-page review coverage and
source digests are in `coursebook-evidence.json`; do not maintain another
revision or current-health assertion here. See the
[content audit](../docs/COURSEBOOK_CONTENT_AUDIT_20261110.md) for corrections,
command prerequisites and the remaining independent acceptance work.

## Validate

`docs/ai-integrated-course.json` owns the chapter sequence, primary-section
placement and time budgets. `docs/ai-integrated-teaching.json` owns the new
worked questions and all 46 causal transitions. `scripts/integrate-ai-course.mbtx`
combines the seven detailed sources with selected supporting artwork from
`scripts/build-ai-lecture.mbtx`, `docs/ai-class-storyboard.json` and
`docs/ai-class-rehearsal.json`. Those older sources and dated walkthroughs
document the supporting artwork's origin; their 43-page totals are historical.
Speaker notes follow the current diagram stage, with primary explanations
expanded in the teacher's panel. Each scene includes three answered student
questions and a budget that includes demonstration and processing time.
This remains a teaching plan, not a measured audience trial. Regenerate the
complete deck and book projection
from the repository root, using the actual content-review time:

```sh
moon run scripts/build-ai-whiteboard.mbtx
moon run scripts/sync-ai-coursebook.mbtx -- REVIEW_TIME_RFC3339
```

The projection retains existing platform pages and localizations. No model
connection is needed for the prepared classroom animations. Original technical
art and calculated teaching experiments live in `lecture-studio.js`, loaded
before `lecture.js`; presentation styling is in `lecture-studio.css`.
The [design research](../docs/AI_TEACHING_DESIGN_REFERENCES_20261110.md) records
the public lectures inspected and the specific design choices derived from them.

```sh
node --check docs-site/app.js
node --check docs-site/server.mjs
node --test docs-site/coursebook.test.mjs
moon run scripts/audit-coursebook.mbtx /ABSOLUTE/REPOSITORY drift
moon run scripts/audit-coursebook.mbtx /ABSOLUTE/REPOSITORY recipes
```

The test verifies the coursebook, localization and evidence contracts,
navigation, supported block shapes, real screenshot files, source existence
and digests, secret/placeholder scans, pet request boundaries, and citation
validation.

## Static preview

The documentation remains fully usable without MoonClaw:

```sh
python3 -m http.server 4390 --bind 127.0.0.1 --directory docs-site
```

Open `http://127.0.0.1:4390/`. Search, navigation, code copy, mobile layout, and
print output work. Advanced mode additionally exposes source disclosure and
technical notes. The **Ask guide** panel reports an offline state because a
plain static server has no same-origin agent adapter.

## Preview with the MoonClaw guide

Start a MoonClaw Gateway separately with an approved model route, then run:

```sh
PET_KNOWLEDGE_ROOT="$(mktemp -d "$PWD/docs-site/.pet-knowledge.XXXXXX")"
cp docs-site/coursebook.json docs-site/coursebook-evidence.json \
  "$PET_KNOWLEDGE_ROOT/"
COURSEBOOK_SITE_ROOT="$PWD/docs-site" \
COURSEBOOK_KNOWLEDGE_ROOT="$PET_KNOWLEDGE_ROOT" \
COURSEBOOK_ENABLE_PET=1 \
MOONCLAW_GATEWAY_URL=http://127.0.0.1:18123 \
MOONCLAW_MODEL=default \
COURSEBOOK_PORT=4390 \
node docs-site/server.mjs
```

The adapter binds loopback by default. The pet is explicit opt-in and refuses
to start against the whole site root: its Cowork workspace must contain exactly
the two copied public JSON files. It sends MoonClaw only the published
structured coursebook and public evidence projection. Before each request it
selects at most six question-relevant pages under a 48,000-byte context budget,
then asks the existing read-only Cowork agent for one typed answer, validates
citations against that selected public context, and removes internal metadata.
It cannot mutate LunaNexa or run an operator command.

## Administrator guide diagnostics

`admin.html` is a separate, role-protected troubleshooting surface. It is not
an expanded pet prompt and it does not give MoonClaw live-cluster access. The
same-origin server makes five fixed `GET` requests through an approved internal
HTTPS controller route: health, operator alerts, node summaries, exclusive
lease summaries, and the recovery plan. It then discards the upstream payloads
and returns only allowlisted aggregate state counts, active alert codes,
reconciliation count, component health, coursebook knowledge revision, index
age, and the enabled guide skill names and versions.

The skill inventory is versioned in the server-only `guide-skills.json`. Every
entry declares audience, required evidence, allowed tools, allowed data, and a
published bilingual runbook page. A missing dependency is shown as missing or
degraded; it is never reconstructed from stale coursebook text. Node IDs,
subjects, lease IDs, credentials, alert parameters, raw logs, prompts, model
answers, source paths, and chain-of-thought are not fields in the administrator
response contract.

The endpoint is `GET /api/coursebook/admin/diagnostics?category=overview` and
is disabled unless all of these are configured:

| Variable | Purpose |
| --- | --- |
| `COURSEBOOK_ENABLE_ADMIN_DIAGNOSTICS=1` | Explicitly enables the read-only adapter |
| `LUNANEXA_CONTROLLER_URL` | Exact internal HTTPS origin; paths and queries are rejected |
| `COURSEBOOK_ALLOW_HTTPS_CONTROLLER=1` | Explicit production HTTPS opt-in |
| `LUNANEXA_GUIDE_DIAGNOSTICS_TOKEN` | Server-side read-only credential scoped to `/v1/guide-diagnostics/aggregate`; never use an operator bearer |
| `COURSEBOOK_ADMIN_AUTH_KEY` | At least 32-byte HMAC key shared only with the trusted identity proxy |
| `COURSEBOOK_ADMIN_AUTH_MAX_SKEW_MS` | Optional signed-header replay window; default 60 seconds |
| `COURSEBOOK_KNOWLEDGE_MAX_AGE_MS` | Optional stale-index threshold; default seven days |

The trusted identity proxy removes caller-supplied identity headers and signs
`METHOD + "\\n" + PATH + "\\n" + ACTOR + "\\n" + ROLE + "\\n" + TIMESTAMP`
with HMAC-SHA-256. It forwards `X-LunaNexa-Actor`, `X-LunaNexa-Role`,
`X-LunaNexa-Auth-Timestamp`, `X-LunaNexa-Auth-Signature`, and an optional
bounded correlation receipt. Only `operator` and `administrator` roles pass.
The browser never receives either HMAC key or controller token.

Every allowed, denied, or failed administrator request writes one bounded JSON
audit event to stdout. It contains a hashed actor reference, role, typed query
category, knowledge revision when available, outcome, latency and correlation
receipt. It never logs the user's question because the diagnostics endpoint
does not accept one. In-memory outcome counters are returned only inside the
authenticated aggregate projection; deployment log/metric collectors remain
the durable evidence destination.

The public `/health` contract exposes only the optional category-level boolean
`dependencies.admin_diagnostics`. It becomes unhealthy when the signed adapter
is misconfigured, its skill manifest is invalid, the knowledge index is stale,
or the fixed controller health route is unavailable. It never exposes the
controller origin, failure body, skill details, alert data, or credentials.

For local contract testing, keep the controller on loopback. A real deployment
requires the identity proxy, internal HTTPS diagnostics route, secret
references, and network policy shown in `deploy/docs-site.yaml`. If any of
those prerequisites is absent, keep administrator diagnostics disabled; the
public coursebook and bounded public pet continue to work.

## Production shape

For a separate production docs origin:

1. build and sign an immutable image containing only this directory and the
   reviewed runtime needed for `server.mjs`;
2. put it behind authenticated HTTPS and set a strict host allowlist;
3. keep the MoonClaw Gateway on an internal route unavailable to browsers;
4. pass its credential, if required, from the secret provider;
5. allow egress only to the selected MoonClaw Gateway and DNS;
6. expose `/health` for readiness; the endpoint reports the coursebook as the
   required dependency and the assistant as optional;
7. retain `Content-Security-Policy`, `no-store` agent responses, request limits,
   timeouts, and concurrency bounds;
8. serve the site even when the optional assistant is unhealthy.

Remote binding is rejected unless `COURSEBOOK_ALLOW_REMOTE_BIND=1` is explicit.
An HTTPS MoonClaw endpoint additionally requires
`COURSEBOOK_ALLOW_HTTPS_GATEWAY=1`. Configure
`COURSEBOOK_ALLOWED_HOSTS=docs.example.com` to fail closed on unexpected Host
headers. TLS termination and authentication belong to the ingress or service
mesh, not this small adapter.

### Build the immutable image

The image has no package-install step or runtime dependency beyond Node. Build
from this directory and require a reviewed, digest-pinned Node 22 base image:

```sh
docker build \
  --build-arg 'NODE_BASE_IMAGE=node:22-alpine@sha256:REVIEWED_BASE_DIGEST' \
  -f docs-site/Containerfile \
  -t registry.example/lunanexa-coursebook:REVISION \
  docs-site
```

Scan and sign the result, push it, and resolve its multi-platform manifest to a
complete SHA-256 digest. Never render a floating image tag into Kubernetes.

### Render the Kubernetes template

Copy `deploy/docs-site.yaml` outside Git and replace every placeholder. Required
values are:

| Placeholder | Meaning |
| --- | --- |
| `DOCS_NAMESPACE` | Separate namespace, for example `lunanexa-docs` |
| `DOCS_HOST` | Authenticated HTTPS hostname |
| `COURSEBOOK_IMAGE_REPOSITORY` | Approved private image repository |
| `COURSEBOOK_IMAGE_DIGEST` | Complete `sha256:` digest |
| `INGRESS_NAMESPACE` | Trusted ingress-nginx namespace |
| `DOCS_TLS_SECRET` | Server TLS secret in the docs namespace |
| `DOCS_CLIENT_CA_SECRET` | Client CA secret for ingress mTLS |
| `MOONCLAW_NAMESPACE` | Namespace containing the approved MoonClaw Gateway |
| `MOONCLAW_GATEWAY_URL` | Internal HTTPS gateway origin with no path or query |
| `MOONCLAW_MODEL` | Approved bounded documentation model route |
| `MOONCLAW_GATEWAY_SECRET` | Optional secret containing key `token` |
| `COURSEBOOK_IDENTITY_AUTH_URL` | Trusted ingress auth endpoint that returns freshly signed operator headers |
| `COURSEBOOK_ADMIN_AUTH_SECRET` | Docs-namespace secret containing key `hmac-key`, shared with the identity proxy |
| `COURSEBOOK_CONTROLLER_AUTH_SECRET` | Docs-namespace secret containing only the least-privilege `guide-diagnostics-token` key; never mount the controller operator token |
| `LUNANEXA_DIAGNOSTICS_NAMESPACE` | Namespace of the approved HTTPS diagnostics gateway |
| `LUNANEXA_DIAGNOSTICS_URL` | Exact internal HTTPS origin for that gateway, with no path or query |

The manifest pins the pod to a management-labelled node, runs non-root with a
read-only filesystem, denies privilege escalation, uses default-deny networking,
accepts traffic only from the ingress namespace, and allows egress only to DNS
and the HTTPS MoonClaw Gateway. Ingress requires TLS plus a verified client
certificate. If MoonClaw is unavailable, `/health` remains ready as long as the
coursebook itself is valid; the page shows the guide as offline.

The identity auth service must remove browser-supplied `X-LunaNexa-*` headers
before returning its signed values. The HMAC secret at that service must match
the docs-namespace `COURSEBOOK_ADMIN_AUTH_SECRET`. The diagnostics gateway may
expose only controller `/health` and the fixed aggregate diagnostics endpoint
used by this adapter; it must reject
redirects, mutations, arbitrary paths and caller-supplied controller headers.

After rendering, this must print nothing:

```sh
rg '\$\{[A-Z0-9_]+\}' RENDERED_DOCS_SITE.yaml
```

Then apply and observe:

```sh
kubectl apply -f RENDERED_DOCS_SITE.yaml
kubectl -n DOCS_NAMESPACE rollout status deployment/lunanexa-coursebook --timeout=5m
kubectl -n DOCS_NAMESPACE get deployment,pod,service,ingress,networkpolicy
kubectl -n DOCS_NAMESPACE logs deployment/lunanexa-coursebook --tail=100
```

Kubernetes readiness uses `/ready`. When administrator diagnostics are enabled,
that endpoint requires both controller `/health` and a successful authenticated
aggregate response with `health: "healthy"`. `/health` remains a liveness and
coursebook availability signal and does not claim the protected adapter works.

## Refresh workflow

### Reader-guide action contracts

Current reader guides are documented journeys, not live deployment acceptance.
Every page has an explicit action-bearing, conceptual-only or historical-evidence
classification in `coursebook-actions.json`. Named buttons and navigation actions
carry exact English/Chinese labels, owning source, catalog enum and actual event
or route binding. The Node suite verifies these connections and published prose;
new pages require classification. Keep this manifest synchronized when renaming
actions. Lifecycle/API verbs are not automatically UI buttons. Historical
`ui-end-to-end-sop` and `production-ui-validation` remain separately dated evidence
records, explicitly excluded from current-action assertions. Do not turn
contract-document renewal into a machine-renewal button.

After changes, run `node --test docs-site/*.test.mjs`. Source assertions cannot
prove accessibility: deployed desktop and narrow-screen scrolling, long text,
keyboard-only operation, modal focus entry/return, and downloads remain manual
release checks. Record unobserved cases as pending; never mark them passed from
markup or these Node tests alone.

Use the MoonBook skill against the LunaNexa repository:

1. re-read repository instructions and authoritative product/architecture,
   implementation, operations, security, recovery, and deployment sources;
2. recompute source digests and record revision plus dirty state;
3. revise claim status without upgrading simulated/documented evidence to
   implemented or production-ready;
4. update `coursebook.json` and `coursebook-evidence.json`;
5. run the test and inspect English/Chinese desktop plus 390 px layouts;
6. review meaning, commands, warnings, and public information disclosure before
   publishing.

## Local diagnostic support report

The existing administrator page now offers selected, reviewed JSON downloads
from its displayed observation. It makes no additional request and never uploads
or sends a support message. Observation time, support receipt and missing-evidence
warnings stay with the selected aggregate sections. See
[the support-report workflow](../docs/GUIDE_SUPPORT_REPORT_QUICKSTART.md) for exact
steps, refresh/cancellation behavior, privacy limits and test qualifications.
