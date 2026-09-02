# Ascend 310P3 temporary-compute qualification

Date: 2026-08-27

This document records the observed state of the current management/data host
and the evidence required before that same physical machine may also carry a
temporary LunaNexa compute role. It is not a DGX substitute and does not change
the future DGX Spark acceptance profile.

## Current verdict

**Management placement may proceed after the guarded UI Apply is explicitly
confirmed. Compute enrollment is blocked.** The host-level Ascend device is
healthy, but Kubernetes and the current LunaNexa node runtime do not provide a
complete Ascend execution path.

Observed host evidence:

- x86_64 Ubuntu 20.04 with a 5.4 kernel;
- Huawei PCI device `19e5:d500` and `/dev/davinci*` device files;
- one Ascend 310P3 reported healthy by `npu-smi 23.0.0`;
- driver/firmware installation at `/usr/local/Ascend`;
- CANN toolkit reported as 7.0.0;
- no Docker, Podman or Ascend container runtime available to the selected user;
- no `huawei.com/Ascend*` Kubernetes capacity, Ascend device-plugin workload or
  reviewed Ascend RuntimeClass.

The repository also remains NVIDIA-specific at the node execution boundary:
the telemetry collector accepts only `nvidia-smi`, and the OCI supervisor emits
`NVIDIA_VISIBLE_DEVICES`. Therefore a healthy `npu-smi` result alone cannot
produce a truthful LunaNexa heartbeat or launch an approved runtime.

Installer Preview now fails closed in both relevant cases:

1. host preflight detects Ascend but the release has no reviewed CANN/device-
   plugin/telemetry/supervisor adapter; or
2. a selected NVIDIA host does not expose positive `nvidia.com/gpu`
   allocatable capacity through Kubernetes.

Detection never creates compute authority.

## Required qualification sequence

Complete these gates in order and retain their outputs as one evidence bundle:

1. **Compatibility decision:** select and pin a mutually supported host OS,
   kernel, driver, firmware, CANN, PyTorch/torch-npu and serving-runtime matrix.
   Do not upgrade the existing driver or CANN in place without a tested reboot
   and rollback plan.
2. **Container boundary:** install a reviewed Ascend OCI runtime integration and
   prove a digest-pinned diagnostic container can see only its assigned device.
3. **Kubernetes authority:** install a reviewed Ascend device plugin and require
   positive `huawei.com/Ascend*` allocatable capacity on the exact node. Exercise
   plugin restart, K3s restart and full host reboot.
4. **LunaNexa adapter:** add an Ascend telemetry collector and an accelerator-
   neutral runtime-supervisor device contract. Keep NVIDIA and Ascend arguments
   in separate reviewed adapters; do not branch on untrusted model metadata.
5. **Serving runtime:** select a CANN-compatible, digest-pinned runtime and prove
   health, readiness, cancellation, timeout, memory limits and clean stop with a
   licensed small model.
6. **Model evidence:** verify license, exact revision, size, SHA-256, signature,
   architecture compatibility and evaluation results before publishing a model
   alias.
7. **UI enrollment:** run **Add compute nodes** Preview. Only after all prior
   evidence is green may Apply install node material, issue the one-use token,
   start the node agent and require a fresh unique heartbeat.
8. **Failure campaign:** remove the device plugin, kill the runtime, restart
   K3s, reboot the host, exhaust device memory, expire a lease and reclaim the
   node. Every failure must remain bounded and auditable.

Huawei's published MindIE 1.0 documentation names newer CANN stacks than the
observed CANN 7.0 host, including CANN 8.0 RC3 for MindIE 1.0 RC3 and CANN 8.0.0
for the MindIE 1.0.0 container example. Those documents are compatibility
inputs, not authorization to change this host:

- <https://www.hiascend.com/document/detail/zh/mindie/10RC3/envdeployment/instg/mindie_instg_0008.html>
- <https://www.hiascend.com/document/detail/zh/mindie/100/envdeployment/instg/mindie_instg_0023.html>

