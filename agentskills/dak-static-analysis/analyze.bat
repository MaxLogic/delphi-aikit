@echo off
setlocal enableextensions

if "%~1"=="" (
  echo Usage: %~nx0 ^<path-to-project.dproj^>
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"

rem Prefer the Python launcher if present.
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 "%SCRIPT_DIR%analyze.py" "%~1"
  exit /b %errorlevel%
)

where python >nul 2>&1
if %errorlevel%==0 (
  python "%SCRIPT_DIR%analyze.py" "%~1"
  exit /b %errorlevel%
)

echo ERROR: Python not found. Install Python 3, or run analyze.sh from WSL.
exit /b 2

