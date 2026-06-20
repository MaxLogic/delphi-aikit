@echo off
setlocal enableextensions

set "SCRIPT_DIR=%~dp0"

rem Prefer the Python launcher if present.
where py >nul 2>&1
if %errorlevel%==0 (
  py -3 "%SCRIPT_DIR%doctor.py" %*
  exit /b %errorlevel%
)

where python >nul 2>&1
if %errorlevel%==0 (
  python "%SCRIPT_DIR%doctor.py" %*
  exit /b %errorlevel%
)

echo ERROR: Python not found. Install Python 3, or run doctor.sh from WSL.
exit /b 2

