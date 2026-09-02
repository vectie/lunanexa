#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"

expected_subjects='CandidateManifestAuthority
OciImageAuthority
SbomAuthority
BuildProvenanceAuthority
LicenseAuthority
KernelAuthority
PhysicalServingAuthority
BenchmarkAuthority
ControlContractAuthority
InvocationContractAuthority'
actual_subjects=$(sed -n \
  '/enum LunaFluxPromotionAuthoritySubject {/,/} derive/p' \
  runtimes/lunaflux_promotion_catalog.mbt | \
  sed -n '/Authority$/p' | sed 's/^[[:space:]]*//')
if [ "$actual_subjects" != "$expected_subjects" ]; then
  printf '%s\n' 'LunaFlux promotion authority subject set drifted' >&2
  exit 1
fi

authority_blocks=$(sed -n \
  -e '/struct LunaFluxEvidenceApproval {/,/^}/p' \
  -e '/struct LunaFluxPromotionAuthorityInput {/,/^}/p' \
  runtimes/lunaflux_promotion_catalog.mbt)
if printf '%s\n' "$authority_blocks" | rg -n 'ToJson|FromJson' ||
  rg -n 'signature[[:space:]]*:|verified[[:space:]]*:|decision[[:space:]]*:' \
    runtimes/lunaflux_promotion_catalog.mbt; then
  printf '%s\n' 'local LunaFlux approval authority became serializable or fabricated signature state' >&2
  exit 1
fi

moon info >/dev/null
if rg -n 'LunaFlux(EvidenceApproval|PromotionAuthorityInput)::(to_json|from_json)' \
  runtimes/pkg.generated.mbti; then
  printf '%s\n' 'trusted LunaFlux promotion authority leaked through JSON construction' >&2
  exit 1
fi

if rg -n \
  'LunaFlux(EvidenceApproval|PromotionAuthorityInput)|prepare_lunaflux_promotion_catalog' \
  runtimes/pkg.generated.mbti; then
  printf '%s\n' \
    'unverified LunaFlux catalog construction leaked through the public interface' >&2
  exit 1
fi

verifier_block=$(sed -n \
  '/struct LunaFluxPromotionVerifier {/,/^}/p' \
  runtimes/lunaflux_promotion_verifier_types.mbt)
if printf '%s\n' "$verifier_block" | \
  rg -n 'Debug|ToJson|FromJson|String[[:space:]]*$' ||
  ! printf '%s\n' "$verifier_block" | rg -Fq \
    'key_bytes : FixedArray[Byte]'; then
  printf '%s\n' \
    'opaque LunaFlux verifier became serializable or stopped owning wipeable key bytes' >&2
  exit 1
fi

if rg -n \
  'LunaFluxPromotionVerifier::(to_json|from_json)|key_bytes\(' \
  runtimes/pkg.generated.mbti; then
  printf '%s\n' 'LunaFlux verifier secret state leaked through the public interface' >&2
  exit 1
fi

signed_receipt_interface=$(sed -n \
  '/pub(all) struct LunaFluxSignedEvidenceApproval {/,/derive/p' \
  runtimes/pkg.generated.mbti)
if ! printf '%s\n' "$signed_receipt_interface" | \
  rg -n 'ToJson.*FromJson' >/dev/null; then
  printf '%s\n' 'inert signed LunaFlux receipts stopped being serializable' >&2
  exit 1
fi

if rg -n \
  'LunaFluxOpaqueAdapter::(from_json|new)|LunaFluxAdapterAuthority::from_json' \
  runtimes/pkg.generated.mbti; then
  printf '%s\n' \
    'opaque LunaFlux adapter or authority gained an untrusted constructor' >&2
  exit 1
fi

authority_producers=$(rg -n 'let authority : LunaFluxAdapterAuthority = \{' \
  runtimes --glob '*.mbt' --glob '!*test.mbt' --glob '!*wbtest.mbt' | wc -l | tr -d ' ')
