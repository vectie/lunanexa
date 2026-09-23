#!/usr/bin/env python3
"""Rebuild the console image from a fresh browser bundle, without docker.

The management node runs k3s, which uses its bundled containerd: there is no
docker, podman, nerdctl, buildah or buildkit on it (checked, including snap).
So the management image build in scripts/deploy/build-management-images.sh, which
shells out to `docker build`, cannot run there -- and it cannot run on the
operator's Mac either, which has no docker at all. That left the console image,
an nginx image with the browser bundle baked in, impossible to update.

This takes the same route deploy/cluster/build-control-image.py already takes for
the control plane: pull the current image out of containerd, build the layer that
changed, re-assemble the OCI layout, import it back. The change here is content,
not a binary: `_build/browser-dist/**` replaces `usr/share/nginx/html/**`.

The static files sit in three separate layers of the current image (three COPYs,
each adding to the previous), so rather than guess which one to drop, a single new
layer is appended and shadows all of them -- later layers win. Files that existed
in the old bundle and are absent from the new one must be removed explicitly,
because a layer can only shadow a path it also contains; that is what the
whiteouts below are for.

Idempotent enough to re-run: it always starts from --base, never from its own
output.

usage:
  build-web-image.py --base lunanexa-web:20260918 --image lunanexa-web:20260921 \
      --dist _build/browser-dist --sudo-password "$PW"
"""

import argparse
import gzip
import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time

HTML_ROOT = "usr/share/nginx/html"
NAMESPACE = "k8s.io"


def sudo(password, command):
    if os.geteuid() == 0:
        return subprocess.run(command, capture_output=True, text=True)
    return subprocess.run(
        ["sudo", "-S", "-k"] + command,
        input=password + "\n",
        capture_output=True,
        text=True,
    )


def old_html_paths(work, manifest, target_root):
    """Every regular file currently under the nginx html root, across all layers.

    Directories are skipped: a whiteout for a directory whose contents the new
    layer is also writing makes the extractor fail ("failed to extract layer"),
    and `.wh.*` entries are whiteout markers from an earlier build, not content.
    """
    found = set()
    for layer in manifest["layers"]:
        path = os.path.join(work, "base", "blobs", "sha256", layer["digest"].split(":")[1])
        with tarfile.open(path, "r:*") as archive:
            for info in archive.getmembers():
                name = info.name.lstrip("./")
                if (
                    info.isfile()
                    and name.startswith(target_root + "/")
                    and not os.path.basename(name).startswith(".wh.")
                ):
                    found.add(name)
    return found


