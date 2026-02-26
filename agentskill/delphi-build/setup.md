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
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --ai
```

Direct Linux absolute paths are supported only in `/mnt/<drive>/...` form; other `/...` inputs are rejected, so `wslpath -w` remains our canonical safe conversion.

Optional compatibility conversion (older DelphiAIKit builds):

```bash
PROJECT_WIN="$(wslpath -w -a "$PROJECT_LINUX")"
"$DAK_EXE" build --project "$PROJECT_WIN" --delphi 23.0 --platform Win32 --config Debug --ai
```

Locked-output-safe rebuild:

```bash
cd /path/to/target-repo
PROJECT_LINUX="_Source/ActiveAppView.dproj"
TEST_OUT_WIN="$(wslpath -w -a _build_verify/test-out)"
"$DAK_EXE" build --project "$PROJECT_LINUX" --delphi 23.0 --platform Win32 --config Debug --target Rebuild --test-output-dir "$TEST_OUT_WIN" --ai
```

WSL wrapper (optional):

```bash
cd /path/to/target-repo
"$DAK_BUILD_SH" _Source/ActiveAppView.dproj -config Debug -platform Win32 -ver 23 -ai
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
& $env:DAK_EXE build --project $Project --delphi 23.0 --platform Win32 --config Debug --ai
```

## Verify Setup

```bash
test -x "$DAK_EXE" && echo "DAK_EXE OK"
if grep -qi microsoft /proc/version 2>/dev/null; then
  if [ -n "${DAK_BUILD_SH:-}" ]; then
    test -x "$DAK_BUILD_SH" && echo "DAK_BUILD_SH OK"
  fi
fi
```
