#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

sh scripts/phase-gate.sh
sh scripts/process-recovery-test.sh
sh scripts/four-node-simulation.sh
sh scripts/evidence-export-test.sh
moon check --target js --deny-warn
moon test ui --target js --deny-warn
moon test ui/workbench --target js --deny-warn
moon test cmd/workbench --target js --deny-warn
moon test workspace --target js --deny-warn
node --check extensions/vscode/extension.mjs
node --check extensions/vscode/client-core.mjs
node --test extensions/vscode/client-core.test.mjs
node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync("extensions/vscode/package.json", "utf8"));'
sh scripts/build-browser-bundles.sh

printf '%s\n' 'repository release gate passed; real-cluster and human acceptance remain required'
