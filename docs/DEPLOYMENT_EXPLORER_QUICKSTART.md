# Explore saved service-deployment placements

`cmd/deployment-report` joins saved operation and node response bodies and exports
operation overviews, planned placements, or both as JSON. This is an offline
operator workflow: no server, live fetch, mutation, provisioning or readiness gate.
It complements the existing live console and offline fleet/history explorers.

## Run the invented example

Build the native executable with your normal pinned MoonBit environment. Keep
all generated targets outside source and evidence:

```text
moon build --frozen --target native --strip -j1 --target-dir /absolute/private/build cmd/deployment-report --deny-warn
```

The executable is under
`/absolute/private/build/native/debug/build/vectie/lunanexa/cmd/deployment-report/deployment-report.exe`.
With `REPORT` set to that executable and `FIXTURES` to this repository's
`tests/fixtures` directory:

```text
$REPORT deployments $FIXTURES/deployment-operations.synthetic.json $FIXTURES/deployment-nodes.synthetic.json $FIXTURES/deployment-query.synthetic.json > deployments.csv
$REPORT placements $FIXTURES/deployment-operations.synthetic.json $FIXTURES/deployment-nodes.synthetic.json $FIXTURES/deployment-query.synthetic.json > placements.csv
$REPORT json $FIXTURES/deployment-operations.synthetic.json $FIXTURES/deployment-nodes.synthetic.json $FIXTURES/deployment-query.synthetic.json > report.json
```

The invented example preserves two historical operations for one deployment.
One records Ready and five planned replicas; the other records Blocked with an
unresolved template and zero planned replicas. Two replicas share node A, whose
heartbeat lists the deployment. Node B does not list it and is stale. Node C is
future-dated. The final planned node has no supplied heartbeat. No actual GPU,
model response or service delivery is represented by these fixtures.

## Use your existing saved responses

1. Retain the existing authorized JSON bodies of `GET /v1/service-deployments`
   (`deployment.DeploymentOperation[]`) and `GET /v1/nodes`
   (`contracts.NodeHeartbeat[]`) in approved private storage. No acquisition is
   performed by this tool. Durable-store wrappers and inventory-only files are
   not accepted. Do not copy access credentials.
2. Copy the query. Set explicit `now_unix_ms` and `maximum_age_ms` as quoted
   decimal millisecond strings. There is no hidden clock or timezone conversion.
3. Leave `deployment_id`, `model_id`, `operation_state`, and `node_id` empty to
   include all values, or supply exact case-sensitive filters. All filters use
   AND. Model filtering requires a resolved template with that exact model ID.
   Operation states are Submitted, Blocked, Planned, Reconciling, Ready,
   Degraded, RollingBack, RolledBack, Failed, and Deleted.
4. A node filter selects planned replicas on that node and includes an overview
   only if the operation has at least one matching planned replica. Without a
   node filter, zero-replica and unresolved-template operations remain visible.
   Each overview preserves the whole operation's `requested_replicas` and
   `planned_replicas`; `selected_placements` counts the filtered rows. These are
   placement records, never an independently observed ready-replica count.
5. Change the query and rerun. No input is modified. Empty selections produce
   empty JSON arrays and header-only CSV. Preserve both originals and the query
   for reproduction; CSV is a projection, not an importable operation snapshot.

## Interpret the observations

`recorded_operation_state` is supplied history, not independently verified
current availability. Model/version/artifact digest and runtime name/version/image
digest are narrow projections from the resolved template. Absent template
properties are omitted in JSON and blank in CSV, never guessed from display names.

`node_deployment_membership` is exactly one of:

- `listed`: the supplied node heartbeat lists this deployment ID
- `not-listed`: that heartbeat does not list this deployment ID
- `missing-node`: no heartbeat for the planned node was supplied

These are node-level observations. Repeating `listed` on two replicas sharing a
node does not prove either individual replica ready. The report lacks matching
assignment, generation, lease, signature and epoch evidence used by the actual
controller readiness function. Missing membership does not prove failure,
confirmed absence or causality. Out-of-plan memberships are not evaluated or
labelled rogue. Planned device IDs remain planned references even when the
heartbeat has no accelerator inventory; device availability is not inferred.

Fresh means `0 <= now - observed <= maximum_age`. Exact threshold is fresh;
older is stale; later timestamps are future with absent age. Missing nodes have
`missing-node` freshness and no observation timestamp/state/age. This compares
supplied times only, without verifying clocks, authenticity or reachability.

Ordering is by operation ID, then replica ID; device lists are sorted copies.
Input order and source arrays are unchanged. JSON keeps exact decimal-string
Int64 values; absent options are omitted. CSV is UTF-8 with CRLF, quoted present
cells, doubled quotes, and leading apostrophes for formula-like text. The device
column contains a JSON array inside the CSV cell. Import large numeric columns
as text in spreadsheets to avoid rounding; JSON preserves the exact values.

Reports omit signatures, secret references, endpoints, artifact URIs, arbitrary
labels, messages and audit free text. They remain private operator data and do
not sanitize source files or authenticate evidence.

## Bounds and failures

Each CLI source is at most 16 MiB and the query 16 KiB, strictly decoded as UTF-8.
Portable importers cap each source at 8 Mi UTF-16 characters and query at 16 Ki.
At most 1,000 operations, 10,000 nodes, 5,000 total planned replicas, 20,000 total
planned device references and 20,000 total node membership references are supported.
Exported identities must contain 1–512 UTF-16 characters; optional filters allow
empty strings. Timestamps and age thresholds are 0–9007199254740991 ms. Generation
is a nonnegative Int64 and requested replica count a nonnegative Int. Each output
is capped at 8 Mi UTF-16 characters before any stdout write.

Duplicate operation/node IDs, mismatched node inventory identity,
operation–intent deployment identity or resolved-template reference, duplicate
replicas within an operation, and duplicate device IDs within a replica reject
the complete report, including invalid rows outside the filter. Separate
operations sharing a deployment ID are supported. Unknown query fields fail;
source decoding retains existing public contract behavior for unknown fields.
Other template policies, signature trust and full snapshot validity are not
revalidated. Errors exit nonzero with stderr and empty stdout. Same-size file
replacement during acquisition is not detected; keep originals stable.

## Focused verification

Portable tests run on native and JS. The native CLI package test invokes the
actual built executable, saves and reopens outputs, and checks unchanged inputs.
It requires `DEPLOYMENT_REPORT_EXE`, `DEPLOYMENT_REPORT_FIXTURES`, and
`DEPLOYMENT_REPORT_EVIDENCE` pointing to that executable, this fixtures directory,
and an existing private writable evidence directory. Build the executable first.
No tests are silently skipped when these are absent; the test explains the missing
configuration. Scope does not include live HTTP/auth, console, controller,
whole-workspace, physical-cluster or production qualification.
