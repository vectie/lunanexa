# LunaNexa-operated public identity

LunaNexa ships a production-oriented, self-hosted public identity profile based
on Keycloak 26.7.3. It gives people without a corporate directory a LunaNexa
registration path while preserving the existing authority split:

```text
public user
  -> LunaNexa-operated Keycloak realm (password, email verification, TOTP)
  -> LunaNexa identity gateway (OIDC code flow + PKCE)
  -> signed 30-second identity assertion
  -> LunaNexa account/session
  -> individual/company organization
  -> terms, quote and payment
  -> shared MaaS, dedicated endpoint or bare machine
```

Keycloak is an infrastructure dependency operated under the LunaNexa service,
not a new Luna product. LunaNexa's controller still never receives or stores a
password, OTP seed, recovery code, OIDC refresh token or upstream browser
session. Enterprise federation remains available as a second issuer profile.

## What the profile provisions

`deploy/platform-identity.yaml` contains:

- a dedicated identity namespace;
- a two-instance Keycloak custom resource backed by an external PostgreSQL
  database and TLS;
- a `lunanexa` realm with open registration, email-as-username, verified email,
  password recovery, brute-force protection, a strong password policy and TOTP
  enrollment for new accounts;
- separate confidential OIDC clients for the operator console and enterprise
  portal, each with one exact callback/origin, PKCE `S256`, and an explicit
  self-audience mapper on access tokens and introspection output so strict
  Keycloak 26 audience checks succeed. Lightweight access-token mapping is
  explicitly disabled;
- bounded token/session lifetimes and user/admin security event persistence;
- a two-replica cluster-local HTTPS identity edge, disruption budgets, and
  network policies that prevent the browser gateway from hairpinning through
  the public issuer;
- a restricted public TLS edge and LoadBalancer Service whose port is derived
  from the exact issuer authority;
- a separate optional DNS-hosted public Ingress template that exposes only
  `/.well-known`, `/realms` and `/resources`. The no-domain/IP:port profile uses
  the deployment's existing public TLS edge instead. Neither path routes the
  Keycloak administration surface.

The realm has no LunaNexa role mapping. A valid Keycloak login creates identity,
not authority: LunaNexa continues to derive operator roles, organization
memberships, contracts, budgets and machine access from its own stores.

## Prerequisites

1. Install the Keycloak Operator version `26.7.3` and its `v2beta1` CRDs. Keep
   the Operator and server image on the same reviewed release.
2. Provision a dedicated, backed-up PostgreSQL database. For a production HA
   claim, it must have synchronous failover and a tested restore path; the
   repository does not create a misleading single-pod identity database.
3. Provision these deployment-owned TLS objects; do not reuse either private
   leaf key for the other endpoint:

   - `lunanexa-platform-idp-tls`: the existing public issuer certificate. Its
     SAN must cover the exact public DNS name or IP address seen by browsers.
   - `lunanexa-platform-idp-internal-tls`: the Keycloak backend certificate.
     Its SAN must cover
     `lunanexa-platform-idp-service.IDENTITY_NAMESPACE.svc.cluster.local`.
   - `lunanexa-identity-internal-tls`: the internal transport-edge certificate.
     Its SAN must cover
     `lunanexa-identity-internal.IDENTITY_NAMESPACE.svc.cluster.local`.
   - `lunanexa-oidc-internal-ca` in the identity namespace and
     `lunanexa-oidc-provider-ca` in the management namespace: public CA
     bundles only, each with a `ca.pem` key. The former validates Keycloak from
     the internal edge; the latter validates the internal edge from the
     identity gateway.

   The two internal leaf certificates may be issued by the same reviewed
   cluster-local CA, but they remain separate Secrets and identities.
4. Provide a working SMTP account. Public registration is fail-closed on email
   verification, so registration is not ready until a real verification email
   completes.
5. Publish the exact issuer authority through the rendered LoadBalancer TLS
   edge. It may be a DNS name or an IP literal with a port. The gateway never
   reaches that public address: it uses the cluster-local transport origin
   `https://lunanexa-identity-internal.IDENTITY_NAMESPACE.svc.cluster.local:8443`
   with strict CA and hostname verification.
6. Build and approve the LunaNexa identity-gateway image separately and pin it
   by digest. The platform IdP does not replace that browser/session boundary.

