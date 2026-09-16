# Registry write-failure regression

## Scope

The durable registry previously mutated its live state before persistence.
A failed save could therefore leave a model, approval, or alias visible in
memory even though the caller received an error. Updates now mutate an
independent restored snapshot and publish it only after persistence returns
successfully. Lock release uses `defer` after acquisition, including readers.

## Local evidence (2026-09-16)

`moon test registry --target native --deny-warn`: 12 passed, 0 failed.

`moon test --target native --warn-list -92-20`: 824 passed, 0 failed.
This full-suite command retains the existing warning exclusions; it is not a
clean full-repository strict-warning gate. PostgreSQL environment-gated tests
are not evidence of a live database run when no database URL is supplied.

- A directory at the test-owned `.next` path forces a real filesystem write
  failure. Model registration leaves memory and the persisted snapshot unchanged.
- Approval and alias promotion failures leave both live and reopened state
  unchanged; removing the obstruction permits retry and restart recovery.
- Two cancelled lock waiters never enter the mutation callback or release the
  owner's lock. A subsequent update and reopen complete within a bounded timeout.
- Public generated interfaces are unchanged.

These are local native regressions, not model inference or hardware acceptance.
They do not prove cancellation during a PostgreSQL commit, resolution of an
ambiguous commit acknowledgement, multi-controller consistency, or deployment
of this change to the acceptance or production controller.

## Live PostgreSQL adapter regression follow-up

On 2026-09-16 the PostgreSQL fixture was expanded beyond opening an empty store.
It acquired primary leadership, rejected a standby acquisition, persisted a
candidate and verified reopen equality. Closing the primary database session
allowed the standby to acquire a higher fencing token. Two writes through the
disconnected original registry then failed without changing its in-memory
snapshot. The successor restored exactly the last committed state, added a
second candidate and verified the new state through another reopen.

The expanded fixture passed 1/1 against a fresh disposable database in the
actual isolated acceptance PostgreSQL Pod, reached only through a loopback SSH
forward. The harness deleted the generated database afterwards. No live model
registry, account, workspace or model file was changed. This proves the tested
closed-connection handoff and failed-write behavior, not PostgreSQL server HA,
unacknowledged commits, a connected stale writer, or runtime deployment.
