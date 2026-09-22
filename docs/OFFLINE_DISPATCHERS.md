# Offline dispatchers

`cmd/offline-dispatcher` is one native executable with two separately deployed
modes. It uses the controller's persisted work claims, not a second queue.
Run one replica per mode with `Recreate`; an exclusive filesystem lock also
refuses a second process sharing that mode's state root.

Common environment:

- `LUNANEXA_OFFLINE_DISPATCHER_KIND`: `artifact` or `entitlement`.
- `LUNANEXA_CONTROLLER_ENDPOINT`: trusted controller origin.
- `LUNANEXA_OFFLINE_DISPATCHER_STATE_ROOT`: durable, mode-specific writable root.
- `LUNANEXA_OFFLINE_DISPATCHER_ONCE=1`: a bounded single polling pass for acceptance.

Artifact mode additionally requires `LUNANEXA_ARTIFACT_WORKER_CALLBACK_TOKEN`,
`LUNANEXA_OFFLINE_TRANSFER_OBJECT_ENDPOINT`,
`LUNANEXA_OFFLINE_TRANSFER_ADAPTER_TOKEN`,
and `LUNANEXA_OFFLINE_ARTIFACT_EXECUTION_BACKEND=kubernetes` in production.
Kubernetes execution requires the reviewed `LUNANEXA_KUBECTL_BIN`, digest-pinned
`LUNANEXA_OFFLINE_ARTIFACT_JOB_IMAGE`, Job namespace, state/font PVC names,
render-secret name and state subpath configured in the deployment overlay.
The dispatcher does not receive the render signing secret or font mount.
Entitlement mode requires `LUNANEXA_ENTITLEMENT_AUTHORITY_CALLBACK_TOKEN`.
Secrets are deployment inputs; child render processes never receive them in
command-line arguments. State contains customer document material: restrict and
back it up under the same retention/access policy as commercial artifacts.

The production Job runs prepare and render as ordered init containers followed
by finalize. It mounts only the one request directory via PVC `subPath`, approved
fonts read-only and an ephemeral `/tmp`. It has no service-account token, no
controller/object-store credentials, no privilege escalation and no network
ingress/egress. Its only secret is the render evidence key. Install the provided
deny-all NetworkPolicy on a CNI that enforces egress before starting dispatchers.
The dispatcher's service account may create/get/delete Jobs only; it cannot read
Secrets or invoke pod exec. A binding digest prevents reuse of a different plan.
Automatic service-account mounting is disabled. Only the artifact dispatcher
container receives an explicit projected API token (one-hour lifetime), root CA
and namespace file; entitlement and document worker containers receive none.
The named management deployment also applies `offline-dispatcher-admission.yaml`:
its enforced policy matches the exact dispatcher service-account identity (not a
caller-controlled label), fixes the executable image/commands, and rejects other
secret references, mounts or privileged/host-network jobs. Job-creation RBAC
alone would otherwise permit indirectly obtaining unrelated namespace secrets.
Because the deployed CNI exempts node-local traffic from NetworkPolicy, workers
also require `Localhost: lunanexa/offline-worker.json`. Derive this from an actual
RuntimeDefault OCI spec with `scripts/derive-offline-worker-seccomp.mbtx`, inspect
the diff, then install it on the pinned management node using the one-shot
`offline-worker-seccomp-installer.yaml`. The derivation retains the default-deny
profile and every other syscall rule while restricting socket/socketpair to
AF_UNIX and removing compatibility socketcall. Remove the installer pod after
success. Never replace this with an allow-all seccomp baseline. Missing profiles
prevent jobs from starting; do not silently fall back to RuntimeDefault.

`development-subprocess` is an explicit development verification profile only,
not the production trust boundary. It additionally uses worker/renderer binary
paths, render signing key and approved font root/configuration environment inputs.
Same-UID subprocesses are not an isolation boundary even with filtered environment.

## Artifact execution

The dispatcher claims a stored request, fetches the controller-bound execution
plan, downloads its exact template through the authenticated transfer adapter,
verifies the template digest, resolves actual DOCX markers against the
order-linked legal packet through a second authenticated plan request, runs
prepare → render → finalize, validates the
worker result against actual bytes, uploads to object storage, and only then
publishes its completion callback. Filenames are confined to a per-request
SHA-256 staging directory. Completed object publications are atomically journaled
so a callback retry does not rerender or rewrite the object. Finalized bytes are
also reused after an ambiguous PUT, so a retry cannot introduce a new PDF timestamp.
Unacknowledged finalized/publication work is journaled and resumed even after the
controller's claim budget is exhausted; invalid pre-render work retains that budget.
Provider storage must
enforce immutable same-key/same-digest replay (conflicting bytes must fail).

## Entitlement execution

