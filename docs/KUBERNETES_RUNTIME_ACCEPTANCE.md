# Managed Kubernetes runtime acceptance

This checklist qualifies the managed runtime lifecycle on an existing cluster.
It does not qualify an actual model, GPU inference, Spark compatibility, or the
complete customer UI/data-plane flow. Keep those acceptance results separate.

## Deployment prerequisites

- Select the `kubernetes` backend, not the legacy OCI engine backend.
- Use a dedicated runtime namespace with default-deny networking and the scoped
  permissions in `deploy/node-kubernetes-rbac.yaml`.
- Match the real node identity, node name and verified model-cache host path.
- Supply a digest-pinned image and deployment-owned, image-bound Secret refs.
- Keep the Kubernetes token, artifact credentials and signature trust outside
  the serving container. No engine socket is required.
- Determine the controller's actual source route to Pod IPs. Configure only
  the required private source addresses; the adapter renders `/32` ingress.
- Preserve the node certificate, agent state and runtime journal across agent
  upgrades. Correct controller routes only after all managed runtimes drain;
  changing identity or cache boundaries still requires a separate migration.

## Lifecycle checks

1. Submit a signed deployment using actual reported hardware. A CPU protocol
   fixture may reserve a real GPU to exercise DRA allocation, but that is not a
   GPU inference test. Never label the host as a different GPU or CPU architecture.
2. Verify the DRA claim allocation and Pod owner/UID, node, image digest,
   containerd container ID, Ready condition and zero restarts. Verify controller
   Ready independently; a ready Pod alone does not prove controller reachability.
3. From the controller's network location, exercise health, unauthorized
   rejection, job creation, progress, completion, early-result rejection,
   result download/hash verification, deletion and post-delete rejection.
   Use a visibly marked fixture, and remove its temporary downloads afterward.
4. Replace only the node-agent Pod while the runtime remains active. Confirm
   that the runtime Pod UID and container do not change. Repeat the protocol
   checks. This tests supervisor recovery, not provider process restart durability.
5. Delete through the deployment API. Confirm actual Pod, ResourceClaim and
   ResourceClaimTemplate deletion, policy cleanup and release of the allocation;
   an API `Deleted` response alone is insufficient evidence.
6. After full cleanup, correct a controller-source configuration and restart
   the agent using the same journal. Confirm the owner nonce is retained, a new
   deployment receives the intended policy, and no supplemental broad policy
   is needed. Active and partially deleted journals must reject this change.
7. Repeat with a short signed lease. Without manually deleting the workload,
   observe expiry-triggered Pod and claim cleanup. Record the observation time
   and remaining resources. Query the deployment and operation endpoints again:
   a previously Ready deployment must become Degraded when signed assignment or
   heartbeat evidence expires. Promotion must reject stale readiness without
   requiring a prior GET. Only readiness-loss degradation may recover when
   current evidence returns; unrelated degradation must not be silently cleared.
   Separately test controller/API outage behavior;
   normal expiry does not prove fencing under a simultaneous agent/API outage.

## Automatic managed media discovery

Upgrade the controller before the node agent. Legacy heartbeats without
`runtime_endpoints` retain their original v1 MAC; endpoint-bearing heartbeats
authenticate the complete endpoint metadata. A restored agent must inspect
actual resources before reporting Ready or an endpoint again.

For a Kubernetes media template profile, set `origin` to the empty string and
add an administrator-owned, per-node route boundary, for example:

```json
"runtime_route": { "network": "10.42.1.0", "prefix_length": 24, "port": 5885 }
```

Use the actual node's Pod network, not this example blindly. Public addresses,
URL-shaped addresses, noncanonical networks, and a simultaneous static origin
are rejected. This policy authorizes discovery; it does not replace Kubernetes
NetworkPolicy or provider authentication. Keep bearer credentials in protected
deployment configuration, never in heartbeat data or customer requests.

Only a fresh endpoint matching the current signed assignment, deployment,
generation, controller epoch, image and artifact is routable. Independent,
read-only resource probes refresh observations; an observation expires after
15 seconds even if the node keeps sending heartbeats. Missing resources,
foreign UIDs, unavailable probes and expired leases fail closed.

Binding identity includes a digest of Pod UID and container ID. Container
restarts change that identity even when the Pod IP stays the same. Old jobs
must not transparently migrate to the replacement instance. This prevents
misrouting; it does **not** establish provider-side durable job recovery.
Test both new-job routing after recreation and rejection of old-instance jobs.

### Discovery implementation validation (2026-09-15)

- Local native tests: 76/76 across contracts, node, Kubernetes supervisor,
  node executable and integration fixtures. The corresponding targeted check
  passed with warnings denied after excluding existing warning 92.
- Linux native combination: 218/218 across contracts, controller, node,
  Kubernetes supervisor, node executable, API, integration fixtures and media
  jobs/runtime. Existing warnings 92 and 20 were excluded; this is not a
  warning-clean whole-repository release gate. The Linux dependency staging
  retains the previously documented Moonleaf compatibility adjustments.
- Regression coverage includes legacy heartbeat JSON/MAC compatibility,
  cross-node/assignment rejection, stale observations, route network/port
  boundaries, duplicate instances, unchanged-IP container replacement,
  read-only probes, foreign UID rejection and missing-resource failure.
- `scripts/check-isolation.sh` still fails on the pre-existing literal
  `moongate` network-policy selector in `workspace/webide/host/manifests.mbt`.
  Do not report that scan, or the full release gate, as passed.
- These results qualify code paths and simulated provider behavior. The new
  discovery implementation still needs controller-first rollout and live
  runtime recreation plus browser-to-provider acceptance. No real Spark or
  model inference claim follows from these tests.

## Remaining customer-flow evidence

The checks above do not substitute for ComfyUI/WebIDE login, tenant isolation,
workspace persistence, MoonGate routing, platform idempotency/quotas/billing,
browser-generated downloads or durable media-job recovery. In particular,
`RuntimeInstance.container_address` being available to the node adapter does
not itself establish a controller routing binding. Validate the deployed
discovery/binding path across runtime recreation before claiming one-click
delivery is complete.
