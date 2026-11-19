"""Bounded asynchronous video transport; no model execution or credentials here."""

import asyncio
import json
import logging
import os
import re
import time
import uuid
import hashlib
from pathlib import Path

import aiohttp

logger = logging.getLogger(__name__)
_JOB_ID = re.compile(r"[A-Za-z0-9_-]{1,128}\Z")
_CONTENT_ATTEMPTS = 2
_CONTENT_RETRY_DELAY = 5.0
_ACTIVE = {}
_RECOVERABLE = {"queued", "generating", "finishing", "downloading", "reconnecting"}


class VideoRequestRejected(RuntimeError):
    """A definitive pre-admission response, not an uncertain connection loss."""


class VideoPollUnavailable(RuntimeError):
    """Transient status-read failure; retry GET, never resubmit generation."""


def _paths():
    # This is a patch to the pinned third-party ComfyUI adapter, not a new
    # service. Both paths belong to this workspace's existing persistent volume.
    import folder_paths
    return (Path(folder_paths.get_user_directory()) / ".video-tasks",
            Path(folder_paths.get_output_directory()))


def _save(record):
    root, _ = _paths()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    record["updated_at"] = time.time()
    temporary = root / (record["id"] + "." + uuid.uuid4().hex + ".tmp")
    with temporary.open("x", encoding="utf-8") as stream:
        os.chmod(temporary, 0o600)
        json.dump(record, stream, ensure_ascii=False)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, root / (record["id"] + ".json"))


def _records():
    root, _ = _paths()
    records = []
    for path in root.glob("*.json"):
        try:
            value = json.loads(path.read_text())
            if isinstance(value, dict) and value.get("id") == path.stem:
                records.append(value)
        except (OSError, ValueError):
            logger.warning("A video task record could not be read; leaving it intact")
    return sorted(records, key=lambda value: value.get("created_at", 0), reverse=True)


def _archive_path(record):
    _, output = _paths()
    return output / "video" / ("LunaNexa_task_" + record["id"] + ".mp4")


def _public_record(record):
    # Never return provider identifiers, internal endpoints, or prompts.
    result = {key: record[key] for key in
              ("id", "phase", "progress", "created_at", "updated_at", "message")
              if key in record}
    result["active"] = record["id"] in _ACTIVE
    result["can_recover"] = bool(record.get("provider_id")) and not result["active"] and record.get("phase") not in {"completed", "failed", "cancelled"}
    if record.get("output"):
        result["output"] = record["output"]
    return result


def _stage(record, phase, progress=None, message=""):
    record["phase"] = phase
    if progress is not None:
        record["progress"] = max(record.get("progress", 0), min(100, int(progress)))
    record["message"] = message
    _save(record)


def _import_outputs():
    """Retain discovery of pre-upgrade MP4s even after in-memory history resets."""
    root, output = _paths()
    for path in output.rglob("*.mp4"):
        if path.is_symlink() or not path.is_file():
            continue
        relative = path.relative_to(output)
        if path.name.startswith("LunaNexa_task_"):
            continue
        task_id = "saved_" + hashlib.sha256(str(relative).encode()).hexdigest()[:32]
        if (root / (task_id + ".json")).exists():
            continue
        _save({"id": task_id, "phase": "completed", "progress": 100,
               "created_at": path.stat().st_mtime,
               "output": {"filename": path.name, "subfolder": str(relative.parent), "type": "output"},
               "message": "已保存的视频"})


