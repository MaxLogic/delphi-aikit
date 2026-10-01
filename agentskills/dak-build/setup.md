# Setup

Set stable environment variables so we can call DelphiAIKit without hardcoded paths.

## Required Variable

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`

There is no build wrapper script. `build-delphi.bat` and `build-delphi.sh` were
retired; call `"$DAK_EXE" build` (WSL) or `& $env:DAK_EXE build` (Windows) directly.

## WSL (bash, primary)

Add to `~/.bashrc`:

```bash
export DAK_EXE="/mnt/f/projects/MaxLogic/DelphiAiKit/bin/DelphiAIKit.exe"
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

Linux-style absolute paths are supported only in `/mnt/<drive>/...` form and relative paths resolve against the current directory; other `/...` inputs (for example `/home/...`) are rejected with exit code 6. Paths DAK does not accept can be converted with `wslpath -w -a` and passed as Windows paths.

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
```
