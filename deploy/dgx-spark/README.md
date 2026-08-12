# DGX Spark runtime qualification templates

These manifests qualify digest-pinned vLLM and SGLang images on one real DGX
Spark before the image, model and measured profile are approved in LunaNexa's
model-service catalog. They are deliberately not a second production deployment
path.

Production LunaNexa continues to use this boundary:

1. the management node owns the source artifact below `/data/models`;
2. a signed assignment authorizes exactly one DGX to pull it;
3. the node agent verifies its size, digest and detached signature and publishes
   the current single-artifact form atomically below
   `/var/lib/lunanexa/models/sha256/`;
4. a production runtime adapter receives only its verified, read-only local
   artifact;
5. the controller reaches the runtime through a separately approved HTTPS
   gateway and strict node-to-endpoint mapping.

The qualification manifests test the runtime boundary before production
promotion. They intentionally use the separate host path
`/var/lib/lunanexa/qualification-models/sha256/DIGEST_HEX/model`, because vLLM
and SGLang normally consume a multi-file Hugging Face model directory while the
current LunaNexa materializer publishes one signed artifact file. They do not
download a model, mount `/data/models`, contain credentials, expose a public
ingress, or replace the node agent.

Stage that qualification directory through a reviewed operator process, verify
the source archive/tree and detached signature before extraction, make it
non-writable by the runtime identity, and place it only on the selected DGX.
Do not copy this qualification path into a production catalog. Production
promotion additionally requires a reviewed artifact packaging/extraction
adapter whose output is bound to the signed assignment and reverified before it
becomes the runtime mount.

## Required cluster state

- DGX OS, driver and CUDA versions have been recorded from the real machine.
- The NVIDIA container runtime and Kubernetes device plugin expose
  `nvidia.com/gpu`.
- The selected node is ARM64 and is labelled `lunanexa.io/role=gpu`.
- `RuntimeClass/nvidia` exists, or the reviewed overlay removes
  `runtimeClassName` because NVIDIA is already the cluster default.
- The verified Hugging Face-format qualification directory exists at
  `/var/lib/lunanexa/qualification-models/sha256/DIGEST_HEX/model` on only the
  assigned DGX.
- Runtime images are ARM64, signed, scanned and pinned by complete SHA-256
  digests. Tags are not accepted.

Verify the platform before rendering:

```sh
kubectl get node DGX_NODE_NAME -o jsonpath='{.status.nodeInfo.architecture}{"\n"}'
kubectl get runtimeclass nvidia
kubectl describe node DGX_NODE_NAME | sed -n '/Capacity:/,/Allocatable:/p'
kubectl get node DGX_NODE_NAME --show-labels
```

## Render the placeholders

Copy the selected manifest outside Git and replace every placeholder:

| Placeholder | Required value |
| --- | --- |
| `DGX_NODE_NAME` | Exact Kubernetes node name, for example `dgx-spark-01` |
| `MODEL_ARTIFACT_DIGEST_HEX` | Verified 64-character lowercase model digest without `sha256:` |
| `MODEL_SELECTOR` | Provider-neutral published alias, for example `text.qwen` |
| `MAX_MODEL_LEN` | Qualification context ceiling, initially `8192` |
| `VLLM_IMAGE_DIGEST` | Complete `sha256:` digest for an approved ARM64 `nvcr.io/nvidia/vllm` image |
| `GPU_MEMORY_UTILIZATION` | Initial vLLM fraction, conservatively `0.70` |
| `MAX_NUM_SEQS` | Initial vLLM concurrency ceiling, conservatively `4` |
| `SGLANG_IMAGE_DIGEST` | Complete `sha256:` digest for an approved ARM64 `nvcr.io/nvidia/sglang` image |
| `SGLANG_MEMORY_FRACTION` | Initial SGLang static fraction, conservatively `0.70` |
| `MAX_RUNNING_REQUESTS` | Initial SGLang concurrency ceiling, conservatively `4` |

The checked-in templates use one GPU, tensor parallelism 1, bfloat16, an 8 GiB
memory-backed `/dev/shm`, a 32 GiB memory request and a 96 GiB limit. They also
start with four concurrent sequences/requests and 70% runtime memory fractions.
Treat those values as conservative qualification starting points, not measured
capacity. DGX Spark uses unified memory, so validate Kubernetes allocatable
memory and reduce model, context, concurrency or cache fractions if the host
approaches OOM.

