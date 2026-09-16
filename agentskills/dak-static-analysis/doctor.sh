#!/usr/bin/env bash
# Forwards to: DelphiAIKit.exe analyze-doctor [--project <project.dproj> | --unit <unit.pas>] [options],
# converting paths for Windows. A first argument that is not an option is the subject.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/find-dak.sh"
dak_find || exit $?
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  exec "$DAK" analyze-doctor --help
fi
dak_share_environment

arguments=(analyze-doctor)
if [[ $# -gt 0 && "$1" != -* ]]; then
  if [[ "$1" == *.pas ]]; then
    arguments+=(--unit "$(dak_windows_path "$1")")
  else
    arguments+=(--project "$(dak_windows_path "$1")")
  fi
  shift
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace-root|--project|--unit|--pa-path)
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
