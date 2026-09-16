# Workspace gateway isolation acceptance — 2026-09-15

## Delivered boundary

Workspace model egress now selects the deployment-owned role
`lunanexa.io/model-gateway=true`, not a gateway product name. The role and the
configured namespace are in the **same NetworkPolicy peer**, so both must
match. Only the configured TCP port is allowed. DNS, controller access and
authenticated workspace ingress retain their separate restricted rules.

Add the role to the trusted gateway's Pod template before upgrading the
workspace host. Label/Pod creation permissions in that namespace are part of
the trust boundary. See [deployment requirements](HOSTED_WEBIDE.md).

## Actual Kubernetes acceptance

The isolated namespace `aigc-acceptance-20260915` was tested from the existing
ComfyUI workspace container to its internal gateway on port 5883. Every allowed
probe used OpenSSL with the disposable deployment CA, hostname verification and
`verify_return_error`; no host trust store or certificate bypass was used.

Observed:

1. Original route: verified TLS succeeds.
2. New role-based policy, gateway without the role: connection is denied.
3. Add the role to the gateway Pod template and complete its rollout: verified
   TLS succeeds.
4. Keep the correct role but select a different namespace: connection is denied.
5. Restore the exact desired namespace-and-role peer: verified TLS succeeds.

The workspace gateway was then built natively and deployed with immutable image
digest `sha256:9d3ef5a3cad0ae3b285bd2027bd2db3bfa3ee8b40787b352fe265358309f7206`
under the isolated registry's `acceptance/webide-runtime` repository. A fresh
private handoff provisioned the workspace using this binary. The resulting
live NetworkPolicy retained the new role, namespace and port after provisioning;
the result is not only a manual policy patch.

The same run verified connect 204, authenticated root 200, WebSocket 101,
cross-site WebSocket 403 and forged-cookie 401. Explicit revocation closed an
established WebSocket with code 1008 after 5774 ms; subsequent HTTP and WebSocket
requests returned 401. The test credential was revoked.

A subsequent fresh private handoff reopened the same persistent workspace.
Both earlier `LunaNexa_00001_.mp4` and `LunaNexa_00002_.mp4` outputs were listed.
The second output downloaded through the authenticated workspace gateway with
its unchanged SHA-256:
`8b4bc945cb35c2dff26e566c525a30fa91649f473aef41a657c9e96bdacb7148`.
The temporary verification download was removed. One bounded scoped handoff
was intentionally retained so the reopened workspace remains authorized.

## Automated checks and limits

- Local native workspace bridge/host tests with `--deny-warn`: **16/16 passed**.
- Linux native workspace bridge/host tests: **16/16 passed** (same test set).
- The exact policy regression rejects extra peers, empty selectors or ports
  through structural equality and confirms deny-by-default policy ordering.
- Isolation/response scan fixtures: **7/7 passed**. The scan now distinguishes
  internal variable names from forbidden field declarations/serialized keys;
  it still rejects all five prohibited output keys and product dependencies.
  These fixtures are included in the release script.
- The repository isolation/response scan now passes. Static scans do not prove
  absence of every dynamically constructed leak and do not replace API tests.
- The full release script still stops at the existing MoonLeaf numeric-parser
  API incompatibility. Full native `--deny-warn` also reports existing fragile
  asynchronous cleanup patterns. Neither gate is waived by this result.

This acceptance uses the existing AMD64 cluster and previously marked TEST ONLY
videos. It does not claim Spark compatibility, GPU inference, real-model
generation or production network availability. The laboratory forwarding
dependencies and other goal-wide pending acceptance items remain unchanged.
