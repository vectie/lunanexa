# Exclusive-node migration: live inventory

Observed 2026-09-22 16:21–16:27 UTC (2026-09-23 00:21–00:27 Asia/Shanghai).
This is a read-only deployment inventory, not a resource grant or delivery acceptance.
No process, Pod, Service, storage, or authorization was changed. No generation was
submitted. Kubernetes observations used the management kubeconfig through the
existing SSH access; physical GPU/storage observations used existing SSH access
from management to each Spark. Public HTTP checks originated on the operator's
external client, not inside the cluster.

## Physical nodes and occupied resources

All five nodes were Ready, running Kubernetes v1.34.10+k3s1 and containerd
2.2.5-k3s2. Four Spark hosts report Ubuntu 24.04.5 LTS, NVIDIA kernel
7.0.0-1019-nvidia, one NVIDIA GB10 each, 20 allocatable CPUs and approximately
121.7 GiB allocatable memory. Management `ubuntu` is 192.168.2.175.

| Node / IP | Actual GPU process | GPU process accounting | Root filesystem available | Existing model placement |
| --- | --- | --- | --- | --- |
| spark-25e2-3d35c8fd / .176 | H3 FL2VA, PID 940867, vLLM-Omni diffusion worker | 96,461 MiB | 3.0 TiB, 16% used | FL2VA and Ref2VA directories, approximately 135 GiB each; original shared H3 files also present |
| spark-3782-feee26eb / .177 | H3 Ref2VA, PID 823489, vLLM-Omni diffusion worker | 93,989 MiB | 3.3 TiB, 7% used | Ref2VA directory approximately 135 GiB |
| spark-57f5-98a504ed / .178 | VLLM Worker TP0, PID 960357 | 102,154 MiB | 3.3 TiB, 8% used | `/var/lib/lunanexa-models` absent; host inference uses another cache |
| spark-368c-0f2ee8b2 / .179 | VLLM Worker TP1, PID 1094338 | 102,152 MiB | 3.4 TiB, 4% used | `/var/lib/lunanexa-models` absent; host inference uses another cache |

These are point-in-time measurements, not guarantees of allocatable space.
Directory `du` figures must not be summed without checking hard links/shared
content. GPU utilization was 0% at sampling time: this does **not** mean a loaded
model's node is free. NVIDIA's whole-device memory used/total fields returned
N/A on GB10; process accounting did return the figures above. Kubernetes top
reported only 12,766 / 10,365 / 7,855 / 5,747 MiB respectively. Do not use that
lower pod/node metric alone to decide Spark unified-memory capacity.

**None of the four nodes can currently be classified as unoccupied.** A new
exclusive allocation must coordinate these existing runtimes, identify their
authorization/owners, and observe their stop/drain or authorized adoption. This
inventory neither authorizes stopping them nor assigns them to a new customer.

## H3 deployment facts and reuse options

Both Deployments are in namespace `lunanexa`, with 1/1 Ready Pods:

| Deployment | Fixed node | Read-only host model directory | Service |
| --- | --- | --- | --- |
| minimaxh3-fl2va | spark-25e2-3d35c8fd | `/var/lib/lunanexa-models/minimaxh3/minimaxh3/FL2VA` | minimaxh3-fl2va:8000 → 10.42.2.224:8000 |
| minimaxh3-ref2va | spark-3782-feee26eb | `/var/lib/lunanexa-models/minimaxh3/minimaxh3/Ref2VA` | minimaxh3-ref2va:8000 → 10.42.3.129:8000 |

Both use tag `lunanexa-cache/vllm-omni-h3:20260914`; the observed running image
ID is `sha256:c3cbf972d026ba07223135b1d6b603edb980aa3123c1ead1dc918f057f21f4e3`.
Requests are 4 CPUs / 96 GiB / one GPU; limits are 16 CPUs / 118 GiB / one GPU.
The runtime has SM121 and serving-video patches, plus an FL2VA progress patch.
Preserve these functioning runtime compatibility adaptations when constructing
the unified adapter. Both use an 8 GiB memory-backed `/dev/shm` and ephemeral
Hugging Face cache. Readiness is HTTP `/health`, every 15 seconds.

Unauthenticated `/v1/models` requests to both H3 services returned Unauthorized.
This confirms protected reachable endpoints, **not successful inference**.
Existing health readiness and GPU workers likewise do not substitute for a
generation test. No credentials were read for this inventory.

Reusable assets: node-local H3 files, already loaded compatible runtime image,
read-only mount arrangement and existing runtime patches. Missing integration:
immutable registered cache identity/completeness evidence, tenant-bound node
reservation and adoption, data-node replenishment when a directory is absent,
and actual per-customer inference readiness. Do not treat fixed Directory
hostPath success as proof of automated materialization.

