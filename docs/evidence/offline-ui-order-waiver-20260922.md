# Approval: current public-UI undertaking test order

On 2026-09-22 the platform owner explicitly answered **“扩展到本次测试订单”**
to the request to extend the offline technical exemption to the order ending
`b0cc`, for time-limited IaaS/PaaS/MaaS acceptance, without signing or paying,
while retaining resource authorization, tenant isolation and automatic expiry.

Exact scope:

- Order: `offline-order-4e349988-6b8b-4f80-9492-9dab2b40b0cc`
- Organization: `organization-403efe8d5588af18406b8123f28a2d70`
- Tenant: `tenant-403efe8d5588af18406b8123f28a2d70`
- Purchaser: `subject-b255cb4f829fac5cf22bddba`
- Packet: `contract-1bd438a8-de6c-418f-aaac-3ebd6da48c8a`

This is a technical authorization record, **not** a signature, payment receipt,
invoice, commercial KYC result or legal opinion. The original 49 CNY draft quote
is preserved; it must not be represented as funds received. The generated
undertaking remains unsigned and must not be uploaded as an executed scan.

The extension must bind the entire immutable quote and the chosen entitlement
kind. A waiver binds one existing administrator-approved resource, cannot be
moved to another target and lasts at most one hour. A draft's 30-day expiry must
be shortened rather than used as a resource lifetime. Existing actual account
authentication and an attributable operator session remain required. Removal or
expiry of deployment permission must not prevent resource revocation/cleanup.

## Status

Implementation phase gate: native check passed; 1149/1149 native tests,
69/69 console, 21/21 offline-commerce UI and 32/32 enterprise JavaScript
tests passed. These are automated checks, not live business acceptance.

The owner subsequently confirmed creation and activation of a maximum 45-minute
Developer workspace for this exact customer/order, without platform-admin access
or an exclusive machine. Public UI preparation, waiver review and fulfillment
completed. Both portals display test access active with expiry
**2026-09-22T16:00:09Z (2026-09-23 00:00:09 Asia/Shanghai)**.
The workspace is
`technical-lease-8ed55f17c16a17288af78aa04b56c5d5ba2989d4b709a02a3308df76843da4df`.
Unsigned/unpaid/non-commercial classification is preserved. No lifetime extension
was requested or applied. Actual WebIDE launch remains blocked by the deployed
localhost destination; provisioning success does not prove service usability.
All business acceptance actions must be performed through the public browser UI.
See `undertaking-public-ui-reconciliation-20260922.md` for observed button actions
and results; test counts alone are not live end-to-end evidence.
