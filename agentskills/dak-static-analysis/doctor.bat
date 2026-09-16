@echo off
rem Forwards to: DelphiAIKit.exe analyze-doctor [--project <project.dproj> | --unit <unit.pas>] [options]
rem A first argument that is not an option is the subject; a .pas file is a unit, anything else a project.
setlocal enableextensions
call "%~dp0find-dak.cmd"
if errorlevel 1 exit /b 2
if "%~1"=="" goto :no_subject
if /i "%~1"=="--help" goto :help
if /i "%~1"=="-h" goto :help
if "%~1"=="/?" goto :help
set "FIRST=%~1"
if "%FIRST:~0,1%"=="-" goto :no_subject

set "SUBJECT_SWITCH=--project"
if /i "%~x1"==".pas" set "SUBJECT_SWITCH=--unit"
"%DAK%" analyze-doctor %SUBJECT_SWITCH% %*
exit /b %errorlevel%

:no_subject
"%DAK%" analyze-doctor %*
exit /b %errorlevel%

:help
"%DAK%" analyze-doctor --help
exit /b %errorlevel%
