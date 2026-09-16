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

Additional HTTP-browser compatibility fix:

- Changed only the operator/enterprise outer edge's Referrer-Policy from
  `no-referrer` to `same-origin`. HTTP browsers can omit Fetch Metadata, so the
  gateway's exact-origin fallback needs same-origin Referer on GET fetches.
  Cross-origin Referer remains suppressed. Verified public `/console/` returns
  HTTP 200 with `Referrer-Policy: same-origin` after a successful edge rollout.
- Updated the public console Service's `appProtocol` hints to `http` while
  preserving port names and selectors.
- Workstation routing uses `utun4`; direct interface-bound probes did not
  establish connectivity. Management-side public 5006 succeeds, while public
  5005 times out. These observations do not isolate a single root cause, and
  no global VPN, routing or firewall changes were made.

### Completed HTTP authentication protocol acceptance

On 2026-09-16 the local `verify-http-login.mbtx` harness completed real
Keycloak password login, mandatory TOTP enrollment, authorization-code callback,
enterprise page redirect and controller session issuance. Public HTTP URLs and
Host headers were preserved through temporary SSH forwards to the management
LAN; internal admin access continued to verify the private TLS CA. This is
protocol acceptance, not evidence of direct public reachability or rendered
browser behavior.

The final run additionally asserted cross-origin session retrieval returns 401,
same-origin logout without CSRF returns 403, authenticated logout succeeds,
and subsequent browser-session retrieval returns 401. Temporary Keycloak users
and local cookie/CA files were removed by cleanup handlers. Controller account
and audit records may remain; this does not claim their deletion or bearer
replay acceptance coverage. No password, token or OTP seed was logged, and MFA
policy was not weakened. The test helper uses the raw TOTP form secret as UTF-8
HMAC key, matching Keycloak's `TotpUtils.encode`, rather than treating that raw
field as an already Base32-encoded value.

### Browser findings: HTTP transition is not end-to-end complete

The actual workstation browser subsequently rendered the public operator
`http://106.39.18.146:5003/console/` login page. It displayed
“Administrative login is blocked on public plain HTTP” and
“Organization sign-in requires HTTPS”; credential entry and Sign in were
disabled. Source confirms `cmd/console/main.mbt:login_transport_allowed`
accepts only HTTPS or loopback HTTP. Workbench's endpoint safety check has
the same restriction. Backend protocol success therefore does **not** prove
usable HTTP operator/workbench entry.

Required follow-up: implement an explicit deployment-scoped HTTP UI opt-in,
retain secure defaults and localhost-only static bootstrap credentials, add
regression tests for enabled/disabled mode, rebuild/deploy the affected UI
assets and repeat real-browser login. Do not globally allow arbitrary HTTP
controller endpoints or mark this item passed from a curl test.

The public enterprise page on port 5005 separately failed to open in the
workstation browser with `net::ERR_BLOCKED_BY_CLIENT`. This observation is
distinct from the earlier curl empty reply; its cause is not established.
No browser security override or global network change was applied.

### Explicit UI opt-in implementation

Console and workbench share `ui/browser_transport`. Their shipped HTML contains
an empty `lunanexa-public-http-origin` meta element, so public HTTP remains
disabled by default. A deployment choosing temporary HTTP must set its content
to the exact public origin, for example `http://106.39.18.146:5003` for the
operator page. The configured origin, actual page origin and requested API
origin must all match. Other hosts/ports, embedded credentials, paths, query
strings and fragments do not gain HTTP permission. Query parameters and local
storage cannot enable this mode. Static operator/audit token bootstrap remains
localhost-only. Enabled HTTP pages display a plaintext-transport warning.

This metadata is deployment policy, not cryptographic protection: HTTP remains
vulnerable to network interception. Restoring HTTPS requires removing the opt-in
as well as the coordinated gateway/identity changes above. Source implementation
and unit tests do not establish that the new assets have been deployed.

Validation for this implementation: 44/44 targeted JS tests passed across
browser transport, console and workbench with `--deny-warn`; targeted strict
JS checking and release browser-bundle build passed. `moon info` reports only
the new JS-only transport package's two functions (the module's canonical
native backend does not emit a tracked interface for JS-only packages).
Live UI rollout and rendered enabled-mode acceptance are still pending.

### Live UI rollout follow-up

The UI assets were subsequently layered over the existing web image, preserving
its enterprise/installer assets and Nginx configuration. Candidate and deployed
digest: `sha256:1d87ab49f114ff8ef0158ff8a5f88e59abc6173a19d8a458bcd1126d1ac7b0b5`
in the private registry's `acceptance/web` repository. An isolated Pod with a
distinct app selector reached Ready with zero restarts; both HTML pages served
their exact deployment-origin metadata. The console Deployment then rolled
successfully without changing its security context or backend.

The actual browser on public port 5003 now displays the temporary HTTP warning,
an enabled organization-sign-in link and an editable session field; the old
HTTP-blocked message is gone. Static bootstrap token fields remain absent.
Following the real OIDC link still fails in this workstation browser with
`net::ERR_BLOCKED_BY_CLIENT`. Thus the UI transport-policy defect is deployed
and its landing state verified, but end-to-end browser authentication remains
unproven. This result does not supersede the outstanding public 5005/5006
reachability investigation or count as ComfyUI/workbench acceptance.

Rollback image remains
`moon/lunanexa-web@sha256:a6136238fb0d39165fb26296b809786204fc6e74c2fee774e5103f7a4fe17550`.

### Controller-direct logout revocation verification

The expanded live password/MFA harness completed on 2026-09-16. Before logout,
the issued bearer returned HTTP 200 from `/v1/auth/self` directly on the
production controller Service through an SSH-only loopback forward, without
gateway cookies or browser metadata. After successful gateway logout, the exact
same bearer returned HTTP 401 from that same controller path. Browser-session
retrieval also returned 401. The cross-origin 401 and missing-CSRF logout 403
negative controls still passed. This closes the bearer-replay evidence gap;
it does not establish public-network reachability or browser self-registration.
The disposable Keycloak user and local credential files were removed. Controller
account/audit records are not claimed deleted. No token or MFA seed was logged.
