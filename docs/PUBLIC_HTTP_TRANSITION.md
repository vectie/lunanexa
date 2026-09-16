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
