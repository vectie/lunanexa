# Temporary public HTTP transition

Requested scope: browser-facing ports 5003 (operator), 5005 (enterprise), and
5006 (platform identity). Internal OIDC HTTPS, certificate verification, token
validation, assertion signatures, RBAC, quotas, and contractual boundaries
remain unchanged. Public HTTP exposes passwords and session credentials to
network observers; it is not a production transport recommendation.

## Gateway configuration

HTTPS remains the default. Temporary HTTP requires all of:

- `LUNANEXA_PUBLIC_HTTP_ENABLED=true`.
- HTTP issuer and both HTTP callback URLs, with distinct audience hosts.
- An explicit HTTPS `LUNANEXA_OIDC_TRANSPORT_ORIGIN`; the CA remains required
  according to the existing private trust deployment.
- Separate `lunanexa_http_`-prefixed operator and enterprise cookie names.
  Cookies retain HttpOnly, SameSite=Lax, path `/`, and no Domain attribute.
- For this existing realm, `LUNANEXA_IDENTITY_CANONICAL_ISSUER` set to the old
  HTTPS issuer, preserving account bindings. Only a scheme-only change for the
  same authority and realm is accepted. Actual provider discovery and token
  validation use the HTTP issuer, not the canonical account namespace.

HTTP browsers may omit Fetch Metadata headers. Only explicit HTTP mode permits
that fallback: session/API fetches require an exact Origin or slash-bounded
same-origin Referer; logout still requires exact Origin plus the session CSRF
token. OIDC callback state, nonce, PKCE and one-time consumption remain enabled.

## Deployment checklist (not yet executed)

Pre-deployment evidence, 2026-09-16:

- Gateway strict native tests: 15/15; Linux release build completed.
- Candidate binary SHA-256:
  `e09be0a85d815f88127c40bee935bda4c2f78580ff0d4fb8916214f7637a9867`.
- Candidate image digest:
  `sha256:c74204ae057e716b2f1606e2f89225ede37ace8e1bd8f7f4f772eb403ca2b89b`.
- An isolated restricted-security Pod on management failed before application
  startup: `libdl.so.2` is absent from the previous minimal runtime image.
  The new binary also declares `libpthread.so.0`; both require resolution
  against the image's runtime library set before another smoke attempt.
- This candidate must not be promoted. The failed smoke Pod was removed;
  the candidate image and build artifacts remain for diagnosis.
- No public listener, Keycloak realm/client, production gateway image, TLS
  certificate, or internal trust setting was changed by this attempt.

Runtime packaging follow-up:

- Rebuilt a standalone runtime using the build environment's resolved library
  closure (including PostgreSQL dependencies), rather than mixing two glibc
  versions. No model artifacts are included.
- Fixed restrictive staging-directory permissions uncovered by the non-root
  smoke test; did not relax Pod security or run the service as root.
- Corrected candidate digest:
  `sha256:79b5bce362a6a343344f27b7067aeb96a79d8be921da0ccdc0cb277147074d32`.
- Management-node smoke passed with UID/GID 65532, read-only root filesystem,
  no privilege escalation, all capabilities dropped and RuntimeDefault seccomp.
  Kubernetes HTTP readiness `/health:8081` passed in relay mode. The temporary
  Pod was then deleted.
- This proves image startup only. Proxy-mode PostgreSQL initialization, actual
  OIDC login and the coordinated public HTTP rollout are still pending.

Proxy-mode and gateway rollout follow-up:

- A standalone canary reused the existing HTTPS configuration and secret
  references. Its custom readiness gate remained false; EndpointSlice confirmed
  `ready=false, serving=false`, so it did not receive Service traffic.
- The application readiness check, including PostgreSQL `SELECT 1`, passed.
  A separate loopback SSH/Pod forward returned `/health` HTTP 200.
- Operator and enterprise `/auth/oidc/start` both returned HTTP 302 to the exact
  configured Keycloak authorization endpoint, with Secure and HttpOnly cookies.
  This covers real verified-TLS discovery and flow creation, not a completed
  user login or authorization-code exchange.
- The corrected image was rolled into `lunanexa-identity-gateway`; rollout
  completed with 2/2 replicas ready. All public protocols remain HTTPS.
  Previous image for rollback:
  `sha256:5cb6a33edd626ebe4881688157c29bdc58640713996dfe11aea8f17da81dba9e`.
- The standalone canary was removed. Keycloak hostname/client callbacks and
  outer proxy protocol changes remain pending.

1. Back up non-secret ingress configuration and Keycloak client/realm settings.
2. Build and smoke-test the gateway candidate with existing HTTPS configuration.
3. Update Keycloak public hostname, realm SSL policy and exact client callbacks.
   Keep internal HTTPS listeners and certificates intact.
4. Update gateway configuration and image, and both outer Nginx listeners and
   forwarded scheme. Remove HSTS from the temporary HTTP entry.
5. Verify both login flows in a browser, existing account identity, logout,
   unauthorized/cross-origin rejection, cookies and internal verified HTTPS.
6. Record actual rollout evidence. Source tests alone do not prove rollout.

Switching back requires restoring HTTPS public URLs, secure cookie names,
Keycloak policy and outer TLS listeners together, and removing the temporary
HTTP flag and canonical issuer override. Users must sign in again.

## Applied public HTTP configuration (2026-09-16)

The public transition was applied after the gateway rollout:

- Keycloak public hostname is `http://106.39.18.146:5006`; the lunanexa realm's
  external SSL requirement is disabled. Internal listener remains HTTPS and
  its certificate, private CA and internal edge are unchanged.
- Operator/enterprise clients allow only their respective exact HTTP callback;
  gateway uses the explicit HTTP flag, separate HTTP cookie names and the
  original HTTPS canonical account namespace.
- Both outer Nginx listeners use HTTP on their existing container ports.
  Upstream certificate verification remains enabled. Outer HSTS was removed.
- Corrected operator/enterprise edge readiness and liveness probes from HTTPS
  to HTTP; both edge replicas then rolled successfully. The identity public
  edge uses TCP probes, requiring no protocol change.
- Verified from management: operator and enterprise root paths return 302 to
  their UI; both OIDC start endpoints return 302 to the HTTP provider with
  HttpOnly, non-Secure cookies in the new namespace. Public discovery advertises
  the exact HTTP issuer and endpoints.
- Workstation direct public port 5003 also returns the correct HTTP 302 without
  HSTS. Direct public ports 5005 and 5006 returned an empty reply during this
  check, despite management-side success. Public reachability and a completed
  browser login remain unresolved; do not claim full login acceptance.

The pre-change private backup is retained outside git at
`/var/folders/_j/kcn3f7817s71gymnv_nnn1bm0000gn/T/lunanexa-public-http-backup-.45436.89ff5d9a`.
It includes provider client configuration and must not be published.
