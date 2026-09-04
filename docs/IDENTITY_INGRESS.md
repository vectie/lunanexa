# Human accounts and OIDC browser ingress

LunaNexa keeps authentication, authorization, contracts, and access tokens as
separate authorities:

```text
approved OIDC provider
  -> browser identity gateway and its OIDC session
  -> signed, short-lived issuer/subject assertion
  -> LunaNexa account mapping (stable subject_ref)
  -> LunaNexa operator role or enterprise/workspace grant
  -> contract entitlement
  -> scoped LunaNexa browser session or API key
```

Passwords, MFA factors, recovery codes, provider access/refresh tokens, and the
upstream OIDC session remain owned by the approved identity provider and
gateway. LunaNexa stores the stable account, a digest of the external
issuer/subject binding, role and entitlement state, and digests of its own
short-lived sessions and API keys. A contract binds the stable LunaNexa
`subject_ref`; it never binds an email address, OIDC cookie, client
certificate DN, or bearer token.

The browser cookie contains only a 256-bit opaque session identifier plus an
HMAC. Authorization-flow state, verified identity claims, the bound LunaNexa
browser bearer, and the CSRF token live in the shared PostgreSQL table
`lunanexa.identity_gateway_sessions`. Both gateway replicas can therefore
continue the same flow and survive pod replacement without putting provider or
LunaNexa credentials in a browser cookie.

The optional deployment profile combines
`deploy/oidc-browser-ingress.yaml` with
`deploy/oidc-browser-ingress-controller-patch.yaml`. The reviewed MoonBit
gateway executable and `images/Containerfile.identity-gateway` are bundled in
this repository; deploy its image only by immutable digest. The identity
provider remains a separate authority. The public gateway runs in a separate
Deployment with only
OIDC, UI, DNS, and identity-relay egress. The patch runs the same immutable
image in `relay` mode as a minimal sidecar in every `lunanexa-control` pod. The
relay admits only signed session-exchange and registration requests and forwards them to
`http://127.0.0.1:8082`; it has no Secret mount and no permitted egress. Port
8082 is a controller-owned loopback-only listener that accepts exactly
`POST /v1/auth/register` and `POST /v1/auth/session:exchange`; it is never
selected by a Service. This
split preserves the controller's proven-loopback identity boundary without
granting the controller pod the public gateway's IdP or UI egress.

## Required OIDC behavior

Use two OIDC clients and two browser audiences: one for the operator host and
one for the enterprise/workbench host. A session or callback issued for one
audience must never authenticate the other.

The gateway must:

- use the Authorization Code flow and require PKCE `S256`;
- compare the discovered issuer exactly with the configured HTTPS issuer;
- validate issuer, audience, expiry, not-before, nonce, and configured client
  ID. The bundled gateway obtains the ID token only from the certificate-
  verified token endpoint and then requires both certificate-verified userinfo
  subject equality and active-token introspection bound to that client; it
  rejects providers without an introspection endpoint;
- generate cryptographically random, single-use `state` and `nonce` values,
  bind them to the initiating browser and exact redirect URI, and reject
  replay;
- register only the exact operator and enterprise HTTPS callback URIs shown in
  the manifest; wildcard redirects are forbidden;
- request only `openid profile email` unless a reviewed provider needs a
  smaller set; email and group claims are display/admission hints, never role
  authority;
- reject an unregistered issuer, client, redirect, audience, or callback host;
- keep client secrets and cookie/assertion keys in the deployment secret
  manager, never a ConfigMap, manifest, URL, browser bundle, or log.

The repository includes a platform-operated public identity profile in
`deploy/platform-identity.yaml`; see
[`PLATFORM_IDENTITY.md`](PLATFORM_IDENTITY.md). It uses Keycloak 26.7.3 with
open registration, verified email, password recovery and TOTP, or a deployment
may use a customer's federated enterprise IdP. A person does not need a
corporate directory to use the public profile: they create an identity at the
platform IdP, then the first verified sign-in creates the LunaNexa account.
Account creation alone grants only the bounded trial policy, when enabled; it
does not create an organization, approve a company, accept machine terms, settle
payment or allocate hardware.

