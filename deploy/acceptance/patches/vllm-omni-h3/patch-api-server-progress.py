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
re-running is safe: an already patched file only gets its cap normalised.

usage: patch-api-server-progress.py [path-to-api_server.py]
"""

import re
import sys
from pathlib import Path

DEFAULT = "/usr/local/lib/python3.12/dist-packages/vllm_omni/entrypoints/openai/api_server.py"

# The bar must not sit at 100 while real work remains. Denoising is only the
# first ~5 minutes of a ~7.5 minute 20-second render; the VAE decode and MP4
# encode that follow have no step granularity to report, so the bar stops here
# and 100 stays reserved for "the clip exists".
CAP = 80

HELPER = '''
_LIVE_PROGRESS_FILE = Path(os.environ.get("LUNANEXA_PROGRESS_FILE", "/tmp/vllm_progress.json"))


def _live_video_progress(job: Any) -> int | None:
    """Denoising progress for a running job, as 0-100, or None if unknown.

    The diffusion worker writes {n,total,updated_unix} once per denoising step
    (LunaNexa's progress_bar patch). This service runs one diffusion slot at a
    time, so a single pod-level file is unambiguous; if concurrency is ever
    enabled the file has to be keyed by request id. A file older than the job is
    ignored, so a finished run's last value cannot be pinned onto a later one.

    The result is capped below 100 on purpose. Denoising is only the first part
    of the wall clock -- a 20 s clip spends about 5 min denoising and another
    2.5 min in VAE decode and MP4 encode, and the service reports nothing for
    those. Capping leaves the bar visibly unfinished until the clip exists.
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
    return max(0, min(__LUNANEXA_PROGRESS_CAP__, round(100 * done / total)))


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

ALREADY = "_live_video_progress"
CAP_RE = re.compile(r"min\(\d+, round\(100 \* done / total\)\)")


def _render_cap(src: str) -> str:
    """Pin the cap wherever the return line already is, or fill the placeholder."""
    src = src.replace("__LUNANEXA_PROGRESS_CAP__", str(CAP))
    return CAP_RE.sub(f"min({CAP}, round(100 * done / total))", src)


def _write(path: Path, text: str) -> None:
    compile(text, str(path), "exec")
    path.write_text(text)


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else DEFAULT)
    src = path.read_text()

    if ALREADY in src:
        out = _render_cap(src)
        if out == src:
            print(f"{path}: already patched (cap {CAP})")
            return 0
        _write(path, out)
        print(f"{path}: cap normalised to {CAP}")
        return 0

    for name, anchor in (("retrieve_video decorator", ANCHOR_DECORATOR), ("retrieve_video body", OLD_BODY)):
        found = src.count(anchor)
        if found != 1:
            raise SystemExit(f"{path}: {name} anchor matched {found} times, expected 1")

    out = src.replace(ANCHOR_DECORATOR, HELPER + ANCHOR_DECORATOR, 1)
    out = out.replace(OLD_BODY, NEW_BODY, 1)
    out = _render_cap(out)
    if not CAP_RE.search(out):
        raise SystemExit(f"{path}: cap line is missing after patching")
    _write(path, out)
    print(f"{path}: patched (cap {CAP})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
