# LunaFlux runtime qualification for LunaNexa

Date: 2026-08-28

LunaFlux is the intended MoonBit-native inference-engine candidate. The initial
2026-08-27 campaign on a temporary x86-64 NVIDIA compute node qualified the
cluster/device plumbing and CUDA inventory boundary. Subsequent bounded
campaigns added physical AOT execution and one native TCP listener result. They
still do **not** qualify LunaFlux as a LunaNexa runtime or production model
service. The later current-source tree also contains loopback observational
`/healthz` and `/readyz` endpoints plus one inherited Unix-stream drain
capability; those locally tested contracts do not establish public TLS,
authenticated external control, or a promoted LunaNexa rollout.

## Observed temporary compute node

The tested node was `lunanexa-gpu-180` (`192.168.2.180`), Ubuntu 22.04.5,
kernel 6.8, 20 CPUs and 125 GiB RAM, with:

- NVIDIA RTX 5060 Ti, 16 GiB, compute capability 12.0;
- NVIDIA RTX 2080, 8 GiB, compute capability 7.5;
- driver 590.48.01 and CUDA toolkit 13.1;
- K3s v1.34.10+k3s1, NVIDIA container toolkit 1.20.0 and RuntimeClass
  `nvidia`.

The worker joined the management K3s server over the LAN. It is labelled
`lunanexa.io/role=gpu`, tainted `lunanexa.io/role=gpu:NoSchedule`, and reports
two allocatable `nvidia.com/gpu` resources. All management-plane workloads
remained on node `ubuntu`; no Netplan, route, bridge, DNS or NAT setting was
changed.

A later stability check still reported both nodes `Ready`, the worker's K3s
agent `active`, and direct `192.168.2.180 -> 192.168.2.175` traffic using
`enp4s0` with zero packet loss. This verifies the current local cluster path;
it does not depend on either public SSH forwarding rule.

The digest-pinned NVIDIA device plugin in `deploy/nvidia-compute` became Ready.
A one-GPU CUDA vector-add Job ran on the worker and printed `Test PASSED`.
This is real kernel-execution evidence, but not LunaFlux numerical inference
evidence.

## LunaFlux physical diagnostic result

The LunaFlux native Linux executables were built from a checksum-recorded
source snapshot on the trusted management host and final-linked on the target
Linux ABI. `lunaflux doctor` reported:

```text
CUDA device probe: available; driver 13010; devices 2
physical CUDA correctness and resource gates: not proven on this host
readiness: false
```

This is the correct result. The first line proves LunaFlux can load the CUDA
driver and enumerate both physical devices. The last two lines are deliberate
fail-closed behavior: inventory is not readiness.

The sibling repository's earlier retained physical campaign goes further than device
inventory: it records passing CUDA Driver/cuBLASLt lifecycle probes, one
residual-add AOT specialization, a small mixed prefill/decode paged-attention
fixture, eight BF16 kernel-family fixtures and a graph-capture lifecycle probe
on the RTX 5060 Ti. Those are real physical CUDA results.

A later r3 campaign crossed an immutable tiny-BF16 launch, spawned worker and
bounded native TCP listener on the same `sm120` GPU. One request produced the
exact ordered result `Accepted`, `Token(1031)`, `Token(2185)`, `Usage`,
`Completed`; accepts equalled disconnects at one, KV returned to 0 used and 32
free pages, listener and child cleanup completed, stderr was empty, and no GPU
process remained. The evidence archive SHA-256 is
`c236f1626fc958fe51f1a24eeaff635a1f3bce367999cca2bf330d6f5228da8b`;
the final source archive SHA-256 is
`08b0139de9d5c2b9e70da27e3f8de2cc4fc2f91571458bdab889b4b824f65a9b`.

This closes the earlier claim that LunaFlux had no complete bounded deployment
payload or physical listener execution at all. It remains a tiny validation
payload, not an approved trained-model rollout, MiniCPM result, published
OpenAI compatibility profile, multi-request serving campaign or benchmark.
That archived source predates the later loopback observation owner and inherited
drain channel, so the campaign itself supplies no health or LunaNexa control
evidence. The RTX 2080 also lacks BF16 support and peer access is unavailable
between the heterogeneous cards, so the pair is correctly rejected for tensor
parallelism.

The campaign also found two build/packaging defects in LunaFlux:

1. GNU process-spawn extensions were compiled without `_GNU_SOURCE`, leaving
   declarations implicit on Linux.
2. the two native executables omitted `-pthread`, so `moon build` generated C
   and archives but failed final linking on Linux.

