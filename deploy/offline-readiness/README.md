# Offline commerce readiness evidence

`capabilities.json` is the input to `cmd/offline-readiness`, which signs it into the
document the control plane loads from `LUNANEXA_OFFLINE_COMMERCE_READINESS_PATH`
and verifies with `LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET`. See
`docs/OFFLINE_COMMERCE.md` for the gate and `docs/UNDERTAKING_TWO_SIDED_RECONCILIATION_20260922.md`
§12.20 for the per-item status this file was derived from.

The file is committed on purpose: an attestation should be reviewable in git, not
live only in a cluster secret.

## Why each entry says what it says

**Declared true — the artifact exists and was checked.**

| capability | basis |
|---|---|
| `MachineCallbackIdentity` | Three distinct callback identities exist in `lunanexa-control-credentials`: `artifact-worker-callback-token`, `artifact-scanner-callback-token`, `entitlement-authority-callback-token`. Each is 64 bytes; all three are pairwise distinct, distinct from every human/inference token in that secret (all 21 values are unique), and all are ≥32 bytes, which is what `docs/OFFLINE_COMMERCE.md` requires. |
| `EntitlementAuthority` | The third, non-reusable identity `entitlement-authority-callback-token` exists (64 bytes). Activation and revocation are gated on it, so no order is fulfilled until this typed authority confirms. |
| `FinanceLegalPolicy` | The deployed policy is `hybrid_offline_policy()` in `api/offline_commercial_http.mbt`: executed agreement, payment, invoice-before-fulfillment, identity verification and internal approval are all required and cannot be weakened by a customer request. Approved by the platform operator on 2026-09-22. **This is an operator approval recorded on the approver's own authority — not a third-party audit.** |

**Pending production attestation — implementation and isolated acceptance are not
the same as a completed production rollout.** The dated four-capability evidence
package is [`docs/evidence/offline-ofl-v2-20260922/README.md`](../../docs/evidence/offline-ofl-v2-20260922/README.md).
The historical reconciliation transcript is not the current implementation inventory.

| capability | what is missing |
|---|---|
| `ApprovedLegalTemplates` | Real immutable `zh-CN` sources include original lease/undertaking and the new `youthpolicy-device-undertaking-ofl-v2`. Technical text/field preservation and visual checks are retained. The platform owner explicitly withdrew the bilingual prerequisite on 2026-09-22: no English counterpart is required for this Chinese-only profile. Approval still binds the exact scope/version/source/fillable hashes and attributable platform approval source. No lawyer's name or third-party legal certification is inferred. Legacy templates retain their own font/render acceptance requirements. |
| `ObjectStorage` | Production SeaweedFS 4.47 serves standard S3 behind private certificate-verified TLS on a dedicated 40 GiB PVC. Adapter credentials are bucket-scoped; the TLS frontend denies delete, list/admin and query operations. Volume-data encryption, versioning and GOVERNANCE 30-day default retention are enabled and read back from S3. Both templates passed scanned conditional storage and exact SHA-256 readback. Production cold restart and a cold archive restored to an independent PVC preserved both template hashes, version IDs and retention; deleting a retained test version on the restored copy returned AccessDenied. Other-bucket access returned 403. Private cold archive remains; temporary restored resources were removed. This single-management-node profile is not HA/offsite DR; chunk keys live in filer metadata, not a separate key-management system. See `docs/evidence/offline-transfer-production-20260922.json`. |
| `MalwareScanner` | Production native adapter invokes real ClamAV 1.4.3 with official signatures, freshness, encryption/macro and size-limit alerts, plus qpdf/OOXML active-content checks. Official daily 28131, main 63 and bytecode 339 were populated on 2026-09-22. Production DOCX/XLSX/PDF scans and S3 roundtrip passed; standard EICAR was detected with exit 1 and empty-database/freshness failure returned exit 2, not clean. Production controller-issued upload/callback acceptance is still a separate end-to-end gate. No isolated result is substituted for production evidence. |
| `OoxmlWorker` | `cmd/offline-artifact-worker` exists as source, but `images/Containerfile.control` builds only `cmd/control/control.exe`, so no image contains the worker. `deploy/offline-artifact-worker-job.yaml` references `${CONTROLLER_IMAGE_DIGEST}` expecting a binary that is not there, and its job needs a `lunanexa-offline-artifact-worker` secret (key `render-evidence-secret`) that does not exist. Nothing invokes the job either — the external dispatcher is absent. |
| `PdfRenderer` | Native MoonLeaf rendering is implemented. The real OFL-v2 undertaking passes four-page rendering, per-page raster evidence, finalization, scanned S3 roundtrip and callback recovery in an isolated Linux cluster run; the PDF equals the macOS output byte for byte. Retained technical baselines do not yet attest to a production image digest, production controller order or all legacy templates. Another office engine was used only as independent DOCX QA, not rebranded as MoonLeaf. |
| `SpreadsheetFormulaEngine` | Implemented bounded native XLSX recalculation plus error scanning and normalized rendered-value proof. Current native suites: MoonLeaf XLSX 38/38 and worker 14/14. The real `49*7=343` synthetic visual is retained; unsupported formulas fail closed. Production `quote-v1` still needs its own complete order/worker/render rehearsal and agreement with the authoritative integer-money ledger; full Excel fidelity is not claimed. |
| `CjkFonts` | New OFL-v2 uses genuine Noto Sans SC Regular, official pinned source, retained SIL OFL 1.1 and deterministic static-font digest. The production `lunanexa-offline-approved-fonts` PVC is populated and all three font/license/config files were hash-verified. No proprietary aliases or private-font binaries are part of the default bundle. Old v1 family requirements remain separate; this evidence is scoped to the new named profile. |

## Not capabilities, but still blocking

The gate also reports adapter and evidence blockers that no attestation can clear —
`docs/OFFLINE_COMMERCE.md`: *"Signed evidence or a deployment boolean alone cannot
make these adapters ready."* As of 2026-09-22 these remain:

- `ReadinessTransferAdapterUnavailable` — native adapter and private TLS service now run at
  `https://lunanexa-offline-transfer.lunanexa.svc:8443/v1/offline-transfers`.
  The dedicated `lunanexa-offline-transfer` Secret holds the adapter/session keys;
  the combined-CA ConfigMap preserves the registry trust bundle. Controller rollout
  must consume these references and real session/callback acceptance must pass.
  The public identity edge forwards only exact capability GET/PUT routes, not internal
  object APIs; general auth routes and outer HTTP policy are unchanged.
- `ReadinessArtifactDispatcherHeartbeatStale` / `…SuccessStale` — no artifact dispatcher runs anywhere;
- `ReadinessEntitlementDispatcherHeartbeatStale` / `…SuccessStale` — no entitlement dispatcher runs anywhere.

## Regenerating the document

```sh
moon run cmd/offline-readiness --target native -- \
  --input deploy/offline-readiness/capabilities.json \
  --output /tmp/readiness.json \
  --secret "$LUNANEXA_OFFLINE_COMMERCE_READINESS_SECRET"
```

The tool refuses to sign a set that is not exactly the ten capabilities with unique
valid `evidence_ref` values, or a window longer than 31 days, so it cannot emit a
document the control plane would reject at startup.
