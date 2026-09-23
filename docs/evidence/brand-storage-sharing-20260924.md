# Brand, storage, and enterprise model sharing — 2026-09-24

## Shipped behavior

- The public `/docs/` and `/user/` sites use the exact brand
  `能源谷“创未来”生态街区` in their visible chrome and document titles. The `/mana/`
  title and chrome now match. Protocol identifiers such as
  `X-LunaNexa-Organization` remain unchanged.
- The Operator Nodes page has a separate `management-storage` row for the
  model-data filesystem mounted at `/data/models`. The controller samples
  capacity, used/available bytes, inode headroom, and sample time directly
  with `statvfs`; this is not counted as a GPU node. On the management host,
  `/data/models` resolves to `/data` on `/dev/mapper/mecvgdata-data` (ext4),
  not the host's root filesystem.
- A ready `ModelApi` delivery remains owned by its launcher and existing GPU
  reservation. Authorized colleagues in the same tenant and organization can
  connect separate WebIDE sessions or issue personal delivery API keys without
  receiving the launcher's secret. The controller checks each member's own
  Developer membership and capability lease as well as the launcher's live
  authority, reservation, and delivery state. MoonGate, when configured, only
  forwards the individual bearer; it is not the source of authorization.

## Verification

- Native MoonBit suite: 1225/1225; focused sharing integration: 5/5.
- Docs-site Node tests: 35/35. Final brand/UI JavaScript tests: 148/148.
- Browser checks on the public `:8443` entrance confirmed the `/mana/` Nodes
  storage row and exact brand on `/mana/`, `/user/`, and `/docs/`. At the time of
  sampling, Operator displayed 7309.4 GiB total, 2388.3 GiB used, 4613.7 GiB
  free, and 486738851 / 486744064 available/total inodes. All four Spark
  compute nodes remained separate rows.
- The controller, Operator, enterprise portal, and public docs gateway all
  rolled out 1/1 after pinning to these in-cluster registry digests:

  | Deployment | OCI digest |
  | --- | --- |
  | `lunanexa-control` | `moon/lunanexa-control@sha256:92944fcc06297dc9031eb4c91a87b13b7505ed91bec683aae2b3922ca18b5829` |
  | `lunanexa-console` | `moon/lunanexa-web@sha256:ed33ad46093d905a1b72b80b51cc2877f5dea2a7b3f860325466e7e0fd5a4741` |
  | `lunanexa-enterprise` | `moon/lunanexa-web@sha256:187ab70281f41627a85a61e363e6c4927c05baae1d3a2c1c420c71a6ba26de7f` |
  | `lunanexa-coursebook-public-gateway` | `moon/lunanexa-coursebook@sha256:3a390d63d41d66f1690b928e1228a776629561f16089e96d5cfa5824820d1a28` |

## Acceptance boundary

The live test enterprise used in the browser check had no ready `ModelApi`
delivery or effective exclusive GPU authorization. Therefore this deployment
has **not** completed a physical two-user, two-WebIDE inference call through
one live model service. The integration test proves credential separation,
same-organization access, cross-organization denial, per-member revocation,
source-owner revocation, and service-stop denial in the controller. A physical
acceptance still requires launching a compatible model for that enterprise on
an authorized GPU node, then making one call from each of two member WebIDEs
and comparing their distinct usage receipts. No GPU service was started merely
to claim this evidence.

Port `8443` was verified from the external test browser. Local port `443` on
the management host passed its TLS route check; an external Mac-side request
to `443` failed during the TLS handshake in this run, so external `443` reachability
is not claimed here.
