@echo off
setlocal

pushd "%~dp0"

call build.bat
if errorlevel 1 goto done
call tests\run.bat %*

:done
set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%
