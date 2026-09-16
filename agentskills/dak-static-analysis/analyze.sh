#!/usr/bin/env bash
# Forwards to: DelphiAIKit.exe analyze --project <project.dproj> [options], converting paths for Windows.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <project.dproj> [--workspace-root <selector>] [DelphiAIKit.exe analyze options]" >&2
  exit 2
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-dak.sh"
dak_find || exit $?
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  exec "$DAK" analyze --help
fi
dak_share_environment

arguments=(analyze --project "$(dak_windows_path "$1")")
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root|--out|--rsvars|--envoptions|--fi-settings|--pa-path|--pa-output)
      arguments+=("$1")
      if [[ $# -gt 1 ]]; then
        arguments+=("$(dak_windows_path "$2")")
        shift
      fi
      ;;
    *)
      arguments+=("$1")
      ;;
  esac
  shift
done
exec "$DAK" "${arguments[@]}"