The selectorless `glm53-exl3` Service (8899 / NodePort 32527) points to
192.168.2.178:8888. Its read-only `/v1/models` response identifies
`GLM-5.3-Flash-EXL3`, model root under the Hugging Face snapshot cache for
`Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw`. TP0/TP1 run as host processes on .178
and .179, not as visible inference Pods. Kubernetes GPU allocation alone will
therefore miss these occupied hosts. No inference request was submitted.

## Workspace and cache storage

- `comfyui-acceptance` runs on management `ubuntu`, not an exclusive Spark. Its
  `/workspace` is a 20 GiB `local-path` PVC bound to management. Its public
  service still selects `app=comfyui-acceptance`.
- It additionally mounts management `/data/models` read-only at
  `/workspace/models`, `/data/models/comfyui` at `/opt/ComfyUI/models`, and
  host patch/template directories. The latter model/template mounts are not
  all read-only. Do not carry broad shared host paths into user delivery.
- Two historical `webide-*` 20 GiB PVCs are also bound to management. Their PV
  reclaim policy is Delete. They survive Pod deletion but must not be deleted
  during instance stop/retry; they are not cross-node shared storage.
- `comfyui-minimaxh3-spark-pv` is a 600 GiB Retain PV bound to
  `comfyui-minimaxh3-spark`, fixed to .176 and host directory
  `/var/lib/lunanexa-models/minimaxh3`. It is not a tenant workspace volume.
- A 40 GiB offline object-store PVC exists on management. Its existence does
  not establish that the data-node model source or model transfer uses it.
- All four Sparks have one allocatable `nvidia.com/gpu`; no taints were shown.
  Explicit exclusive reservation enforcement remains necessary for non-GPU
  Pods and host-native workloads as well as GPU-requesting Pods.
- Traditional NVIDIA device-plugin Pods are Running on all four hosts. A
  separate NVIDIA DRA plugin is stuck in Init:ImagePullBackOff on all four;
  do not require that unused path for the first existing-runtime delivery.

## Management ingress and external observations

| Published port | External read-only HTTP result | Management observation |
| --- | --- | --- |
| 4174 `/console/` | 200 | 0.0.0.0:4174 listening |
| 5002 `/enterprise/` | 200 | .175:5002 and loopback listeners |
| 5000 `/` | Empty reply, curl status 000; repeated with proxy bypass | .175:5000 returns 200; ClusterIP:5000 and ComfyUI Pod:8188 return 200 |
| 5001 `/` | 401 | .175:5001 and loopback listeners |
| 5007 `/` | 401 | 0.0.0.0:5007 listening |

These HTTP probes are diagnostics, not browser login or final UI acceptance.
The public 5000 failure is outside the healthy sampled ComfyUI Pod/Service
path; inspect its public forwarding/edge path before claiming public delivery.
The observed mapping requirement remains TCP public IP:port → .175:same port
for the listed user-facing services. Exact external router configuration was
not inspected and cannot be inferred solely from Kubernetes Services.

The new `webide-gateway` is Running on management with image
`sha256:49d2b62d4696e44c986dba42e786a0117fe74d7fc989090792051da26cb82bfc`, but
the public ComfyUI Service does not select it yet. Its readiness does not mean
users are routed through tenant-bound sessions.

The internal TLS gateway routes controller traffic to
`http://lunanexa-control.lunanexa.svc.cluster.local:8080` and model gateway
traffic to `http://192.168.2.175:5889`. The latter has a live listener, but its
model authorization/routing behavior was not exercised here.

## Migration order and remaining evidence

1. Classify/adopt or coordinate draining all existing H3 and GLM workloads;
   enforce the same whole-node ownership for host-native and Kubernetes tasks.
2. Register existing H3 cache versions and source manifests without copying
   weights unnecessarily; connect missing-cache preparation to the data node.
3. Provision tenant workspace PVCs on the chosen exclusive node or explicit
   transferable storage. Preserve old management PVCs; local-path is not HA.
4. Replace broad workspace host paths with selected licensed read-only cache
   mounts or authenticated model API connections.
5. Publish tenant-bound gateway routing, resolve public port 5000 transport,
   then perform the complete external browser flow.
6. Obtain the new time-limited resource authorization before real delivery;
   the previous 45-minute authorization is not renewed by this inventory.

Not tested here: actual H3 output, model transfer/repair, cross-tenant isolation,
file persistence after rebuild, multi-node allocation, expiry/drain/reassignment,
router configuration, data-node source completeness, or disk-level erasure.
Those remain explicit implementation/acceptance work, not passing evidence.