async def _download(session, url, record, maximum_result_bytes):
    target = _archive_path(record)
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_suffix(".mp4.part")
    timeout = aiohttp.ClientTimeout(total=None, sock_connect=30, sock_read=180)
    for attempt in range(_CONTENT_ATTEMPTS):
        # Resume only with a validator; an upstream returning 200 is an explicit
        # full restart, never an append of a second MP4 to a partial file.
        offset = partial.stat().st_size if partial.exists() and record.get("etag") else 0
        headers = {"Range": f"bytes={offset}-", "If-Range": record["etag"]} if offset else {}
        try:
            async with session.get(url + "/content", headers=headers, allow_redirects=False, timeout=timeout) as response:
                if response.status not in {200, 206} or response.content_type != "video/mp4":
                    raise RuntimeError("Completed video content is unavailable")
                append = response.status == 206
                if append:
                    match = re.fullmatch(r"bytes (\d+)-(\d+)/(\d+)", response.headers.get("Content-Range", ""))
                    if (not offset or not match or int(match[1]) != offset
                            or int(match[2]) + 1 != int(match[3])
                            or response.headers.get("ETag") != record["etag"]):
                        raise RuntimeError("Video download returned an inconsistent byte range")
                if not append:
                    offset = 0
                    record["etag"] = response.headers.get("ETag", "")
                    _save(record)
                count = offset
                with partial.open("ab" if append else "wb") as stream:
                    async for chunk in response.content.iter_chunked(65536):
                        count += len(chunk)
                        if count > maximum_result_bytes:
                            raise RuntimeError("Video result exceeds its download limit")
                        stream.write(chunk)
                    stream.flush()
                    os.fsync(stream.fileno())
                length = response.headers.get("Content-Length")
                if count == 0 or (length is not None and count - offset != int(length)):
                    raise RuntimeError("Video download is incomplete")
                with partial.open("rb") as stream:
                    header = stream.read(12)
                if len(header) < 12 or header[4:8] != b"ftyp":
                    raise RuntimeError("Video download is not a valid MP4 container")
                os.replace(partial, target)
                record["output"] = {"filename": target.name, "subfolder": "video", "type": "output"}
                _stage(record, "completed", 100, "成片已保存，可随时回来下载")
                return target.read_bytes()
        except (aiohttp.ClientError, TimeoutError):
            if attempt + 1 >= _CONTENT_ATTEMPTS:
                raise
            await asyncio.sleep(_CONTENT_RETRY_DELAY)


async def _receive(session, record, maximum_result_bytes, on_progress=None, poll_interval=5.0):
    url = record["base_url"].rstrip("/") + "/videos/" + record["provider_id"]
    while True:
        if time.time() >= record["deadline"]:
            raise TimeoutError("Video observation deadline reached")
        try:
            data = await _json(session, "GET", url)
        except (aiohttp.ClientError, TimeoutError, VideoPollUnavailable):
            _stage(record, "reconnecting", message="连接暂时中断，保留原任务并重连；请勿重复提交")
            await asyncio.sleep(poll_interval)
            continue
        if data.get("id") != record["provider_id"]:
            raise RuntimeError("Video service returned a different job")
        status = data.get("status")
        if status == "completed":
            _stage(record, "downloading", 90, "生成已完成，正在保存视频")
            break
        if status in {"failed", "cancelled", "expired"}:
            _stage(record, "failed", message="生成服务报告失败，任务记录已保留")
            raise RuntimeError("Video generation failed or its access ended" + _failure_detail(data))
        if status not in {"queued", "in_progress"}:
            raise RuntimeError("Video service returned an invalid job status")
        progress = data.get("progress", 0)
        # Older LunaNexa video DTOs encode Option[Int] as [] / [n]. The direct
        # vLLM endpoint uses a scalar; preserve real progress from both paths.
        if isinstance(progress, list):
            progress = progress[0] if len(progress) == 1 else None
        progress = min(80, max(0, int(progress))) if isinstance(progress, (int, float)) and not isinstance(progress, bool) else record.get("progress", 0)
        _stage(record, "queued" if status == "queued" else ("finishing" if progress >= 80 else "generating"), progress)
        _report_progress(on_progress, {"progress": progress})
        await asyncio.sleep(poll_interval)
    result = await _download(session, url, record, maximum_result_bytes)
    # Cleanup is safe only after the MP4 and its durable completion record exist.
    try:
        await asyncio.wait_for(_cleanup(session, url, record["provider_id"]), timeout=10)
    except Exception:
        logger.warning("Video saved locally; upstream cleanup will require reconciliation")
    _report_progress(on_progress, {"progress": 100})
    return result


