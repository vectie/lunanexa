#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

test -s assets/fonts/contract-fonts.css
grep -F '@font-face' assets/fonts/contract-fonts.css >/dev/null
grep -F 'LunaNexa FangSong GB2312' assets/fonts/contract-fonts.css >/dev/null
grep -F 'LunaNexa FZ XiaoBiaoSong' assets/fonts/contract-fonts.css >/dev/null
grep -F 'LunaNexa SimHei' assets/fonts/contract-fonts.css >/dev/null
grep -F '../assets/fonts/contract-fonts.css' cmd/console/index.html >/dev/null
grep -F 'assets/fonts/contract-fonts.css' scripts/build-browser-bundles.sh >/dev/null
grep -F '/assets/fonts/private/*' .gitignore >/dev/null
moon test cmd/font-inspect --target native --deny-warn --warn-list +73

if git ls-files assets/fonts/private | grep -Ev '/README\.md$' >/dev/null; then
  printf '%s\n' 'licensed private font binary is tracked by Git' >&2
  exit 1
fi

printf '%s\n' 'contract font bundle wiring is present and private font binaries are untracked'
