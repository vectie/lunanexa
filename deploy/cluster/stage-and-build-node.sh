#!/bin/bash
# Prepare an arm64 build environment on a Spark and build the node agent.
#
# There is no cross-compilation here: the node agent is built on the same
# architecture it runs on. Everything the build needs is staged from the
# management node, which is the only machine with the artifacts, so the Spark
# itself never has to reach a registry or a package mirror.
#
# usage: stage-and-build-node.sh <spark-ip> <spark-user> [<src-tar>]
set -euo pipefail

SPARK="${1:?spark address}"
USER="${2:?spark user}"
TAR="${3:-$HOME/lunanexa-src.tar.gz}"
BUILD="$HOME/spark-build"
SSH="ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=15 $USER@$SPARK"
SCP="scp -q -o BatchMode=yes -o StrictHostKeyChecking=no"

echo "=== staging the toolchain and the dependency snapshot on $SPARK"
$SSH 'mkdir -p ~/stage ~/libpq-root'
$SCP "$BUILD/moonbit-linux-aarch64.tar.gz" "$USER@$SPARK:~/stage/moonbit.tar.gz"
$SCP "$BUILD/mooncakes2.tar.gz" "$USER@$SPARK:~/stage/mooncakes.tar.gz"
$SCP "$BUILD"/debs/libpq5_*_arm64.deb "$BUILD"/debs/libpq-dev_*_arm64.deb "$USER@$SPARK:~/stage/"
$SCP "$TAR" "$USER@$SPARK:~/stage/lunanexa-src.tar.gz"

echo "=== unpacking"
$SSH 'set -e
  rm -rf ~/moon ~/src ~/libpq-root
  mkdir -p ~/moon ~/src ~/libpq-root
  tar -xzf ~/stage/moonbit.tar.gz -C ~/moon
  chmod -R u+x ~/moon/bin ~/moon/lib
  for deb in ~/stage/libpq*.deb; do dpkg-deb -x "$deb" ~/libpq-root; done
  tar -xzf ~/stage/lunanexa-src.tar.gz -C ~/src
  if [ ! -d ~/src/.mooncakes ]; then
    mkdir -p ~/src/.mooncakes
    tar -xzf ~/stage/mooncakes.tar.gz -C ~/src/.mooncakes 2>/dev/null || true
  fi
  find ~/src -name "._*" -delete
  export MOON_HOME=$HOME/moon
  export PATH=$HOME/moon/bin:$PATH
  moon version'
echo "=== building the node agent and the loopback proxy"
$SSH 'set -e
  export MOON_HOME=$HOME/moon
  export PATH=$HOME/moon/bin:$PATH
  export C_INCLUDE_PATH=$HOME/libpq-root/usr/include/postgresql:$HOME/libpq-root/usr/include
  export LIBRARY_PATH=$HOME/libpq-root/usr/lib/aarch64-linux-gnu
  cd ~/src
  moon build --target native --release cmd/node cmd/loopback-proxy
  proxy=_build/native/release/build/cmd/loopback-proxy/loopback-proxy
  [ -x "$proxy" ] || proxy="$proxy.exe"
  cp "$proxy" ~/lunanexa-loopback-proxy-arm64
  ls -l _build/native/release/build/cmd/node/node.exe ~/lunanexa-loopback-proxy-arm64'
echo "BUILD-OK"

