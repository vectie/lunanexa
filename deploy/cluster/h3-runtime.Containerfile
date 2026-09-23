# The base is the reviewed ARM64 vLLM-Omni image with the MiniMax-H3 SM121,
# video-progress, and serving-video compatibility patches already baked in.
# This image contains runtime code only. Model weights are mounted read-only by
# the LunaNexa node agent at LUNANEXA_MODEL_PATH for the selected assignment.
FROM lunanexa-registry.lunanexa-registry.svc.cluster.local:5000/moon/h3-runtime@sha256:b0bb860f5d369ff7e89e1e36fb91d416b15cbaad7f5b689f812f099f3a86529c

RUN groupadd --gid 65532 lunanexa && \
    useradd --uid 65532 --gid 65532 --no-create-home --home-dir /tmp lunanexa

ENV HOME=/tmp \
    HF_HOME=/tmp/huggingface \
    VLLM_WORKER_MULTIPROC_METHOD=spawn \
    FLASHINFER_DISABLE_VERSION_CHECK=1 \
    HF_HUB_OFFLINE=1 \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    VLLM_OMNI_VIDEO_SYNC_TIMEOUT=7200

USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["vllm", "serve", "/var/lib/lunanexa/model/model", "--omni", "--trust-remote-code", "--host", "0.0.0.0", "--port", "8080", "--num-gpus", "1", "--num-weight-load-threads", "2", "--diffusion-attention-backend", "CUDNN_ATTN", "--diffusion-quantization-config", "{\"method\":\"fp8\",\"activation_scheme\":\"dynamic\",\"ignored_layers\":[\"video_patch_proj\",\"audio_patch_proj\",\"time_embedder.proj_in\",\"time_embedder.proj_out\",\"final_layer.video_out\",\"final_layer.audio_out\"]}", "--force-cutlass-fp8", "--stage-init-timeout", "1800", "--init-timeout", "2400"]
