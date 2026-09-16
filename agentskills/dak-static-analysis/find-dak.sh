#!/usr/bin/env bash
# Sourced by the launchers beside this file. Sets DAK to DelphiAIKit.exe as a Linux path and provides
# dak_windows_path, which converts one path for the Windows process. Order: DAK_EXE, then Windows PATH,
# then bin/DelphiAIKit.exe of the repository that contains this skill. The analyzed workspace and the
# current directory are never searched.

dak_windows_path() {
  local value="$1"
  if [[ "$value" == /* ]]; then
    wslpath -w "$value"
  elif [[ "$value" == *[/\\]* || "$value" == *.dproj || "$value" == *.dpr || "$value" == *.pas || "$value" == . || "$value" == .. ]]; then
    if [[ -e "$value" ]]; then
      wslpath -w "$(realpath "$value")"
    else
      printf '%s' "$value"
    fi
  else
    printf '%s' "$value"
  fi
}

dak_find() {
  local skill_dir candidate
  skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  DAK=""
  if [[ -n "${DAK_EXE:-}" ]]; then
    candidate="$DAK_EXE"
    if [[ "$candidate" =~ ^[A-Za-z]:[\\/] ]]; then
      candidate="$(wslpath -u "$candidate")"
    fi
    if [[ ! -f "$candidate" ]]; then
      echo "ERROR: DAK_EXE points to missing file: $DAK_EXE" >&2
      return 2
    fi
    DAK="$candidate"
    return 0
  fi
  candidate="$(cmd.exe /C where DelphiAIKit.exe 2>/dev/null | tr -d '\r' | head -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    DAK="$(wslpath -u "$candidate")"
    return 0
  fi
  candidate="$skill_dir/../../bin/DelphiAIKit.exe"
  if [[ -f "$candidate" ]]; then
    DAK="$(realpath "$candidate")"
    return 0
  fi
  echo "ERROR: DelphiAIKit.exe not found. Set DAK_EXE to its full path or add it to Windows PATH." >&2
  return 2
}

# DAK reads its analysis settings from the environment. A Windows process sees WSL variables only
# through WSLENV, and path values must be Windows paths.
dak_share_environment() {
  local name value shared="${WSLENV:-}"
  local path_variables=" DAK_OUT DAK_RSVARS DAK_ENVOPTIONS DAK_BASELINE FIXINSIGHT_SETTINGS FI_SETTINGS PA_PATH "
  while IFS='=' read -r name _; do
    case "$name" in
      DAK_EXE) continue ;;
      DAK_*|PA_*|FI_*|FIXINSIGHT_*) ;;
      *) continue ;;
    esac
    value="${!name}"
    if [[ "$path_variables" == *" $name "* && "$value" == /* ]]; then
      export "$name=$(wslpath -w "$value")"
    fi
    shared="${shared:+$shared:}$name"
  done < <(env)
  export WSLENV="$shared"
}
