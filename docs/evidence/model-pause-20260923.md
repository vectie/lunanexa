# H3 / GLM temporary acceptance pause

On 2026-09-23 the operator explicitly requested temporarily stopping H3 and
GLM to test existing business delivery. This maintenance action does not renew
the expired customer grant or imply business acceptance.

## Observed result

- Namespace `lunanexa`: Deployments `minimaxh3-fl2va` and
  `minimaxh3-ref2va` changed from one replica each to zero. Both reported 0/0
  and their Pod selectors returned no Pods after termination.
- Spark `192.168.2.178`: existing Docker container `glm53-exl3-head` stopped;
  subsequent inspection reported `exited`.
- Spark `192.168.2.179`: existing Docker container `glm53-exl3-worker` stopped;
  subsequent inspection reported `exited`.
- `nvidia-smi --query-compute-apps=pid,process_name,used_memory` returned no
  compute processes on each of the four Sparks after the pause.
- `glm53-nfs` remained running on `.178`. No model files, volumes or containers
  were deleted. No unknown workload was stopped.

## Recovery material

Management host private backup root:
`/home/HwHiAiUser/h3-component-preparation.K9UzNR`.

`h3-pause-backup/` contains the two original Deployment JSON documents;
`glm-pause-backup/` contains the two full original Docker inspections.
Directories are private and backup files mode 0600. Raw backup content must
not enter Git or reports because deployment environments may contain secrets.

The checked-in `.mbtx` pause scripts back up both members before stopping
either. The Kubernetes action uses the observed current replica count as a
precondition; Docker actions address inspected full container IDs.

To restore after acceptance workloads have drained and their exclusive
reservations have released, first recheck placement and availability. Restore
the two H3 replica counts to their recorded value (one each), and start the
same retained GLM head/worker containers on their original hosts. Check actual
model readiness before advertising either service. Do not restore shared
inference onto a customer-reserved node. Manual Docker stop retains the
original restart policy; a Docker daemon restart needs a fresh workload audit.

This evidence proves only the observed pause, not continuing absence of new
workloads, a working restoration, or successful customer model inference.
