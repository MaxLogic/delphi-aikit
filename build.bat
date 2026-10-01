@echo off
setlocal

pushd "%~dp0"

if not defined DAK_BUILD_HOST set "DAK_BUILD_HOST=%~dp0bin\DelphiAIKit.exe"
if not exist "%DAK_BUILD_HOST%" (
  echo [ERROR] Set DAK_BUILD_HOST to a known-good Win64 DelphiAIKit.exe.
  popd
  exit /b 2
)
if not defined DAK_DELPHI set "DAK_DELPHI=23.0"

"%DAK_BUILD_HOST%" build --project projects\DelphiAIKit.dproj --delphi %DAK_DELPHI% --config Debug --platform Win64 --target Build --ai
if errorlevel 1 goto done

"%DAK_BUILD_HOST%" build --project tests\DelphiAIKit.Tests.dproj --delphi %DAK_DELPHI% --config Debug --platform Win64 --target Build --ai

rem Preserve the exit code from whichever ran last (build or tests)
:done
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