def is_junk(path):
    """AppleDouble / Finder droppings that a macOS build can bake into an image."""
    name = os.path.basename(path)
    return name.startswith("._") or name == ".DS_Store"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True, help="image reference to start from")
    parser.add_argument("--image", required=True, help="tag to produce")
    parser.add_argument("--dist", required=True, help="directory whose contents become the html root")
    parser.add_argument("--target-root", default=HTML_ROOT,
                        help="path within the image to shadow (default: nginx HTML root)")
    parser.add_argument("--work", default=os.path.expanduser("~/web-image-build"))
    parser.add_argument("--prune", action="store_true",
                        help="also remove html files the bundle does not contain "
                             "(destructive: drops the private fonts and contract previews)")
    parser.add_argument("--sudo-password", default=os.environ.get("LUNANEXA_SUDO_PASSWORD"))
    arguments = parser.parse_args()

    if not arguments.sudo_password and os.geteuid() != 0:
        sys.exit("no sudo password: pass --sudo-password or set LUNANEXA_SUDO_PASSWORD")
    if not os.path.isdir(arguments.dist):
        sys.exit(f"no bundle at {arguments.dist}; run scripts/build-browser-bundles.sh first")
    target_root = arguments.target_root.strip("/")
    if not target_root or ".." in target_root.split("/"):
        sys.exit("target root must be a bounded image-relative path")

    work = arguments.work
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(f"{work}/base", exist_ok=True)

    exported = sudo(
        arguments.sudo_password,
        ["k3s", "ctr", "-n", NAMESPACE, "images", "export", f"{work}/web-base.tar", arguments.base],
    )
    if exported.returncode != 0:
        sys.exit(f"cannot export {arguments.base}: {exported.stderr.strip()[:400]}")
    sudo(arguments.sudo_password, ["chmod", "644", f"{work}/web-base.tar"])
    with tarfile.open(f"{work}/web-base.tar") as archive:
        archive.extractall(f"{work}/base")

    def blob(digest):
        with open(os.path.join(work, "base", "blobs", "sha256", digest.split(":")[1]), "rb") as handle:
            return handle.read()

    index = json.load(open(f"{work}/base/index.json"))
    target = index["manifests"][0]
    manifest = json.loads(blob(target["digest"]))
    config = json.loads(blob(manifest["config"]["digest"]))

    previous = old_html_paths(work, manifest, target_root)
    print(f"base carries {len(previous)} html files across {len(manifest['layers'])} layers")

    wanted = {}
    for root, _, files in os.walk(arguments.dist):
        for name in files:
            if name.startswith("._") or name == ".DS_Store":
                continue
            source = os.path.join(root, name)
            rel = os.path.relpath(source, arguments.dist)
            wanted[f"{target_root}/{rel}"] = source
    if not wanted:
        sys.exit(f"bundle at {arguments.dist} is empty")

    removed = sorted(path for path in previous if is_junk(path))
    stale = sorted(path for path in previous if path not in wanted and path not in removed)
    print(f"bundle has {len(wanted)} files; removing {len(removed)} macOS droppings")
    for path in removed[:6]:
        print(f"  whiteout {path}")
    if len(removed) > 6:
        print(f"  ... and {len(removed) - 6} more")
    # The bundle is produced by scripts/build-browser-bundles.sh, which does not
    # own the whole html root: the licensed contract fonts (assets/fonts/private,
    # deliberately outside the repository) and the rendered contract previews
    # (console/contract-previews/**.webp) come from other steps. Removing files
    # this bundle merely does not know about would delete them and break contract
    # rendering, so anything it does not overwrite is left alone and only
    # reported. --prune turns that into the destructive behaviour, for the case
    # where the bundle really is a complete replacement.
    if arguments.prune:
        removed = sorted(previous - set(wanted))
        print(f"--prune: removing {len(removed)} files the bundle does not contain")
    elif stale:
        print(f"  leaving {len(stale)} files the bundle does not overwrite "
              f"(fonts, contract previews); pass --prune to remove them")

    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for path, source in sorted(wanted.items()):
            info = tarfile.TarInfo(path)
            info.mode = 0o644
            info.mtime = int(time.time())
            info.size = os.path.getsize(source)
            with open(source, "rb") as handle:
                archive.addfile(info, handle)
        for path in removed:
            # An OCI whiteout is an empty file named .wh.<basename> in the parent.
            parent, _, name = path.rpartition("/")
            entry = tarfile.TarInfo(f"{parent}/.wh.{name}")
            entry.size = 0
            entry.mtime = int(time.time())
            archive.addfile(entry)
    raw = buffer.getvalue()
    compressed = gzip.compress(raw, mtime=0)
    layer_digest = hashlib.sha256(compressed).hexdigest()
    with open(os.path.join(work, "base", "blobs", "sha256", layer_digest), "wb") as handle:
        handle.write(compressed)
    layer_diff = hashlib.sha256(raw).hexdigest()

    manifest["layers"] = manifest["layers"] + [{
        "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
        "digest": f"sha256:{layer_digest}",
        "size": len(compressed),
    }]
    config["rootfs"]["diff_ids"] = config["rootfs"]["diff_ids"] + [f"sha256:{layer_diff}"]
    config["created"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    config_raw = json.dumps(config).encode()
    config_digest = hashlib.sha256(config_raw).hexdigest()
    with open(os.path.join(work, "base", "blobs", "sha256", config_digest), "wb") as handle:
        handle.write(config_raw)

    manifest["config"] = {
        "mediaType": "application/vnd.oci.image.config.v1+json",
        "digest": f"sha256:{config_digest}",
        "size": len(config_raw),
    }
    manifest_raw = json.dumps(manifest).encode()
    manifest_digest = hashlib.sha256(manifest_raw).hexdigest()
    with open(os.path.join(work, "base", "blobs", "sha256", manifest_digest), "wb") as handle:
        handle.write(manifest_raw)

    index["manifests"] = [{
        "mediaType": "application/vnd.oci.image.manifest.v1+json",
        "digest": f"sha256:{manifest_digest}",
        "size": len(manifest_raw),
        "annotations": {"org.opencontainers.image.ref.name": arguments.image},
        "platform": target.get("platform", {"architecture": config.get("architecture", "amd64"), "os": "linux"}),
    }]
    with open(f"{work}/base/index.json", "w") as handle:
        json.dump(index, handle)

    archive_path = f"{work}/{arguments.image.replace(':', '-').replace('/', '_')}.oci.tar"
    with tarfile.open(archive_path, "w") as archive:
        archive.add(f"{work}/base", arcname=".")

    imported = sudo(arguments.sudo_password, ["k3s", "ctr", "-n", NAMESPACE, "images", "import", archive_path])
    if imported.returncode != 0:
        sys.exit(f"import failed: {imported.stderr.strip()[:400]}")
    sudo(
        arguments.sudo_password,
        ["k3s", "ctr", "-n", NAMESPACE, "images", "tag", "--force", arguments.image,
         f"docker.io/library/{arguments.image}"],
    )
    print(f"WEB-IMAGE-OK {arguments.image} {archive_path} ({len(wanted)} files, {len(removed)} whiteouts)")


if __name__ == "__main__":
    main()
