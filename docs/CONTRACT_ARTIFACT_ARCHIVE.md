# Contract artifact archive and download boundary

The undertaking path publishes a generated DOCX/PDF pair into the existing
offline-commerce artifact authority before marking its packet `Generated`.
This is an archive metadata bridge, **not a renderer or object-store upload
service**. It does not certify that a production document pipeline is deployed.

## Trusted worker protocol

`POST /v1/contract-documents/worker/results` retains the dedicated renderer bearer
boundary. For `youthpolicy-device-undertaking-v1`, the payload additionally
requires `docx_storage` and `pdf_storage`, each a
`commercial/offline/store.ContractArchiveObject`:

- `artifact_id`, `object_ref`, `media_type`, `sha256`, `byte_count`;
- `storage_receipt`, `stored_unix_ms`, `verified`, `active_content_detected`.

The renderer obtains stable IDs from `contract_archive_artifact_id(packet_id,
revision, kind)` and logical object keys from `contract_archive_object_ref(org,
order, packet_id, revision, kind)`. The controller recomputes both. These keys
are not browser URLs, file paths, presigned URLs or credentials. The deployment's
storage adapter must map the `object://contract-documents/` namespace to its
private storage, durably store the exact bytes and verify their digest/size
before issuing the trusted receipt. Merely setting `verified=true` is not an
independent proof of object existence; the worker identity is a trust boundary.

The controller validates the requested packet revision and generation transition,
matches both storage receipts to the rendered artifacts, checks tenant,
organization and purchaser against the linked order, then archives both objects
in one offline-store mutation. Invalid/active-content/mismatched objects fail
before either artifact becomes downloadable. No customer endpoint accepts these
storage evidence fields.

## Recovery ordering

1. Write and verify immutable object bytes in deployment-owned storage.
2. Persist the DOCX and PDF archive metadata together.
3. Persist the packet's `Generated` transition.
4. Return the successful result.

The two stores are not one cross-domain transaction. A failure at step 3 leaves
the packet `GenerationRequested` with both objects retained. The worker retries
the same revision, stable artifact IDs and exact storage receipts; the archive
replay is a no-op, and the packet transition resumes. A lost step-4 reply is also
safe to replay while the packet remains at that exact `Generated` revision.
Different bytes or receipt metadata for an existing ID are a conflict. Do not
delete objects solely because the controller result POST timed out; reconcile
the packet and archive before any retention cleanup.

## Browser downloads

For archived undertaking artifacts, the existing authenticated
`POST /v1/offline-commerce/self/artifacts/{artifact_id}:download` issues a
five-minute, one-time, purchaser-scoped transfer grant. The storage endpoint
remains private; the UI uses the returned grant rather than turning an artifact
identifier into a URL. Existing transfer adapter configuration and transport
verification remain required. Traditional packets whose arbitrary `order_ref`
does not bind a real offline order are not automatically migrated by this
bridge; the UI must report their archive/download unavailability honestly.

## Operator evidence review downloads

`POST /v1/offline-commerce/operator/artifacts/{artifact_id}:download` accepts
`tenant_ref`, `organization_id`, `order_id`, `session_id`, `idempotency_key`.
It requires a currently authenticated platform operator, not an asserted actor
header. Platform operators have platform-wide review authority; the explicit
scope is checked against the order/artifact rather than becoming a tenant-role
delegation. Successful issuance returns the same `OfflineTransferGrant` shape
as customer downloads, with a maximum 120-second lifetime.

The durable session subject is `operator:<authenticated identity>`, never the
purchaser. Idempotency includes operator, tenant, organization, order, artifact
and digest. Existing purchaser or another operator's session ID cannot be
overwritten. Only `ScanPassed` originals can be reviewed; review rejection does
not hide an original from authorized reviewers, but scan quarantine still does.
An attributed issuance audit is persisted before returning a capability to the browser.

Revoking the operator credential immediately prevents new issuance/reissuance.
Already issued one-time capabilities may remain usable for their remaining
**at most 120 seconds**: the existing external adapter does not perform a live
operator-authorization callback on every byte read. This is not immediate
revocation of an already delegated capability. Consumption still rejects expiry
and replay. The adapter must enforce the same expiry and one-time semantics.
Its configured endpoint must be exposed through the reviewed same-origin
browser transfer ingress; no raw object key or storage credential is returned.

## Remaining renderer dependency

The currently pinned MoonLeaf 0.1.15 can fill and semantically reopen DOCX,
inspect styled flow blocks and calculate a pagination projection. Its `render`
package defines and validates an evidence record; it does not implement
DOCX-to-PDF byte output. The pagination projection is not glyph-placement or
PDF fidelity evidence. A real renderer plus pinned, licensed fonts and visual
acceptance is still required. No LibreOffice output, preview page count or
test-only receipt is relabelled as a MoonLeaf production render by this bridge.

Repository regression tests cover pair persistence/reopen, exact replay,
namespace substitution, ownership mismatch, invalid evidence, changed-byte
replay, write-failure rollback and cross-store recovery. They use explicitly
synthetic storage/render evidence and do not prove live object storage or PDF
rendering.