async def _resume(record):
    if record["id"] in _ACTIVE:
        return
    _ACTIVE[record["id"]] = asyncio.current_task()
    try:
        # This only observes an already accepted job. It never issues a POST.
        async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=60)) as session:
            async with asyncio.timeout(max(1, record["deadline"] - time.time())):
                await _receive(session, record, record.get("maximum_result_bytes", 1024 * 1024 * 1024))
    except asyncio.CancelledError:
        raise
    except Exception:
        if record["phase"] not in {"completed", "failed"}:
            _stage(record, "needs_attention", message="未取回成片，原任务已保留；可重新连接，不会重复生成")
    finally:
        _ACTIVE.pop(record["id"], None)


def install_recovery_routes(server):
    """Use the existing ComfyUI server and workspace boundary, not a new daemon."""
    from aiohttp import web

    @server.routes.get("/lunanexa/video-tasks")
    async def list_tasks(request):
        return web.json_response({"adapter": "durable-video-v1", "tasks": [_public_record(record) for record in _records()]}, headers={"Cache-Control": "no-store"})

    @server.routes.post("/lunanexa/video-tasks/{task_id}/recover")
    async def recover_task(request):
        record = next((item for item in _records() if item["id"] == request.match_info["task_id"]), None)
        if record is None:
            return web.json_response({"error": "任务不存在"}, status=404)
        if not _public_record(record)["can_recover"]:
            return web.json_response({"error": "任务正在运行或已有结果"}, status=409)
        if time.time() >= record["deadline"]:
            # A renewed observation window is not renewed model authority. The
            # personal model proxy rechecks the user's grant on every GET.
            record["deadline"] = time.time() + 1800
        _stage(record, "reconnecting", message="正在连接原任务，不会重新提交生成")
        asyncio.create_task(_resume(record))
        # _resume claims ownership on its first scheduled step. Yield before
        # returning so repeated recovery clicks see an active task.
        await asyncio.sleep(0)
        return web.json_response({"task": _public_record(record)})

    async def startup(app):
        _import_outputs()
        for record in _records():
            if record["phase"] == "submitting":
                _stage(record, "uncertain", message="提交时连接中断，尚未确认后台任务；不会自动重复提交")
            elif (record["phase"] in _RECOVERABLE or record["phase"] == "needs_attention") and record.get("provider_id") and record.get("deadline", 0) > time.time():
                asyncio.create_task(_resume(record))
    server.app.on_startup.append(startup)


async def _json(session, verb, url, **kwargs):
    async with session.request(verb, url, allow_redirects=False, **kwargs) as response:
        if verb == "GET" and response.status in {500, 502, 503, 504}:
            raise VideoPollUnavailable("Video status service is temporarily unavailable")
        if 300 <= response.status < 400:
            raise RuntimeError("Video service redirects are not permitted")
        chunks = bytearray()
        async for chunk in response.content.iter_chunked(8192):
            chunks.extend(chunk)
            if len(chunks) > 262144:
                raise RuntimeError("Video service metadata exceeds its limit")
        try:
            data = json.loads(chunks)
        except (ValueError, UnicodeError):
            raise RuntimeError("Video service returned invalid metadata") from None
        if not isinstance(data, dict):
            raise RuntimeError("Video service returned invalid metadata")
        if response.status == 409 and verb == "DELETE":
            return {"deleted": False}
        if verb == "POST" and response.status in {400, 401, 403, 404, 413, 415, 422}:
            raise VideoRequestRejected(f"视频请求被拒绝（HTTP {response.status}），请检查模型权限与视频参数；本次未进入生成")
        # vLLM-Omni can return a failed job object with an error HTTP status.
        if not 200 <= response.status < 300 and not (verb == "GET" and data.get("status") == "failed"):
            raise RuntimeError(f"Video service rejected the operation (HTTP {response.status})")
        return data