The sibling LunaFlux working tree now adds `_GNU_SOURCE` to the process native
stubs and `-pthread` to both executable link configurations. Targeted
`moon check --target native --deny-warn` and native executable builds pass on
the development host. The exact Moon-generated commands then final-linked on
the Ubuntu 22.04 worker and the rebuilt `doctor` repeated the two-device result.
Production Linux hosts must use glibc 2.34 or newer:
LunaFlux uses `posix_spawn_file_actions_addclosefrom_np`, introduced in that
ABI. The Ubuntu 20.04 management node is a trusted build coordinator, not a
supported LunaFlux execution target.

The same campaign exposed the missing POSIX thread link flag on the LunaNexa
node-agent executable. `cmd/node/moon.pkg` now supplies it, and generated
artifacts final-linked successfully on the worker as an ELF64 executable. The
agent was deliberately not started: the live pilot currently exposes HTTP UI
gateways but no reviewed HTTPS/mTLS node-control ingress, and the production
node agent rejects non-loopback HTTP. Starting it through the public console
port or weakening that check would be a security bypass. Kubernetes worker
qualification and LunaNexa control-plane enrollment therefore remain two
separate states.

## Evidence-based verdict

The sibling LunaFlux repository provides a typed CUDA execution architecture,
native/OpenAI service owners, strict deployment-root admission and an OCI
source contract. Its own current documentation also states that:

- the first useful release targets one CUDA GPU;
- the macOS development host cannot prove physical CUDA readiness;
- no final Linux/CUDA image digest, approved base/builder provenance, final
  rootfs scan, SBOM or reproducible physical image has been produced;
- broader physical CUDA correctness, positive I8, target-profile approval and
  promotion gates remain open despite the narrow BF16 listener pass;
- the production CLI contract is
  `lunaflux run ABSOLUTE_DEPLOYMENT_ROOT#sha256=<64-lowercase-hex>`.

That is enough to define a future integration boundary, but not enough to
invent a LunaNexa runtime image, port, health path or readiness claim.

The standard MiniCPM5-1B configuration identifies `LlamaForCausalLM`, which is
schema-compatible with LunaFlux's Llama direction. This is not execution
evidence. The 2.16 GB checkpoint also exceeds LunaFlux's current 64 MiB
whole-file offline reference limit; real use depends on the separately gated
streaming production loader and physical device execution.

## Promotion gates

Do not add LunaFlux to the LunaNexa approved runtime catalog until one rollout
unit retains all of the following:

1. an approved DGX Spark CUDA driver/runtime profile and physical device report;
2. externally built Linux ARM64 LunaFlux and device-worker executables;
3. an approved digest-pinned CUDA base, exact build context, final OCI digest,
   SBOM, vulnerability scan and forbidden-tool/rootfs scan;
4. immutable model, tokenizer, kernel modules, descriptor, instance policy and
   `lunaflux.launch.json` roots with independent digests;
5. successful LunaFlux `doctor`, `plan` and kernel inspection followed by the
   one-argument production `run` form reporting live readiness;
6. approval of the exact external HTTPS listener, `/healthz` and `/readyz`
   observation contract, streaming/cancellation behavior, and the
   authenticated LunaNexa-to-inherited-drain bridge—never guessed defaults or
   a fabricated LunaFlux HTTP drain route;
7. MiniCPM correctness, long-context bounds, memory headroom, cold start,
   concurrency, cancellation, restart and 24-hour soak evidence;
8. a LunaNexa catalog template pinning that final image and model rollout unit;
9. UI-to-UI deploy, invoke, receipt, drain, restart, rollback and delete proof.

## LunaNexa adapter shape after promotion

LunaNexa must continue treating LunaFlux as an opaque, digest-pinned runtime
adapter. LunaNexa owns assignment, artifact materialization, placement,
readiness observation, routing, metering and audit. LunaFlux owns model loading,
CUDA execution, batching, KV state, sampling and its service protocol. Neither
repository imports the other's private packages.

The future runtime manifest may be created only from the promoted evidence. It
must mount the verified model root read-only, use numeric non-root identity and
read-only rootfs, pass the exact deployment-root digest, request the selected
NVIDIA resource, and expose only the listener and health contract proven by the
physical campaign.

### Repository-side candidate boundary

`runtimes/LunaFluxCandidateManifest` provides an inert, digest-only admission
foundation for that future promotion. It binds the generic LunaNexa runtime
identity plus the model artifact, LunaFlux launch manifest, kernel manifest,
build provenance, SBOM, license-manifest and physical-serving evidence digests.
It deliberately contains no endpoint, credential, health path, command, mount
path or conversion to `RuntimeAdapter`.

