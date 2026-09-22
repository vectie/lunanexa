# Offline pipeline implementation — 2026-09-22

This is an implementation and verification record, not a production acceptance
certificate. A running dispatcher, synthetic receipt or administrator approval
does not prove a PDF, scan, storage transfer or machine provisioning succeeded.

## Executable components

- `cmd/offline-dispatcher`: separate artifact and entitlement processes with
  durable work/result journals, independent authenticated heartbeats and bounded
  retries. Production document generation uses isolated Kubernetes Jobs;
  a subprocess backend is explicitly development-only.
- `cmd/offline-artifact-worker`: prepares exact DOCX/XLSX edits and validates
  source-bound render evidence before finalizing a result.
- `cmd/offline-pdf-renderer`: MoonLeaf PDF generation and retained page images;
  unsupported layout and unapproved/missing font inputs fail closed.
- `cmd/offline-transfer`: immutable S3 writes with read-back verification,
  scoped browser transfers, real malware/document scanning and a durable
  completion outbox. Standard storage and scanners remain external services.
- MoonLeaf `xlsx`: bounded recalculation with references, supported arithmetic,
  aggregate functions and cycle/error rejection; cached values alone are not
  verification. The executable quote template is
  `assets/contracts/offline/quote-v1/quote.xlsx`.

The new MoonLeaf renderer and spreadsheet code must be built from the same
reviewed source as LunaNexa. The local `moon.work` connects sibling checkouts;
the old registry release alone does not contain these APIs. Stage both sources
for reproducible builds, or publish and pin a reviewed MoonLeaf release before
switching to a single-repository build.

## Control-plane integration

Machine-only endpoints use the corresponding existing callback identity, not
the human operator token:

| Endpoint suffix under `/v1/offline-commerce/operator` | Purpose |
| --- | --- |
| `/dispatcher-heartbeat` | Observe liveness without claiming or completing work |
| `/generation-plan` | Resolve only persisted, claimed work into immutable template and field inputs |
| `/entitlement-execute` | Execute the real existing workspace, exclusive-node or capacity authority; pending provisioning is not success |

Generation is two-stage: discover immutable template metadata, then resolve the
exact markers extracted from digest-verified bytes. Legal values come from the
order-linked document packet, with organization, tenant, subject and template
bindings checked. Missing fields produce a conflict, never invented legal text.
The first completed plan is frozen in offline snapshot v6 and survives restart;
editing a document thereafter requires a new generation request. Existing
snapshot versions migrate without losing historical orders. Operational
snapshots omit the retained field values.

Quotation admission checks legal/template policy, not unrelated rendering or
storage health. Each later operation checks its own capabilities and live
dependencies. Historical business successes remain diagnostics, not prerequisites
for the first job or reasons to reject an idle platform after 24 hours. Genuine
terminal evidence remains required by the order state machine.

Authenticated exact transfer-completion replay acknowledges the existing result
after a lost response, including after expiry. Different bytes, digest, media,
receipt or token are rejected; this never reissues a consumed browser capability.
Typed transfer conflicts remain conflicts instead of becoming generic 503s.
Browser transfer capabilities may use a validated same-origin
`/v1/offline-transfers/<id>` path while the controller uses its private TLS
adapter endpoint. This does not require switching the outer website to TLS or
publishing an internal service hostname to customers.
Operator attribution uses the verified token/session identity, not a supplied
subject header or a shared hard-coded operator name.

## Deployment and acceptance boundaries

Verification checkpoint before the new OFL template integration:

- LunaNexa native suite with `--deny-warn`: 1111/1111 passed.
- MoonLeaf native suite with `--deny-warn`: 122/122 passed.
- Offline commerce UI JavaScript suite: 19/19 passed.
- Existing font-bundle and offline deployment invariant scripts passed.
- Isolated management-node real S3/ClamAV and rendering tests are recorded in
  `../deploy/offline-transfer/VERIFICATION_20260922.md`. The integrated artifact
  probe used real worker/render/storage components but a simulated controller
  plan/callback boundary; it is not an online customer acceptance test.

These totals are a checkpoint, not a claim that later template edits have
already passed or that optional infrastructure-dependent probes all ran.

After integrating the OFL v2 template, its version-bound quote routing and
absolute runtime asset lookup, the native suite passed 1120/1120 with
`--deny-warn`. The contract/portal JavaScript subset passed 60/60. Subsequent
real CJK PDF transfer testing exposed an active-content scanner false positive
and Linux regular-file I/O errors; these were fixed and separately revalidated.
The final OFL v2 Linux probe completed prepare, four-page PDF rendering,
finalization, real scanning, S3 write/read verification and recovery from an
intentional callback 503 without rerendering (two plan calls, two callbacks).
The 10,824,742-byte PDF SHA-256 is
`7f47f4fec8dba952bc9dc700e7a5bebb7c42946b2780364c26a3529162740b19`,
identical to the locally visually reviewed output. The controller plan/callback
boundary was still a fixture, not a production customer order. See the OFL v2
template README and transfer verification record for retained evidence.

The final default browser package was rebuilt into a fresh directory and
contains only the OFL font, its license/configuration and both template preview
versions. Copying private fonts is opt-in with a local license-evidence input;
stale private binaries in an output directory cause the build to fail.

Deploy these management services outside managed GPU runtimes. See
`OFFLINE_DISPATCHERS.md`, `../deploy/offline-transfer/README.md` and the worker
image instructions. Use reviewed image digests and secret references, private
object ingress, persistent journals and explicit retention/backups.

Required real checks include actual template → PDF/page images → object store →
browser download, actual clean/malicious document scanning, actual entitlement
activation and reversal, and restart after side effects but before callbacks.
Unit tests and isolated fixtures must be labelled separately from this evidence.

The original template's prescribed FangSong_GB2312, FZXiaoBiaoSong-B05S and SimHei
fonts remain inputs for that original version, not platform-wide prerequisites.
The user selected a separately versioned open-font template on 2026-09-22.
Ubuntu distributes `fonts-noto-cjk`, and upstream Noto fonts use the SIL Open
Font License. The new profile must name its actual fonts, retain their license
and provenance, preserve document text and pass its own pagination review.
It must not relabel a substitute as a proprietary font or retroactively change
an existing order's template/digest. See the [Ubuntu package](https://packages.ubuntu.com/noble/fonts-noto-cjk)
and [upstream license information](https://notofonts.github.io/noto-docs/website/homepage/).
An English translation or engineering quote template does not constitute legal
approval. Readiness remains scoped to the verified template/profile and actual
service evidence, rather than inferred from installation alone.

None of these commercial-document prerequisites are added to private-cloud
administrator-granted WebIDE/ComfyUI admission. Traditional rental contracts,
undertaking admission and IaaS/PaaS/MaaS delivery boundaries remain distinct.