Keycloak's official production guidance requires TLS, a production database,
readiness checks and multiple instances for availability. See the
[Keycloak production guide](https://www.keycloak.org/server/configuration-production),
[Operator deployment guide](https://www.keycloak.org/operator/basic-deployment),
and [self-registration guide](https://www.keycloak.org/docs/26.7.0/server_admin/#_user-registration).

## Generate matching secrets

Create an absolute `0700` input directory containing these files, populated
from the deployment secret manager:

```text
database-username
database-password
smtp-host
smtp-port
smtp-username
smtp-password
smtp-from
```

Then generate a new protected manifest:

```sh
scripts/deploy/generate-platform-identity-secrets.sh \
  /ABSOLUTE/PROTECTED/platform-identity-secrets.yaml \
  /ABSOLUTE/PROTECTED/platform-identity-input \
  lunanexa \
  lunanexa-identity
```

The output is mode `0600` and contains three namespace-scoped Secrets. The
generator creates distinct random client, cookie and assertion authorities. It
copies each OIDC client secret to both the gateway Secret and realm-import
Secret so the two ends cannot drift. Do not commit, print or email this
manifest.

The Keycloak Operator creates `lunanexa-platform-idp-initial-admin` on first
bootstrap. Retrieve it only through the cluster secret-management procedure,
create a named break-glass administrator with MFA, test it, then remove or
disable the temporary administrator. Day-to-day realm administration should
use a separately audited administrative path or a port-forward, not the public
Ingress.

## Render the complete profile

Render on top of an existing production management manifest:

```sh
scripts/deploy/render-platform-identity.sh \
  --output /ABSOLUTE/PROTECTED/management-with-platform-identity.yaml \
  --management-manifest /ABSOLUTE/PROTECTED/management.yaml \
  --management-namespace lunanexa \
  --identity-namespace lunanexa-identity \
  --identity-host 203.0.113.40:5006 \
  --operator-host 203.0.113.40:5003 \
  --enterprise-host 203.0.113.40:5005 \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --gateway-image REGISTRY/IDENTITY_GATEWAY@sha256:EXACT_DIGEST \
  --keycloak-image quay.io/keycloak/keycloak@sha256:EXACT_26_7_3_DIGEST \
  --identity-edge-image REGISTRY/NGINX_EDGE@sha256:EXACT_DIGEST
```

`--identity-host` is the public issuer authority, not a Kubernetes Ingress
host. It accepts a reviewed DNS name or IPv4 address with an optional port. The
renderer derives the public issuer URL and its forwarded port while configuring
the gateway's transport origin exclusively from the identity namespace. It
also treats `--operator-host` and `--enterprise-host` as HTTPS authorities, so
one reviewed IP may use distinct UI ports. It rejects mutable images, invalid
authorities or ports, unsafe names and hosts, equal browser authorities,
unresolved deployment placeholders and non-absolute paths.
Realm `${...}` values remain intentionally:
the Keycloak Realm Import Operator resolves only those allowlisted values from
the namespace-local Secret.

Apply the secret manifest first, then the rendered profile. The source template
contains no Secret object and no credential. A realm import is bootstrap-only;
after the first successful import, make future realm changes through reviewed,
versioned administration migrations rather than deleting the realm or database.

The rendered no-domain profile uses `lunanexa-identity-public`, a LoadBalancer
Service whose configured port terminates the existing public certificate on a
restricted edge and then verifies the cluster-local Keycloak backend name.
For the browser applications, the same render also creates a separate
two-replica `lunanexa-identity-edge`. It terminates the existing
`lunanexa-oidc-ingress-tls` certificate and exposes only operator `5003` and
enterprise `5005` through the repointed `lunanexa-console-public` Service. The
edge can reach only `lunanexa-identity-gateway`; it never proxies directly to
the controller. The render sets both former plaintext public-gateway
Deployments to zero replicas and removes public ports `4174`, `3000`, and
`5001`. The enterprise bundle continues to serve `/workbench/` on the protected
enterprise origin.

The no-domain profile deliberately omits Kubernetes public Ingress resources
because Ingress host rules cannot contain an IP literal or port. DNS
deployments may separately render `deploy/platform-identity-public-ingress.yaml` by adding
`--identity-ingress-host EXACT_DNS_ISSUER_HOST` to the same renderer call. The
renderer requires that DNS host to equal `--identity-host`; its public TLS
Secret is never mounted into Keycloak or the internal edge.

## Password-form deployments

Deployments explicitly enabling the existing password form retain their current
identity-provider credential policy; upgrading the gateway does not reset user
passwords, rename accounts, change roles, or clear provider lockouts. Public
self-registration uses the email as the login name and the submitted name only
as a display name. Both portals explain this distinction. Legacy operator login
names remain accepted; only surrounding login-name whitespace is trimmed, never
the password.

Keycloak 26 returns the same `invalid_grant` for incorrect credentials and
brute-force lockouts ([provider implementation](https://github.com/keycloak/keycloak/blob/26.7.3/services/src/main/java/org/keycloak/authentication/authenticators/directgrant/ValidateUsername.java)).
On a rejected password the gateway uses the configured
server-side registration service account to read the exact user and its
attack-detection status through the private TLS edge. That account needs user
view authority (the existing `manage-users` registration authority includes it).
No new browser authority is granted. The edge allows GET/POST only on the exact
users collection and GET only on the individual lockout-status route; password
reset, role-write and failure-clearing routes remain inaccessible. Public admin
routes remain closed. The browser receives only stable error codes:

- `invalid-credentials` (401): login name or password not accepted;
- `account-temporarily-locked` (429): provider reports a lock; wait before retrying;
- `login-status-unavailable` (503): rejected login, but lockout diagnosis unavailable;
- `operator-access-denied` (403): identity verified, but no `PlatformOperator` role;
- `identity-provider-unavailable` (503): provider/client configuration or transport failure.

Management login and cookie bootstrap check the live LunaNexa account role.
Organization administrators do not implicitly become platform operators. A
denied management entry offers a customer-portal link and preserves the
independent customer session. Background HTTP 403 responses no longer clear a
valid operator session as though it expired; HTTP 401 retains expiry recovery.

For an existing private edge, run `moon run
scripts/deploy/enable-login-status.mbtx IDENTITY_NAMESPACE /ABSOLUTE/NEW_BACKUP.json`.
The script preserves existing host/CA settings, saves a private backup and rolls
the edge deployment: nginx reload alone cannot update a ConfigMap `subPath`
mount. Inspect both new ready pods before deploying the gateway. Also verify
that the deployed process actually uses the binary inside the pinned image;
an old hostPath command override can silently defeat an image upgrade.

### Login regression verification — 2026-10-20

The native functional suite passed 1856/1856, identity-gateway focused tests
40/40, and console/enterprise JavaScript tests 144/144. The identity manifest
tests also passed. `moon info`, formatting and native checking completed;
the repository's strict `--deny-warn` gate remains blocked by pre-existing
deprecated `to_json` calls under the October toolchain. The functional suite
was run with that deprecation warning suppressed, not with assertions disabled.

The deployed HTTPS customer portal was exercised with an existing, operator-
provided non-operator account and its unchanged password: password login reached
the authenticated enterprise page. The same account's management login and
existing-cookie bootstrap displayed explicit permission denial, not expiry;
the customer-portal link returned to the authenticated enterprise page. One
deliberately incorrect password produced the credential error, then the correct
password again produced permission denial. This also exercised both private
user lookup and authoritative lock-status reads. No lockout was deliberately
induced on an existing user; the locked and unavailable-status branches have
automated regression coverage. The originally reported account was not used
for password acceptance, at the operator's request. No existing password,
account role, organization membership or machine entitlement was changed.

The publicly served browser bundles matched the final tested build:

- console SHA-256: `8886fe278904b78bf5b826677a2f7430e046c5f8800c39492e4c411a5876a83e`;
- enterprise SHA-256: `83c22f2190f1f75db9d7892268ab8da5226623f55041b7494e32412242d07b75`.

Only the gateway, browser bundles and private identity edge were updated;
model servers, application workspaces and compute-node allocations were outside
this release. Previous immutable images were retained for rollback.

## Required smoke acceptance

Before enabling public exposure, prove all of the following with a new email address:

1. registration sends a real verification email and an unverified address
   cannot complete sign-in;
2. TOTP enrollment is required and a wrong or replayed code fails;
3. operator and enterprise clients reject each other's callbacks, origins,
   cookies and audiences;
4. implicit flow, password grant, service-account login and wildcard redirects
   are unavailable;
5. the public host returns discovery/login/account resources but `/admin`,
   `/metrics` and `/health` are not routed;
6. first verified enterprise login creates only the bounded LunaNexa account
   and trial, never a company, contract, paid order, node lease or operator role;
7. account suspension and LunaNexa role removal invalidate effective access;
8. Keycloak pod loss, database failover, backup restore, SMTP outage and key
   rotation behave according to the signed recovery procedure; and
9. Keycloak, ingress, gateway and LunaNexa logs contain no passwords, OTP seeds,
   client secrets, cookies, provider tokens or LunaNexa session/API secrets.

Repository manifest tests validate the declarative safety contract. They do not
claim that DNS, TLS, SMTP, PostgreSQL failover or a physical cluster has passed
this smoke acceptance.
