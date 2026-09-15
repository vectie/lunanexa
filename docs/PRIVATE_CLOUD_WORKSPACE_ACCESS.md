# Private-cloud workspace admission

Set `LUNANEXA_PRIVATE_CLOUD_WORKSPACE_ACCESS=1` only for a deployment serving
administrator-owned private-cloud resources. Missing or other values retain
the existing contract-gated behavior. This setting is deployment-owned, not
accepted from a customer request.

An operator prepares and enables the existing access package. Active account,
Developer membership, workspace user/grant, bounded lease and approved model
checks remain required. Public registration does not enable a workspace.
Client launch, single-use redemption and subsequent credential requests use
the same private-cloud authority. Revoking or expiring workspace access still
denies the credential. Commercial order-bound credentials do not inherit this
exemption, and commercial ordering/payment/provisioning remain unchanged.

This policy does not merge delivery mechanisms: IaaS remains a bare-machine
lease, PaaS remains an isolated WebIDE/ComfyUI workspace, and MaaS remains a
model API. A unified role-aware workspace is an interface decision, not shared
tenant storage or unlimited administrator access to raw secrets.

For an internal HTTPS model gateway using a deployment-owned CA, the workspace
host accepts optional `trusted_ca_config_map`. It names a ConfigMap in the
workspace namespace with public `ca-bundle.crt` data. Only the model-proxy
container mounts this bundle read-only and receives `SSL_CERT_FILE`; ComfyUI
receives neither the trust mount nor model credentials. Missing configuration
retains system trust. The gateway process itself must be configured with the
same reviewed trust bundle by its deployment. Certificate verification stays on;
private CA keys must never be put in this ConfigMap.

Video jobs distinguish commercial order ownership from private workspace-lease
ownership. Private jobs must bind the exact active workspace lease, never a
synthetic machine order; model/deployment readiness and per-capability limits
remain required. Commercial job serialization and idempotency identity must
remain unchanged when this authority distinction is introduced.

Implementation status: backend admission and private video authority have
component/API tests, including private task restoration in an isolated PostgreSQL
database. These tests use synthetic providers, not GPU inference. Unified UI,
live deployment and complete browser-to-provider acceptance remain separate
unfinished work; this document is not a production acceptance claim.
