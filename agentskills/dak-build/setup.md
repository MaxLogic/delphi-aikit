# Setup

Set stable environment variables so we can call DelphiAIKit without hardcoded paths.

## Required Variable

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`

## Optional WSL Convenience Variable

- `DAK_BUILD_SH`: absolute path to `build-delphi.sh`

## WSL (bash, primary)

Add to `~/.bashrc`:

```bash
export DAK_EXE="/mnt/f/projects/MaxLogic/DelphiAiKit/bin/DelphiAIKit.exe"
export DAK_BUILD_SH="/mnt/f/projects/MaxLogic/DelphiAiKit/build-delphi.sh"
```

Reload:

```bash
source ~/.bashrc
```

## Usage Examples (WSL)

Canonical build via DAK:

```bash
cd /path/to/target-repo
PROJECT_LINUX="_Source/ActiveAppView.dproj"
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --ai
```

Build plus DFM validation:

```bash
cd /path/to/target-repo
PROJECT_LINUX="_Source/ActiveAppView.dproj"
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --dfmcheck --all --ai
```

Direct Linux absolute paths are supported only in `/mnt/<drive>/...` form; other `/...` inputs are rejected, so `wslpath -w` remains our canonical safe conversion.

Optional compatibility conversion (older DelphiAIKit builds):

```bash
PROJECT_WIN="$(wslpath -w -a "$PROJECT_LINUX")"
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_EXE" build --project "$PROJECT_WIN" --delphi 23.0 --platform "$PLATFORM" --config Debug --ai
```

Locked-output-safe rebuild:

```bash
cd /path/to/target-repo
PROJECT_LINUX="_Source/ActiveAppView.dproj"
PLATFORM="${DAK_PLATFORM:-Win32}"
TEST_OUT_WIN="$(wslpath -w -a _build_verify/test-out)"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --target Rebuild --test-output-dir "$TEST_OUT_WIN" --ai
```

Profiler/compiler overlay build:

```bash
cd /path/to/target-repo
PROJECT_LINUX="src/maxtdb.dproj"
PLATFORM="${DAK_PLATFORM:-Win64}"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform "$PLATFORM" --config Debug --target Rebuild \
  --define maxProfiling --unit-search-path "/mnt/f/projects/MaxLogic/profiling/src/runtime" --ai
```

Use these typed overlays for MaxProfiler-style temporary Delphi compiler context instead of raw MSBuild `/p:DCC_Define=...` or `/p:DCC_UnitSearchPath=...` calls.

WSL wrapper (optional):

```bash
cd /path/to/target-repo
PLATFORM="${DAK_PLATFORM:-Win32}"
"$DAK_BUILD_SH" _Source/ActiveAppView.dproj -config Debug -platform "$PLATFORM" -ver 23 -ai
```

## Windows (PowerShell, secondary)

Set user-scoped variable:

```powershell
[Environment]::SetEnvironmentVariable("DAK_EXE", "F:\projects\MaxLogic\DelphiAiKit\bin\DelphiAIKit.exe", "User")
```

Use in session:

```powershell
Set-Location F:\projects\SomeRepo
$Project = "F:\projects\SomeRepo\_Source\App.dproj"
$Platform = if ($env:DAK_PLATFORM) { $env:DAK_PLATFORM } else { "Win32" }
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform $Platform --config Debug --ai
```

For DelphiAiKit itself, set `DAK_PLATFORM=Win64` or pass `--platform Win64` explicitly.

## Verify Setup

```bash
test -x "$DAK_EXE" && echo "DAK_EXE OK"
if grep -qi microsoft /proc/version 2>/dev/null; then
  if [ -n "${DAK_BUILD_SH:-}" ]; then
    test -x "$DAK_BUILD_SH" && echo "DAK_BUILD_SH OK"
  fi
fi
```