## MiniCPM and LunaFlux boundary

`OpenBMB/MiniCPM5-1B` is the small staging candidate. The observed ModelScope
tree revision is `fc2e73f63bbf2cce5739929c2bebbb046fbfae8d`. ModelScope's
download route accepts `master` but currently returns HTTP 500 when that commit
is placed in the resolve URL, so the staging recipe treats the branch as an
untrusted transport and admits every file only by its exact size and SHA-256.
The official repository listing and public Git/LFS metadata were independently
rechecked from the operator machine:

- weight file: `model-00000-of-00001.safetensors`;
- expected size: `2161290912` bytes;
- expected SHA-256: `7ab8fd86563125929be78aeec8cb3969c7ed2ead3be1ab9d3ec0a9fa69c8660d`;
- tokenizer size/SHA-256: `9894271` bytes /
  `3e065a558a034185fe299917b398685c1facd0169a9eea1e629eb30c171fed81`;
- architecture: standard `LlamaForCausalLM`, BF16, 24 layers;
- the two README files and `.gitattributes` are retained in the staged snapshot;
- the repository README declares Apache-2.0, but the snapshot contains no
  standalone `LICENSE` file, so license acceptance must retain the upstream
  license reference rather than pretending the snapshot is self-contained.

The same upstream README links an Ascend-specific
`FlagRelease/MiniCPM5-1B-ascend-FlagOS` variant, but its repository metadata was
not anonymously retrievable during this run. Treat that link as an unverified
candidate, not a downloadable or approved artifact.

The first download attempt exposed a stale-manifest bug: an obsolete recipe
listed a nonexistent `configuration.json` and failed closed after two small
files. It created no staging evidence and registered nothing. The corrected
recipe covers all 11 files in the observed tree and uses a fresh destination;
it remains an unapproved staging operation until the complete manifest passes.

After the management foundation is healthy, the operator may inspect the
immutable staging plan and then run the resumable content-verifying download on
the management host:

```sh
scripts/deploy/stage-minicpm5-1b.sh --plan
scripts/deploy/stage-minicpm5-1b.sh --download \
  --destination /data/models/.staging/minicpm5-1b-fc2e73f
```

The ModelScope `master` transport is mutable, so the recipe accepts each file
only when its exact size and SHA-256 match the pinned manifest. Completion
creates `staging-evidence.json` with `approval_state=StagingOnly`; it never
registers, approves or publishes the model.

LunaFlux is currently a CUDA backend. Its product contract, runtime supervisor
and physical promotion gates do not provide an Ascend/CANN/ACL path. It must not
be represented as an inference engine for this 310P3. LunaFlux can be evaluated
later on the DGX Spark profile after its own physical CUDA gate passes, or after
a separately designed and tested Ascend backend exists.

## Access incident during qualification

After successful earlier sessions, both public SSH forwarding ports began
accepting TCP and closing before an SSH banner or key exchange. The access node
later returned while the management host still failed ARP on `192.168.2.175`.
Physical observation then established that two live LAN paths disrupted the
switch and that removing the wrong cable also removed the management path.

The persistent host configuration had combined `eni3` and `eni0` in
`br-ngfw-in` with STP disabled while also accepting DHCP address
`192.168.2.9` beside static `192.168.2.175`. Bridge forwarding evidence showed
the management router and access node behind `eni3`. A timed, automatically
reversible Netplan change retained only `eni3`, made `.175` the sole static
management address and default-route source, and left `eni0` unconfigured.
Fresh direct and jump-host SSH, gateway, DNS, external HTTPS and K3s readiness
checks passed. Management Apply is now allowed only under the network freeze
recorded in `docs/MANAGEMENT_FOUNDATION_UI_RUNBOOK.md`; temporary Ascend compute
enrollment remains blocked.