`inspect_lunaflux_candidate` and `inspect_lunaflux_promotion` remain untrusted
structural inspectors and always return `routable=false`; caller-provided
approval claims still end in `PromotionVerifierUnavailable`. A separate local
authenticated path now uses an opaque, rollout-scoped
`LunaFluxPromotionVerifier`. It owns a deployment-injected HMAC-SHA256 key,
verifies exactly ten domain-separated signed receipts with constant-time MAC
comparison, and deterministically wipes its key on close. Only that verifier
may prepare the private `LunaFluxPromotionCatalog` that can produce opaque
adapter authority. The production interface exposes no catalog or
approval-input constructor: syntactically valid receipt digests are not trusted
verification. The private fixed-field join requires distinct
candidate-manifest, OCI image, SBOM, build-provenance, license, kernel,
physical-serving, comparative-benchmark, control-contract and
invocation-contract approvals. Deployment still owns key acquisition, key-id
and authority policy, receipt issuance and rotation; no production secret,
receipt set or approved catalog entry is committed here.

The verifier recomputes the canonical candidate and control digests, binds
physical-serving evidence to the exact target, and binds benchmark and
invocation approval to the exact candidate/control pair. Any missing-equivalent,
malformed, replayed, mismatched or substituted authority leaves
`routable=false`. Hostile fixtures cover subject substitution, missing and
duplicate receipts, cross-rollout and cross-candidate replay, authority/key
mismatch, wrong signatures and verifier closure. The public package remains
unable to construct a catalog or adapter authority directly. No approved
LunaFlux catalog entry, production verifier key, signed deployment receipt set
or deployment template is published by this document.

Verifier-issued authority now narrows into one opaque LunaNexa-side
`LunaFluxOpaqueAdapter` capability. Its identity binds the exact candidate,
runtime image, model artifact, launch manifest, control contract, invocation
contract and approval catalog. The capability exposes only digest-pinned
runtime facts, approved health/readiness observations, the inherited-drain
contract path, and credential-at-call-time Responses adapter construction. It
is neither JSON-constructible nor independently restorable, and callers cannot
derive it from candidate metadata or claimed receipt digests. This closes the
local authenticated adapter projection without creating a production catalog
entry, credential, deployment template, or routability claim.

## Remaining hard blocker

LunaFlux now has one complete bounded tiny-BF16 deployment payload with a
descriptor, instance policy, `lunaflux.launch.json`, AOT module set, execution
manifest and matching synthetic model root, and r3 proves that payload through
the native listener. It must not be represented as a deployable production
model: it is not a trained approved artifact, final OCI image, target-profile
approval, SBOM/rootfs result, approved public health/readiness projection,
approved authenticated LunaNexa-to-inherited-drain bridge, qualified OpenAI
contract, broad concurrency/cancellation campaign or benchmark baseline.

Therefore no LunaFlux model service, guessed endpoint or placeholder catalog
entry was published. The next valid step is to assemble an approved trained
model rollout and final OCI unit, then run pinned preflight, OpenAI-compatible
invocation, health/readiness observation, cancellation, restart, drain, soak
and benchmark gates under the exact LunaNexa deployment contract. Only after
those pass may LunaNexa approve the runtime template.

## Managed-node artifact hygiene

The physical campaign retained development source snapshots, Moon/Zig tools
and build trees under `/home/jiaanguo/lunaflux-validation`. Five campaign
directories are approximately 1.9--2.0 GiB each; the durable result logs and
small numerical fixtures are only a small fraction of that content. This is a
deployment-boundary defect: managed compute nodes may retain immutable runtime
artifacts and evidence, but not repository checkouts or build toolchains.

Before production enrollment, copy the evidence inventories, result logs and
required immutable binaries/modules to the operator evidence store, verify the
copy by digest, and remove only the identified source/toolchain/build residue
from the worker. Do not delete the campaign directories until that off-node
copy is verified. Future campaigns must transfer a minimal execution bundle
and return evidence, never a repository snapshot.

The non-destructive archive step is complete. The worker and operator machine
both retain `lunaflux-validation-evidence-20260827.tgz`, 7.0 MiB, SHA-256
`72a787a5675c2acde063ff9dda7a2be756fffe6a04d404d44c62b3bb52c7ddd4`.
Its 264 entries include result records, SHA-256 inventories, logs, compact
source snapshots used as provenance, generated CUDA fixture inputs and the
validated residual CUBIN. An independent archive listing confirms that no
directory named `source`, `source-clean`, `moon-home`, `tools` or
`toolchain-20260803` is present.

The operator subsequently authorized cleanup. On 2026-08-28 the worker archive
was rehashed to the same digest and passed a full tar listing before deletion.
Only `/home/jiaanguo/lunaflux-validation` was targeted. An initial owner-level
delete stopped on deliberately read-only evidence directories; their owner
write bit was restored inside that tree only, then the exact tree was removed.
`/home/jiaanguo/lunaflux-validation-evidence-20260827.tgz` remains on the
worker and was rehashed to the same digest after cleanup. No model path,
runtime service, node agent, driver or network configuration was changed.
