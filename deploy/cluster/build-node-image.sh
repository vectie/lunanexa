#!/bin/bash
# Package the arm64 node agent image on a Spark.
#
# This is the procedure that produced the image currently running on all four
# nodes, moved out of a home directory and into the repository. It builds a
# single-layer rootfs rather than a base image plus layers because the agent
# binary is linked against the Spark's own toolchain: the glibc it needs, the
# resolver modules it dlopens, nvidia-smi and the NVML library it calls all
# come from the host it runs on, so they are copied in explicitly. Nothing is
# fetched from a registry.
#
# The image is imported locally on each node by one-click.sh; the cluster's
# registry cannot be reached by kubelets, so a pull would never work.
#
# usage: build-node-image.sh [--source ~/src] [--tag lunanexa-node:20260918-arm64-r5]
#                            [--proxy ~/lunanexa-loopback-proxy-arm64]
set -euo pipefail

SOURCE="$HOME/src"
TAG="lunanexa-node:20260920-arm64-r5"
PROXY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --tag) TAG="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

AGENT="$SOURCE/_build/native/release/build/cmd/node/node.exe"
[ -x "$AGENT" ] || { echo "no agent binary at $AGENT; build cmd/node first" >&2; exit 1; }
if [ -z "$PROXY" ]; then
  for candidate in \
    "$SOURCE/_build/native/release/build/cmd/loopback-proxy/loopback-proxy" \
    "$SOURCE/_build/native/release/build/cmd/loopback-proxy/loopback-proxy.exe" \
    "$HOME/lunanexa-loopback-proxy-arm64" \
    "$HOME/lunanexa-loopback-proxy"; do
    [ -x "$candidate" ] && PROXY="$candidate" && break
  done
fi
[ -n "$PROXY" ] && [ -x "$PROXY" ] || { echo "no loopback proxy binary found" >&2; exit 1; }

WORK="$HOME/node-image"
ROOT="$WORK/rootfs"
rm -rf "$WORK"
mkdir -p "$ROOT"/usr/local/bin "$ROOT"/usr/bin "$ROOT"/lib/aarch64-linux-gnu \
  "$ROOT"/usr/lib/aarch64-linux-gnu "$ROOT"/etc/ssl/certs "$ROOT"/data/models \
  "$ROOT"/var/lib/lunanexa "$WORK"/oci/blobs/sha256

install -m 0755 "$AGENT" "$ROOT/usr/local/bin/lunanexa-node"
install -m 0755 "$PROXY" "$ROOT/usr/local/bin/lunanexa-loopback-proxy"
install -m 0755 /usr/bin/nvidia-smi "$ROOT/usr/bin/nvidia-smi"

# The agent measures the GPUs it owns through nvidia-smi and the NVML library.
for lib in libc.so.6 libpthread.so.0 libm.so.6 libdl.so.2 librt.so.1 \
  libnss_dns.so.2 libnss_files.so.2 libresolv.so.2; do
  cp -L "/lib/aarch64-linux-gnu/$lib" "$ROOT/lib/aarch64-linux-gnu/$lib"
done
cp -L /lib/ld-linux-aarch64.so.1 "$ROOT/lib/ld-linux-aarch64.so.1"
cp -L /usr/lib/aarch64-linux-gnu/libnvidia-ml.so.1 "$ROOT/usr/lib/aarch64-linux-gnu/libnvidia-ml.so.1"
cp /etc/ssl/certs/ca-certificates.crt "$ROOT/etc/ssl/certs/ca-certificates.crt"

grep -E 'root|65532' /etc/passwd > "$ROOT/etc/passwd" || cp /etc/passwd "$ROOT/etc/passwd"
grep -E 'root|65532' /etc/group > "$ROOT/etc/group" || cp /etc/group "$ROOT/etc/group"
printf 'hosts: files dns\n' > "$ROOT/etc/nsswitch.conf"
echo 'nogroup:x:65534:' >> "$ROOT/etc/group"
echo 'nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin' >> "$ROOT/etc/passwd"

cd "$ROOT"
tar --numeric-owner --owner=0 --group=0 -cf "$WORK/layer.tar" .
cd "$WORK"
gzip -n -9 layer.tar
LAYER_SHA=$(sha256sum layer.tar.gz | cut -d' ' -f1)
mv layer.tar.gz "oci/blobs/sha256/$LAYER_SHA"
LAYER_SIZE=$(stat -c%s "oci/blobs/sha256/$LAYER_SHA")
DIFF_ID=$(gunzip -c "oci/blobs/sha256/$LAYER_SHA" | sha256sum | cut -d' ' -f1)

cat > config.json <<EOF
{
  "architecture": "arm64",
  "os": "linux",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "config": {
    "Entrypoint": ["/usr/local/bin/lunanexa-node"],
    "WorkingDir": "/",
    "Env": ["PATH=/usr/local/bin:/usr/bin:/bin"]
  },
  "rootfs": {"type": "layers", "diff_ids": ["sha256:$DIFF_ID"]}
}
EOF
CFG_SHA=$(sha256sum config.json | cut -d' ' -f1)
CFG_SIZE=$(stat -c%s config.json)
mv config.json "oci/blobs/sha256/$CFG_SHA"

cat > manifest.json <<EOF
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:$CFG_SHA",
    "size": $CFG_SIZE
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:$LAYER_SHA",
      "size": $LAYER_SIZE
    }
  ]
}
EOF
MAN_SHA=$(sha256sum manifest.json | cut -d' ' -f1)
MAN_SIZE=$(stat -c%s manifest.json)
mv manifest.json "oci/blobs/sha256/$MAN_SHA"

cat > oci/index.json <<EOF
{
  "schemaVersion": 2,
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:$MAN_SHA",
      "size": $MAN_SIZE,
      "annotations": {"org.opencontainers.image.ref.name": "$TAG"},
      "platform": {"architecture": "arm64", "os": "linux"}
    }
  ]
}
EOF
echo '{"imageLayoutVersion": "1.0.0"}' > oci/oci-layout

ARCHIVE="$HOME/$(echo "$TAG" | tr ':' '-').oci.tar"
cd oci && tar -cf "$ARCHIVE" .
echo "NODE-IMAGE-OK $TAG $ARCHIVE layer=$LAYER_SHA"
