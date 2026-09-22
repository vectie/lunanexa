# Public HTTP workspace acceptance

The WebIDE gateway defaults to HTTPS (loopback HTTP is allowed for local tests).
For an explicitly approved, temporary no-TLS deployment, set
`LUNANEXA_WEBIDE_ALLOW_INSECURE_PUBLIC_HTTP=true` and set
`LUNANEXA_WEBIDE_PUBLIC_ORIGIN` to the exact public IPv4 origin, including its
port. DNS names, wildcard binds, paths, credentials and malformed authorities
are not accepted by this override. No incoming header can enable it.

This does **not** make plaintext transport safe. HTTP exposes session traffic
to network interception. Cookies are host-scoped, not port-isolated; every
service on that IP must therefore be trusted. Use only disposable technical
acceptance accounts and the approved short-lived resource grants. Do not use
real commercial or personal data. Replace the origin with HTTPS and remove
the override before production use.

Ingress must preserve the configured Host and Origin, support WebSockets, and
route `/connect` and the workspace root to the same isolated gateway. Keep the
controller and model gateway on their existing verified private TLS routes.
Do not route the handoff to a shared application daemon: workspace provisioning
must remain bound to the controller's tenant, subject, organization and project.

Publishing a client catalog entry is a separate deployment step. Its launch URI
must point to this gateway's public `/connect` endpoint; its model API origin
must match the host's configured gateway exactly. A reachable public application
page or issued handoff alone is not successful delivery.

Deploy a controller supporting `LUNANEXA_CLIENT_HTTP_LAUNCH_ORIGINS_JSON` before
running `scripts/deploy-public-comfyui.mbtx`. The value is a JSON array of exact
approved HTTP origins; it applies only to client launch URLs, never to model API
URLs. Catalog `handoff_lifetime_ms` and `maximum_requests` are Int64 and must be
JSON **strings**, not numbers. The deployment script retains private backups,
waits for component readiness, and switches the public service last. On a failed
controller rollout, restore its prior catalog before attempting customer launch.

Acceptance must prove UI launch, isolated persistence across reopening, result
download and expiration/revocation denial. Unit tests of the override are not
evidence that any public deployment was switched or accepted.
