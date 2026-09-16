#!/usr/bin/env bash
# Forwards to: DelphiAIKit.exe analyze-unit --unit <unit.pas> [--project-context <project.dproj>] [options],
# converting paths for Windows. A second argument that is not an option names the project context.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <unit.pas> [project.dproj] [--workspace-root <selector>] [DelphiAIKit.exe analyze-unit options]" >&2
  exit 2
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-dak.sh"
dak_find || exit $?
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  exec "$DAK" analyze-unit --help
fi
dak_share_environment

arguments=(analyze-unit --unit "$(dak_windows_path "$1")")
shift
if [[ $# -gt 0 && "$1" != -* ]]; then
  arguments+=(--project-context "$(dak_windows_path "$1")")
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root|--out|--project-context|--pa-path|--pa-output)
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
