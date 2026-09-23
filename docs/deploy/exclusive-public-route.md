# Exclusive ComfyUI public route

The accepted test address is `http://106.39.18.146:5000`. The external router
must forward TCP 5000 to management node `192.168.2.175:5000`. The Kubernetes
`comfyui-public` LoadBalancer exposes port 5000 and maps it to node port 30918.
This HTTP address is only for the approved acceptance environment.

Traffic at `/v1` passes through the internal gateway to the existing MoonGate
upstream at `192.168.2.175:5889`. Other paths go to the WebIDE gateway, which
binds the browser session to a client handoff and workspace. The workspace's
model proxy still calls the private TLS MoonGate origin on port 5883. Its
configuration never contains the public HTTP URL or browser credentials.

The controller accepts that one HTTP API origin only when
`LUNANEXA_CLIENT_HTTP_API_ORIGINS_JSON` includes the exact
`http://106.39.18.146:5000` origin. The launch URL uses the separate
`LUNANEXA_CLIENT_HTTP_LAUNCH_ORIGINS_JSON` list. The public URL in the catalog
is `http://106.39.18.146:5000/v1`; the gateway's `public_api_base_url` must
match it exactly when redeeming a handoff.

## Prepare, publish, restore

On the management node, run the MoonBit preparation script with the management
kubeconfig, a **new private directory**, and four pinned image references:

```text
moon run scripts/prepare-exclusive-comfyui.mbtx KUBECONFIG PRIVATE_DIRECTORY CONTROL_AMD64_IMAGE GATEWAY_AMD64_IMAGE PROXY_ARM64_IMAGE COMFY_ARM64_IMAGE
```

Preparation reads the current Deployments, ConfigMaps, public Service and both
NetworkPolicies. It checks the namespace default-deny policy, stores unmodified
snapshots under `before/`, and writes candidate manifests under `prepared/`.
It also creates one random observation token in two private Secret manifests.
The directory must remain mode 0700 and the files mode 0600; do not commit or
print them. Preparation changes no Kubernetes resources.

Once all four images are available and the combined source gate passes, use:

```text
moon run scripts/rollout-exclusive-comfyui.mbtx apply KUBECONFIG PRIVATE_DIRECTORY
```

The rollout installs the two Secrets and WebIDE gateway Service, updates the
two scoped NetworkPolicies and internal gateway route, waits for the WebIDE
gateway and controller, then switches the public Service last. A failed step
triggers restore from `before/`. To restore manually:

```text
moon run scripts/rollout-exclusive-comfyui.mbtx rollback KUBECONFIG PRIVATE_DIRECTORY
```

Restoration first returns public port 5000 to its previous Service target. It
then restores the controller, gateway, internal route and the two original
NetworkPolicies, and removes the new Service and Secrets only when their
ownership labels match this rollout. Review concurrent changes before a late
manual restore, because the saved snapshots represent the preparation time.

Network isolation remains deny by default. The policy additions allow only
external traffic to the internal gateway's public port 5000, traffic from that
gateway to the WebIDE gateway's port 8082, and traffic from the WebIDE gateway
back to the existing controller and private MoonGate routes. The script does
not change the namespace default-deny policy.

Public browser acceptance must still verify `/connect`, the tenant-bound
workspace, `/v1` with an issued test credential, file persistence and model
generation. An internal rollout status is not evidence that external NAT or
the complete user flow works.
