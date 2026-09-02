# NVIDIA compute-node qualification

These manifests expose NVIDIA devices only on nodes explicitly labelled
`lunanexa.io/role=gpu` and tainted with
`lunanexa.io/role=gpu:NoSchedule`. Management workloads do not tolerate that
taint.

Apply the digest-pinned device plugin, wait for its DaemonSet, then require a
positive allocatable count before running the one-GPU CUDA job:

```sh
kubectl apply -f deploy/nvidia-compute/device-plugin.yaml
kubectl -n kube-system rollout status daemonset/lunanexa-nvidia-device-plugin
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
job=$(kubectl create -f deploy/nvidia-compute/cuda-vectoradd-job.yaml -o name)
kubectl wait --for=condition=complete "$job" --timeout=5m
kubectl logs "$job"
```

`Test PASSED` proves one CUDA kernel can execute through Kubernetes. It does
not qualify a LunaFlux model, AOT kernel set, health contract, cancellation,
restart, or soak behavior.
