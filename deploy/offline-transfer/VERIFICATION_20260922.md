# Real offline-transfer verification — 2026-09-22

This is isolated dependency/adapter verification, not a production release or
browser/contract acceptance claim. No production controller mutation was made.

## Environment and provenance

- Management host `ubuntu`, Kubernetes namespace
  `offline-transfer-verify-20260922`, disposable `tools` pod.
- Native Linux adapter built from `cmd/offline-transfer` using MoonBit
  `0.1.20260920` in a separate staged checkout.
- Third-party AWS CLI `2.31.34`, official release zip SHA-256
  `50e1c4cd2c8137ef288284ef53a1e5044355b046425e52ae0c818125f654c2c1`.
- Debian signed packages from USTC: ClamAV `1.4.3+dfsg-1~deb12u2`, qpdf
  `11.3.0-1+deb12u1`, unzip `6.0-28+deb12u1`.
- Actual freshclam-downloaded, signature-verified databases: daily `28131`
  (355666 signatures), main `63` (3287027), bytecode `339` (80).
  Freshclam reports recommended engine `1.4.6`; production image should use
  the supported patched engine and a continuously updated database, not freeze
  this test engine/database indefinitely. NotifyClamd warning is expected: this
  profile uses clamscan, not a clamd daemon.
- Standard S3 backend: SeaweedFS **4.47**, official GitHub release asset
  `linux_amd64.tar.gz`, SHA-256 verified against release metadata:
  `31fb804858885f9e7f18b6d3b1da09e824baac3e6a55b5a62c3c4c77e6ed6d7d`.
  It listens only on pod loopback; test credentials have no production use.
  Unauthenticated bucket access was independently checked: HTTP **403**.

## Executed results

The adapter's `--self-test` runs real external binaries and actual object I/O;
it does not fabricate scanner or storage success.

1. qpdf created a valid PDF; real ClamAV returned `OK` and qpdf structure check
   succeeded.
2. S3 PutObject followed by range-bounded GetObject returned identical bytes.
3. Repeating the same immutable write returned S3 `PreconditionFailed`; the
   adapter verified the existing digest and accepted the idempotent retry.
4. Writing different bytes to the same object returned `PreconditionFailed`;
   the adapter rejected the conflicting digest. Original bytes remained intact.
5. The real scanner detected the standard harmless antivirus test string:
   `Eicar-Test-Signature FOUND`, exit status **1**, not an engine-error status.
6. Result emitted by the native adapter:

```json
{"schema":"lunanexa.offline-transfer.self-test.v1","s3_roundtrip":true,"immutable_retry":true,"conflicting_write_rejected":true,"pdf_scan":true,"eicar_rejected":true,"sha256":"sha256:13230b1dbabe63c86820f03352c5b7198801c732e33872383b55faa794845cd7"}
```

Local native suite: **5/5 passed**, covering bucket/path traversal, capability
limits/expiry/media, durable pending recovery, authenticated HTTP issuance,
wrong-token rejection, one-time replay rejection and public receipt redaction.
The public endpoint also accepts exact root-relative `/v1/offline-transfers`;
protocol-relative redirects, credentials in URLs and query/fragment forms are
rejected. Controller transport trust is separate and unchanged.

## Failures found and handled honestly

MinIO's historical image pulls from Quay and DaoCloud stalled; its direct
upstream binary URLs returned HTTP 410. Neither was counted as a successful
backend deployment. SeaweedFS **3.85** was initially tested and **rejected**:
it silently ignored conditional PutObject and the self-test caught an immutable
overwrite. The 4.47 rerun passed. Do not declare an arbitrary “S3 compatible”
endpoint ready without this conditional-write test.

Initial SeaweedFS test capacity (`volume.max=2`) was too small because metadata
logs occupied the available volumes. The test was corrected to 20 volumes,
100 MB size limit each, no preallocation. This is not production sizing.

## Retention and cleanup ownership

The subsequent real Chinese-font OFL template probe exposed additional issues:
PDF QDF substring scanning could mistake embedded font/image bytes for active
names; it now examines qpdf's decoded JSON object names with stream data omitted.
Debian `zipgrep` incorrectly treated `[Content_Types].xml` as a glob while
iterating ZIP entries; Office scanning now uses `unzip -p` patterns directly,
after ClamAV expansion-limit checks, and examines the resulting XML.
The current async runtime's file-output redirection attempted epoll registration
of regular files on Linux; subprocess output now uses pipes or the utility's
own output-file option. Regular-file reads use the filesystem API explicitly.
Restarting with an existing state directory also now preserves that directory.
Nine package tests cover the name checks, subprocess/regular-file bounds and prior
capability/replay checks. Final OFL end-to-end evidence is recorded separately;
failed probe attempts are not represented as successful runs.

The final `pipeline-ofl-evidence5` run subsequently **passed** on the management
node: the formal OFL v2 DOCX produced a four-page, 10,824,742-byte PDF with digest
`sha256:7f47f4fec8dba952bc9dc700e7a5bebb7c42946b2780364c26a3529162740b19`.
Real ClamAV scanning, bounded Office XML pipe inspection, PDF structural checks,
S3 write/readback and recovery from an intentional HTTP 503 callback all passed.
The PDF digest matches the separately inspected macOS-rendered output.

The `tools` pod and its loopback S3/adapter processes were retained
for the sibling dispatcher/renderer integrated E2E. They contained only test
documents, test credentials, downloaded dependencies and scanner databases.
The test namespace has a same-namespace-only ingress NetworkPolicy. No NodePort,
LoadBalancer, host-network listener or production Secret was created.

After successful integrated E2E and verification of the locally retained PDF,
four preview PNGs and callback evidence, deletion of the exact test namespace
was requested and the dedicated remote staging directory
`/home/HwHiAiUser/offline-transfer-verify.ihVqSL` (362 MB) was removed.
Local evidence is retained under
`/tmp/lunanexa-ofl-pipeline.Zp22X7/ofl-pipeline-pass` and
`/tmp/lunanexa-offline-pipeline.jrRaGW`.
The namespace deletion completed; a subsequent `get namespace
offline-transfer-verify-20260922 --ignore-not-found` returned no resources.
Do not remove
the production checkout, existing namespaces, model data or shared build caches.
Native self-test temporary directories are removed automatically on exit.
The S3 verification objects live only in the disposable test backend.

The never-started MinIO `object-store` pod and its unused Service were deleted
after the SeaweedFS verification passed; they held no documents or volumes.
The verification manifest no longer creates those failed-attempt resources.
