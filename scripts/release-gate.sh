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

printf '%s\n' 'repository release gate passed; real-cluster and human acceptance remain required'