The default repositories are NVIDIA's NGC framework containers because the
published images are multi-architecture and current NVIDIA release notes list
DGX Spark support. Select a release whose CUDA requirement is compatible with
the installed driver, review its current known issues and security scan, verify
its ARM64 platform manifest, and resolve the selected tag to a full digest. A
tag alone is never an acceptable rendered value.

Before applying, this command must print nothing:

```sh
rg '\$\{[A-Z0-9_]+\}' RENDERED_RUNTIME.yaml
```

## Qualify vLLM

```sh
kubectl apply -f deploy/dgx-spark/runtime-qualification-prerequisites.yaml
kubectl apply -f RENDERED_VLLM.yaml
kubectl -n lunanexa-runtime-qualification rollout status \
  deployment/vllm-dgx-spark --timeout=30m
kubectl -n lunanexa-runtime-qualification logs \
  deployment/vllm-dgx-spark --tail=200
```

From a second trusted operator terminal, keep the service loopback-only and
probe it without creating ingress:

```sh
kubectl -n lunanexa-runtime-qualification port-forward \
  service/vllm-dgx-spark 18000:8000
curl --fail http://127.0.0.1:18000/health
curl --fail http://127.0.0.1:18000/v1/models
curl --fail http://127.0.0.1:18000/v1/responses \
  -H 'Content-Type: application/json' \
  -d '{"model":"MODEL_SELECTOR","input":"Reply briefly: ready","max_output_tokens":16}'
```

vLLM exposes `/health`, `/v1/models`, `/v1/chat/completions` and
`/v1/responses`. The Responses endpoint is the direct compatibility target for
LunaNexa's current text runtime adapter. Exercise non-streaming, streaming,
invalid-model, cancellation, saturation and restart cases before recording the
image as approved.

## Qualify SGLang

Do not run vLLM and SGLang simultaneously on the same one-GPU Spark. Remove the
vLLM deployment first, then apply the rendered SGLang manifest:

```sh
kubectl -n lunanexa-runtime-qualification delete deployment vllm-dgx-spark
kubectl apply -f RENDERED_SGLANG.yaml
kubectl -n lunanexa-runtime-qualification rollout status \
  deployment/sglang-dgx-spark --timeout=30m
kubectl -n lunanexa-runtime-qualification logs \
  deployment/sglang-dgx-spark --tail=200
```

Use a separate loopback forward for SGLang's qualified OpenAI-compatible
surface:

```sh
kubectl -n lunanexa-runtime-qualification port-forward \
  service/sglang-dgx-spark 13000:30000
curl --fail http://127.0.0.1:13000/health
curl --fail http://127.0.0.1:13000/v1/models
curl --fail http://127.0.0.1:13000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"MODEL_SELECTOR","messages":[{"role":"user","content":"Reply briefly: ready"}],"max_tokens":16}'
```

The template uses the documented `sglang.launch_server` arguments and `/health`
probe. Qualify its OpenAI-compatible APIs against the exact pinned image. Do
not point LunaNexa's `/v1/responses` adapter directly at SGLang unless that
exact image proves Responses API compatibility. Otherwise deploy a separately
reviewed, digest-pinned compatibility gateway and test streaming, usage,
cancellation, error normalization and response-size limits through it.

## Promotion evidence

Record at least:

- DGX OS, kernel, ARM64 architecture, driver, CUDA and container-runtime
  versions;
- exact runtime image, model artifact and detached-signature digests;
- cold start, warm start, time to first token, p50/p95/p99 latency and tokens/s;
- context length, cache fraction, peak unified-memory pressure and power/thermal
  observations;
- concurrent saturation, OOM rejection, malformed input, cancellation, process
  restart and node drain results;
- the approved HTTPS runtime route and a successful LunaNexa streaming receipt.

Delete the qualification namespace after exporting evidence. Model-cache
removal remains owned by the LunaNexa assignment lifecycle, not this manifest:

```sh
kubectl delete namespace lunanexa-runtime-qualification
```
