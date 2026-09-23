# Enterprise model-service sharing

A ready `ModelApi` delivery is one physical model service owned by its creator's
resource reservation. Colleagues in the same tenant and organization can use
that service without sharing the creator's API secret or WebIDE.

## Connection path

1. The enterprise portal lists ready deliveries for the selected organization.
   Only the creator sees retry/stop controls. A ready `ModelApi` delivery offers
   **Connect to my WebIDE** to every authorized member.
2. The member selects the same organization and project. The controller checks
   Developer membership, an active personal workspace lease with the model's
   capability, the service owner's grant, the active node reservation, and the
   exact approved model selector. It issues a one-time, member-specific handoff
   bound to the delivery ID.
3. The WebIDE redeems the code and receives its own scoped credential. Its own
   workspace, files, and browser session remain separate from other members.
   The workspace model proxy forwards that credential to MoonGate; MoonGate
   transports the member's bearer token to LunaNexa, which performs the live
   delivery, tenant, organization, project, capability, quota, and lease checks.
4. Each member can also create a one-time delivery API key for API use. That key
   is scoped to the same service but has an independent identity and usage
   counter. Revoking one member's grant denies only that member. Stopping the
   delivery or revoking the creator's resource authority denies everyone.

This is **shared inference, not shared compute ownership**. Joining a service
does not create another GPU reservation or another model replica. There is no
implicit cross-enterprise access and no fallback to an unbound model route when
the delivery or its authorization ends.

## Storage observation

The operator Nodes page separately displays the configured model-storage mount
capacity, available space, inode headroom, and Beijing-time sample timestamp.
`GET /v1/storage-nodes` requires operator authority. The controller measures its
read-only mounted host path directly with `statvfs`; it does not count that
storage row as a GPU node. A missing mount is shown as an unavailable sample,
not as zero capacity. Configure `LUNANEXA_STORAGE_MONITOR_PATH` and optionally
`LUNANEXA_STORAGE_NODE_ID` on the controller.
