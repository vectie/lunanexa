# Native lease helper acceptance — 2026-09-15

The existing `scripts/lease-cleanup-simulation.sh` passed on the Linux AMD64
management host with MoonBit 0.10.10 after adding explicit `-pthread -ldl`
native link flags to both helper executables. Before this correction, native
linking failed with unresolved pthread symbols, so the suite could not run.
The simulation node executable needs the same flags and was previously built
and exercised in the isolated controller acceptance environment.

Validation:

- Native builds of `cmd/lease-helper` and `cmd/lease-helper-authorize-fixture`
  succeeded.
- `moon info --target native cmd/lease-helper
  cmd/lease-helper-authorize-fixture cmd/sim-node` succeeded.
- The unmodified cleanup simulation script exited 0 and printed
  `exclusive lease cleanup simulation passed`.
- The host lacked `rg`; an Ubuntu ripgrep package was extracted into the
  acceptance tooling directory and added only to the test process PATH.
  No system installation was changed.

The suite uses isolated temporary directories and fake host commands. It
checks signed helper receipts, credential prerequisites, stale generations,
provision/revoke/sanitize behavior and repeated cleanup, cross-lease rejection,
home-marker tampering, account/process inventory failures, stuck processes,
and stuck runtime cleanup/quarantine behavior. Its temporary test roots are
removed by the existing script's exit trap.

This is software simulation evidence, **not** real Unix account provisioning,
SSH credential issuance, disk erasure, GPU inference, or Spark qualification.
No helper receipt from this suite was submitted to an order. The end-to-end
ComfyUI order and authenticated video pipeline remain separate pending tests.
