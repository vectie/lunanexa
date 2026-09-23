# Public UI developer-grant and WebIDE checkpoint — 2026-09-23

This is a bounded browser acceptance record, **not** a claim that the nine-step
undertaking order or ComfyUI generation is complete. The public endpoints were
Operator `http://106.39.18.146:4174/console/` and Enterprise
`http://106.39.18.146:5002/enterprise/`. The test organization was
`organization-403efe8d5588af18406b8123f28a2d70` and the existing test
subject was `subject-b255cb4f829fac5cf22bddba`. No password, handoff code,
contract signature, payment, or exclusive machine assignment is recorded here.

## Buttons and visible feedback

1. Operator policy form: submitted a 45-minute Developer grant
   `grant-ui-b0cc-20260923` for the test workspace user. Its recorded interval
   was `2026-09-23T00:26:25.539Z` to `2026-09-23T01:11:25.539Z`.
2. Operator leases: created `lease-ui-b0cc-20260923` with the same interval,
   one session and one concurrent TextGenerate/VideoGenerate request. Pressed
   **Activate**; the lease list showed **有效**. The Users page showed the grant
   valid and the organization's access bundle **Ready**.
3. Enterprise **WebIDE**: after reload, the progress list showed login,
   master policy and developer workspace access completed, including
   **开发者租约已生效**. It did not show an exclusive GPU delivery.
4. Enterprise selected **ComfyUI** and pressed **打开 ComfyUI** on the old live
   bundle. The browser reached the public workspace gateway but displayed
   “Unable to open this workspace”. Source inspection found the gateway
   requires an exclusive delivery placement; a Developer lease alone is not
   sufficient. This was a real false-ready UI bug.
5. Enterprise selected **MoonDesk / MoonCode** and pressed its open button. The
   browser attempted the `127.0.0.1:4188` handoff, but no local MoonDesk app was
   listening on this test computer. The local address is not a public URL.
6. Fixed and redeployed the enterprise browser bundle. In a fresh public
   Enterprise tab, pressed **WebIDE**, then selected **ComfyUI**. The button is
   now **disabled** and the page explains that an active GPU delivery and
   published template must be selected under **独占资源服务**. The progress step
   now explicitly says the generic WebIDE handoff cannot launch ComfyUI. When
   MoonDesk is selected, the page explains that the local app must be running.

The final enterprise image was pushed to the private registry, pulled back by
containerd with configured registry trust, and the `lunanexa-enterprise`
deployment rolled out successfully at
`moon/lunanexa-web@sha256:e175b18438f755a5e9177a21d28f2f85e9e2da83633b1a0ffc734134c82ab566`.
The public browser then displayed the corrected copy and disabled button.
The enterprise MoonBit JS suite passed 47/47.

## Remaining acceptance gaps

- No exclusive GPU delivery was allocated in this 45-minute grant, as
  explicitly scoped. Therefore ComfyUI start, generation, download, saved-work
  reopen, and operator/customer delivery-state reconciliation remain untested.
- The local MoonDesk executable was not running on the test computer, so its
  120-second handoff was not accepted by a client.
- The undertaking/order chain was not signed or paid. The approved offline
  test waiver is not a real commercial acceptance.
- Public HTTP is the user-approved test setup, not a production-safe way to
  exchange credentials or handoff tokens.
