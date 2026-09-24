# Personal MoonDesk workspace isolation

## Incident and boundary

The former `desktop-workspace` launch points at `http://127.0.0.1:4188`.
That address is a process on the operator's computer, started with one fixed
`/Users/kq/moonsuite` root. Switching the LunaNexa portal account changes the
model handoff, not MoonDesk's data root. Existing chats were therefore visible
to the next account that opened that local application. They are retained in
place, not migrated into another person's workspace or deleted.

The public portal must not call that local process a personal WebIDE. It now
issues `desktop-workspace` handoffs only to the hosted, account-bound gateway.
The API continues to reject a loopback-only launch URI as
`HostedWorkspaceRequired`.

## Target runtime

- One authenticated gateway session binds exactly one tenant, subject,
  organization, project, and `desktop-workspace` client.
- The gateway creates one Deployment and one PVC for that identity. A second
  subject in the same organization gets different resource names and a
  different PVC. A renewed grant for the same identity reuses its own PVC.
- The MoonDesk application runs only inside that Deployment, with its saved
  root mounted at `/workspace`. It must not mount a host-wide MoonSuite home,
  another user's PVC, the API credential Secret, or a GPU node's model files.
- MoonClaw and MoonGate must likewise be per-workspace processes with
  per-workspace configuration. The enterprise GLM endpoint is shared, but
  provider credentials and chat/session state are not.
- MoonDesk and MoonClaw persist user work under the identity-specific
  `/workspace` PVC. The private execution-control file is copied into a
  separate per-pod `emptyDir`; it is neither a user file nor a shared volume.
- This per-active-workspace MoonGate is an implementation boundary, not a
  product rule requiring one gateway forever. A central MoonGate may replace
  it only after provider choice, authorization, usage attribution, and
  revocation are evaluated from each request's subject and organization,
  rather than a process-global active provider.
- Browser traffic goes through the lease-aware WebIDE gateway. It must check
  the current grant on each HTTP and WebSocket operation and never expose a
  bare MoonDesk port publicly.
- Termination closes browser access and scales down the pod, retaining only
  that subject's PVC for reopen under the same identity. Revocation never
  switches the PVC into another account's pod.

## Live acceptance snapshot (2026-09-24)

The hosted catalog and two account-bound gateways are deployed. The gateway
at public port 5002 is bound to limuheng; port 5003 is bound to wangzhixiang.
Unauthenticated requests to either root return 401. The personal MoonDesk pod
and its 20 GiB RWX PVC are keyed from the subject/organization/project grant,
not from the browser or the shared GLM model. The per-pod MoonGate and MoonClaw
run with the application; `shareProcessNamespace` lets MoonDesk verify its
companion MoonClaw process without exposing another user's process namespace.
All companion listeners remain on pod loopback. Their probes execute inside
the pod because kubelet HTTP probes cannot reach those loopback listeners.

The wangzhixiang browser acceptance used the public `/user` portal, clicked
WebIDE then the default MoonDesk choice, and followed the one-time handoff to
port 5003. Code selected `moongate/glm-5.3.flash`; two consecutive prompts
received GLM answers, the composer remained usable, and the same two-turn
history reappeared after the gateway and workspace were rebuilt. The public
ComfyUI trial on port 5005 remained reachable. `/user`, `/mana`, and `/docs`
on the HTTPS edge also returned 200 during the check.

The shared GLM upstream is the `glm53-exl3` Kubernetes Service, currently
`10.43.242.46:8899`, forwarding to Spark 192.168.2.178:8888. The host
MoonGate provider had retained a removed `127.0.0.1:4174/glm53/v1` URL; its
service environment and persisted `codex/lunanexa` provider route were both
updated to the Service IP. If that Service is recreated with a new ClusterIP,
update both records together, then test an actual completion—not just the
model catalog. The manifest pins the gateway/model-proxy image by registry
digest; no model weights are packaged in it.

The second-account UI proof is still outstanding: open limuheng's workspace
through the portal, create a chat and file, verify wangzhixiang sees neither,
and repeat after expiry/revocation. Port 5002 being healthy and account-bound
does not by itself prove the complete two-account isolation workflow.

Do not restore the old `127.0.0.1:4188` catalog entry as the enterprise
one-click path. Local MoonDesk remains a separate, explicitly local product
profile and cannot prove hosted multi-user isolation.
