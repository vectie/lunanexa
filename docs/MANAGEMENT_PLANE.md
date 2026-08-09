# Management plane and one-click model services

## Purpose

LunaNexa's management plane turns the existing registry, scheduler, controller,
node agent, and runtime adapters into a governed model-service product. It is a
higher-level intent layer inside LunaNexa, not a second product and not a new
orchestrator.

The management plane runs outside managed GPU nodes. It owns catalog templates,
deployment planning, durable operations, service readiness, capacity policy,
and operator evidence. The existing controller remains the sole authority that
turns accepted intent into signed, generation-fenced node assignments.

## One-click contract

"One click" means submitting one idempotent `ModelServiceIntent` from an
operator-approved, controller-signed `ModelServiceTemplate`. It never bypasses
license acceptance, artifact and image verification, evaluation, alias
approval, data-class policy, secret references, capacity checks, or node
readiness.

The flow is:

```text
catalog template
→ deterministic preflight plan
→ durable deployment operation
→ signed desired assignments
→ node reconciliation
→ observed runtime readiness
→ provider-neutral service endpoint and audit receipt
```

If a prerequisite is absent, the operation is durable but `Blocked`; its
preflight findings identify the missing approval, evidence, secret reference,
or capacity. Re-submitting the same idempotency key returns the same operation.

## Public resources

- `ModelServiceTemplate` is an immutable catalog entry naming exact model and
  runtime digests, resource/network/health/data policy, secret references, and
  rollout policy.
- `ModelServiceIntent` is the compact northbound request: deployment identity,
  template reference, replica count, data class, lease, and promotion choice.
- `DeploymentPlan` records deterministic selected nodes and all preflight
  findings without exposing runtime endpoints or node credentials.
- `DeploymentOperation` is restart-safe progress and evidence for a deployment.
- `ServiceEndpoint` exposes only the canonical workload path and model selector.

Public concrete types are owned by the `deployment` package. Native durable
storage and signing live in `deployment/store`; UI and automation consume the
same public types.

## API

```text
GET    /v1/catalog/templates
POST   /v1/catalog/templates
POST   /v1/deployment-plans
GET    /v1/service-deployments
POST   /v1/service-deployments
GET    /v1/service-deployments/{deployment_id}
POST   /v1/service-deployments/{deployment_id}/promote
POST   /v1/service-deployments/{deployment_id}/rollback
POST   /v1/service-deployments/{deployment_id}/scale
DELETE /v1/service-deployments/{deployment_id}
GET    /v1/operations/{operation_id}
```

Template registration is an operator approval action. The controller replaces
empty approval/signature fields with a receipt and management-plane signature;
callers cannot mint accepted catalog entries themselves.

## Reconciliation and recovery

An executable plan is persisted before assignments are published. Assignment
publication is idempotent by assignment ID and generation. A controller restart
reloads operations, and an operation remains `Reconciling` until every planned
assignment is durable and every selected node reports the deployment ready.

Rollback and deletion remove the operation's assignments through the existing
audited controller path. Scaling creates a new operation generation and a new
deterministic plan; scale-down removes assignments no longer in the plan.

## Installation boundary

Installing LunaNexa and deploying a model service are separate operations.
Kubernetes or GitOps installs the LunaNexa management components from signed,
digest-pinned artifacts. LunaNexa deploys model services through its node-agent
contract. The controller does not acquire a general Kubernetes service-account
token, and nodes never receive Kubernetes credentials, repositories, editor
runtimes, MoonSuite state, or arbitrary shell instructions.
