@echo off
setlocal EnableExtensions
for %%I in ("%~dp0..") do set "ROOT=%%~fI"
set "EXE=%ROOT%\bin\Debug\DelphiAIKit.exe"
if defined DAK_TEST_RESOLVER_EXE set "EXE=%DAK_TEST_RESOLVER_EXE%"
if not exist "%EXE%" (
  echo [ERROR] Build the Win64 Debug candidate with build.bat before running tests:
  echo         "%EXE%"
  exit /b 2
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-dunitx.ps1" %*
exit /b %ERRORLEVEL%
