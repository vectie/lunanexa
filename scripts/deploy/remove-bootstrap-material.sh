#!/bin/sh
set -eu

sudo -n rm -f -- /etc/lunanexa/bootstrap-token-id /etc/lunanexa/bootstrap-token
printf '%s\n' '[ok] consumed bootstrap material removed'
