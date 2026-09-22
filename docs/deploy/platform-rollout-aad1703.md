# Platform image rollout preparation (2026-09-23)

Prepared, **not applied**. The pinned plan `deploy/platform-images-aad1703.json`
contains four verified image digests for nine deployments. It does not contain
the subsequent shared-storage and replica changes currently under development.
Rebuild and replace this plan after their gate; do not claim aad1703 includes them.

## Snapshot and rollback

Run `scripts/rollout-platform-images.mbtx` on management with arguments:

```
snapshot KUBECONFIG NEW_PRIVATE_BACKUP REVIEWED_PLAN_JSON
apply KUBECONFIG EXISTING_PRIVATE_BACKUP SAME_REVIEWED_PLAN_JSON
rollback KUBECONFIG EXISTING_PRIVATE_BACKUP SAME_REVIEWED_PLAN_JSON
```

Only snapshot was executed. Actual private snapshot directory:
`/home/HwHiAiUser/release-aad1703/pre-rollout-private-20260923`.
It contains the plan and all nine complete original Deployment JSONs (0700
directory, 0600 files). They can contain inline deployment credentials; never
commit or publish these snapshots. The script prints only old image references.

Exact targets: control/control; console/console; enterprise/enterprise;
workbench/workbench (all with `lunanexa-` deployment prefix); the four
`lunanexa-node-agent-spark-*` deployments/container `node-agent`; and namespace
`aigc-acceptance-20260915`, deployment `webide-gateway`, container `gateway`.
Other targets are rejected. H3/GLM, proxy sidecars, environment, replicas,
Services, ConfigMaps, resource grants and business state are not modified.
The apply and rollback modes preflight all current images against snapshot or
planned images and stop on unrelated image drift. Rollout is serial with a
300-second readiness timeout. On failure, earlier targets may already be
updated; invoke rollback explicitly after reviewing the failure. Rollback
restores only the named container images, never the whole historical spec.

## Required configuration review before rollout

The live controller lacks `LUNANEXA_RESERVATION_HOST_JSON`,
`LUNANEXA_WEBIDE_OBSERVATION_TOKEN`, `LUNANEXA_CLIENT_LAUNCH_CATALOG_JSON`,
`LUNANEXA_CLIENT_HTTP_LAUNCH_ORIGINS_JSON` and GPU offering configuration.
Existing single-client settings must be retained/merged into the catalog.

Reservation host JSON fields: `kubernetes_origin`, `token_file`, `ca_file`,
`workload_namespace`/`workload_namespaces`, `node_names`, `infrastructure`.
Observed Spark node IDs equal Kubernetes names:
`spark-25e2-3d35c8fd`, `spark-3782-feee26eb`, `spark-57f5-98a504ed`,
`spark-368c-0f2ee8b2`. Node maps should map each ID to itself. Infrastructure
allowlist must be derived from real approved system pods, not wildcard tenant
workloads. Controller reservation RBAC still requires explicit review.

The live gateway lacks `LUNANEXA_WEBIDE_REQUIRE_EXCLUSIVE`,
`LUNANEXA_WEBIDE_OBSERVATION_TOKEN`, `LUNANEXA_WEBIDE_CONTAINER_FILE`.
Configure one shared observation credential through Secret references in both
controller and gateway; never inline it in this plan. Gateway ServiceAccount
is `aigc-acceptance-20260915/webide-gateway`; shared-storage read RBAC is a
separate artifact and must be reviewed with the final storage class.

The deployment-owned GPU offering env is
`LUNANEXA_GPU_CONTAINER_OFFERING_JSON`: fields `template_id`, `version`,
`display_name`, `client_id`, `image_digest`, `cpu_millis`, `memory_mib`.
It must match the gateway pinned container profile (`image`, `command`, `args`,
`port`, `cpu_millis`, `memory_mib`, `gpu`) and catalog client. No suitable
offering/profile is invented by this image-only helper.

Observed first Spark node runtime config already uses managed namespace
`lunanexa-managed-runtime`, cache `/var/lib/lunanexa/models`, device class
`gpu.nvidia.com`, resource `nvidia.com/gpu`, runtime class `nvidia`; other
node-specific fabric addresses must remain intact. Cache settings can use
new binary defaults. No new model download or live cache deletion was done.

Validation: helper compiles; `--self-test` confirms named-container selection
and rejection of H3 deployment targets. Actual nine-deployment snapshot mode
completed successfully. Apply/rollback remain intentionally unexecuted.
