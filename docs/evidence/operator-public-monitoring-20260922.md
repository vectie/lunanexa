# Public Operator and Spark telemetry correction

Scope: the explicitly authorized public Operator entry at
`http://106.39.18.146:4174/console/`. Enterprise and workbench authentication
are not opened. An existing enterprise proxy authority leak was corrected (see
verification below). This is intentionally public administrator access, not an
authenticated personal account. Anyone reaching this port receives the proxy's
operator authority. HTTP remains unencrypted; this is not a production security
acceptance. No account password is embedded in the browser bundle.

## Corrections

- Render the exact public HTTP origin and operator-open meta into the deployed
  console bundle. Keep source defaults closed. The existing same-origin proxy
  translates the `deployment-open` marker to its server-held operator token.
- Show loading instead of briefly displaying a password form on open deployments.
- Reject node measurements older than 60 seconds, over five seconds in the
  future, or scoped to an individual workload. Missing GPU sensors are not zero.
- Preserve tenths of a percent for CPU/GPU and fractional watts for power.
- Present GB10 memory as the shared CPU/GPU pool, in GiB, with total, used and
  available values. `MemAvailable` is not `MemFree`, and neither is per-model
  GPU allocation. GB10's independent `nvidia-smi` VRAM fields report N/A.
- A missing controller assignment does not prove a machine is idle. A lease
  projection that has not been read does not prove the machine is unassigned.
- Registry approval counts are not running model counts. Node heartbeats are
  not proof that inference endpoints work. The logical topology does not claim
  that an HTTP browser connection is HTTPS.
- Load actual alert records before displaying the overview's alert count.
  Unloaded audit history is not zero recent changes.
- Collapse the topology by default to prioritize live node data; align all five
  sensor cards and wrap long readiness explanations.

## On-machine cross-check

On 2026-09-22 around 20:48 CST, SSH reads from all four Sparks reported
`MemTotal` approximately 127,598,768 KiB (121.7 GiB available to Linux).
`MemAvailable` was approximately 14,104,688 / 21,490,444 / 9,761,468 /
11,822,832 KiB on 25e2 / 3782 / 57f5 / 368c. Values change with workload.
Direct NVIDIA sensor reads reported 0% GPU use, 47–49°C, and approximately
10.9–13.2 W. The controller telemetry agreed within normal sampling changes.
Memory comparisons must use the same pool and account for asynchronous reads.

## Deployment and rollback

Use `scripts/build-browser-bundles.sh`, then
`scripts/deploy/render-public-http-origin.py` with both console origins set to
`http://106.39.18.146:4174`. Package only the console via
`scripts/package-browser-layer.mbtx`; it preserves the existing image's fonts,
PDF previews, and other applications. The additive layer must retain world
traversal permissions on `/usr` and its descendants. The first packaging attempt
failed that check and did not replace the healthy replica; it was rolled back.
Use digest-pinned `scripts/deploy-offline-web.mbtx --console-only`, retaining its
private before-deployment JSON for rollback. Never print proxy configuration or
secrets as diagnostic output.

The previous console image for rollback is
`sha256:eeb30ffef8a2dc18364a796671488cece2f86636eb0d03a1f85b10b4719b55e3`.
No Spark workload, model placement, node agent, contract, or financial state was
changed by this work. Full undertaking-chain UI acceptance remains a separate
task; the monitoring screenshots are not substitute evidence for that flow.

## Final verification

- Console-only deployed image:
  `sha256:40831561cd69be712cd9dd8c4646ebf913c28b40e65138b750bf06ca87882d3c`.
- Public console JavaScript matches the fresh build:
  `ac8af5c5dcdb61cf162fd2be1943ba5514ae1b774551db02061b9822f39ea10e`.
- Browser reload entered the public Operator without typing credentials; initial
  state showed loading, then actual four-node inventory. Node details showed
  121.7 GiB total shared memory, approximately 108.1 GiB used / 13.6 GiB available
  on 25e2, 48°C and 11.44 W. CPU and memory values changed across polling cycles.
- Desktop layout: topology collapsed, five sensor cards in one row. At a 390px
  responsive viewport the document and scroll widths were both 390px, with 324px
  sensor cards contained at x=33. Viewport override was reset afterwards.
- 156 UI/console JS tests passed; targeted JS checks passed. Native warning-denying
  check and all 1,141 native tests passed. Generated interface change is the
  intended `NodeRow.power_watts: Int -> Double` precision correction.
- Found an older enterprise port 5002 proxy fallback to operator authority.
  `restrict-operator-open-boundary.mbtx` backed up the configuration privately
  and removed that fallback only from the enterprise server. After ConfigMap
  propagation, syntax check and graceful nginx reload, anonymous enterprise
  `/v1/nodes` and the `deployment-open` marker both returned 401; Operator
  `/v1/nodes` remained 200. Public operator authority does not apply to enterprise.
- Production-readiness blockers are still displayed truthfully. This change
  does not assert that the separate contract/provider acceptance suite passed.
