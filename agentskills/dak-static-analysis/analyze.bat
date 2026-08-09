@echo off
setlocal enableextensions

if "%~1"=="" (
  echo Usage: %~nx0 ^<path-to-project.dproj^>
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"

rem Prefer the Python launcher if present.
where py >nul 2>&1
if errorlevel 1 goto try_python
py -3 "%SCRIPT_DIR%analyze.py" %*
exit /b %errorlevel%

:try_python
where python >nul 2>&1
if errorlevel 1 goto python_missing
python "%SCRIPT_DIR%analyze.py" %*
exit /b %errorlevel%

:python_missing
echo ERROR: Python not found. Install Python 3, or run analyze.sh from WSL.
exit /b 2
