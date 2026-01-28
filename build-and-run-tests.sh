#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build-and-run-tests.bat")"

if [[ "$BAT_PATH_WINDOWS" == *" "* ]]; then
  /mnt/c/Windows/System32/cmd.exe /C "\"$BAT_PATH_WINDOWS\""
else
  /mnt/c/Windows/System32/cmd.exe /C $BAT_PATH_WINDOWS
fi
exit $?
