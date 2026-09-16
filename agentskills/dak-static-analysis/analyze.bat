@echo off
rem Forwards to: DelphiAIKit.exe analyze --project <project.dproj> [options]
setlocal enableextensions
if "%~1"=="" goto :usage
call "%~dp0find-dak.cmd"
if errorlevel 1 exit /b 2
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h" goto :help
if "%~1"=="/?" goto :help
"%DAK%" analyze --project %*
exit /b %errorlevel%

:help
"%DAK%" analyze --help
exit /b %errorlevel%

:usage
>&2 echo Usage: %~nx0 ^<project.dproj^> [--workspace-root ^<selector^>] [DelphiAIKit.exe analyze options]
exit /b 2