def _failure_detail(data):
    """Return the service's own reason for a failed job, as a message suffix.

    The upstream transport throws this away and the caller sees only a generic
    line, which is how "MiniMax H3 output fps is fixed at 24" reached an operator
    as "Video generation failed or its access ended". This is not logging: the
    text goes back to whoever asked for the clip, bounded and whitespace-folded.
    """
    detail = data.get("error")
    if isinstance(detail, dict):
        for key in ("message", "detail", "error", "reason"):
            value = detail.get(key)
            if isinstance(value, str) and value.strip():
                detail = value
                break
        else:
            detail = None
    if not isinstance(detail, str):
        return ""
    text = " ".join(detail.split())[:200]
    return f": {text}" if text else ""


async def _cleanup(session, url, job_id):
    for _ in range(4):
        result = await _json(session, "DELETE", url)
        if result.get("id") == job_id and result.get("deleted") is True:
            return
        await asyncio.sleep(1)
    raise RuntimeError("Video cancellation has not been acknowledged")


def _report_progress(on_progress, data):
    """Forward the service's best-effort progress to the caller, if it gave one.

    The API documents `progress` as "best-effort ... from 0 to 100" and upstream
    writes it exactly once, with 100, when the job finishes. LunaNexa's service
    patch fills it in per denoising step while the job runs, which is what makes
    a ComfyUI progress bar possible at all. A broken hook must never fail a
    render that is otherwise fine, so any exception here is swallowed.
    """
    if on_progress is None:
        return
    value = data.get("progress")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return
    try:
        on_progress(max(0, min(100, int(value))))
    except Exception:
        logger.debug("Video progress callback raised; continuing", exc_info=True)


async def run_video_job(
    base_url,
    form,
    *,
    timeout=None,
    poll_interval=5.0,
    max_poll_duration=7200.0,
    maximum_result_bytes=1024 * 1024 * 1024,
    on_progress=None,
):
    """Submit once; journal accepted identity; archive before cleanup.

    Neither a browser reconnect nor a failed download submits another job.
    Unknown submissions and interrupted jobs remain visible for reconciliation.
    """
    if not 0 < poll_interval <= 60 or not 0 < max_poll_duration <= 7200:
        raise ValueError("Video polling limits are invalid")
    if not 0 < maximum_result_bytes <= 1024 * 1024 * 1024:
        raise ValueError("Video result limit is invalid")
    timeout = timeout or aiohttp.ClientTimeout(total=60)
    record = {"id": uuid.uuid4().hex, "phase": "submitting", "progress": 0,
              "created_at": time.time(), "deadline": time.time() + max_poll_duration,
              "base_url": base_url, "maximum_result_bytes": maximum_result_bytes}
    _save(record)
    _ACTIVE[record["id"]] = asyncio.current_task()
    url = base_url.rstrip("/") + "/videos"
    async with aiohttp.ClientSession(timeout=timeout) as session:
        try:
            async with asyncio.timeout(max_poll_duration):
                data = await _json(session, "POST", url, data=form, headers={"Idempotency-Key": record["id"]})
                candidate = data.get("id")
                if not isinstance(candidate, str) or not _JOB_ID.fullmatch(candidate):
                    raise RuntimeError("Video service returned an invalid job identifier")
                record["provider_id"] = candidate
                _stage(record, "queued")
                return await _receive(session, record, maximum_result_bytes, on_progress, poll_interval)
        except VideoRequestRejected as error:
            _stage(record, "failed", message=str(error))
            raise
        except asyncio.CancelledError:
            _stage(record, "needs_attention", message="等待已中断，后台任务与已有成片均保留；可重新连接")
            raise
        except Exception as error:
            if record["phase"] == "failed":
                raise
            if record["phase"] not in {"completed", "failed"}:
                _stage(record, "needs_attention" if record.get("provider_id") else "uncertain",
                       message="连接未完成，记录已保留；请在视频任务中查看，不要重复生成")
            raise RuntimeError(
                "Video task retained. Open 视频任务 to reconnect or retrieve its result; do not submit a duplicate."
            ) from error
        finally:
            _ACTIVE.pop(record["id"], None)
