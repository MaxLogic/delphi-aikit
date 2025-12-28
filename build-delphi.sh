#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build-delphi.bat")"

args=()

if [ "$#" -gt 0 ]; then
  first="$1"
  if [[ "$first" == *.dproj || "$first" == *.dpr || "$first" == *.groupproj ]]; then
    if [[ "$first" == [A-Za-z]:* ]]; then
      proj_win="$first"
    else
      if [[ "$first" == /* ]]; then
        proj_path="$first"
      else
        proj_path="$ROOT_DIR/$first"
      fi
      proj_win="$(wslpath -w -a "$proj_path")"
    fi
    args+=("$proj_win")
    shift
  fi
fi

while [ "$#" -gt 0 ]; do
  args+=("$1")
  shift
done

/mnt/c/Windows/System32/cmd.exe /C "$BAT_PATH_WINDOWS" "${args[@]}"
exit $?
