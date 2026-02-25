# Setup

Set stable environment variables so we can call our build entry points without hardcoded paths.

## Required Variables

- `DAK_EXE`: absolute path to `DelphiAIKit.exe`
- `DAK_REPO_ROOT`: absolute path to repository root

## WSL-Required Variable

- `DAK_BUILD_SH`: absolute path to `build-delphi.sh`

## WSL (bash, primary)

Add to `~/.bashrc`:

```bash
export DAK_REPO_ROOT="/mnt/f/projects/MaxLogic/DelphiAiKit"
export DAK_EXE="/mnt/f/projects/MaxLogic/DelphiAiKit/bin/DelphiAIKit.exe"
export DAK_BUILD_SH="/mnt/f/projects/MaxLogic/DelphiAiKit/build-delphi.sh"
```

Reload:

```bash
source ~/.bashrc
```

## Usage Examples

Canonical build via DAK:

```bash
cd "$DAK_REPO_ROOT"
"$DAK_EXE" build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --ai
```

WSL path-conversion wrapper:

```bash
cd "$DAK_REPO_ROOT"
"$DAK_BUILD_SH" projects/DelphiAIKit.dproj -config Debug -platform Win32 -ver 23 -ai
```

## Windows (PowerShell, secondary)

Set user-scoped variables:

```powershell
[Environment]::SetEnvironmentVariable("DAK_REPO_ROOT", "F:\projects\MaxLogic\DelphiAiKit", "User")
[Environment]::SetEnvironmentVariable("DAK_EXE", "F:\projects\MaxLogic\DelphiAiKit\bin\DelphiAIKit.exe", "User")
```

Use in session:

```powershell
Set-Location $env:DAK_REPO_ROOT
& $env:DAK_EXE build --project "projects/DelphiAIKit.dproj" --delphi 23.0 --platform Win32 --config Debug --ai
```

## Verify Setup

```bash
test -x "$DAK_EXE" && echo "DAK_EXE OK"
test -d "$DAK_REPO_ROOT" && echo "DAK_REPO_ROOT OK"
if grep -qi microsoft /proc/version 2>/dev/null; then test -x "$DAK_BUILD_SH" && echo "DAK_BUILD_SH OK"; fi
```