if [ "$authority_producers" -ne 1 ]; then
  printf '%s\n' 'opaque LunaFlux adapter authority must have one production producer' >&2
  exit 1
fi

catalog_verifier_calls=$(rg -n 'prepare_lunaflux_promotion_catalog\(' \
  runtimes/lunaflux_promotion_verifier.mbt | wc -l | tr -d ' ')
if [ "$catalog_verifier_calls" -ne 1 ]; then
  printf '%s\n' \
    'authenticated LunaFlux verifier must be the sole production catalog caller' >&2
  exit 1
fi

adapter_producers=$(rg -n 'LunaFluxOpaqueAdapter = \{' \
  runtimes --glob '*.mbt' --glob '!*test.mbt' --glob '!*wbtest.mbt' | wc -l | tr -d ' ')
if [ "$adapter_producers" -ne 0 ]; then
  printf '%s\n' 'opaque LunaFlux adapter gained an alternate typed producer' >&2
  exit 1
fi

if [ "$(rg -n 'contract_digest: lunaflux_adapter_contract_digest\(self\)' \
  runtimes/lunaflux_adapter.mbt | wc -l | tr -d ' ')" -ne 1 ]; then
  printf '%s\n' 'opaque LunaFlux adapter must have one authority-owned producer' >&2
  exit 1
fi

for required in \
  'blockers.push(PromotionVerifierUnavailable)' \
  'routable: false, authority: None' \
  'AuthenticatedInheritedDrainV1' \
  'lunaflux_candidate_manifest_digest' \
  'lunaflux_control_contract_digest' \
  'lunaflux_physical_serving_approval_digest' \
  'lunaflux_benchmark_approval_digest' \
  'lunaflux_invocation_approval_digest' \
  'lunanexa.lunaflux.signed-promotion-receipt-hmac-sha256.v1' \
  'candidate_manifest_digest' \
  'self.key_bytes.fill(0)' \
  'receipts.length() != 10' \
  'maximum_length=128' \
  'value.length() == 64' \
  'left.length() != 32 || right.length() != 32' \
  'InvalidSignedPromotionReceiptCount' \
  'SignedPromotionReceiptAuthenticationFailed'; do
  if ! rg -Fq "$required" runtimes/lunaflux_promotion*.mbt; then
    printf 'LunaFlux promotion boundary lost required anchor: %s\n' \
      "$required" >&2
    exit 1
  fi
done

if rg -n 'HttpGracefulDrainV1|vectie/lunaflux' \
  runtimes/lunaflux_candidate.mbt \
  runtimes/lunaflux_promotion.mbt \
  runtimes/lunaflux_promotion_catalog.mbt \
  runtimes/lunaflux_adapter.mbt; then
  printf '%s\n' 'LunaFlux promotion boundary gained a false drain, source dependency, or credential' >&2
  exit 1
fi

for source_file in \
  runtimes/lunaflux_candidate.mbt \
  runtimes/lunaflux_promotion.mbt \
  runtimes/lunaflux_promotion_catalog.mbt \
  runtimes/lunaflux_promotion_verifier_types.mbt \
  runtimes/lunaflux_promotion_verifier.mbt \
  runtimes/lunaflux_adapter.mbt \
  runtimes/lunaflux_candidate_test.mbt \
  runtimes/lunaflux_promotion_test.mbt \
  runtimes/lunaflux_promotion_catalog_wbtest.mbt \
  runtimes/lunaflux_promotion_verifier_wbtest.mbt \
  runtimes/lunaflux_adapter_wbtest.mbt \
  runtimes/lunaflux_promotion_wbtest.mbt; do
  lines=$(wc -l < "$source_file" | tr -d ' ')
  if [ "$lines" -gt 500 ]; then
    printf '%s exceeds the 500-line LunaFlux promotion boundary\n' \
      "$source_file" >&2
    exit 1
  fi
done

printf '%s\n' 'LunaNexa LunaFlux promotion verifier/catalog boundary is valid.'
