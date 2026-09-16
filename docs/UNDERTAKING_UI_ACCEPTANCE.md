# Undertaking rental UI acceptance — 2026-09-16

## Implemented customer journey

1. In **Contract forms**, select the equipment undertaking and an eligible
   existing order. Traditional bilateral rental remains a separate choice.
   Existing packets are reopened rather than recreated for the same order.
2. Review the original Attachment 2 and its two customer fields: organization
   name and undertaking date. Verified profile/order facts are reused; Party A
   supplies rental start/end and amount as admission metadata, not new clauses.
3. Save, review/confirm, and request original-format DOCX/PDF generation. The
   undertaking downloads use the existing authenticated offline-artifact
   transfer grant and digest verification, never a guessed storage URL.
4. Sign/stamp offline, upload the scan, select its scan-passed revision, and
   submit to Party A. The signing date is initialized from the document.
   Pending submissions can be withdrawn. Rejected submissions show the reason;
   revision invalidates prior confirmation, generated files and approval, so a
   newly generated/signed version must be submitted.

Only the backend's authorized signatory may submit. A visible UI control does
not create authority. Submission, approval, payment, resource availability and
actual access activation remain separate facts.

## Operator journey

- Existing order UI offers fixed daily/weekly/monthly/quarterly/yearly tariffs
  and device count. It binds the Attachment 2 source digest automatically.
- Payment receipts have an explicit **Verify full prepayment** confirmation,
  requiring human checking of order amount, currency, receiving account and
  actual bank receipt. Its audited reason is `FullPrepaymentVerified`; merely
  accepting an uploaded file does not make that assertion. Old immutable
  generic reviews require a replacement receipt and a new independent review.
- The document editor exposes the operator's admission metadata. The existing
  governance inbox exposes Party A approve/reject with revision, source values
  digest and tenant-signature evidence. It clearly says approval is not Party
  A's countersignature. Existing resource and payment gates cannot be waived.

## Verified scope

`moon test ui/contract_documents ui/offline_commerce ui/enterprise cmd/enterprise
cmd/console --target js --deny-warn --warn-list -29`: **123/123** passed at the
recorded gate (including legacy bilateral-contract UI tests).
Warning 29 is excluded for the existing unused PostgreSQL import under JS;
this does not describe a strict all-target release pass.

`sh scripts/build-browser-bundles.sh` built the real browser bundles and copied
the undertaking's separate MoonLeaf preview scene.

Browser testing used the built **DEMO** enterprise portal on loopback, not
production credentials. It verified template switching, the four-page original
undertaking, only two editable customer fields, and live propagation of an
edited organization name into the signature line. Desktop inspection found
overlapping labels in the inherited two-column editor; undertaking fields now
use one column and the overlap was rechecked. A 390 × 844 viewport showed the
fields, save/confirm controls and preview without overlap. The temporary
preview servers/tabs were closed and the viewport restored afterwards.

These checks do **not** prove live approval, bank settlement, generated-PDF
fidelity, file download, or physical machine provisioning. Those require the
composed backend/renderer/cluster evidence. A four-page preview is not a PDF.

## Editor boundary

Operator reviewers now have a verified-original download beside the evidence
review buttons, including for rejected documents that passed malware scanning.
The console requests its own operator-scoped, 120-second one-use grant and checks
direction, expiry, size and SHA-256 before saving the original with its file
extension. It never impersonates the purchaser. Transfer URLs must resolve to
the console's own origin; deployments need a same-origin adapter ingress.
This additional UI/command regression suite passed 125/125 with
`moon --target-dir _build/undertaking-ui-final test ui/contract_documents ui/offline_commerce ui/enterprise cmd/enterprise cmd/console --target js --deny-warn --warn-list -29`.
The operator download itself has not been browser-tested against a live adapter.

Final integration removed the JS warning exclusion by marking the libpq-only
`internal/postgres` package as native-only, consistent with its consuming
database package. Whole-repository `moon check --target js --deny-warn` passed.
`moon test ui cmd/enterprise cmd/console cmd/workbench installer workspace
--target js --deny-warn` passed **153/153**, without warning exclusions.
The final rerun also passed 153/153 with the release gate's additional
`--warn-list +73`; whole-native regressions passed 858/858 with the same strict
warning policy. These remain local tests, not deployed browser acceptance.

The existing integration is MoonLeaf source-faithful preview plus Rabbita
controlled-field editing. The adjacent MoonEdit project currently describes
itself as editor-core alpha and explicitly provides no document UI/persistence
host. This implementation does not invent a MoonEdit integration or introduce
a MoonSuite product dependency into LunaNexa. The original undertaking's text
is preserved; the UI does not independently guarantee legal equivalence.
