# Exclusive delivery operations

This native package owns the restart-safe progress of one authorized delivery.
It does not grant authority, reserve nodes, run Kubernetes, or assert readiness
on its own. The controller resolves an approved template and live authorization,
then calls `create`. Repeated tenant/organization/idempotency keys return the same
operation; a changed intent conflicts.

The controller drives one stage at a time:

- `Reserving`: reserve the complete node set with the scheduler reservation
  authority, using the operation ID as a stable reservation/service identity.
- `PreparingModel`: report actual transfer progress; issue `ModelPrepared` only
  after the node materializer verifies and atomically publishes the exact digest.
- `LoadingModel`: issue `ModelResponded` only after a response from the exact
  selected model/runtime, not a Kubernetes Running condition. Text uses a small
  inference probe. Media requires loaded health plus the expected provider model
  identity; that readiness probe does not substitute for actual video generation.
- `StartingWorkspace`: restore the persistent volume, configure the selected
  model/workflow, then report a successful workspace/terminal response.
- `Ready`: publish access through the tenant-bound public gateway.

IaaS without an approved model mount skips model preparation. IaaS with a model
mount prepares weights but does not start managed inference. MaaS stops at a
verified model response and does not create a workspace.

`observe`, `retry` and `stop` carry the current generation. Adapter resource names
must be derived from the stable operation ID, not the observation generation, so
a crash between adapter success and persisted observation does not duplicate
resources. `Failure` remembers the stage to retry and retains reservation and
workspace references. Error codes must be public-safe codes, not exception text.

`expire_due` requests stopping before the next dispatch. Gateway/API admission
must independently enforce live lease expiry; this operation state is not an
authorization cache. Stopping does not erase workspace volumes or public model
caches. `WorkloadsStopped` requires actual adapter termination evidence, after
which the controller separately asks the scheduler to release its reservation.
If other services still claim that reservation, their claims must remain.

File snapshots are an atomic local fallback. Production uses PostgreSQL domain
`exclusive_deliveries`, schema `lunanexa.exclusive-deliveries.v1`, under the
existing single-active controller leadership boundary.

Operation records contain internal node IDs. Public enterprise projections must
omit them and return only counts, stages, model/template versions and safe
failure codes. Business authorization and physical GPU/model/UI acceptance are
integration requirements, not claims made by this package's unit tests.
