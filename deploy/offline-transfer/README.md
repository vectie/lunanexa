# Offline commerce transfer adapter

Native MoonBit executable: `moon build --target native --release cmd/offline-transfer`.
Durable bytes live in an existing S3-compatible store, not on GPU nodes and
not in a new home-grown object store. Package the resulting executable using
this Dockerfile and a reviewed immutable `RUNTIME_IMAGE` digest containing
AWS CLI v2 (PutObject If-None-Match support), clamscan, qpdf, unzip and CA roots.
The deployment is a template: render `OFFLINE_TRANSFER_IMAGE_DIGEST` before use.
`Dockerfile.runtime` builds that dependency image from a digest-pinned Debian
13 base and explicit package versions. Retain the apt snapshot used for the
build. The installed awscli is a third-party CLI, not first-party Python code.

If the deployment has no S3 service, `Dockerfile.object-store` and
`object-store.yaml` provide an optional **standard SeaweedFS 4.47** backend
using the release asset verified during integration testing. Its image remains
a digest-pinned deployment input, and IAM comes exclusively from Secret
`lunanexa-offline-object-store-iam` key `iam.json`. Configure an admin bootstrap
identity separately from the adapter's bucket-scoped Read/Write/List identity;
disable unused IAM/STS credential-vending interfaces. Never copy test
credentials. Provision the bucket before starting the adapter, configure
encrypted storage and backups. Supply a trusted internal TLS certificate via
Secret `lunanexa-offline-object-store-tls` (`tls.crt`, `tls.key`); the Service
exposes HTTPS port 8443 through the certificate-verified TLS proxy, with S3
bound only to pod loopback 8333. This does not enable the
outer website's TLS. Preserve the deployment's reviewed Moongate routing,
extending the gateway's exact NetworkPolicy selector if it proxies S3. Do not
publish raw backend HTTP or filer/admin ports. NetworkPolicy admits only adapter S3
traffic; management/bootstrap access requires a deliberate temporary rule.
This 40 GiB single-replica profile is durable across pod restart but **not HA**.

The 2026-09-22 production deployment uses a reviewed Debian 12 runtime snapshot
with ClamAV 1.4.3, qpdf 11.3.0, Poppler 22.12.0, AWS CLI 2.31.34 and SeaweedFS
4.47. Its OCI archives are assembled by `scripts/package-offline-rootfs.mbtx`
without Docker, imported into existing containerd, then pushed to the internal
registry with CA verification. `production-services.yaml` supplies private TLS,
the signature updater, and narrow policy additions; existing controller/edge
network policies are preserved. Production evidence and exact digests live in
`docs/evidence/offline-transfer-production-20260922.json`. Object encryption is
chunk encryption with keys in filer metadata, not an external KMS guarantee.

## Required deployment inputs

Create private S3 bucket with encryption, versioning, retention/backups and
service credentials restricted to GetObject/PutObject on that bucket. Deny
public ACLs. The adapter does not require DeleteObject or bucket administration.
`object://offline-uploads/org/order/artifact` maps to the identically namespaced
key within the configured bucket; `s3://` references to other buckets fail.

ConfigMap `lunanexa-offline-transfer`:

- `LUNANEXA_OFFLINE_TRANSFER_PUBLIC_ENDPOINT`: preferably root-relative
  `/v1/offline-transfers`; proxy that path without rewriting it. This lets the
  browser retain the outer website's HTTP/HTTPS scheme without revealing an
  internal service hostname. The controller separately uses its private HTTPS
  adapter endpoint (or approved loopback proxy); do not weaken its TLS checks.
- `LUNANEXA_CONTROLLER_ENDPOINT`: trusted HTTPS controller origin or explicit
  loopback HTTP proxy; remote plaintext callback origins are rejected.
- `LUNANEXA_OFFLINE_S3_ENDPOINT`: reviewed S3 HTTPS endpoint. Only exact
  loopback HTTP is accepted for isolated tests or local trusted proxies.
- `LUNANEXA_OFFLINE_S3_BUCKET`, `AWS_DEFAULT_REGION`.

Secret `lunanexa-offline-transfer`:

- `LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN` matching controller configuration.
- `LUNANEXA_ARTIFACT_SCANNER_CALLBACK_TOKEN` matching controller configuration.

Secret `lunanexa-offline-s3`: AWS-format `credentials` file. S3 secrets never
appear in process arguments. Provision `lunanexa-clamav-signatures` PVC and
maintain fresh databases with a separately deployed freshclam updater. Missing
databases/scanning errors fail closed. The adapter loads only official
signatures and refuses databases older than three days. Monitor the updater;
an expired database makes scanning unavailable rather than silently clean.

Restrict internal object routes with private ingress and NetworkPolicy to the
artifact dispatcher/controller. Never expose S3, state files, or internal object
routes on the public frontdoor. Configure request body limits of at most 64 MiB.

## Protocol and recovery

Controller POST `/v1/offline-transfers` implements the typed adapter intent,
with optional `upload_grant_id` (required for uploads). Browser PUT/GET uses
`Authorization: Bearer <session_token>`. Object keys cannot be supplied by the
browser. MIME, expiry, size, SHA-256 and one-time redemption are enforced.

Authenticated internal routes use the adapter token:

- POST `/internal/v1/objects/read`, JSON `{object_ref, maximum_byte_count}`;
  returns raw bytes. Int64 uses decimal-string MoonBit JSON encoding.
- POST `/internal/v1/objects/write`, raw bytes with `X-LunaNexa-Object-Ref`,
  `X-LunaNexa-Sha256`, `Content-Type`; returns digest/size/receipt after
  conditional S3 creation and read-back verification.

ClamAV scans real bytes and rejects macros, encryption, oversized scan inputs
and failures. PDF structure and normalized active-content checks use qpdf;
Office XML is checked for external relationships, DDE and embedded active
objects. No clean receipt is generated on scanner failure.

The process holds an OS lock on its persistent state directory. Single-active
Recreate deployment avoids competing consumers. Session snapshots use atomic
rename and 0600 permissions. A durable outbox retries callbacks every 5 seconds
after restart; tokens remain only until acknowledgement. Protect/encrypt this
PVC. Exact callback replay must be accepted by the controller. Consumed
downloads require a new grant if the network response is lost, never a replay.

Unit tests cover reference traversal/bucket isolation, intent bounds and expiry,
MIME signatures and restart persistence. Real S3, scanner database and browser
acceptance remain separate: EICAR, active PDF, macro OOXML, incorrect digest,
expired/replayed/wrong-tenant token, conflicting object, and process termination
after S3 put/controller acknowledgement must all be exercised. Do not mark
ObjectStorage/MalwareScanner readiness proved by unit tests alone.

Run the built adapter with `--self-test` against a **dedicated disposable S3
bucket** to exercise real PDF scanning, round-trip storage, immutable retry,
conflicting-write rejection and EICAR detection. It does not contact the
controller, but it does leave uniquely named test objects in that disposable
bucket. Delete the test bucket/backend after retaining the result JSON.
See `VERIFICATION_20260922.md` for the executed real-backend evidence and
the incompatible backend version that this test correctly rejected.