The dispatcher calls the controller's narrow authenticated execution endpoint,
which owns the real provisioning authorities. A `202` or Requested state is not
completion. The original work is journaled and retried after restart, independent
of the claim retry budget. A terminal result is durably saved before the callback,
so callback loss cannot replay the provisioning mutation. The authority itself
must remain idempotent across the crash window before that journal commit.

An independent 15-second heartbeat loop stays live during document rendering;
it does not create claims or fabricate successful-execution evidence.

## Packaging and acceptance

Build the three native executables for the target architecture against the exact
updated sibling MoonLeaf source through `moon.work` (the released 0.1.15 does not
contain this renderer/recalculation implementation), stage them under
the names in `images/Containerfile.offline-dispatcher`, include a reviewed
checksum-verified architecture-matching kubectl binary, build the image, and replace
the explicit image placeholder in `deploy/offline-dispatchers.yaml` with its digest.
Mount approved fonts read-only; this image does not grant font licenses or legal
template approval. Provision the two Secrets, common ConfigMap and named PVCs.

For the named management deployment, `scripts/deploy-offline-dispatchers.mbtx`
accepts the kubeconfig and immutable image reference and installs the state PVC,
private-CA endpoint configuration, egress policies, enforced Job admission policy
and both deployments. Callback secrets reference the existing controller secret;
the renderer-only evidence key is provisioned with
`scripts/provision-offline-render-secret.mbtx` without printing or persisting it
outside Kubernetes. A reviewed secret-free OCI runtime snapshot may alternatively
be packaged with `scripts/package-offline-rootfs.mbtx`; record the resulting
digest and actual package/binary hashes, not a claim of byte reproducibility.

Required live acceptance remains a real DOCX/XLSX/PDF generation and download,
an actual lease activation and reversal, plus process death after publication but
before callback. A running process/heartbeat alone proves none of those outcomes.

### Repeatable image build

Use a clean target-architecture Linux checkout of LunaNexa plus the exact modified
MoonLeaf checkout, with `moon.work` selecting both. Record both Git revisions and
working-tree diff digests if testing uncommitted work. Verify the supplied kubectl
binary against the selected official release checksum before packaging it.

```text
moon run scripts/build-offline-dispatcher-image.mbtx NEW_CONTEXT_DIR REVIEWED_KUBECTL_PATH REGISTRY/IMAGE:VERSION UBUNTU_IMAGE@sha256:EXACT_DIGEST
```

The script refuses non-Linux build hosts and unpinned base images, builds all
three binaries, creates a new build context without overwriting an existing one,
and builds locally. It never pushes or deploys. Use the pushed registry digest,
not the mutable build tag, for both image fields in the deployment overlay.
APT package resolution is not byte-reproducible without a pinned package snapshot;
capture the resulting SBOM/package versions and OCI digest for the release.

### Recorded isolated runtime probe (2026-09-22)

`pipeline_probe_wbtest.mbt` was executed as a compiled Linux test inside the
disposable `offline-transfer-verify-20260922` tools pod with an actual worker,
MoonLeaf renderer, Poppler rasterizer, ClamAV and SeaweedFS 4.47 S3 adapter.
It uploaded a real test-only DOCX, generated and downloaded a 575641-byte PDF,
then recovered an intentionally rejected first callback without rerendering.
The controller plan/callback boundary was explicitly mocked. The single page was
visually reviewed: readable disclaimer and substituted order value, no clipping.
The production Kubernetes Job manifest also passed the actual API server's dry run;
that is schema/admission evidence, not execution or CNI isolation evidence.

See `docs/evidence/offline-pipeline-20260922.json` for hashes and exact claims.
The probe uses an OFL Latin font and does not certify an actual legal template,
production font authorization, actual lease provisioning or production launch.
Set `LUNANEXA_OFFLINE_PIPELINE_PROBE_ROOT` only for this opt-in isolated test; use
`LUNANEXA_OFFLINE_ARTIFACT_EXECUTION_BACKEND=development-subprocess` plus the
explicit test adapter, font and binary settings above. Preserve its summary and
page evidence before deleting the disposable namespace.

### Production runtime qualification (2026-09-22)

`production_probe_wbtest.mbt` exports bounded, explicitly non-commercial XLSX and
Chinese OFL-v2 DOCX qualification inputs. These were submitted as the actual
dispatcher service account in `lunanexa`; both three-container Jobs completed in
7 seconds with the production font PVC, render key, subPath mounts, enforced
admission and AF_UNIX-only seccomp profile. This qualifies actual document runtime
execution, not a stored order, legal signature, payment or entitlement. The quote
generated a one-page normalized proof; the DOCX generated four raster-verified
pages. Evidence and explicit remaining business checks are recorded in
`docs/evidence/offline-dispatcher-production-20260922.json`.
