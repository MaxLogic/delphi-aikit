#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BAT_PATH_WINDOWS="$(wslpath -w -a "$ROOT_DIR/build-and-run-tests.bat")"

if [[ "$BAT_PATH_WINDOWS" == *" "* ]]; then
  /mnt/c/Windows/System32/cmd.exe /C "for %I in (\"$BAT_PATH_WINDOWS\") do @set \"BAT=%~sI\" & call \"%BAT%\" & exit /b %ERRORLEVEL%"
else
  /mnt/c/Windows/System32/cmd.exe /C "$BAT_PATH_WINDOWS & exit /b %ERRORLEVEL%"
fi
exit $?
