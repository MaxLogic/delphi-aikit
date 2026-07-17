@echo off
setlocal enableextensions

if "%~1"=="" (
  echo Usage: %~nx0 ^<path-to-unit.pas^> [project.dproj]
  exit /b 2
)

set "SCRIPT_DIR=%~dp0"

where py >nul 2>&1
if errorlevel 1 goto try_python
py -3 "%SCRIPT_DIR%analyze-unit.py" "%~1" "%~2"
exit /b %errorlevel%

:try_python
where python >nul 2>&1
if errorlevel 1 goto python_missing
python "%SCRIPT_DIR%analyze-unit.py" "%~1" "%~2"
exit /b %errorlevel%

:python_missing
echo ERROR: Python not found. Install Python 3, or run analyze-unit.sh from WSL.
exit /b 2
