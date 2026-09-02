#!/bin/sh

set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
fixture_root=$(mktemp -d /tmp/lunanexa-coursebook-build-test.XXXXXX)
cleanup() {
  rm -rf "$fixture_root"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$fixture_root/bin"
docker_log=$fixture_root/docker.log
export LUNANEXA_COURSEBOOK_DOCKER_LOG=$docker_log
cat > "$fixture_root/bin/docker" <<'EOF'
#!/bin/sh
set -eu
context=
for argument in "$@"; do context=$argument; done
[ -d "$context" ]
printf '%s\n' "$@" > "$LUNANEXA_COURSEBOOK_DOCKER_LOG"
find "$context" -type f -print | sed "s#^$context/##" | LC_ALL=C sort \
  >> "$LUNANEXA_COURSEBOOK_DOCKER_LOG"
printf 'context_kib=%s\n' "$(du -sk "$context" | awk '{print $1}')" \
  >> "$LUNANEXA_COURSEBOOK_DOCKER_LOG"
EOF
chmod 755 "$fixture_root/bin/docker"

PATH="$fixture_root/bin:$PATH" sh \
  "$repository_root/scripts/deploy/build-coursebook-image.sh" \
  test-minimal --build-arg HTTPS_PROXY=http://proxy.invalid:8080 >/dev/null

rg -q '^lunanexa/coursebook-static:test-minimal$' "$docker_log"
rg -q '^docs-site/coursebook.json$' "$docker_log"
rg -q '^docs-site/coursebook.zh-CN.json$' "$docker_log"
rg -q '^docs-site/coursebook-evidence.json$' "$docker_log"
rg -q '^images/nginx.docs.conf$' "$docker_log"
if rg -q '(^|/)(moon\.mod|\.mooncakes|_artifacts|_build)(/|$)' "$docker_log"; then
  printf '%s\n' 'coursebook build context leaked repository build inputs' >&2
  exit 1
fi
context_kib=$(sed -n 's/^context_kib=//p' "$docker_log")
[ -n "$context_kib" ] && [ "$context_kib" -lt 65536 ]

if PATH="$fixture_root/bin:$PATH" sh \
  "$repository_root/scripts/deploy/build-coursebook-image.sh" \
  'unsafe/tag' >/dev/null 2>&1; then
  printf '%s\n' 'unsafe coursebook tag was accepted' >&2
  exit 1
fi

printf '%s\n' 'coursebook minimal image context tests passed'
