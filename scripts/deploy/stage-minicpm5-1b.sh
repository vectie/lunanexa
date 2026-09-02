#!/bin/sh
set -eu
umask 077

mode=
destination=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) mode=plan; shift ;;
    --download) mode=download; shift ;;
    --destination) destination=${2:-}; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 64 ;;
  esac
done

test -n "$mode" || { printf '%s\n' 'choose --plan or --download' >&2; exit 64; }
# ModelScope's file transport currently accepts the branch name but returns
# HTTP 500 for the repository commit in the resolve path. Pin the observed Git
# tree revision as provenance and admit bytes only through the exact manifest
# below. A branch update therefore fails closed instead of changing staging.
revision=fc2e73f63bbf2cce5739929c2bebbb046fbfae8d
base_url=https://www.modelscope.cn/models/OpenBMB/MiniCPM5-1B/resolve/master
manifest='.gitattributes|1591|4a924f9f3caa6ec3c6076c1052483e7e3275490e92c0bf6a8defd23fbf4281e1
chat_template.jinja|9062|7451a05cf1e28a79d97d7c0bc951028c0b1915119bf9046acd06a0e3d931f47c
config.json|726|6a6509b646cb3169616c5ffc3196e7ccaf9d4d6bc17b266581d241a31c217714
generation_config.json|213|92afd6424501426eddcf7e1542f013d19e5987544977b4ee7bd26359bd5fd2ab
model.safetensors.index.json|18004|162add042e75abc3d571c4a8679523fa4f1ffc55d1fea25fc6658a19d6e957ee
README-cn.md|22108|037ef3b6c2288689aa06795eae97b85be02ab844efecb15568ad17542786796f
README.md|23472|b032e36400dc26ba8d78aa5ad63e4cf8bd17f70bf8551e500335185d8e7d061a
special_tokens_map.json|551|82d96d7a9e6ced037f12394b7ea6a5b02e6ca87e0d11edaa8d60d9be857ce7db
tokenizer_config.json|94416|094efb3cf1ff412284cc5945fc99dff58673a912760d04483a04aa1c716f66fd
tokenizer.json|9894271|3e065a558a034185fe299917b398685c1facd0169a9eea1e629eb30c171fed81
model-00000-of-00001.safetensors|2161290912|7ab8fd86563125929be78aeec8cb3969c7ed2ead3be1ab9d3ec0a9fa69c8660d'

if [ "$mode" = plan ]; then
  printf 'source=OpenBMB/MiniCPM5-1B\nrevision=%s\napproval_state=StagingOnly\n' "$revision"
  printf '%s\n' "$manifest"
  printf '%s\n' 'transport_note=The branch URL is mutable; every accepted byte is pinned by the manifest size and SHA-256.'
  exit 0
fi

case "$destination" in
  /*) ;;
  *) printf '%s\n' 'destination must be an absolute path' >&2; exit 64 ;;
esac
case "/$destination/" in
  */../*) printf '%s\n' 'destination must not contain ..' >&2; exit 64 ;;
esac
test ! -L "$destination" || { printf '%s\n' 'destination must not be a symlink' >&2; exit 64; }
for command_name in curl awk wc tr basename mkdir chmod mv; do command -v "$command_name" >/dev/null; done
if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
  printf '%s\n' 'sha256sum or shasum is required' >&2
  exit 1
fi
if [ -e "$destination" ]; then
  test -d "$destination" || { printf '%s\n' 'destination must be a directory' >&2; exit 64; }
else
  mkdir -p "$destination"
fi
test ! -L "$destination/.partial" || { printf '%s\n' 'partial directory must not be a symlink' >&2; exit 64; }
mkdir -p "$destination/.partial"
test -d "$destination/.partial"
chmod 0700 "$destination/.partial"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

verify_file() {
  verify_path=$1 verify_size=$2 verify_digest=$3
  actual_size=$(wc -c < "$verify_path" | tr -d ' ')
  actual_digest=$(sha256_file "$verify_path")
  if [ "$actual_size" != "$verify_size" ] || [ "$actual_digest" != "$verify_digest" ]; then
    printf '[blocked] verification failed for %s; expected size=%s sha256=%s\n' \
      "$(basename "$verify_path")" "$verify_size" "$verify_digest" >&2
    return 1
  fi
}

download_file() {
  file_name=$1 expected_size=$2 expected_digest=$3
  final_path=$destination/$file_name
  partial_path=$destination/.partial/$file_name.partial
  test ! -L "$final_path" || { printf '[blocked] %s must not be a symlink\n' "$file_name" >&2; return 1; }
  test ! -L "$partial_path" || { printf '[blocked] partial %s must not be a symlink\n' "$file_name" >&2; return 1; }
  if [ -f "$final_path" ]; then
    verify_file "$final_path" "$expected_size" "$expected_digest"
    printf '[verified] %s already present\n' "$file_name"
    return
  fi
  test ! -e "$final_path" || { printf '[blocked] %s is not a regular file\n' "$file_name" >&2; return 1; }
  printf '[download] %s\n' "$file_name"
  curl --fail --location --retry 5 --retry-connrefused --continue-at - \
    --proto '=https' --tlsv1.2 --output "$partial_path" "$base_url/$file_name"
  verify_file "$partial_path" "$expected_size" "$expected_digest"
  mv "$partial_path" "$final_path"
  printf '[verified] %s\n' "$file_name"
}

old_ifs=$IFS
IFS='
'
for record in $manifest; do
  file_name=${record%%|*}
  remainder=${record#*|}
  expected_size=${remainder%%|*}
  expected_digest=${remainder#*|}
  download_file "$file_name" "$expected_size" "$expected_digest"
done
IFS=$old_ifs

evidence_new=$destination/.partial/staging-evidence.json.new
printf '%s\n' \
  '{' \
  '  "contract_version": "lunanexa.model-staging-evidence.v1",' \
  '  "source": "modelscope:OpenBMB/MiniCPM5-1B",' \
  "  \"revision\": \"$revision\"," \
  '  "approval_state": "StagingOnly",' \
  '  "verified_files": 11,' \
  '  "note": "Download verification is not license, runtime, evaluation or publication approval."' \
  '}' > "$evidence_new"
mv "$evidence_new" "$destination/staging-evidence.json"
printf '[complete] verified staging bytes at %s; approval_state=StagingOnly\n' "$destination"
