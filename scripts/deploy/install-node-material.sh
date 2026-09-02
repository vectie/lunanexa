#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  printf '%s\n' 'this fixed-path helper must run as root through the reviewed sudoers rule' >&2
  exit 77
fi

if [ "${1:-}" = --check ]; then
  getent passwd lunanexa >/dev/null
  getent group lunanexa >/dev/null
  command -v systemctl >/dev/null
  printf '%s\n' '[ok] LunaNexa node-material helper is ready'
  exit 0
fi

if [ "${1:-}" = --start ]; then
  /usr/bin/systemctl daemon-reload
  if test -f /etc/systemd/system/lunanexa-controller-tunnel.service; then
    /usr/bin/systemctl enable --now lunanexa-controller-tunnel.service
  fi
  /usr/bin/systemctl enable --now lunanexa-node.service
  printf '%s\n' '[ok] LunaNexa node services started'
  exit 0
fi

if [ "${1:-}" = --cleanup-bootstrap ]; then
  rm -f -- /etc/lunanexa/bootstrap-token-id /etc/lunanexa/bootstrap-token
  printf '%s\n' '[ok] consumed bootstrap material removed'
  exit 0
fi

source_directory=${1:-}
case "$source_directory" in
  /tmp/lunanexa-install-*) ;;
  *) printf '%s\n' 'refusing unexpected staging directory' >&2; exit 64 ;;
esac

caller=${SUDO_USER:-}
case "$caller" in
  ''|*[!A-Za-z0-9._-]*) printf '%s\n' 'refusing missing or unsafe sudo caller' >&2; exit 77 ;;
esac
test "$(stat -c '%U' "$source_directory")" = "$caller"
test "$(stat -c '%a' "$source_directory")" = 700

for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token; do
  path=$source_directory/$name
  test -f "$path"
  test ! -L "$path"
  test "$(stat -c '%U' "$path")" = "$caller"
  case "$(stat -c '%a' "$path")" in
    400|440|600|640|644) ;;
    *) printf 'refusing unsafe source mode for %s\n' "$name" >&2; exit 77 ;;
  esac
done

host_systemd=0
if test -e "$source_directory/lunanexa-node" ||
  test -e "$source_directory/node.env" ||
  test -e "$source_directory/lunanexa-node.service"; then
  host_systemd=1
  for name in lunanexa-node node.env lunanexa-node.service admin-settings.json; do
    path=$source_directory/$name
    test -f "$path"
    test ! -L "$path"
    test "$(stat -c '%U' "$path")" = "$caller"
    case "$(stat -c '%a' "$path")" in
      400|440|500|550|600|640|644|700|750|755) ;;
      *) printf 'refusing unsafe source mode for %s\n' "$name" >&2; exit 77 ;;
    esac
  done
fi

tunnel_bundle=0
if test -e "$source_directory/lunanexa-controller-tunnel.service" ||
  test -e "$source_directory/tunnel-identity" ||
  test -e "$source_directory/tunnel-known-hosts"; then
  tunnel_bundle=1
  for name in lunanexa-controller-tunnel.service tunnel-identity tunnel-known-hosts; do
    path=$source_directory/$name
    test -f "$path"
    test ! -L "$path"
    test "$(stat -c '%U' "$path")" = "$caller"
    case "$(stat -c '%a' "$path")" in
      400|440|500|550|600|640|644|700|750|755) ;;
      *) printf 'refusing unsafe source mode for %s\n' "$name" >&2; exit 77 ;;
    esac
  done
fi

getent passwd lunanexa >/dev/null
getent group lunanexa >/dev/null
install -d -o root -g lunanexa -m 0750 /etc/lunanexa
install -d -o lunanexa -g lunanexa -m 0750 /var/lib/lunanexa
install -d -o lunanexa -g lunanexa -m 0750 /var/lib/lunanexa/models
install -o root -g lunanexa -m 0640 "$source_directory/node-token" /etc/lunanexa/node-token
install -o root -g lunanexa -m 0640 "$source_directory/assignment-verification-key" /etc/lunanexa/assignment-verification-key
install -o root -g lunanexa -m 0644 "$source_directory/cosign.pub" /etc/lunanexa/cosign.pub
install -o root -g lunanexa -m 0640 "$source_directory/inventory.json" /etc/lunanexa/inventory.json
install -o root -g lunanexa -m 0640 "$source_directory/bootstrap-token-id" /etc/lunanexa/bootstrap-token-id
install -o root -g lunanexa -m 0640 "$source_directory/bootstrap-token" /etc/lunanexa/bootstrap-token
if [ "$host_systemd" -eq 1 ]; then
  install -o root -g root -m 0755 "$source_directory/lunanexa-node" /usr/libexec/lunanexa-node
  install -o root -g lunanexa -m 0640 "$source_directory/node.env" /etc/lunanexa/node.env
  install -o root -g lunanexa -m 0640 "$source_directory/admin-settings.json" /etc/lunanexa/admin-settings.json
  install -o root -g root -m 0644 "$source_directory/lunanexa-node.service" /etc/systemd/system/lunanexa-node.service
fi
if [ "$tunnel_bundle" -eq 1 ]; then
  install -o lunanexa -g lunanexa -m 0600 "$source_directory/tunnel-identity" /etc/lunanexa/tunnel-identity
  install -o root -g lunanexa -m 0644 "$source_directory/tunnel-known-hosts" /etc/lunanexa/tunnel-known-hosts
  install -o root -g root -m 0644 "$source_directory/lunanexa-controller-tunnel.service" /etc/systemd/system/lunanexa-controller-tunnel.service
fi
rm -f -- "$source_directory/node-token" "$source_directory/assignment-verification-key" \
  "$source_directory/cosign.pub" "$source_directory/inventory.json" \
  "$source_directory/bootstrap-token-id" "$source_directory/bootstrap-token"
if [ "$host_systemd" -eq 1 ]; then
  rm -f -- "$source_directory/lunanexa-node" "$source_directory/node.env" \
    "$source_directory/admin-settings.json" "$source_directory/lunanexa-node.service"
fi
if [ "$tunnel_bundle" -eq 1 ]; then
  rm -f -- "$source_directory/lunanexa-controller-tunnel.service" \
    "$source_directory/tunnel-identity" "$source_directory/tunnel-known-hosts"
fi
rmdir "$source_directory"
printf '%s\n' '[ok] protected LunaNexa node material installed'
