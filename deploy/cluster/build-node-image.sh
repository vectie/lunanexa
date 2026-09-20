#!/bin/bash
# Build the ARM64 node agent on a DGX Spark and package it as an OCI archive.
#
# Runs ON a Spark. libpq is not installed system-wide there, so the dev package
# is unpacked into the home directory instead: no root, no change to the host's
# package state. The archive is consumed by one-click.sh --node-image-tar.
#
# usage: build-node-image.sh [--source ~/src] [--tag lunanexa-node:20260918-arm64]
#
# NOTE: the build half is the procedure that produced the image currently
# running on all four nodes. The packaging half mirrors
# deploy/cluster/build-control-image.py, but has not been exercised end to end
# on this cluster -- the running image is still used as-is by default.
set -euo pipefail

SOURCE="$HOME/src"
TAG="lunanexa-node:20260918-arm64"
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

export MOON_HOME="$HOME/moon"
export PATH="$HOME/moon/bin:$PATH"
PQ="$HOME/libpq-root"
if [ ! -d "$PQ" ]; then
  mkdir -p "$PQ"
  for deb in "$HOME"/libpq-dev_*_arm64.deb "$HOME"/libpq5_*_arm64.deb; do
    [ -f "$deb" ] && dpkg-deb -x "$deb" "$PQ"
  done
fi
export C_INCLUDE_PATH="$PQ/usr/include/postgresql:$PQ/usr/include"
export LIBRARY_PATH="$PQ/usr/lib/aarch64-linux-gnu"

cd "$SOURCE"
moon build --target native --release cmd/node
BINARY="$SOURCE/_build/native/release/build/cmd/node/node.exe"
PROXY="$HOME/lunanexa-loopback-proxy-arm64"
[ -x "$PROXY" ] || { echo "missing $PROXY (the loopback proxy must ship beside the agent)" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/config.json" <<JSON
{
  "architecture": "arm64",
  "os": "linux",
  "config": {
    "Entrypoint": ["/usr/local/bin/lunanexa-node"],
    "Env": ["PATH=/usr/local/bin:/usr/bin:/bin"],
    "WorkingDir": "/"
  },
  "rootfs": {"type": "layers", "diff_ids": []}
}
JSON

# The binaries are linked against the Spark's own toolchain, so their library
# closure is shipped alongside them rather than relied on from a base image.
LIBS=$(ldd "$BINARY" "$PROXY" | awk '/=>/ {print $3} /^[[:space:]]*\// {print $1}' | grep '^/' | sort -u)
python3 - "$BINARY" "$PROXY" "$WORK" "$TAG" "$LIBS" <<'PY'
import gzip, hashlib, io, json, os, subprocess, sys, tarfile, time

binary, proxy, work, tag, libraries = sys.argv[1:6]
sources = [(binary, "usr/local/bin/lunanexa-node"), (proxy, "usr/local/bin/lunanexa-loopback-proxy")]
for library in sorted(set(x for x in libraries.split() if os.path.exists(x))):
    sources.append((os.path.realpath(library), library.lstrip("/")))

buffer = io.BytesIO()
with tarfile.open(fileobj=buffer, mode="w") as archive:
    for source, target in sources:
        info = tarfile.TarInfo(target)
        info.mode = 0o755
        info.mtime = int(time.time())
        info.size = os.path.getsize(source)
        with open(source, "rb") as handle:
            archive.addfile(info, handle)
raw = buffer.getvalue()
compressed = gzip.compress(raw, mtime=0)
layer_digest = hashlib.sha256(compressed).hexdigest()

config = json.load(open(f"{work}/config.json"))
config["rootfs"]["diff_ids"] = [f"sha256:{hashlib.sha256(raw).hexdigest()}"]
config["created"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
config_raw = json.dumps(config).encode()
config_digest = hashlib.sha256(config_raw).hexdigest()
manifest = {
    "schemaVersion": 2,
    "mediaType": "application/vnd.oci.image.manifest.v1+json",
    "config": {"mediaType": "application/vnd.oci.image.config.v1+json",
               "digest": f"sha256:{config_digest}", "size": len(config_raw)},
    "layers": [{"mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
                "digest": f"sha256:{layer_digest}", "size": len(compressed)}],
}
manifest_raw = json.dumps(manifest).encode()
manifest_digest = hashlib.sha256(manifest_raw).hexdigest()
index = {"schemaVersion": 2,
         "manifests": [{"mediaType": "application/vnd.oci.image.manifest.v1+json",
                        "digest": f"sha256:{manifest_digest}", "size": len(manifest_raw),
                        "annotations": {"org.opencontainers.image.ref.name": tag},
                        "platform": {"architecture": "arm64", "os": "linux"}}]}

base = os.path.join(work, "image")
os.makedirs(os.path.join(base, "blobs/sha256"), exist_ok=True)
for digest, payload in ((layer_digest, compressed), (config_digest, config_raw), (manifest_digest, manifest_raw)):
    open(os.path.join(base, "blobs/sha256", digest), "wb").write(payload)
open(os.path.join(base, "index.json"), "w").write(json.dumps(index))
open(os.path.join(base, "oci-layout"), "w").write('{"imageLayoutVersion": "1.0.0"}')

out = os.path.expanduser(f"~/lunanexa-node-{tag.split(':')[1]}.oci.tar")
with tarfile.open(out, "w") as archive:
    archive.add(base, arcname=".")
print(f"NODE-IMAGE-OK {tag} {out}")
PY
