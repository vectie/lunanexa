#!/bin/sh
set -eu

program_name=${0##*/}
program_directory=${0%/*}
fake_state=${program_directory}/.fake-state
mkdir -p "$fake_state"

case "$program_name" in
  id)
    printf '%s\n' '0'
    ;;
  getent)
    if [ -f "$fake_state/lookup-failure" ]; then exit 3; fi
    if [ -f "$fake_state/account" ]; then
      username=$(sed -n '1p' "$fake_state/account")
      printf '%s:x:2001:2001::%s:/bin/bash\n' "$username" "$(sed -n '1p' "$fake_state/home")"
    else
      exit 2
    fi
    ;;
  useradd)
    home_path=
    username=
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --home-dir)
          home_path=$2
          shift 2
          ;;
        --*)
          if [ "$1" = '--shell' ]; then shift 2; else shift; fi
          ;;
        *)
          username=$1
          shift
          ;;
      esac
    done
    test -n "$home_path"
    test -n "$username"
    mkdir -p "$home_path"
    printf '%s\n' "$username" > "$fake_state/account"
    printf '%s\n' "$home_path" > "$fake_state/home"
    ;;
  usermod|loginctl|pkill|chown)
    ;;
  pgrep)
    if [ -f "$fake_state/process-inventory-failure" ]; then exit 2; fi
    if [ -f "$fake_state/stuck-process" ]; then exit 0; else exit 1; fi
    ;;
  runuser)
    test "$1" = '--user'
    shift 2
    test "$1" = '--'
    shift
    shift
    case "${1:-}" in
      ps)
        test -f "$fake_state/containers" && sed -n '/./p' "$fake_state/containers"
        ;;
      stop)
        ;;
      rm)
        if [ ! -f "$fake_state/stuck-runtime" ]; then
          : > "$fake_state/containers"
        fi
        ;;
      volume)
        case "${2:-}" in
          ls)
            test -f "$fake_state/volumes" && sed -n '/./p' "$fake_state/volumes"
            ;;
          rm)
            if [ ! -f "$fake_state/stuck-runtime" ]; then
              : > "$fake_state/volumes"
            fi
            ;;
          *) exit 2 ;;
        esac
        ;;
      *) exit 2 ;;
    esac
    ;;
  userdel)
    if [ -f "$fake_state/home" ]; then
      home_path=$(sed -n '1p' "$fake_state/home")
      rm -rf -- "$home_path"
    fi
    rm -f -- "$fake_state/account" "$fake_state/home"
    ;;
  podman)
    ;;
  *)
    exit 2
    ;;
esac
