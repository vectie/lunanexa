# LunaNexa coursebook site

This is a separate, source-grounded documentation site generated with
MoonBook's `wiki-course` repository-coursebook skill and reusable site asset.
It teaches LunaNexa's features, architecture, data flows, use, operation, and
debugging. It is not the source of truth: the repository documents and typed
contracts referenced by `coursebook-evidence.json` remain authoritative.

The published default is newcomer-first: overview, quickstart, concepts,
deployment, operations, troubleshooting, and public reference. Implementation
status, readiness judgment, repository revision, source provenance, and the
generation process appear only after the reader explicitly selects **Show
technical notes** or follows a direct advanced-page link. This is progressive
disclosure, not a security boundary.

English is the canonical content in `coursebook.json`; the complete Simplified
Chinese overlay lives in `coursebook.zh-CN.json`. The native language selector
uses the same `lunanexa.locale` browser preference as the console and
workbench. It translates explanations and labels while preserving commands,
paths, protocol IDs, model names, and other copy-sensitive technical values.
Real product screenshots live below `images/` and state exactly which live UI
condition was captured.

The current projection is marked `draft` because it records commit
`db481df6104c5c93056eae6dc4e03b62ddbe096c` plus a dirty working tree. Refresh
it after the deployment/runtime changes are committed and after tomorrow's
physical-cluster evidence is available.

## Validate

```sh
node --check docs-site/app.js
node --check docs-site/server.mjs
node --test docs-site/coursebook.test.mjs
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

The manifest pins the pod to a management-labelled node, runs non-root with a
read-only filesystem, denies privilege escalation, uses default-deny networking,
accepts traffic only from the ingress namespace, and allows egress only to DNS
and the HTTPS MoonClaw Gateway. Ingress requires TLS plus a verified client
certificate. If MoonClaw is unavailable, `/health` remains ready as long as the
coursebook itself is valid; the page shows the guide as offline.

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

## Refresh workflow

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
