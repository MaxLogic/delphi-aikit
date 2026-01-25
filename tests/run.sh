#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"

if ! command -v wslpath >/dev/null 2>&1; then
  echo "[ERROR] wslpath not found. This runner is intended for WSL on Windows." >&2
  exit 2
fi

cmd_exe="${CMD_EXE:-/mnt/c/Windows/System32/cmd.exe}"
if [[ ! -x "${cmd_exe}" ]]; then
  echo "[ERROR] Windows cmd.exe not found/executable at: ${cmd_exe}" >&2
  echo "        Set CMD_EXE to override (WSL path), or run tests/run.bat from Windows." >&2
  exit 2
fi

win_root="$(wslpath -w "${repo_root}")"

# Run the Windows batch test from the repo root so relative paths match.
exec "${cmd_exe}" /C "cd /d \"${win_root}\" && tests\\run.bat"

