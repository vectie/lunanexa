#!/bin/sh
set -eu

source_directory=${1:-}
case "$source_directory" in
  /tmp/lunanexa-install-*) ;;
  *) printf '%s\n' 'refusing unexpected staging directory' >&2; exit 64 ;;
esac

for name in node-token assignment-verification-key cosign.pub inventory.json bootstrap-token-id bootstrap-token; do
  test -f "$source_directory/$name"
done

sudo -n install -d -o root -g root -m 0750 /etc/lunanexa
sudo -n install -d -o root -g root -m 0750 /var/lib/lunanexa
sudo -n install -o root -g root -m 0600 "$source_directory/node-token" /etc/lunanexa/node-token
sudo -n install -o root -g root -m 0600 "$source_directory/assignment-verification-key" /etc/lunanexa/assignment-verification-key
sudo -n install -o root -g root -m 0644 "$source_directory/cosign.pub" /etc/lunanexa/cosign.pub
sudo -n install -o root -g root -m 0600 "$source_directory/inventory.json" /etc/lunanexa/inventory.json
sudo -n install -o root -g root -m 0600 "$source_directory/bootstrap-token-id" /etc/lunanexa/bootstrap-token-id
sudo -n install -o root -g root -m 0600 "$source_directory/bootstrap-token" /etc/lunanexa/bootstrap-token
rm -f -- "$source_directory/node-token" "$source_directory/assignment-verification-key" \
  "$source_directory/cosign.pub" "$source_directory/inventory.json" \
  "$source_directory/bootstrap-token-id" "$source_directory/bootstrap-token" \
  "$source_directory/install-node-material.sh"
rmdir "$source_directory"
printf '%s\n' '[ok] protected LunaNexa node material installed'
