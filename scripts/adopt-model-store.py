#!/usr/bin/env python3
"""Adopt every verified model-store import into the model registry.

The imports in the adapter's store are already checksum-verified: each one
carries a source manifest the adapter wrote after re-hashing the files. What
they lack is a registry record, and until they have one the operator console
cannot list them -- it renders `GET /v1/registry`, not the import store.

This performs exactly the request the console's "Adopt as Candidate" button
performs, for every import that is adoptable, and nothing else: no licence is
accepted, nothing is verified, evaluated or approved, because those are
operator decisions with evidence attached and inventing them would be worse
than leaving them pending.

Runs on the management node; the front door injects the operator token.
"""
import json
import re
import subprocess
import sys
import urllib.request

API = "http://127.0.0.1:4174"


def get(path):
    with urllib.request.urlopen(f"{API}{path}", timeout=30) as response:
        return json.load(response)


def post(path, body):
    request = urllib.request.Request(
        f"{API}{path}",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()[:300]


def slug(value):
    """A registry identifier: lowercase, and only characters that survive one."""
    value = value.lower().replace("/", "-")
    value = re.sub(r"[^a-z0-9.-]+", "-", value)
    return re.sub(r"-{2,}", "-", value).strip("-.")[:96]


# Architecture of the compute nodes, from the cluster's own inventory.
ARCHITECTURE = "nvidia-sm121"

imports = get("/v1/model-sources/modelscope/imports")
registry = get("/v1/registry")
already = {model["model_id"] for model in registry.get("models", [])}
print(f"{len(imports)} imports, {len(already)} model ids already in the registry")

adopted, skipped, failed = 0, 0, 0
for item in imports:
    if item.get("state") != "Verified":
        skipped += 1
        continue
    if not item.get("artifact_uri", "").startswith(("s3://", "modelstore://")):
        skipped += 1
        continue
    total, completed = int(item.get("bytes_total", 0)), int(item.get("bytes_completed", 0))
    if total <= 0 or completed != total:
        skipped += 1
        continue

    model_id = slug(item["model_id"])
    if model_id in already:
        print(f"  = {model_id}: already registered")
        skipped += 1
        continue

    # The licence is the one the store recorded from the upstream repository.
    licence = slug(item.get("license") or "other")
    # The floor the machine must hold is the model itself; recorded as the
    # size the store verified, because nothing else is known yet.
    memory_mib = total // (1024 * 1024) + 1

    status, payload = post(
        f"/v1/model-sources/modelscope/imports/{item['import_id']}:adopt",
        {
            "model_id": model_id,
            "version": f"modelscope-{item['revision']}",
            "license_id": f"license-{model_id}-{licence}",
            "compatible_architectures": [ARCHITECTURE],
            "minimum_memory_mib": memory_mib,
        },
    )
    if status in (200, 201, 202):
        adopted += 1
        print(f"  + {model_id}: adopted as candidate ({total} bytes, {licence})")
    else:
        failed += 1
        print(f"  ! {model_id}: HTTP {status} {payload}", file=sys.stderr)

after = get("/v1/registry")
print(
    f"\nadopted {adopted}, skipped {skipped}, failed {failed}; "
    f"registry now holds {len(after.get('models', []))} model records"
)
sys.exit(1 if failed else 0)