The upstream IdP should require MFA for operator accounts and support provider
session revocation, recovery, and account suspension. LunaNexa still checks its
own account state and roles on every LunaNexa session authorization, so an IdP
login alone grants no cluster or tenant authority.

## Signed identity assertion

After validating the OIDC session, the gateway exchanges only the verified
issuer and provider subject for a LunaNexa browser session at:

```text
POST /v1/auth/session:exchange
```

Before proxying, it must delete every caller-supplied `X-LunaNexa-Identity-*`,
`X-LunaNexa-Subject`, `SSL-Client-Verify`, and `SSL-Client-Subject-DN` header.
It then sends exactly these headers:

- `X-LunaNexa-Identity-Issuer`
- `X-LunaNexa-Identity-Subject`
- `X-LunaNexa-Identity-Issued-At` (Unix milliseconds)
- `X-LunaNexa-Identity-Expires-At` (Unix milliseconds)
- `X-LunaNexa-Identity-Nonce`
- `X-LunaNexa-Identity-Signature`

The signature is `sha256:` plus lowercase HMAC-SHA256 hex over these canonical
UTF-8 bytes, with no trailing newline:

```text
lunanexa.identity.assertion.v1\n<issuer>\n<provider subject>\n<issued Unix ms>\n<expires Unix ms>\n<nonce>
```

Here `\n` denotes one LF byte between fields.

For a verified identity that has no LunaNexa account, the gateway calls
`POST /v1/auth/register` with the same short lifetime and adds the verified
OIDC `email` and display-name claims. Those two headers are covered by a
separate canonical signature:

```text
lunanexa.identity.registration.v1\n<issuer>\n<provider subject>\n<email>\n<display name>\n<issued Unix ms>\n<expires Unix ms>\n<nonce>
```

The corresponding headers are `X-LunaNexa-Identity-Email` and
`X-LunaNexa-Identity-Display-Name`; caller-supplied copies must be stripped at
the edge. The request body contains only `lifetime_ms` and an optional
`invitation_secret`. Without an invitation, registration creates an active
`EnterpriseUser` account and browser session. When the controller's reviewed
open-trial policy is enabled, it also creates a strictly bounded shared
inference membership and workspace lease. It never creates an exclusive-node
lease, SSH credential, contract, or machine authority. With an invitation, the
gateway-signed email must match the invited email and the invitation-bound
Developer membership is added.

The assertion lifetime must not exceed 30 seconds. The nonce is a unique
assertion/JTI and is consumed once. The gateway must never send tenant, role,
account ID, or internal `subject_ref` as authority. Email and display name are
sent only in the registration assertion where the signature covers them; they
are absent from ordinary login assertions. LunaNexa resolves the signed
issuer/subject through its durable account mapping and derives all roles and
tenant access from LunaNexa stores.

`LUNANEXA_IDENTITY_ASSERTION_SECRET` is mounted from the same Kubernetes Secret
key into the identity gateway and controller. It must contain at least 32
unpredictable bytes and be distinct from every operator, inference, audit,
cookie, API-key issuer, account-session issuer, assignment, or callback
authority. Rotation must use a
reviewed overlap procedure; never replace the key while an old gateway replica
can still issue assertions unless the controller temporarily accepts an
explicit previous key identifier.

The exchange reveals one `lnxs_...` session secret. The browser keeps it only
in memory and sends it as an `Authorization: Bearer` header. LunaNexa persists
only its digest. LunaNexa derives that secret with the separate required
`LUNANEXA_ACCOUNT_SESSION_ISSUER_SECRET`; the identity assertion key must never
be reused for session issuance. Reload intentionally loses this LunaNexa
bearer from UI memory; the still valid encrypted OIDC gateway session returns
its existing, host-bound bearer without a new exchange. Long-lived automation
uses separately issued `lnx_...` API keys, not the browser session.

