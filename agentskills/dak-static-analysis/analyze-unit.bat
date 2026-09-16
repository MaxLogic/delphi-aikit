@echo off
rem Forwards to: DelphiAIKit.exe analyze-unit --unit <unit.pas> [--project-context <project.dproj>] [options]
rem A second argument that is not an option names the project context.
setlocal enableextensions
if "%~1"=="" goto :usage
call "%~dp0find-dak.cmd"
if errorlevel 1 exit /b 2
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h" goto :help
if "%~1"=="/?" goto :help

set "UNIT_ARG=%1"
shift
set "CONTEXT_ARG="
if "%~1"=="" goto :collect
set "NEXT=%~1"
if "%NEXT:~0,1%"=="-" goto :collect
set "CONTEXT_ARG=--project-context %1"
shift

:collect
set "REST="
:next_argument
if "%~1"=="" goto :run
set REST=%REST% %1
shift
goto :next_argument

:run
"%DAK%" analyze-unit --unit %UNIT_ARG% %CONTEXT_ARG%%REST%
exit /b %errorlevel%

:help
"%DAK%" analyze-unit --help
exit /b %errorlevel%

:usage
>&2 echo Usage: %~nx0 ^<unit.pas^> [project.dproj] [--workspace-root ^<selector^>] [DelphiAIKit.exe analyze-unit options]
exit /b 2
