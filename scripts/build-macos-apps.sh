#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
lepusa_root=${LEPUSA_ROOT:-"$repo_root/../lepusa"}
base_url=${1:-${LUNANEXA_DESKTOP_BASE_URL:-}}
version=${2:-${LUNANEXA_DESKTOP_VERSION:-0.1.0}}
output_root="$repo_root/_build/macos"
signing_identity=${LUNANEXA_MACOS_SIGNING_IDENTITY:--}
notarization_profile=${LUNANEXA_MACOS_NOTARIZATION_PROFILE:-}
allow_loopback=${LUNANEXA_DESKTOP_ALLOW_HTTP_LOOPBACK:-0}
minimum_system_version=${LUNANEXA_MACOS_MINIMUM_VERSION:-13.0}
probe_timeout_ms=${LUNANEXA_DESKTOP_PROBE_TIMEOUT_MS:-7000}
architecture=$(uname -m)

fail() {
  printf '%s\n' "error: $*" >&2
  exit 1
}

test -n "$base_url" || fail "management base URL is required (for example, https://manage.example.com)"
test -d "$lepusa_root" || fail "Lepusa checkout was not found at $lepusa_root; set LEPUSA_ROOT"
test -f "$lepusa_root/moon.mod" || fail "LEPUSA_ROOT is not a Lepusa MoonBit workspace: $lepusa_root"
command -v jq >/dev/null 2>&1 || fail "jq is required to generate concrete Lepusa manifests"

if printf %s "$base_url" | LC_ALL=C grep -q '[[:space:]]'; then
  fail "management base URL must not contain whitespace"
fi
case "$base_url" in
  *\\*|*\"*) fail "management base URL contains an invalid character" ;;
esac

case "$architecture" in
  arm64|x86_64) ;;
  *) fail "unsupported macOS build architecture: $architecture" ;;
esac

case "$minimum_system_version" in
  *.*) ;;
  *) fail "minimum macOS version must use major.minor form" ;;
esac
minimum_major=${minimum_system_version%%.*}
minimum_minor=${minimum_system_version#*.}
case "$minimum_major:$minimum_minor" in
  *[!0-9:]*|:|*:) fail "minimum macOS version must use numeric major.minor form" ;;
esac
test "$minimum_major" -ge 13 || fail "LunaNexa desktop requires a minimum target of macOS 13.0 or newer"

case "$probe_timeout_ms" in
  ''|*[!0-9]*) fail "desktop probe timeout must be an integer number of milliseconds" ;;
esac
test "$probe_timeout_ms" -ge 1000 && test "$probe_timeout_ms" -le 30000 || \
  fail "desktop probe timeout must be between 1000 and 30000 milliseconds"

case "$base_url" in
  *\?*|*\#*|*://*@*)
    fail "management base URL must not contain credentials, a query, or a fragment"
    ;;
  https://*)
    ;;
  http://127.0.0.1:*|http://localhost:*)
    test "$allow_loopback" = "1" || fail "plain HTTP is accepted only for loopback builds with LUNANEXA_DESKTOP_ALLOW_HTTP_LOOPBACK=1"
    ;;
  *)
    fail "management base URL must use HTTPS (or explicit loopback development mode)"
    ;;
esac