## Public browser route contract

The gateway must implement these same-origin routes exactly. These are public
gateway routes; the controller does not implement them and they must never be
sent directly to native port 8080.

- `GET /auth/oidc/start?audience=operator` on the configured operator host and
  `GET /auth/oidc/start?audience=enterprise` on the configured enterprise host
  start Authorization Code + PKCE login. The host and audience must agree.
  Unknown, missing, or cross-host audiences fail with `400`; the gateway must
  not accept a caller-selected return URL.
- `GET /auth/session` uses the current host-specific HttpOnly gateway cookie.
  A signed-out or expired session returns `401` and no credential. On the
  first call after OIDC login, the gateway performs one signed loopback
  exchange and binds the resulting LunaNexa bearer to the encrypted gateway
  session, exact host, and `operator` or `enterprise` audience. Later calls and
  page reloads return that same still-valid bearer; they must not create
  another LunaNexa session. A valid request returns status `200`,
  content type `application/json`, and exactly
  `{"session_token":"lnxs_...","csrf_token":"...","expires_unix_ms":123}`.
  `expires_unix_ms` is an integer in the future. Both tokens are opaque and
  bounded; neither may appear in a URL, redirect, HTML, or log. The LunaNexa
  bearer may exist only inside the authenticated-and-encrypted HttpOnly
  gateway session and the UI's memory. The response must include `Cache-Control: no-store`,
  `Pragma: no-cache`, and `Vary: Cookie`.
- `POST /auth/logout` accepts no body and requires the host-specific gateway
  cookie plus its synchronizer token in `X-LunaNexa-CSRF`. Success returns
  `204` with no body only after the gateway uses its bound bearer to revoke the
  LunaNexa session, invalidates the gateway session, and expires the matching
  cookie. Cookie cleanup still occurs if the already-expired LunaNexa bearer
  returns `401`. Other controller failures return an error after local gateway
  invalidation. Missing, stale, cross-session, cross-host, or incorrectly
  sized CSRF values fail closed. The UI separately calls controller
  `POST /v1/auth/logout` with the in-memory LunaNexa bearer before this route;
  it erases both in-memory values even if either network call fails. That UI
  call is a latency optimization only; the gateway remains responsible for
  server-side LunaNexa revocation.

All three routes require the exact configured `Host`, HTTPS, and same-origin
Fetch Metadata. They emit no permissive CORS headers. `/auth/session` is the
only cookie-authenticated credential bootstrap that does not already have a
CSRF token; it is a same-origin, non-navigational `GET`, and its secret response
is unreadable cross-origin. OIDC `state` and `nonce`, `SameSite=Lax`, exact-host
validation, the fetch-metadata check, and the no-store response are all
required. No other cookie-authenticated unsafe operation has this exception.

For same-origin `/v1/*` application calls, the gateway accepts only the exact
`Authorization: Bearer lnxs_...` value bound to the current encrypted gateway
session, host, and audience. A bearer without that matching cookie state, or a
bearer copied between operator and enterprise hosts, is rejected. The
enterprise host additionally allows only `/v1/auth/`, `/v1/portal/self`,
`/v1/portal/signature-requests`, `/v1/portal/lease-requests`,
`/v1/notifications/self`, `/v1/contract-documents/self`,
`/v1/contract-documents/manifest`, `/v1/offline-commerce/self`, and
`/v1/machine-access/self`; the operator host admits the controller `/v1/`
surface after role authorization. The gateway removes the ambient cookie and
every identity/auth-TLS header before proxying to
`http://lunanexa-control:8080`. Static tokens and `lnx_` API keys are rejected
at this browser boundary; API keys use the separate authenticated API ingress.
The controller also refuses asserted identity on this non-loopback connection,
so the direct path cannot perform session exchange; only the relay path can do
so. Allowlist matching uses the decoded canonical path. The gateway rejects
dot segments, NULs, backslashes, encoded `/` or `\\`, repeated decoding, and
any path whose canonical form differs from the request target; it never
normalizes a hostile path into an allowed prefix.

