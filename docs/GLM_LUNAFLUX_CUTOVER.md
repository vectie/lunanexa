# GLM LunaFlux route cutover

The existing company route `glm-5.3.flash` is being migrated from the stopped
EXL3/vLLM pair to the validated LunaFlux NVFP4 pair. This is an explicit
externally operated text binding, not a fabricated single-node managed
deployment. LunaNexa owns tenant admission, the public alias, metadata and
the lifecycle adapter; LunaFlux owns inference and the two-rank protocol.

## Deployment contract

- Preserve the public alias and company scope. Publish NVFP4 as a distinct
  checkpoint version, never relabel the old EXL3 artifact as NVFP4.
- Resolve the backend credential from deployment-owned secret configuration;
  pass it to readiness and inference, never to public responses.
- Use persistent paired native units with coordinator-first graceful stop,
  `KillMode=mixed`, bounded termination and no acceptance-run time limit.
- Start the peer before the coordinator, only with both GPUs idle and at least
  16 GiB host memory available. Keep each rank at 100 GiB, no unit swap.
- Observe both units and memory while running. A peer exit or resource-limit
  violation stops the owned pair, not unrelated workloads. Do not independently
  restart one TP rank into a surviving peer.
- The tested initial allocation is four resident sequences, 64 prefill rows
  and 2048 context tokens per sequence. This is an allocation, not the model's
  architectural context limit or a claim of all vLLM features.
- Reuse the source-pinned executable and AOT files validated on both Sparks;
  do not compute payload hashes or scan checkpoint integrity during cutover.
  Existing declared artifact identifiers remain metadata, not new verification.

## Rollout and acceptance

Keep the public route unavailable until private loading, real gateway JSON/SSE
generation, model identity, concurrency, cancellation/reuse and memory checks
pass. Preserve the previous route configuration and stopped containers for
rollback; rollback must not silently restore the old engine without operator
intent. Test lifecycle stop/start through LunaNexa before enabling public
traffic. Record actual results here; the plan itself is not evidence of an
online service.