authority_and_path=${base_url#*://}
authority=${authority_and_path%%/*}
test -n "$authority" || fail "management base URL must include a host"
case "$authority_and_path" in
  "$authority"|"$authority"/) ;;
  *) fail "management base URL must be an origin without a path" ;;
esac

case "$version" in
  ''|*[!0-9A-Za-z.-]*) fail "version may contain only letters, digits, dots, and hyphens" ;;
esac

if test "$signing_identity" = "-" && test -n "$notarization_profile"; then
  fail "Apple notarization requires a Developer ID signing identity"
fi

base_url=${base_url%/}
operator_url="$base_url/console/"
enterprise_url="$base_url/enterprise/"
config_root="$output_root/config"
icon_root="$output_root/icons"
bundle_root="$output_root/bundles"
package_root="$output_root/packages"
release_root="$output_root/releases"
startup_root="$output_root/startup"
lepusa_target_root="$output_root/lepusa-target-macos-$minimum_system_version"

mkdir -p \
  "$config_root" \
  "$icon_root" \
  "$bundle_root" \
  "$package_root" \
  "$release_root" \
  "$startup_root"

make_icon() {
  name=$1
  source_svg=$2
  iconset="$icon_root/$name.iconset"
  source_png="$icon_root/$name-1024.png"
  raster_root="$icon_root/$name-raster"
  rasterized="$raster_root/${source_svg##*/}.png"
  target_icns="$icon_root/$name.icns"

  rm -rf "$iconset" "$raster_root"
  mkdir -p "$iconset" "$raster_root"
  /usr/bin/qlmanage -t -s 1024 -o "$raster_root" "$source_svg" >/dev/null
  test -s "$rasterized" || fail "failed to rasterize $source_svg"
  cp "$rasterized" "$source_png"
  /usr/bin/sips -z 16 16 "$source_png" --out "$iconset/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$source_png" --out "$iconset/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$source_png" --out "$iconset/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$source_png" --out "$iconset/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$source_png" --out "$iconset/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$source_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$source_png" --out "$iconset/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$source_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$source_png" --out "$iconset/icon_512x512.png" >/dev/null
  cp "$source_png" "$iconset/icon_512x512@2x.png"
  /usr/bin/iconutil -c icns "$iconset" -o "$target_icns"
  test -s "$target_icns" || fail "failed to create $target_icns"
}

make_config() {
  name=$1
  template=$2
  icon=$3
  startup=$4
  target="$config_root/$name.json"

  if test -n "$notarization_profile"; then
    jq \
      --arg version "$version" \
      --arg icon "$icon" \
      --arg identity "$signing_identity" \
      --arg profile "$notarization_profile" \
      --arg startup "$startup" \
      '.version = $version | .icon = $icon | .signing.identity = $identity | .signing.notarizationProfile = $profile | .window.source = {"packaged": $startup}' \
      "$template" >"$target"
  else
    jq \
      --arg version "$version" \
      --arg icon "$icon" \
      --arg identity "$signing_identity" \
      --arg startup "$startup" \
      '.version = $version | .icon = $icon | .signing.identity = $identity | del(.signing.notarizationProfile) | .window.source = {"packaged": $startup}' \
      "$template" >"$target"
  fi
  jq -e . "$target" >/dev/null
}

make_startup() {
  name=$1
  product_name=$2
  edition=$3
  target_url=$4
  application_route=$5
  target="$startup_root/$name"

  rm -rf "$target"
  mkdir -p "$target"
  cp "$repo_root/desktop/startup/index.html" "$target/index.html"
  cp "$repo_root/desktop/startup/startup.css" "$target/startup.css"
  cp "$repo_root/desktop/startup/startup.js" "$target/startup.js"
  config_json=$(jq -cn \
    --arg productName "$product_name" \
    --arg edition "$edition" \
    --arg managementOrigin "$base_url" \
    --arg targetUrl "$target_url" \
    --arg applicationRoute "$application_route" \
    --argjson probeTimeoutMs "$probe_timeout_ms" \
    '{productName: $productName, edition: $edition, managementOrigin: $managementOrigin, targetUrl: $targetUrl, applicationRoute: $applicationRoute, probeTimeoutMs: $probeTimeoutMs}')
  printf '%s\n' "globalThis.LUNANEXA_DESKTOP_CONFIG = $config_json;" >"$target/config.js"
  test -s "$target/config.js" || fail "failed to create startup configuration for $product_name"
}

make_icon \
  lunanexa-operator \
  "$repo_root/assets/desktop/lunanexa-operator.svg"
make_icon \
  lunanexa-enterprise \
  "$repo_root/assets/desktop/lunanexa-enterprise.svg"

make_startup \
  operator \
  "LunaNexa Operator" \
  "Operator" \
  "$operator_url" \
  "/console/"
make_startup \
  enterprise \
  "LunaNexa Enterprise" \
  "Enterprise" \
  "$enterprise_url" \
  "/enterprise/ → /workbench/"

