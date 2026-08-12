#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

sh scripts/phase-gate.sh
sh scripts/process-recovery-test.sh
sh scripts/lease-cleanup-simulation.sh
sh scripts/four-node-simulation.sh
sh scripts/evidence-export-test.sh
if [ "${LUNANEXA_RUN_POSTGRES_TEST:-0}" = "1" ]; then
  sh scripts/postgres-integration-test.sh
fi
moon check --target js --warn-list +73 --deny-warn
moon test ui --target js --warn-list +73 --deny-warn
moon test ui/workbench --target js --warn-list +73 --deny-warn
moon test ui/enterprise --target js --warn-list +73 --deny-warn
moon test installer --target js --warn-list +73 --deny-warn
moon test ui/installer --target js --warn-list +73 --deny-warn
moon test cmd/enterprise --target js --warn-list +73 --deny-warn
moon test cmd/workbench --target js --warn-list +73 --deny-warn
moon test workspace --target js --warn-list +73 --deny-warn
node --check extensions/vscode/extension.mjs
node --check extensions/vscode/client-core.mjs
node --test extensions/vscode/client-core.test.mjs
node -e 'const fs=require("fs"); JSON.parse(fs.readFileSync("extensions/vscode/package.json", "utf8"));'
sh -n scripts/start-deployment-ui.sh scripts/start-local-kubernetes-simulation.sh scripts/stop-local-kubernetes-simulation.sh scripts/deploy/preflight-host.sh scripts/deploy/install-node-material.sh scripts/deploy/remove-bootstrap-material.sh scripts/deploy/run-cluster-install.sh
sh scripts/build-browser-bundles.sh

printf '%s\n' 'repository release gate passed; real-cluster and human acceptance remain required'