## Cookies, CSRF, and origins

OIDC gateway cookies are ambient browser authority even though the resulting
LunaNexa session is an in-memory bearer. The operator and enterprise cookies
must therefore be different and use all of these attributes:

```text
__Host-...; Path=/; Secure; HttpOnly; SameSite=Lax
```

Do not set `Domain`. Rotate the cookie on successful login and privilege
change. Enforce both the configured idle limit and absolute limit. Store the
gateway session server-side or in an authenticated, encrypted cookie no larger
than the gateway's reviewed limit; never place provider tokens in browser-
readable storage.

For every cookie-authenticated unsafe request, including refresh, linking, and
logout, the gateway must require:

1. an exact `Origin` match for the current operator or enterprise HTTPS host;
2. a cryptographically random synchronizer token bound to the gateway session,
   sent in `X-LunaNexa-CSRF` and compared in constant time; and
3. a content type and method accepted by the exact route.

`SameSite=Lax` is defense in depth, not the CSRF check. Do not enable wildcard
CORS or credentialed cross-origin requests. The gateway admits only its
cookie-, host-, and audience-bound `lnxs_` bearer and must not forward `lnx_`
API keys or legacy static operator, audit, or inference tokens through the
production browser route.

## Logout and revocation

Logout is a CSRF-protected `POST`, never a state-changing `GET`. It must:

1. revoke the current LunaNexa browser session;
2. invalidate the gateway session server-side;
3. expire the matching `__Host-...` cookie with the same Path and security
   attributes;
4. use the provider's reviewed RP-initiated logout when available; and
5. redirect only to a pre-registered same-origin signed-out page.

Account suspension, revocation, role removal, and "log out all sessions" must
invalidate all LunaNexa browser sessions immediately. Logout does not silently
revoke separately issued API keys; the account's access-token page lists their
scope, model allowlist, expiry, quota, last use, and revocation state and offers
an explicit revoke action. API secrets are shown only once at issue time and
remain stored as digests.

## Deployment

For the LunaNexa-operated issuer, use
`scripts/deploy/render-platform-identity.sh`. It renders the resources below
together with the dedicated Keycloak namespace, realm, exact clients,
restricted Ingress and network path. Use the generic renderer only for an
approved enterprise issuer or another reviewed platform IdP.

Provision the following keys in a Secret named
`lunanexa-identity-ingress-credentials` using the deployment's secret manager:

- `operator-client-id`
- `operator-client-secret`
- `enterprise-client-id`
- `enterprise-client-secret`
- `operator-cookie-secret`
- `enterprise-cookie-secret`
- `identity-assertion-secret`

Provision `lunanexa-oidc-ingress-tls` separately. Render the non-secret
provider reference, issuer URL, two public hostnames, and immutable
digest-pinned identity-gateway image on top of an already rendered management
manifest before applying the result:

```sh
scripts/deploy/render-oidc-browser-ingress.sh \
  --output /ABSOLUTE/PROTECTED/management-with-oidc.yaml \
  --management-manifest /ABSOLUTE/PROTECTED/management.yaml \
  --provider-ref PLATFORM_OR_ENTERPRISE_OIDC \
  --issuer-url https://IDP_HOST/REALM_PATH \
  --operator-host OPERATOR_HOST \
  --enterprise-host ENTERPRISE_HOST \
  --gateway-image REGISTRY/IDENTITY_GATEWAY@sha256:EXACT_64_HEX_DIGEST
```

The renderer verifies the existing management manifest has no unresolved or
invalid deployment placeholders, injects the sidecar into its named controller
Deployment, and includes the identity ConfigMap, Service, NetworkPolicy, and
Ingress. It rejects non-HTTPS issuers, malformed or equal browser hosts,
mutable images, unsafe substitution characters, and unresolved inputs. It
writes the combined rendered file with mode `0600`. Apply the combined file;
do not apply the source patch directly or use a mutable image tag.

