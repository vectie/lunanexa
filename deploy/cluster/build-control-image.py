#!/usr/bin/env python3
"""Package the control plane image from a locally built binary.

The management node has no route to an image registry the cluster trusts, so the
deployed image is assembled here and imported straight into containerd. The
existing image supplies the process metadata and whatever the base filesystem
already had; the binary layer is replaced with the freshly built control binary
plus the host's own C library closure, because the binaries are linked against
the host toolchain rather than the base image's.

Idempotent: the layer that carries the binaries is identified by shape, not by
position, so running this on an image this script produced replaces that layer
instead of stacking another one.

Every value that used to be a literal -- the sudo password, the base reference,
the binary paths -- is an argument or an environment variable, so this can live
in the repository instead of in one operator's home directory.
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

BINARY_NAMES = ("lunanexa-control", "lunanexa-loopback-proxy")
# glibc NSS modules are dlopen'd at runtime and never appear in ldd output, so
# they have to be added by hand to keep name resolution working.
NSS_MODULES = (
    "/lib/x86_64-linux-gnu/libnss_dns.so.2",
    "/lib/x86_64-linux-gnu/libnss_files.so.2",
)


def sudo(password, command):
    if os.geteuid() == 0:
        return subprocess.run(command, capture_output=True, text=True)
    return subprocess.run(
        ["sudo", "-S", "-k"] + command,
        input=password + "\n",
        capture_output=True,
        text=True,
    )


def ldd_closure(binary):
    out = subprocess.run(["ldd", binary], capture_output=True, text=True).stdout
    libs = []
    for line in out.splitlines():
        parts = line.split("=>")
        if len(parts) == 2:
            path = parts[1].strip().split(" ")[0]
        else:
            path = line.strip().split(" ")[0]
        if path.startswith("/") and "linux-vdso" not in path:
            libs.append(path)
    return sorted(set(libs))


def is_binary_layer(names):
    """True when every file in the layer is a binary or a library.

    Both the base image's own two-file binary layer and a layer written by an
    earlier run of this script satisfy it, which is what makes re-running safe.
    """
    for name in names:
        stripped = name.lstrip("./")
        if not stripped:
            continue
        if os.path.basename(stripped) in BINARY_NAMES:
            continue
        if stripped.startswith(("usr/local/bin/", "lib/", "lib64/", "usr/lib/")):
            continue
        return False
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", required=True, help="tag to produce, e.g. lunanexa-control:20260918")
    parser.add_argument("--base-image", help="image to take the base layers from (default: --image)")
    parser.add_argument("--binary", required=True, help="path to the built control binary")
    parser.add_argument("--aux-binary", required=True, help="path to the loopback proxy binary")
    parser.add_argument("--work", default=os.path.expanduser("~/control-build/image"))
    parser.add_argument("--sudo-password", default=os.environ.get("LUNANEXA_SUDO_PASSWORD", ""))
    arguments = parser.parse_args()

    base = arguments.base_image or arguments.image
    for path in (arguments.binary, arguments.aux_binary):
        if not os.path.exists(path):
            sys.exit(f"no binary at {path}")
    if not arguments.sudo_password and os.geteuid() != 0:
        sys.exit("missing sudo credentials; pass --sudo-password or set LUNANEXA_SUDO_PASSWORD")

    work = arguments.work
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(f"{work}/base", exist_ok=True)

    exported = sudo(
        arguments.sudo_password,
        ["k3s", "ctr", "-n", "k8s.io", "images", "export", f"{work}/control-base.tar", base],
    )
    if exported.returncode != 0:
        sys.exit(f"cannot export {base} from containerd: {exported.stderr.strip()[:400]}")
    sudo(arguments.sudo_password, ["chmod", "644", f"{work}/control-base.tar"])
    with tarfile.open(f"{work}/control-base.tar") as archive:
        archive.extractall(f"{work}/base")

    def blob(digest):
        with open(f"{work}/base/blobs/sha256/{digest.split(':')[1]}", "rb") as handle:
            return handle.read()

    with open(f"{work}/base/index.json") as handle:
        index = json.load(handle)
    manifest = json.loads(blob(index["manifests"][0]["digest"]))
    config = json.loads(blob(manifest["config"]["digest"]))

    binary_layer = None
    for position, layer in enumerate(manifest["layers"]):
        with tarfile.open(f"{work}/base/blobs/sha256/{layer['digest'].split(':')[1]}", "r:*") as archive:
            # Directory entries are not files. Some archives carry them without a
            # trailing slash, and counting those made every layer look like it
            # held something other than binaries.
            names = [member.name for member in archive.getmembers() if member.isfile()]
        if any("lunanexa-control" in name for name in names) and is_binary_layer(names):
            binary_layer = position
            print(f"replacing binary layer {position} ({len(names)} files)")
            break
    if binary_layer is None:
        # Appending is enough: layers stack last-wins, so the fresh binaries at
        # /usr/local/bin shadow whatever the base put there. Picking a layer to
        # delete is only a size optimisation and it depends on the base's layout,
        # so do not fail the build on it.
        print("no replaceable binary layer; appending the new binaries as a layer")

    keep_layers = [layer for position, layer in enumerate(manifest["layers"]) if position != binary_layer]
    keep_diffs = [diff for position, diff in enumerate(config["rootfs"]["diff_ids"]) if position != binary_layer]

    libraries = sorted(
        set(
            path
            for binary in (arguments.binary, arguments.aux_binary)
            for path in ldd_closure(binary)
        )
        | {module for module in NSS_MODULES if os.path.exists(module)}
    )
    print(f"library closure: {len(libraries)} entries")

    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w") as archive:
        for source, target in (
            (arguments.binary, "usr/local/bin/lunanexa-control"),
            (arguments.aux_binary, "usr/local/bin/lunanexa-loopback-proxy"),
        ):
            info = tarfile.TarInfo(target)
            info.mode = 0o755
            info.mtime = int(time.time())
            info.size = os.path.getsize(source)
            with open(source, "rb") as handle:
                archive.addfile(info, handle)
        for library in libraries:
            real = os.path.realpath(library)
            info = tarfile.TarInfo(library.lstrip("/"))
            info.mode = 0o755
            info.mtime = int(time.time())
            info.size = os.path.getsize(real)
            with open(real, "rb") as handle:
                archive.addfile(info, handle)
    raw = buffer.getvalue()
    compressed = gzip.compress(raw, mtime=0)
    layer_digest = hashlib.sha256(compressed).hexdigest()
    with open(f"{work}/base/blobs/sha256/{layer_digest}", "wb") as handle:
        handle.write(compressed)
    layer_diff = hashlib.sha256(raw).hexdigest()

    # the libraries come first so the fresh binaries shadow any older copy
    manifest["layers"] = keep_layers + [
        {
            "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
            "digest": f"sha256:{layer_digest}",
            "size": len(compressed),
        }
    ]
    config["rootfs"]["diff_ids"] = keep_diffs + [f"sha256:{layer_diff}"]
    config["created"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    config_raw = json.dumps(config).encode()
    config_digest = hashlib.sha256(config_raw).hexdigest()
    with open(f"{work}/base/blobs/sha256/{config_digest}", "wb") as handle:
        handle.write(config_raw)

    manifest["config"] = {
        "mediaType": "application/vnd.oci.image.config.v1+json",
        "digest": f"sha256:{config_digest}",
        "size": len(config_raw),
    }
    manifest_raw = json.dumps(manifest).encode()
    manifest_digest = hashlib.sha256(manifest_raw).hexdigest()
    with open(f"{work}/base/blobs/sha256/{manifest_digest}", "wb") as handle:
        handle.write(manifest_raw)

    index["manifests"] = [
        {
            "mediaType": "application/vnd.oci.image.manifest.v1+json",
            "digest": f"sha256:{manifest_digest}",
            "size": len(manifest_raw),
            "annotations": {"org.opencontainers.image.ref.name": arguments.image},
            "platform": {"architecture": "amd64", "os": "linux"},
        }
    ]
    with open(f"{work}/base/index.json", "w") as handle:
        json.dump(index, handle)

    archive_path = f"{work}/{arguments.image.replace(':', '-').replace('/', '_')}.oci.tar"
    with tarfile.open(archive_path, "w") as archive:
        archive.add(f"{work}/base", arcname=".")

    imported = sudo(arguments.sudo_password, ["k3s", "ctr", "-n", "k8s.io", "images", "import", archive_path])
    if imported.returncode != 0:
        sys.exit(f"import failed: {imported.stderr.strip()[:400]}")
    sudo(
        arguments.sudo_password,
        ["k3s", "ctr", "-n", "k8s.io", "images", "tag", "--force", arguments.image,
         f"docker.io/library/{arguments.image}"],
    )
    print(f"CONTROL-IMAGE-OK {arguments.image} {archive_path}")


if __name__ == "__main__":
    main()
