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
  portal, each with one exact callback/origin and PKCE `S256`;
- bounded token/session lifetimes and user/admin security event persistence;
- a disruption budget and network policies;
- a public ingress that exposes only `/.well-known`, `/realms` and `/resources`.
  The Keycloak administration surface is not publicly routed.

The realm has no LunaNexa role mapping. A valid Keycloak login creates identity,
not authority: LunaNexa continues to derive operator roles, organization
memberships, contracts, budgets and machine access from its own stores.

## Prerequisites

1. Install the Keycloak Operator version `26.7.3` and its `v2beta1` CRDs. Keep
   the Operator and server image on the same reviewed release.
2. Provision a dedicated, backed-up PostgreSQL database. For a production HA
   claim, it must have synchronous failover and a tested restore path; the
   repository does not create a misleading single-pod identity database.
3. Provision `lunanexa-platform-idp-tls` in the identity namespace. The
   certificate must cover the exact public identity hostname.
4. Provide a working SMTP account. Public registration is fail-closed on email
   verification, so registration is not ready until a real verification email
   completes.
5. Publish the identity hostname through the trusted ingress and determine the
   reviewed `/24`-to-`/32` egress CIDR used by the identity gateway to reach
   that HTTPS issuer. A split-horizon deployment may resolve the same public
   hostname to the Keycloak service internally.
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
  --identity-host id.example.com \
  --operator-host operator.example.com \
  --enterprise-host app.example.com \
  --database-host postgres-ha.lunanexa-identity.svc.cluster.local \
  --database-name keycloak \
  --identity-egress-cidr 203.0.113.40/32 \
  --gateway-image REGISTRY/IDENTITY_GATEWAY@sha256:EXACT_DIGEST \
  --keycloak-image quay.io/keycloak/keycloak@sha256:EXACT_26_7_3_DIGEST
```

The renderer rejects mutable images, non-HTTPS issuers, unsafe names and hosts,
equal browser hosts, broad identity egress ranges, unresolved deployment
placeholders and non-absolute paths. Realm `${...}` values remain intentionally:
the Keycloak Realm Import Operator resolves only those allowlisted values from
the namespace-local Secret.

Apply the secret manifest first, then the rendered profile. The source template
contains no Secret object and no credential. A realm import is bootstrap-only;
after the first successful import, make future realm changes through reviewed,
versioned administration migrations rather than deleting the realm or database.

## Required smoke acceptance

Before enabling public DNS, prove all of the following with a new email address:

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
