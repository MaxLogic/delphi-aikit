@echo off
setlocal

pushd "%~dp0"

call tests\run.bat

set "EXITCODE=%ERRORLEVEL%"
popd
exit /b %EXITCODE%
