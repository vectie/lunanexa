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

The optional deployment profile combines
`deploy/oidc-browser-ingress.yaml` with
`deploy/oidc-browser-ingress-controller-patch.yaml`. It is a contract for a
reviewed, deployment-supplied OIDC identity-gateway image, not a bundled
identity provider. The patch runs that gateway as a sidecar in every
`lunanexa-control` pod. This placement is a security boundary: session exchange
calls `http://127.0.0.1:8080`, and the controller accepts proxy identity only
from a proven loopback peer. A separate gateway Deployment cannot satisfy that
proof and must not be substituted based on NetworkPolicy alone.

## Required OIDC behavior

Use two OIDC clients and two browser audiences: one for the operator host and
one for the enterprise/workbench host. A session or callback issued for one
audience must never authenticate the other.

The gateway must:

- use the Authorization Code flow and require PKCE `S256`;
- compare the discovered issuer exactly with the configured HTTPS issuer;
- validate signature, issuer, audience, expiry, not-before, authorization-code
  hash when present, and the configured client ID;
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

The assertion lifetime must not exceed 30 seconds. The nonce is a unique
assertion/JTI and is consumed once. The gateway must never send tenant, role,
email, account ID, or internal `subject_ref` as authority. LunaNexa resolves
the signed issuer/subject through its durable account mapping and derives all
roles and tenant access from LunaNexa stores.

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
bearer; the still valid OIDC gateway session may perform a fresh, state-bound
exchange. Long-lived automation uses separately issued `lnx_...` API keys, not
the browser session.

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

For every cookie-authenticated unsafe request, including session exchange,
refresh, linking, and logout, the gateway must require:

1. an exact `Origin` match for the current operator or enterprise HTTPS host;
2. a cryptographically random synchronizer token bound to the gateway session,
   sent in `X-LunaNexa-CSRF` and compared in constant time; and
3. a content type and method accepted by the exact route.

`SameSite=Lax` is defense in depth, not the CSRF check. Do not enable wildcard
CORS or credentialed cross-origin requests. Ordinary LunaNexa `lnxs_` and
`lnx_` bearer calls are non-ambient, but the gateway still admits them only
from the two configured origins and must not forward legacy static operator,
audit, or inference tokens through the production browser route.

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
  --provider-ref CORP_OIDC \
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

The identity provider must be reachable on TCP 443 from a namespace labeled
`lunanexa.io/service=oidc-provider`. Kubernetes NetworkPolicy cannot select an
external DNS name; an external provider therefore needs a reviewed static-IP
or CNI FQDN-policy overlay. Do not replace that fail-closed rule with arbitrary
Internet egress.

The base controller policy does not admit ingress-nginx or a separate identity
pod to native controller port 8080. The OIDC overlay creates a Service selecting
the controller pods but targeting only the sidecar's distinct `identity-http`
port 8081. Its policy admits only label-locked ingress-nginx pods from the
explicitly trusted ingress namespace to 8081, plus the sidecar's bounded UI,
DNS, and IdP egress. Kubernetes NetworkPolicy is pod-scoped, so the controller
container technically shares those overlay egress grants; the sidecar and
controller still have separate credentials and filesystem mounts. No public
console, enterprise, or workbench gateway may connect directly to port 8080.

`LUNANEXA_ACCOUNT_PATH=/var/lib/lunanexa/accounts.json` resides on the existing
controller state PVC. Back it up and restore it with the workspace, portal,
access-key, contract, and audit state. The file is an atomic `0600` fallback;
move it to the approved transactional database profile before claiming highly
available account/session storage.

## Local development compatibility

The existing static-token browser path remains supported only for localhost,
port-forwarded acceptance, and the explicitly temporary plain-HTTP management
foundation. That overlay applies
`deploy/management-foundation/network-policy-dev-browser-patch.yaml` to admit
its public gateway pods. It is not part of the OIDC production profile and
must never be copied into a public TLS deployment.

Static `LUNANEXA_OPERATOR_TOKEN`, `LUNANEXA_AUDIT_TOKEN`, and
`LUNANEXA_INFERENCE_TOKEN` remain available to native CLI, automation, and
local acceptance. The production browser gateway forwards only scoped
`lnxs_...` browser sessions and `lnx_...` API keys.

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
