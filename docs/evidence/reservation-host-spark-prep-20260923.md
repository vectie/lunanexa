# Four-Spark reservation host wiring — staged infrastructure

Status: scoped RBAC and ConfigMap **created**; controller patch only passed
server dry-run, **not activated**. No host installations, Pod deletion, taint
changes or credential reads. This config does not imply that NFS, model serving
or the delivery UI has passed live acceptance.

## Actual inventory

All four Kubernetes names match enrolled node IDs:

| IP | Kubernetes/enrolled node |
| --- | --- |
| 192.168.2.176 | spark-25e2-3d35c8fd |
| 192.168.2.177 | spark-3782-feee26eb |
| 192.168.2.178 | spark-57f5-98a504ed |
| 192.168.2.179 | spark-368c-0f2ee8b2 |

The live cluster returned 36 nonterminal Pods across these four nodes: nine infrastructure identities, one Pod of each identity per node. No unknown/non-infrastructure nonterminal Kubernetes Pods were found on these nodes in this observation. Terminal debug/transfer Pods are ignored by the adapter's existing phase rule, not by extra exemption rules. This inventory does not enumerate arbitrary host processes; existing host-level audits remain required, and the separate GLM NFS container on .178 is intentionally untouched.

| Namespace | Service account | Exact label key=value | State |
| --- | --- | --- | --- |
| lunanexa | lunanexa-node | app=lunanexa-node-agent | Running ×4 |
| kube-system | default | app.kubernetes.io/name=nvidia-device-plugin | Running ×4 |
| dra-driver-nvidia-gpu | dra-driver-nvidia-gpu-service-account-kubeletplugin | dra-driver-nvidia-gpu-component=kubelet-plugin | Pending ×4 |
| kube-system | svclb | app=svclb-comfyui-public-77e2cfa7 | Running ×4 |
| kube-system | svclb | app=svclb-glm53-exl3-a5867a07 | Running ×4 |
| kube-system | svclb | app=svclb-lunanexa-console-public-32ba9a98 | Running ×4 |
| kube-system | svclb | app=svclb-lunanexa-coursebook-public-2d9e97b3 | Running ×4 |
| kube-system | svclb | app=svclb-lunanexa-identity-public-6d5d117f | Running ×4 |
| kube-system | svclb | app=svclb-traefik-7f511ce3 | Running ×4 |

DRA's init container has `ImagePullBackOff`: `registry.k8s.io/dra-driver-nvidia/dra-driver-nvidia-gpu:v0.5.0` is being routed to `docker.m.daocloud.io`, whose manifest HEAD returns **403 Forbidden**. It is an identified infrastructure component, but this exemption does not claim that DRA works. Existing legacy NVIDIA device-plugin Pods are Running. No DRA/image-mirror changes were made in this subtask.

The active `lunanexa/lunanexa-control` Deployment uses SA `lunanexa-control`, `automountServiceAccountToken=false`, Pod UID/fsGroup 1000, and containers `identity-relay`, `runtime-loopback-proxy`, `control`, `runtime-loopback-proxy-glm`. The new projection is mounted only in `control`; other containers keep their current mounts and receive no Kubernetes token from this patch.

## Prepared artifacts

- `deploy/reservation-host-spark.json`: exact nine infrastructure rules, four node mappings, workload namespaces `lunanexa-managed-runtime` and `aigc-acceptance-20260915`.
- `deploy/reservation-host-spark-rbac.yaml`: node get/patch restricted by four explicit `resourceNames`; cluster-wide Pod list only, needed to discover occupants outside known namespaces. No node list/update/delete, Pod mutation, Secret access or wildcard resources/verbs.
- `deploy/reservation-host-spark-control.patch.yaml`: **strategic merge patch**, not a complete Deployment. ConfigMap-backed host JSON and projected one-hour service-account token plus namespace cluster CA, mode 0440, mounted only in `control`. Token audience is omitted so Kubernetes uses its API audience. No static bearer token committed; adapter reads projected token on each request, permitting rotation.

`workload_namespaces` is **not** a namespace exemption: only Pods bearing the matching reservation ownership label in one of those namespaces pass while reserved. During release, even owned nonterminal customer Pods continue to block. `lunanexa` is deliberately not a workload namespace because it contains the exempt node-agent identity; the adapter rejects an infrastructure exemption inside a workload namespace.

The exact svclb `app` values include Service-derived IDs. Recreated Services must be re-inventoried; unknown replacements block reservations instead of receiving a namespace-wide exception. If/when the prepared NFS node DaemonSets are installed, add their then-observed exact namespace/SA/app identities after verifying them. This draft deliberately does not pretend those not-yet-installed Pods were observed.

## Validation and coordinated application

- Both RBAC documents passed client dry-run using management's existing kubeconfig.
- ConfigMap creation from the JSON passed local client dry-run.
- Deployment patch passed server admission dry-run but has not been applied;
  reserve/release and token rotation require a coordinated rollout with the
  updated control binary.

Main-task staging subsequently verified both same-name RBAC resources were
absent, ran server dry-run, then created the ClusterRole and ClusterRoleBinding.
The ConfigMap was created using `create` (not overwrite/apply). Authorization
checks as `system:serviceaccount:lunanexa:lunanexa-control` returned:

- `patch node/spark-25e2-3d35c8fd`: yes.
- `patch node/ubuntu`: no.
- `get secrets -n lunanexa`: no.

These checks prove effective permission scope for those tested actions, not
physical reservation enforcement. No Deployment was changed or restarted. The
new objects had no prior versions to restore; rollback before activation means
removing only the newly created binding/role/ConfigMap after confirming no
controller references them. Do not remove them after activation without first
coordinating the controller configuration rollback.

After main coordination, from a checkout containing these files and using the explicit management kubeconfig:

```text
kubectl --kubeconfig /home/HwHiAiUser/.kube/lunanexa-management -n lunanexa create configmap lunanexa-reservation-host-spark --from-file=config.json=deploy/reservation-host-spark.json
kubectl --kubeconfig /home/HwHiAiUser/.kube/lunanexa-management apply -f deploy/reservation-host-spark-rbac.yaml
kubectl --kubeconfig /home/HwHiAiUser/.kube/lunanexa-management -n lunanexa patch deployment lunanexa-control --type=strategic --patch-file deploy/reservation-host-spark-control.patch.yaml
```

Inspect an existing same-name ConfigMap rather than overwriting it blindly. Ensure any older generic `lunanexa-reservation-host` ClusterRoleBinding is absent or intentionally replaced: adding a narrow role does not remove broader grants from another binding. Confirm `control` can get/patch the four nodes and list Pods, cannot patch management `ubuntu`, and sidecars have no token volume mount. Keep token automount disabled. No `kubectl exec` secret output is needed for these checks.

NFS host enablement remains separate and was not attempted; the blocked sudo credentials were not worked around.
