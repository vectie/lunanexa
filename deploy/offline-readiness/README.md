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

**Declared false — there is nothing yet to approve.**

| capability | what is missing |
|---|---|
| `ApprovedLegalTemplates` | The requirement is *bilingual* legal DOCX templates. Both templates in the repository are `locale: "zh-CN"` only — `assets/contracts/youthpolicy/v1/NVIDIA-DGX-Spark-remote-lease-revised.docx` and `assets/contracts/youthpolicy/undertaking-v1/device-use-undertaking.docx`. Their hashes and page geometry are recorded in `contractdoc/`, so the *templates* are real; what does not exist is a bilingual pair, plus the named legal owner. `assets/contracts/youthpolicy/undertaking-v1/README.md` also states that preserving the source wording "is not a platform certification of enforceability". |
| `ObjectStorage` | No S3-compatible storage is configured and there is no client for one in the tree. `docs/OFFLINE_COMMERCE.md` routes object traffic through the transfer adapter, which is itself absent (see below). |
| `MalwareScanner` | No scanner service and no scanner client. `commercial/offline` only knows the `MalwareScanner` capability code and carries a `scan_receipt` field; nothing produces one. |
| `OoxmlWorker` | `cmd/offline-artifact-worker` exists as source, but `images/Containerfile.control` builds only `cmd/control/control.exe`, so no image contains the worker. `deploy/offline-artifact-worker-job.yaml` references `${CONTROLLER_IMAGE_DIGEST}` expecting a binary that is not there, and its job needs a `lunanexa-offline-artifact-worker` secret (key `render-evidence-secret`) that does not exist. Nothing invokes the job either — the external dispatcher is absent. |
| `PdfRenderer` | MoonLeaf has **no renderer**. `.mooncakes/vectie/moonleaf/render/` contains only the `Evidence` receipt type (`engine_id`, `contract_version`, `Evidence`); there is no rendering implementation. `deploy/offline-pdf-pipeline-job.yaml` pins `registry.invalid/moonleaf/renderer@${MOONLEAF_RENDERER_IMAGE_DIGEST}` — a placeholder — and says another office engine is not an acceptable substitute. |
| `SpreadsheetFormulaEngine` | Not implemented. `.mooncakes/vectie/moonleaf/xlsx/edit.mbt:254` states it "intentionally does not recalculate formulas, shared strings, dimensions, tables, charts, or pivot caches", and `inspect.mbt` only reads formula text and cached values. The requirement is recalculation plus error scan plus rendered-sheet inspection. |
| `CjkFonts` | The three licensed faces are absent by design: `assets/fonts/private/README.md` says font binaries are intentionally not committed and must be supplied from organization-licensed sources (`FangSong_GB2312.ttf`, `FZXiaoBiaoSong-B05S.ttf`, `SimHei.ttf`), and that a renamed substitute is not accepted. The directory currently holds only that README. |

## Not capabilities, but still blocking

The gate also reports adapter and evidence blockers that no attestation can clear —
`docs/OFFLINE_COMMERCE.md`: *"Signed evidence or a deployment boolean alone cannot
make these adapters ready."* As of 2026-09-22 these remain:

- `ReadinessTransferAdapterUnavailable` — the secret has no `offline-transfer-adapter-endpoint`,
  `offline-transfer-adapter-token` or `offline-transfer-session-secret` key;
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
