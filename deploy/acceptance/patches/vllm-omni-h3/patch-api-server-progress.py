#!/usr/bin/env python3
"""Publish denoising progress on a running video job in vLLM-Omni's API server.

Why this exists
---------------
The job model declares `progress: int = Field(default=0, description="Best-effort
progress indicator from 0 to 100.")` (protocol/videos.py), and the only write to
it anywhere in the serving path is next to `status: completed`, where it is set
to 100. So a GET of an *in-progress* job reports 0 for the whole render and every
client has nothing to drive a progress bar with.

The step count does exist. The diffusion worker writes {n,total,updated_unix}
once per denoising step (LunaNexa's progress_bar patch; upstream only prints the
bar to stdout). This script connects the two: `retrieve_video` fills the field in
from that file while the job is running, without touching the store.

Why it is a substitution and not a shipped file
-----------------------------------------------
api_server.py is 3,500 lines. Shipping a copy would add ~144 KB of upstream code
to the repository and bury a 20-line change inside it. The two anchors are
asserted to be unique, the result is byte-compiled before it is written, and
re-running on an already patched file is a no-op.

usage: patch-api-server-progress.py [path-to-api_server.py]
"""

import sys
from pathlib import Path

DEFAULT = "/usr/local/lib/python3.12/dist-packages/vllm_omni/entrypoints/openai/api_server.py"

HELPER = '''
_LIVE_PROGRESS_FILE = Path(os.environ.get("LUNANEXA_PROGRESS_FILE", "/tmp/vllm_progress.json"))


def _live_video_progress(job: Any) -> int | None:
    """Denoising progress for a running job, as 0-100, or None if unknown.

    The diffusion worker writes {n,total,updated_unix} once per denoising step
    (LunaNexa's progress_bar patch). This service runs one diffusion slot at a
    time, so a single pod-level file is unambiguous; if concurrency is ever
    enabled the file has to be keyed by request id. A file older than the job is
    ignored, so a finished run's last value cannot be pinned onto a later one.

    Capped at 99 on purpose: the service has no granularity for the VAE decode and
    MP4 encode that follow denoising, so 100 stays reserved for "the clip exists".
    """
    try:
        info = json.loads(_LIVE_PROGRESS_FILE.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(info, dict):
        return None
    done, total = info.get("n"), info.get("total")
    if not isinstance(done, int) or not isinstance(total, int) or total <= 0:
        return None
    updated = info.get("updated_unix")
    created = getattr(job, "created_at", None)
    if isinstance(updated, (int, float)) and isinstance(created, int) and updated < created:
        return None
    return max(0, min(99, round(100 * done / total)))


'''

ANCHOR_DECORATOR = '@router.get("/v1/videos/{video_id}", response_model=None)\nasync def retrieve_video('

OLD_BODY = '''    job = await VIDEO_STORE.get(video_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Video not found")
    if job.status == VideoGenerationStatus.FAILED:'''

NEW_BODY = '''    job = await VIDEO_STORE.get(video_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Video not found")
    if job.status == VideoGenerationStatus.IN_PROGRESS:
        live = _live_video_progress(job)
        if live is not None and live > job.progress:
            # A copy: the store hands out the shared object, and the completion
            # path is the only thing allowed to write 100.
            job = job.model_copy(update={"progress": live})
    if job.status == VideoGenerationStatus.FAILED:'''

ALREADY = ('_live_video_progress', 'job.model_copy(update={"progress": live})')


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()
    if all(marker in src for marker in ALREADY):
        print(f"{path}: already patched")
        return 0
    for name, anchor, want in (
        ("retrieve_video decorator", ANCHOR_DECORATOR, 1),
        ("retrieve_video body", OLD_BODY, 1),
    ):
        found = src.count(anchor)
        if found != want:
            raise SystemExit(f"{path}: {name} anchor matched {found} times, expected {want}")
    out = src.replace(ANCHOR_DECORATOR, HELPER + ANCHOR_DECORATOR, 1)
    out = out.replace(OLD_BODY, NEW_BODY, 1)
    compile(out, str(path), "exec")
    path.write_text(out)
    print(f"{path}: patched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
