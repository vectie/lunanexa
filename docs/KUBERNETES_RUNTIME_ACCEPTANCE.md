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

## Remaining customer-flow evidence

The checks above do not substitute for ComfyUI/WebIDE login, tenant isolation,
workspace persistence, MoonGate routing, platform idempotency/quotas/billing,
browser-generated downloads or durable media-job recovery. In particular,
`RuntimeInstance.container_address` being available to the node adapter does
not itself establish a controller routing binding. Validate the deployed
discovery/binding path across runtime recreation before claiming one-click
delivery is complete.
