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

win_root="$(wslpath -w -a "${repo_root}")"

# WSL -> Windows interop can mangle quotes inside cmd.exe `/C` strings.
# Our repo path is expected to be on a drive path without spaces (e.g. F:\projects\...).
if [[ "${win_root}" == *" "* ]]; then
  echo "[ERROR] Repo path contains spaces; cmd.exe invocation would require quoting which is unreliable under WSL interop." >&2
  echo "        Windows path: ${win_root}" >&2
  echo "        Run tests\\run.bat from a Windows shell, or move the repo to a path without spaces." >&2
  exit 2
fi

# Run the Windows batch test from the repo root so relative paths match.
"${cmd_exe}" /C "cd /d ${win_root} && tests\\run.bat"
rc=$?
if [[ $rc -eq 126 || $rc -eq 127 ]]; then
  echo "[ERROR] Failed to execute Windows cmd.exe from WSL (exit $rc)." >&2
  echo "        Run tests\\run.bat from a Windows shell instead." >&2
fi
exit $rc
