#!/usr/bin/env python3
"""Walk every adopted model through licence, verification and approval.

Each step is the same request the console's buttons make; this exists so the
whole batch can be done in one pass and re-run safely. Evaluation is shelved on
this deployment (`LUNANEXA_REQUIRE_MODEL_EVALUATION=0`), so approval does not
require a benchmark -- but nothing else is relaxed: the licence has to be
accepted with a citation that really exists, and the artifact has to pass the
control plane's own revision attestation, which re-reads the source manifest
from the model store and checks every file it declares.

  --only <model_id>   act on one model
  --dry-run           print what would be sent
"""
import argparse
import json
import sys
import urllib.error
import urllib.request

API = "http://127.0.0.1:4174"
LICENCE_FILES = {
    # Discovered from each revision's source manifest: the digest of the
    # in-tree LICENSE, which the manifest lists and the artifact digest covers.
    "qwen-qwen3.8-27b-fp8": (
        "Qwen/Qwen3.8-27B-FP8",
        "50cbab8a892c5f2993b8c7351a99182507472def3b1374558308605d99b86b32",
    ),
    "mia-ailab-glm-5.3-flash-exl3-tr3-4bpw": (
        "Mia-AiLab/GLM-5.3-Flash-EXL3-TR3-4bpw",
        "9a354667162e40201fa556e29ae7a327cdb112eacaa8ef100106e6063635e28a",
    ),
    "libertaidai-glm-5.3-flash-nvfp4": (
        "LibertAIDAI/GLM-5.3-Flash-NVFP4",
        "30b85b6b9659f2e78aa259f8faf5d920a68dee7c9ced3fa6dba1f19f2bc4fca1",
    ),
    "minimax-minimax-h3": (
        "MiniMax/MiniMax-H3",
        "59b99642b95ea21630e311198ddbfffbfe05aadba0c2f5d884cbdf4efcc90f44",
    ),
    "deepseek-ai-deepseek-v4-flash-dspark": (
        "deepseek-ai/DeepSeek-V4-Flash-DSpark",
        "1c8f573e830ca9b3ebfeb7ace1823146e22b66f99ee223840e7637c9e745e1c7",
    ),
}


def call(method, path, body=None):
    request = urllib.request.Request(
        f"{API}{path}",
        data=None if body is None else json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        raw = error.read().decode()[:400]
        try:
            return error.code, json.loads(raw)
        except Exception:
            return error.code, raw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--no-alias", action="store_true")
    arguments = parser.parse_args()

    status, registry = call("GET", "/v1/registry")
    if status != 200:
        sys.exit(f"cannot read the registry: {status} {registry}")
    licences = {record["license_id"]: record for record in registry.get("licenses", [])}

    done = skipped = failed = 0
    for model in registry.get("models", []):
        model_id, version = model["model_id"], model["version"]
        if arguments.only and model_id not in arguments.only:
            continue
        if model["state"] in ("Approved", "Evaluated"):
            skipped += 1
            continue
        if model["state"] != "Candidate":
            print(f"  ? {model_id}: state {model['state']}, not a candidate yet")
            skipped += 1
            continue

        licence = licences.get(model["license_id"])
        if licence is None:
            print(f"  ! {model_id}: no licence record to accept")
            failed += 1
            continue
        if model_id in LICENCE_FILES:
            directory, digest = LICENCE_FILES[model_id]
            evidence = f"modelstore://{directory}/LICENSE#sha256={digest}"
        else:
            # No licence file in the revision: cite the SPDX identifier the
            # adapter recorded from the upstream repository, unchanged, rather
            # than inventing a path that does not exist.
            evidence = licence.get("evidence_ref", "")
        if not evidence:
            print(f"  ! {model_id}: nothing to cite as licence evidence")
            failed += 1
            continue

        steps = [
            (
                "licence",
                "POST",
                "/v1/licenses",
                {
                    "license_id": licence["license_id"],
                    "model_id": model_id,
                    "status": "Accepted",
                    "accepted_by": "operator",
                    "evidence_ref": evidence,
                },
            ),
            (
                "verification",
                "POST",
                "/v1/verifications",
                {
                    "kind": "managed-revision",
                    "subject": model["artifact"]["uri"],
                    "digest": model["artifact"]["digest"],
                    "provenance_verified": True,
                },
            ),
            ("approval", "POST", "/v1/models/approve", {"model_id": model_id, "version": version}),
        ]
        if not arguments.no_alias:
            steps.append(
                (
                    "alias",
                    "POST",
                    "/v1/aliases/promote",
                    {
                        "alias_name": model_id,
                        "model_id": model_id,
                        "version": version,
                        "stage": "Canary",
                        "actor": "operator",
                    },
                )
            )

        for name, method, path, body in steps:
            if arguments.dry_run:
                print(f"  -> {model_id} {name}: {method} {path} {json.dumps(body)[:160]}")
                continue
            status, payload = call(method, path, body)
            if status not in (200, 201, 202):
                print(f"  ! {model_id} {name}: HTTP {status} {json.dumps(payload)[:200]}")
                failed += 1
                break
        else:
            done += 1
            print(f"  + {model_id}: licensed, verified, approved and aliased")

    print(f"\ncompleted {done}, skipped {skipped}, failed {failed}")
    if not arguments.dry_run:
        status, registry = call("GET", "/v1/registry")
        states = {}
        for model in registry.get("models", []):
            states[model["state"]] = states.get(model["state"], 0) + 1
        print(f"registry states: {states}; aliases: {len(registry.get('aliases', []))}")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
