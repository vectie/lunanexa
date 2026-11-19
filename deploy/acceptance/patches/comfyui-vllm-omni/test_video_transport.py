"""Native regression tests for the pinned third-party adapter patch; no GPU."""
import asyncio
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from types import SimpleNamespace
from unittest.mock import patch
from aiohttp import web, ClientTimeout

spec = importlib.util.spec_from_file_location("video_transport", Path(__file__).with_name("video_transport.py"))
transport = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transport)
MP4 = b"\x00\x00\x00\x18ftypmp42" + b"a" * 300


class RecoveryTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = patch.object(transport, "_paths", lambda: (self.root / "jobs", self.root / "output"))
        self.paths.start()
        transport._ACTIVE.clear()
        self.posts = self.deletes = self.downloads = self.polls = 0
        self.mode = "ok"
        self.ranges = []
        self.app = web.Application()
        self.app.router.add_post("/v1/videos", self.submit)
        self.app.router.add_get("/v1/videos/job-1", self.status)
        self.app.router.add_delete("/v1/videos/job-1", self.delete)
        self.app.router.add_get("/v1/videos/job-1/content", self.content)
        self.runner = web.AppRunner(self.app)
        await self.runner.setup()
        site = web.TCPSite(self.runner, "127.0.0.1", 0)
        await site.start()
        self.base = f"http://127.0.0.1:{site._server.sockets[0].getsockname()[1]}/v1"
        self.delay = patch.object(transport, "_CONTENT_RETRY_DELAY", 0.01)
        self.delay.start()

    async def asyncTearDown(self):
        await self.runner.cleanup()
        self.paths.stop()
        self.delay.stop()
        self.temp.cleanup()

    async def submit(self, request):
        self.posts += 1
        if self.mode == "rejected":
            return web.json_response({"error":"invalid dimensions"}, status=400)
        if self.mode == "unknown":
            await asyncio.sleep(.1)
        return web.json_response({"id": "job-1", "status": "queued"})

    async def status(self, request):
        self.polls += 1
        if self.mode == "poll_disconnect" and self.polls == 1:
            await asyncio.sleep(.1)
        if self.mode == "poll_unavailable" and self.polls == 1:
            return web.Response(status=503, text="temporarily unavailable")
        if self.mode == "failure":
            return web.json_response({"id":"job-1", "status":"failed", "error":"model failed"})
        if self.mode in {"scalar_progress", "legacy_progress"} and self.polls == 1:
            return web.json_response({"id":"job-1", "status":"in_progress", "progress": [57] if self.mode == "legacy_progress" else 57})
        return web.json_response({"id":"job-1", "status":"completed", "progress":100})

    async def content(self, request):
        self.downloads += 1
        self.ranges.append(request.headers.get("Range"))
        if self.mode == "download_failure":
            return web.Response(status=503)
        if self.mode in {"partial", "range_ignored"} and self.downloads == 1:
            response = web.StreamResponse(headers={"Content-Type":"video/mp4", "Content-Length":str(len(MP4)), "ETag":'"v1"'})
            await response.prepare(request)
            await response.write(MP4[:40])
            request.transport.close()
            return response
        if self.mode == "partial" and request.headers.get("Range"):
            return web.Response(body=MP4[40:], status=206, content_type="video/mp4", headers={"ETag":'"v1"', "Content-Range":f"bytes 40-{len(MP4)-1}/{len(MP4)}"})
        return web.Response(body=MP4, content_type="video/mp4")

    async def delete(self, request):
        # Provider cleanup is forbidden until both archive and journal exist.
        record = transport._records()[0]
        self.assertEqual(record["phase"], "completed")
        self.assertEqual(transport._archive_path(record).read_bytes(), MP4)
        self.deletes += 1
        return web.json_response({"id":"job-1", "deleted":True})

    async def run_video(self, **kwargs):
        return await transport.run_video_job(self.base, {"prompt":"private synthetic prompt"}, poll_interval=.01, max_poll_duration=2, **kwargs)

    async def test_archive_precedes_cleanup_and_public_record_is_redacted(self):
        self.assertEqual(await self.run_video(), MP4)
        record = transport._records()[0]
        self.assertEqual((self.posts, self.deletes), (1, 1))
        public = json.dumps(transport._public_record(record))
        for forbidden in (self.base, "job-1", "private synthetic prompt", "provider_id"):
            self.assertNotIn(forbidden, public)
        self.assertNotIn("private synthetic prompt", json.dumps(record))
        self.assertFalse(list((self.root / "jobs").glob("*.tmp")))

    async def test_unknown_submission_is_not_retried_or_deleted(self):
        self.mode = "unknown"
        with self.assertRaises(RuntimeError):
            await self.run_video(timeout=ClientTimeout(total=.02))
        self.assertEqual((self.posts, self.deletes), (1, 0))
        self.assertEqual(transport._records()[0]["phase"], "uncertain")

    async def test_scalar_and_legacy_progress_are_preserved(self):
        for mode in ("scalar_progress", "legacy_progress"):
            self.mode, self.polls = mode, 0
            seen = []
            self.assertEqual(await self.run_video(on_progress=seen.append), MP4)
            self.assertEqual(seen, [57, 100])

    async def test_explicit_rejection_is_failed_not_uncertain(self):
        self.mode = "rejected"
        with self.assertRaisesRegex(transport.VideoRequestRejected, "HTTP 400"):
            await self.run_video()
        record = transport._records()[0]
        self.assertEqual(record["phase"], "failed")
        self.assertIn("HTTP 400", record["message"])
        self.assertEqual((self.posts, self.polls, self.deletes), (1, 0, 0))

    async def test_failed_download_survives_process_recovery_without_post(self):
        self.mode = "download_failure"
        with self.assertRaises(RuntimeError):
            await self.run_video()
        self.assertEqual(self.deletes, 0)
        record = transport._records()[0]  # fresh disk read, not in-memory state
        self.assertEqual(record["phase"], "needs_attention")
        self.mode = "ok"
        await transport._resume(record)
        self.assertEqual((self.posts, self.deletes), (1, 1))
        self.assertEqual(transport._records()[0]["phase"], "completed")

    async def test_status_connection_loss_only_retries_get(self):
        self.mode = "poll_disconnect"
        self.assertEqual(await self.run_video(timeout=ClientTimeout(total=.02)), MP4)
        self.assertEqual(self.posts, 1)
        self.assertGreaterEqual(self.polls, 2)

    async def test_status_service_failure_only_retries_get(self):
        self.mode = "poll_unavailable"
        self.assertEqual(await self.run_video(), MP4)
        self.assertEqual(self.posts, 1)
        self.assertEqual(self.polls, 2)

    async def test_startup_reconnects_interrupted_known_job(self):
        transport._save({"id":"abc", "provider_id":"job-1", "base_url":self.base,
                        "created_at":time.time(), "deadline":time.time()+2,
                        "phase":"needs_attention", "progress":57})
        server = SimpleNamespace(app=web.Application(), routes=web.RouteTableDef())
        transport.install_recovery_routes(server)
        await server.app.on_startup[-1](server.app)
        for _ in range(100):
            if transport._records()[0]["phase"] == "completed":
                break
            await asyncio.sleep(.01)
        self.assertEqual(transport._records()[0]["phase"], "completed")
        self.assertEqual(self.posts, 0)

    async def test_interrupted_download_resumes_verified_range(self):
        self.mode = "partial"
        self.assertEqual(await self.run_video(), MP4)
        self.assertEqual(self.ranges, [None, "bytes=40-"])
        self.assertEqual(self.posts, 1)

    async def test_upstream_without_range_support_restarts_without_corruption(self):
        self.mode = "range_ignored"
        self.assertEqual(await self.run_video(), MP4)
        self.assertEqual(self.ranges, [None, "bytes=40-"])

    async def test_model_failure_is_not_resubmitted(self):
        self.mode = "failure"
        with self.assertRaises(RuntimeError):
            await self.run_video()
        self.assertEqual(transport._records()[0]["phase"], "failed")
        self.assertEqual((self.posts, self.deletes), (1, 0))

    async def test_previous_output_import_is_idempotent(self):
        output = self.root / "output" / "video"
        output.mkdir(parents=True)
        (output / "old.mp4").write_bytes(MP4)
        transport._import_outputs()
        transport._import_outputs()
        self.assertEqual(len(transport._records()), 1)
        self.assertEqual(transport._records()[0]["output"]["filename"], "old.mp4")

    async def test_restart_resumes_known_job_and_preserves_progress(self):
        record = {"id":"abc", "provider_id":"job-1", "base_url":self.base,
                  "created_at":time.time(), "deadline":time.time()+2,
                  "phase":"generating", "progress":71}
        transport._save(record)
        transport._stage(record, "reconnecting", 0)
        self.assertEqual(transport._records()[0]["progress"], 71)
        await transport._resume(transport._records()[0])
        self.assertEqual(self.posts, 0)
        self.assertEqual(transport._records()[0]["phase"], "completed")


if __name__ == "__main__":
    unittest.main()
