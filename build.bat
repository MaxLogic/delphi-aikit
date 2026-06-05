@echo off
setlocal

pushd "%~dp0"

call build-delphi.bat projects\DelphiAIKit.dproj -config Debug -platform Win64 -target Rebuild
if errorlevel 1 goto done

call build-delphi.bat tests\DelphiAIKit.Tests.dproj -config Debug -platform Win64 -target Rebuild

rem Preserve the exit code from whichever ran last (build or tests)
:done
set "EXITCODE=%ERRORLEVEL%"

popd
exit /b %EXITCODE%
