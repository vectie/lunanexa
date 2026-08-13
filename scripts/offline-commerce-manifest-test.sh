#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
network="$root/deploy/network-policy.yaml"
controller="$root/deploy/controller.yaml"
pdf_job="$root/deploy/offline-pdf-pipeline-job.yaml"
ooxml_job="$root/deploy/offline-artifact-worker-job.yaml"

grep -q 'app: lunanexa-control' "$network"
grep -q 'name: lunanexa-offline-artifact-jobs' "$network"
grep -q 'values: \[offline-artifact-worker, offline-pdf-pipeline\]' "$network"
grep -q '^  ingress: \[\]$' "$network"
grep -q '^  egress: \[\]$' "$network"
grep -q 'lunanexa.io/component: offline-pdf-pipeline' "$pdf_job"
grep -q 'lunanexa.io/component: offline-artifact-worker' "$ooxml_job"
grep -q 'automountServiceAccountToken: false' "$pdf_job"
grep -q 'automountServiceAccountToken: false' "$ooxml_job"
grep -q 'claimName: lunanexa-offline-artifact-${JOB_ID}' "$pdf_job"
grep -q 'claimName: lunanexa-offline-artifact-${JOB_ID}' "$ooxml_job"

if grep -q 'LUNANEXA_OFFLINE_ARTIFACT_PIPELINE_CONFIGURED' "$controller"; then
  echo 'static offline pipeline readiness flag remains in controller manifest' >&2
  exit 1
fi

echo 'offline-commerce manifest invariants passed'
