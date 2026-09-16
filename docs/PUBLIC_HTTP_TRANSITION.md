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
