#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:-"$repo_root/_build/browser-dist"}

cd "$repo_root"
moon build cmd/console cmd/enterprise cmd/workbench cmd/installer-ui --target js --release --target-dir _build/browser-compiled

# Workspace builds are module-qualified. Never package stale standalone output
# left behind before moon.work was enabled.
browser_build_root=_build/browser-compiled/js/release/build
if test -f moon.work; then
  browser_build_root=$browser_build_root/vectie/lunanexa
fi

mkdir -p "$output_root/console" "$output_root/enterprise" "$output_root/workbench" "$output_root/installer" "$output_root/assets/contracts/youthpolicy/v1" "$output_root/assets/fonts/private"
cp cmd/console/index.html "$output_root/console/index.html"
cp assets/platform-logo.png "$output_root/assets/platform-logo.png"
cp assets/platform-logo-light.png "$output_root/assets/platform-logo-light.png"
cp "$browser_build_root/cmd/console/console.js" "$output_root/console/console.js"
cp cmd/enterprise/index.html "$output_root/enterprise/index.html"
if [ -n "${LUNANEXA_ENTERPRISE_PUBLIC_HTTP_ORIGINS:-}" ]; then
  case "$LUNANEXA_ENTERPRISE_PUBLIC_HTTP_ORIGINS" in
    *[!a-zA-Z0-9:./,_-]*)
      printf '%s\n' 'invalid enterprise public HTTP origins' >&2
      exit 1
      ;;
  esac
  sed "s|name=\"lunanexa-public-http-origin\" content=\"\"|name=\"lunanexa-public-http-origin\" content=\"$LUNANEXA_ENTERPRISE_PUBLIC_HTTP_ORIGINS\"|" \
    "$output_root/enterprise/index.html" > "$output_root/enterprise/index.html.tmp"
  mv "$output_root/enterprise/index.html.tmp" "$output_root/enterprise/index.html"
fi
cp "$browser_build_root/cmd/enterprise/enterprise.js" "$output_root/enterprise/enterprise.js"
cp cmd/workbench/index.html "$output_root/workbench/index.html"
cp "$browser_build_root/cmd/workbench/workbench.js" "$output_root/workbench/workbench.js"
cp cmd/installer-ui/index.html "$output_root/installer/index.html"
cp "$browser_build_root/cmd/installer-ui/installer-ui.js" "$output_root/installer/installer-ui.js"

asset_digest() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{ print $1 }'
  else
    printf '%s\n' 'sha256sum or shasum is required to version browser assets' >&2
    exit 1
  fi
}

render_asset_version() {
  index=$1
  placeholder=$2
  asset=$3
  digest=$(asset_digest "$asset")
  temporary="$index.tmp"
  sed "s/$placeholder/$digest/g" "$index" > "$temporary"
  mv "$temporary" "$index"
  grep -Fq "?v=$digest" "$index"
  if grep -Fq "$placeholder" "$index"; then
    printf 'browser asset digest placeholder was not rendered in %s\n' "$index" >&2
    exit 1
  fi
}

render_asset_version "$output_root/console/index.html" \
  __LUNANEXA_CONSOLE_ASSET_DIGEST__ "$output_root/console/console.js"
render_asset_version "$output_root/enterprise/index.html" \
  __LUNANEXA_ENTERPRISE_ASSET_DIGEST__ "$output_root/enterprise/enterprise.js"
render_asset_version "$output_root/workbench/index.html" \
  __LUNANEXA_WORKBENCH_ASSET_DIGEST__ "$output_root/workbench/workbench.js"
render_asset_version "$output_root/installer/index.html" \
  __LUNANEXA_INSTALLER_ASSET_DIGEST__ "$output_root/installer/installer-ui.js"
cp assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json "$output_root/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json"
mkdir -p "$output_root/assets/contracts/youthpolicy/undertaking-v1"
cp assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json "$output_root/assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json"
mkdir -p "$output_root/assets/contracts/youthpolicy/undertaking-ofl-v2"
cp assets/contracts/youthpolicy/undertaking-ofl-v2/moonleaf-preview-template.v2.json "$output_root/assets/contracts/youthpolicy/undertaking-ofl-v2/moonleaf-preview-template.v2.json"
cp assets/fonts/contract-fonts.css "$output_root/assets/fonts/contract-fonts.css"
moon run scripts/copy-open-contract-font-assets.mbtx -- "$repo_root" "$output_root"
moon run scripts/copy-private-contract-font-assets.mbtx -- "$repo_root" "$output_root"
moon run scripts/verify-browser-bundle-output.mbtx -- "$repo_root" "$output_root"

test -s "$output_root/console/index.html"
test -s "$output_root/console/console.js"
test -s "$output_root/enterprise/index.html"
test -s "$output_root/enterprise/enterprise.js"
test -s "$output_root/workbench/index.html"
test -s "$output_root/workbench/workbench.js"
test -s "$output_root/installer/index.html"
test -s "$output_root/installer/installer-ui.js"
test -s "$output_root/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json"
test -s "$output_root/assets/contracts/youthpolicy/undertaking-v1/moonleaf-preview-template.v1.json"
test -s "$output_root/assets/contracts/youthpolicy/undertaking-ofl-v2/moonleaf-preview-template.v2.json"
test -s "$output_root/assets/fonts/contract-fonts.css"

printf '%s\n' "browser bundles ready at $output_root"
