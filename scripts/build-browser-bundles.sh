#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_root=${1:-"$repo_root/_build/browser-dist"}

cd "$repo_root"
moon build cmd/console cmd/enterprise cmd/workbench cmd/installer-ui --target js --release

mkdir -p "$output_root/console" "$output_root/enterprise" "$output_root/workbench" "$output_root/installer" "$output_root/assets/contracts/youthpolicy/v1" "$output_root/assets/fonts/private"
cp cmd/console/index.html "$output_root/console/index.html"
cp _build/js/release/build/cmd/console/console.js "$output_root/console/console.js"
cp cmd/enterprise/index.html "$output_root/enterprise/index.html"
cp _build/js/release/build/cmd/enterprise/enterprise.js "$output_root/enterprise/enterprise.js"
cp cmd/workbench/index.html "$output_root/workbench/index.html"
cp _build/js/release/build/cmd/workbench/workbench.js "$output_root/workbench/workbench.js"
cp cmd/installer-ui/index.html "$output_root/installer/index.html"
cp _build/js/release/build/cmd/installer-ui/installer-ui.js "$output_root/installer/installer-ui.js"
cp assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json "$output_root/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json"
cp assets/fonts/contract-fonts.css "$output_root/assets/fonts/contract-fonts.css"
for font in FangSong_GB2312.ttf FZXiaoBiaoSong-B05S.ttf SimHei.ttf; do
  if [ -f "assets/fonts/private/$font" ]; then
    cp "assets/fonts/private/$font" "$output_root/assets/fonts/private/$font"
  fi
done

test -s "$output_root/console/index.html"
test -s "$output_root/console/console.js"
test -s "$output_root/enterprise/index.html"
test -s "$output_root/enterprise/enterprise.js"
test -s "$output_root/workbench/index.html"
test -s "$output_root/workbench/workbench.js"
test -s "$output_root/installer/index.html"
test -s "$output_root/installer/installer-ui.js"
test -s "$output_root/assets/contracts/youthpolicy/v1/moonleaf-preview-template.v1.json"
test -s "$output_root/assets/fonts/contract-fonts.css"

printf '%s\n' "browser bundles ready at $output_root"
