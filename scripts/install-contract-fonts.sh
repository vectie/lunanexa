#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
private_dir="$repo_root/assets/fonts/private"
user_font_dir=${LUNANEXA_USER_FONT_DIR:-"$HOME/Library/Fonts/LunaNexa"}

usage() {
  printf '%s\n' \
    'usage: scripts/install-contract-fonts.sh <FangSong_GB2312.ttf> [FZXiaoBiaoSong-B05S.ttf] [SimHei.ttf]' \
    '' \
    'Only organization-licensed font files may be supplied. Accepted files are' \
    'copied to assets/fonts/private for the browser build and to the current' \
    'macOS user font directory. Private font binaries remain Git-ignored.'
}

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 64
fi

mkdir -p "$private_dir" "$user_font_dir"

verify_font() {
  source_path=$1
  output_name=$2
  required_family=$3

  if [ ! -f "$source_path" ]; then
    printf '%s\n' "font file not found: $source_path" >&2
    exit 66
  fi

  metadata=$(moon run cmd/font-inspect --target native -- "$source_path" "$required_family")
  fs_type=$(printf '%s\n' "$metadata" | sed -n 's/^fs_type=//p')

  cp "$source_path" "$private_dir/$output_name"
  cp "$source_path" "$user_font_dir/$output_name"
  printf '%s\n' "installed $required_family -> $output_name (OS/2 fsType=$fs_type)"
}

verify_font "$1" FangSong_GB2312.ttf FangSong_GB2312
if [ "$#" -ge 2 ]; then
  verify_font "$2" FZXiaoBiaoSong-B05S.ttf 方正小标宋简体
fi
if [ "$#" -ge 3 ]; then
  verify_font "$3" SimHei.ttf SimHei
fi

printf '%s\n' 'Rebuild with: sh scripts/build-browser-bundles.sh'
