# MoonEdit offline document bridge regression

Local verification on 2026-09-22; this is software regression evidence, not a
production callback, signature, legal certification or payment receipt.

`moon test --target-dir /tmp/lunanexa-bridge-build-20260922 --target native --deny-warn api commercial/offline/store`
passed **179/179** tests. `moon info --target native` and native deny-warning
checks of API, offline store and controller also passed. The generation worker
has separate real-page-count tests owned by the dispatcher workstream.

The three bridge regressions in `api/offline_contract_bridge_wbtest.mbt` cover:

- purchaser generate queues one deterministic DOCX/PDF pair; exact click replay
  does not change the packet revision or create another pair;
- both worker plans carry the same frozen packet revision and confirmed values;
- first artifact completion does not prematurely mark the packet Generated;
- a final document-store write failure leaves both commerce results durable;
  reopening both stores and reconciling completes the same packet exactly once;
- actual page count and visual evidence survive result persistence; changed
  callback proof, missing page proof and mismatched paired page counts fail;
- failed initial commerce enqueue retains GenerationRequested and is resumed by
  reconciliation, without a new user click or manually inserted worker job;
- old generated packets remain readable, while unapproved legacy-template
  re-rendering reports TemplateApprovalScopeMissing and leaves the record intact.

Separate sibling-generation tests cover atomic rollback, restart, concurrent
artifact claims, cancellation and expiry fences. Existing packet binding tests
cover source/fillable hashes and tenant, organization, purchaser, order and
template matching. Deployment scope tests cover exact version/locale/digest
approval without changing historical reads.

Production acceptance is recorded separately after deploying the controller
bridge and the worker image that emits real `page_count`; local fixtures must not
be substituted for that acceptance.

## Generated preview regression

The actual browser later exposed a separate preview-only defect: it sends its
current editable-field values even when opening a Generated packet, and the
backend incorrectly treated those unchanged values as an edit. The preview
adapter now accepts only role-scoped, exact unchanged values in frozen states;
it leaves the packet and its generated files untouched. Changed values, foreign
or unknown fields and duplicate fields still fail closed.

`moon test --target-dir /tmp/lunanexa-preview-fix-20260922 --target native --deny-warn contractdoc/preview`
passed **8/8**, including GenerationRequested, Generated, GenerationFailed,
Effective, Closed and Superseded read-only previews with unchanged revision.
Production browser confirmation follows the controller v4 rollout and is not
claimed by this local regression result.
