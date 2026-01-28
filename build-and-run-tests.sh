#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build-and-run-tests.bat")"

if [[ "$BAT_PATH_WINDOWS" == *" "* ]]; then
  echo "[ERROR] Windows path contains spaces; run build-and-run-tests.bat from a Windows shell." >&2
  exit 2
fi

/mnt/c/Windows/System32/cmd.exe /C "$BAT_PATH_WINDOWS & exit /b %ERRORLEVEL%"
exit $?