make_config \
  operator \
  "$repo_root/desktop/operator/lepusa.template.json" \
  "$icon_root/lunanexa-operator.icns" \
  "$startup_root/operator"
make_config \
  enterprise \
  "$repo_root/desktop/enterprise/lepusa.template.json" \
  "$icon_root/lunanexa-enterprise.icns" \
  "$startup_root/enterprise"

cd "$lepusa_root"
MACOSX_DEPLOYMENT_TARGET="$minimum_system_version" \
  moon build \
    cmd/main \
    cmd/runtime \
    --target native \
    --release \
    --target-dir "$lepusa_target_root"
lepusa_cli="$lepusa_target_root/native/release/build/cmd/main/main.exe"
lepusa_runtime="$lepusa_target_root/native/release/build/cmd/runtime/runtime.exe"
test -x "$lepusa_cli" || fail "Lepusa CLI release executable was not built"
test -x "$lepusa_runtime" || fail "Lepusa runtime release executable was not built"
runtime_minimum=$(/usr/bin/vtool -show-build "$lepusa_runtime" | awk '$1 == "minos" { print $2; exit }')
test "$runtime_minimum" = "$minimum_system_version" || \
  fail "Lepusa runtime minimum is $runtime_minimum, expected $minimum_system_version"

package_app() {
  name=$1
  display_name=$2
  manifest="$config_root/$name.json"
  app_bundle_root="$bundle_root/$name"
  app_package_root="$package_root/$name"

  rm -rf "$app_bundle_root" "$app_package_root"
  LEPUSA_RUNTIME_EXECUTABLE="$lepusa_runtime" \
    "$lepusa_cli" verify macos --strict --project "$manifest"
  LEPUSA_RUNTIME_EXECUTABLE="$lepusa_runtime" \
    "$lepusa_cli" bundle-write macos "$app_bundle_root" --project "$manifest"

  distribution=$(find "$app_bundle_root" -type f -name distribution.json -print -quit)
  test -n "$distribution" || fail "Lepusa did not write a distribution manifest for $display_name"
  app_bundle=$(find "$app_bundle_root" -maxdepth 1 -type d -name '*.app' -print -quit)
  test -n "$app_bundle" || fail "Lepusa did not write an app bundle for $display_name"
  info_plist="$app_bundle/Contents/Info.plist"
  /usr/libexec/PlistBuddy \
    -c "Add :LSMinimumSystemVersion string $minimum_system_version" \
    "$info_plist"
  declared_minimum=$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$info_plist")
  test "$declared_minimum" = "$minimum_system_version" || \
    fail "$display_name declares macOS $declared_minimum, expected $minimum_system_version"
  bundled_minimum=$(/usr/bin/vtool \
    -show-build \
    "$app_bundle/Contents/MacOS/lepusa-runtime" | \
    awk '$1 == "minos" { print $2; exit }')
  test "$bundled_minimum" = "$minimum_system_version" || \
    fail "$display_name runtime requires macOS $bundled_minimum, expected $minimum_system_version"
  "$lepusa_cli" bundle-package-write "$distribution" "$app_package_root"
  test -f "$app_package_root/package.sh" || fail "Lepusa did not write the macOS package script for $display_name"
  BUNDLE_ROOT="$app_bundle_root" sh "$app_package_root/package.sh"

  dmg=$(find "$app_bundle_root" -maxdepth 1 -type f -name '*.dmg' -print -quit)
  test -n "$dmg" || fail "Lepusa did not create a DMG for $display_name"
  release_dmg="$release_root/$display_name-$version-macos-$architecture.dmg"
  cp "$dmg" "$release_dmg"
  /usr/bin/hdiutil verify "$release_dmg" >/dev/null
  (cd "$release_root" && /usr/bin/shasum -a 256 "${release_dmg##*/}") >"$release_dmg.sha256"
  printf '%s\n' "ready: $release_dmg"
}

package_app operator LunaNexa-Operator
package_app enterprise LunaNexa-Enterprise

printf '%s\n' "macOS desktop release complete: $release_root"
