# Security operations

- Bootstrap tokens are short-lived and single use. Revoke unused tokens after
  an enrollment window.
- Give every node a distinct node token. Enrollment stores only its SHA-256
  digest. Rotate certificates before expiry; a new serial supersedes the old
  one, and expired certificates cannot authenticate node APIs.
- Rotate secret references by version. Secret values remain in the deployment
  provider and are delivered only to the runtime that requires them.
- Keep assignment signing authority on the controller. Operators submit
  unsigned desired state; pre-signed operator input is rejected, and nodes hold
  the matching host-owned HMAC verification key needed for reconciliation.
  Treat disclosure of that symmetric key as signing-authority compromise and
  rotate it across the controller and every node.
- Administrative, audit, inference, and monitoring credentials are separate.
  Audit and metrics endpoints accept only their read-only role token; deny
  permissions not explicitly granted by the deployment identity provider.
- Require SHA-256 digest pinning and the fixed-command Cosign adapter with an
  allowed public-key path for artifacts and runtime images. The S3 verifier
  streams and hashes bytes with a configured maximum size. Never translate a
  hand-authored boolean into successful verification evidence; the API accepts
  verification inputs and mints the result only after the Cosign process exits
  successfully. Both runtime-image and model-artifact digests are checked at
  deployment admission.
- Treat an OCI container as ready only when engine inspection reports the exact
  assigned digest reference and assignment label plus a healthy image-defined
  health check. Starting, missing-health-check, unhealthy, exited, or substituted
  containers are never advertised as running in node heartbeats.
- Default runtime networking denies arbitrary ingress and limits egress to the
  management channel and artifact service.
- Log only `RequestLog` metadata. Raw payloads and outputs are not fields of the
  log type.
- Retain content only for `RetainUntil` or consented evaluation capture. Expiry
  emits a deletion receipt without reproducing the storage reference.
- The built-in deployment advertises and accepts only `Ephemeral` retention.
  Non-ephemeral requests fail closed until an encrypted external retention
  provider is configured; request/output bodies are never written to controller
  snapshots.
- Terminate TLS and validate client certificates at the trusted ingress/service
  mesh boundary. Keep the native controller off untrusted networks and keep
  `/metrics` management-only. Application-level per-node HMAC and replay fences
  remain required even behind mTLS.
- The supplied NGINX ingress template requires client certificates rooted in
  the externally provisioned `lunanexa-client-ca` Secret and never forwards the
  presented certificate to the application. Label only the trusted ingress
  namespace with `lunanexa.io/ingress=trusted`; the default network policies
  otherwise admit controller/console traffic only from LunaNexa components.
  Replace these controls with equivalent service-mesh policy when NGINX is not
  the deployment ingress. Do not disable verification to make enrollment work.