The controller's required `lunanexa-control-credentials` Secret must also
contain an independent `account-session-issuer-secret`. The standard
`scripts/deploy/generate-management-secrets.sh` creates it with the other
distinct control-plane authorities. It is not mounted into the identity
gateway. Conversely, `identity-assertion-secret` remains optional in the local
static-token profile but is mandatory whenever this OIDC profile is enabled.

For the current private/self-signed issuer, create Secret
`lunanexa-oidc-provider-ca` in the gateway namespace with key `ca.pem`
containing the issuer's existing CA. The gateway passes that exact file to TLS
verification for discovery, token, userinfo, and introspection requests. It
never enables an insecure TLS mode. Copying the CA does not change the issuer
hostname or certificate. The gateway also reads the existing
`lunanexa-database/url` Secret to persist opaque browser sessions across its two
replicas.

The identity provider must be reachable on its configured TLS port (443 or the
current private 5006 endpoint) from a namespace labeled
`lunanexa.io/service=oidc-provider`. Kubernetes NetworkPolicy cannot select an
external DNS name; an external provider therefore needs a reviewed static-IP
or CNI FQDN-policy overlay. Do not replace that fail-closed rule with arbitrary
Internet egress.

The base controller policy does not admit ingress-nginx to native controller
port 8080. The OIDC overlay exposes the separate
gateway Deployment to ingress-nginx and lets it reach only the UI services,
the relay Service on 8081, the controller's ordinary bearer API on 8080, DNS,
and the selected IdP. A second Service selects
the controller pods but targets only the relay sidecar's distinct
`identity-http` port 8081. The controller-pod overlay admits the identity
gateway on ports 8081 and 8080 and adds no egress. Only stripped, cookie-bound
`lnxs_` requests may use the 8080 route; asserted identity still requires the
identity-only relay and loopback hop. No public console, enterprise, or
workbench pod may connect directly to controller port 8080.

`LUNANEXA_ACCOUNT_PATH=/var/lib/lunanexa/accounts.json` is only the atomic
`0600` local fallback. The production PostgreSQL profile commits the account,
portal and related snapshot domains to the configured management database.
Back up and restore those domains together. Controller leader fencing provides
single-active failover; it is not a multi-writer account service.

## Local development compatibility

The existing static-token browser path remains supported only for localhost,
port-forwarded acceptance, and the explicitly temporary plain-HTTP management
foundation. That overlay applies
`deploy/management-foundation/network-policy-dev-browser-patch.yaml` to admit
its public gateway pods. It is not part of the OIDC production profile and
must never be copied into a public TLS deployment.

Static `LUNANEXA_OPERATOR_TOKEN`, `LUNANEXA_AUDIT_TOKEN`, and
`LUNANEXA_INFERENCE_TOKEN` remain available to native CLI, automation, and
local acceptance. The production browser gateway forwards only its host- and
cookie-bound `lnxs_...` browser session. `lnx_...` API keys use the
non-browser API ingress.

## Acceptance checks

Before opening browser ingress, prove all of the following:

- forged identity, subject, and auth-TLS headers sent by a browser are removed
  and rejected by the controller;
- wrong issuer, client, audience, redirect, signature, timestamp, nonce,
  callback host, or assertion replay fails closed;
- operator and enterprise cookies cannot cross-authenticate;
- missing, stale, cross-session, and cross-origin CSRF tokens fail every
  cookie-authenticated unsafe route;
- account suspension and role removal invalidate existing LunaNexa sessions;
- enterprise users cannot reach operator routes and operator read-only roles
  cannot mutate state;
- self-service API-key issuance derives tenant and subject from the account,
  reveals the secret once, and cannot list or revoke another subject's key;
- POST logout invalidates both sessions and a replayed bearer/cookie fails;
- gateway and controller restart preserve or deliberately revoke sessions
  according to the selected persistence policy; and
- API, ingress, gateway, and audit logs contain no password, provider token,
  cookie, LunaNexa session/API secret, raw contract document, or model payload.
