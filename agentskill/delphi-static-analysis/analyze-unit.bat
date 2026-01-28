@echo off
setlocal enableextensions

if "%~1"=="" (
  echo Usage: %~nx0 ^<path-to-unit.pas^>
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"

where py >nul 2>&1
if %errorlevel%==0 (
  py -3 "%SCRIPT_DIR%analyze-unit.py" "%~1"
  exit /b %errorlevel%
)

where python >nul 2>&1
if %errorlevel%==0 (
  python "%SCRIPT_DIR%analyze-unit.py" "%~1"
  exit /b %errorlevel%
)

echo ERROR: Python not found. Install Python 3, or run analyze-unit.sh from WSL.
exit /b 2

