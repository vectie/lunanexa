# ModelScope model onboarding

LunaNexa exposes ModelScope as an operator-selected model source, not as an
implicit deployment authority. The normal operator experience is:

```text
sign in
→ search the ModelScope public catalog
→ inspect model identity, license, task, size and source revision
→ start a durable download
→ observe automatically refreshed, resumable progress and exact per-file SHA-256 verification
→ satisfy LunaNexa signature and evaluation gates
→ explicitly approve the version
→ expose the approved version or alias to users
```

Raw registry JSON is not part of the normal console workflow. It remains an
automation contract for reviewed clients and tests.

## Security boundary

The controller remains the model-policy authority and retains read-only access
to the model store. A separately deployed native MoonBit model-source adapter
is the only LunaNexa component allowed to:

- make outbound HTTPS requests to the configured ModelScope origin;
- write beneath the deployment-owned model staging and artifact roots;
- maintain durable import-operation state; and
- return bounded catalog and verified-import evidence to the controller.

The adapter has no Kubernetes service-account token, node credential,
operator credential, database credential or inference credential. Its internal
HTTP API requires a distinct bearer authority. The console never receives that
authority: authenticated operator routes on the controller proxy the narrow
catalog/import contract.

Model identifiers, revisions and repository paths are validated before they
enter a filesystem path or upstream URL. Partial downloads use a private
temporary suffix and never become model artifacts. Publication uses an atomic
rename only after every declared file matches its ModelScope size and SHA-256.
The adapter resolves the requested branch to the observed source revision
before file transfer. A retry reuses complete verified files and requests only
the remaining byte range for a partial file. Transfers are bounded to 64 MiB
Range requests so a file larger than the MoonBit HTTP parser's signed `Int`
limit never requires parsing an oversized `Content-Length`. Every `206`
response must return the exact requested `Content-Range`; a large unbounded
`200` response fails closed. If a small-file origin does not honor Range, the
adapter safely restarts that file and resets the visible byte count.

## Trust and approval

ModelScope's public file API provides a repository revision and SHA-256 for
each file. LunaNexa records those values as source and integrity evidence. That
does **not** by itself prove an artifact signature.

Consequently, a completed ModelScope import is `Verified` in the download
sense but is not automatically `Approved` in LunaNexa's model registry. Final
user visibility still requires:

1. accepted license metadata;
2. the configured artifact-signature verification gate;
3. a passing evaluation record for the exact model version; and
4. an explicit operator approval and, where configured, alias promotion.

The UI must show these gates separately. It must never label a checksum-only
download as signed or deployable.

## ModelScope protocol profile

The adapter uses the official ModelScope service origin and these bounded
operations:

- `GET /openapi/v1/models` for paginated search;
- `GET /openapi/v1/models/{owner}/{repo}` for model details;
- `GET /api/v1/models/{owner}/{repo}/repo/files` for the repository tree and
  exact file metadata; and
- `GET /models/{owner}/{repo}/resolve/{revision}/{path}` for file transfer.

The origin is deployment configuration and must be HTTPS. The download path
follows at most three HTTPS redirects, because ModelScope commonly redirects
large LFS objects to a signed `*.modelscope.cn` CDN URL. Every hop is parsed
again and must remain on `modelscope.cn` or one of its subdomains; userinfo,
custom ports, fragments, backslashes and unapproved hosts fail closed. A
private-model token, if later supported, is a deployment Secret reference and
is never accepted from a browser field.

## Operator UI states

- `Queued`: accepted and durable; no bytes are yet trusted.
- `Downloading`: partial bytes are private and progress is observable.
- `Verified`: all source-declared sizes and SHA-256 values match and the
  artifact directory is atomically published.
- `Failed`: the reason is safe for the operator UI; partial content is not
  visible to runtimes.
- `Cancelled`: operator cancellation was observed and no artifact was
  published.
- `Approval blocked`: download is verified but one or more registry gates are
  still missing.
- `Approved`: registry approval succeeded for the exact model version.

The console refreshes an active download automatically; the manual refresh
control is a recovery aid, not the normal progress mechanism. Failed and
cancelled operations expose a Retry action. Retries reuse the deterministic
import identity and verified files rather than creating duplicate user-visible
model versions. A process restart requeues an in-flight operation, reconstructs
its counters from the staged files and never carries stale progress forward.

A ModelScope directory is source material, not automatically a LunaNexa
deployment artifact. The current registry accepts immutable deployable
artifacts and requires signature/provenance verification, accepted license
evidence, a passing evaluation, and a qualified runtime/service template. The
UI therefore shows the four gates and keeps **Approve for users** disabled after
source checksum verification. Enabling it before the directory has a reviewed
packaging/materialization contract would falsely promise deployability and is
not an acceptable shortcut.

## Management deployment

The management foundation deploys `lunanexa-model-source` as a private
ClusterIP service on port `8090`. It has a dedicated PVC for operation state,
writes approved import paths beneath the deployment-owned model-store mount,
and receives a bearer authority from the separate
`lunanexa-model-source-credentials/token` Secret. The controller receives only
that service endpoint and Secret reference. Do not reuse the operator,
inference, node, database or audit authorities.

The public console gateway never exposes the adapter directly. Browser calls
use the operator-authenticated controller contract under
`/v1/model-sources/modelscope/*`; the controller proxies the corresponding
bounded `/internal/v1/modelscope/*` operation. A live management acceptance
must verify search through that controller route, not merely call adapter
`/health`.

The current public-HTTP operator page intentionally disables all credential
entry. Use a localhost-only port-forward or reviewed TLS when testing the
authenticated search/download UI. Never weaken that gate merely to demonstrate
the catalog.

## Initial physical-host acceptance

For `OpenBMB/MiniCPM5-1B`, the current staging evidence pins every file and the
observed source revision. It may be used to exercise the import UI, but it must
remain non-user-visible until the signature and evaluation gates have real
evidence. See `ASCEND_310P3_TEMPORARY_COMPUTE.md` for the temporary compute
qualification boundary.

## Executed physical-host UI acceptance (2026-08-28)

This is the observed result for the management host, not a substitute for the
remaining approval gates:

1. An authenticated operator opened **Models**, searched ModelScope for
   `MiniCPM`, and selected `OpenBMB/MiniCPM5-1B` from 362 results.
2. The first download exposed two real adapter defects rather than being
   bypassed: missing ModelScope CDN redirect handling, followed by a signed
   32-bit `Content-Length` overflow on the 2,161,290,912-byte safetensors file.
3. The adapter was corrected with the bounded redirect policy and 64 MiB Range
   chunks. The failed durable import was retried from the same UI identity and
   reused four already verified files.
4. UI-observed progress advanced from 3% to 43%, 77%, then 100%. The terminal
   state was **Checksum verified**, `11/11` files, with the completed-download
   message visible to the operator.
5. **Approve for users** remained disabled. The UI separately showed the
   missing deployable-artifact signature, license/evaluation and qualified
   runtime/template gates. No manual staging directory, pre-existing model
   file or direct adapter request was used to manufacture success.

The final deployed adapter image was
`lunanexa/model-source:management-20260828-modelsource-range-13`; its Pod was
`1/1 Running`, had zero restarts and owned the ready Service endpoint after the
import completed.
