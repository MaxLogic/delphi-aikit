@echo off
rem Sets DAK to DelphiAIKit.exe for the launchers beside this file. Order: DAK_EXE, then PATH,
rem then bin\DelphiAIKit.exe of the repository that contains this skill. The analyzed workspace and
rem the current directory are never searched, so an unrelated outer checkout cannot supply the tool.
set "DAK="
if not defined DAK_EXE goto :search_path
if not exist "%DAK_EXE%" goto :missing_env
set "DAK=%DAK_EXE%"
exit /b 0

:search_path
for /f "delims=" %%I in ('where DelphiAIKit.exe 2^>nul') do if not defined DAK set "DAK=%%I"
if defined DAK exit /b 0
if exist "%~dp0..\..\bin\DelphiAIKit.exe" for %%I in ("%~dp0..\..\bin\DelphiAIKit.exe") do set "DAK=%%~fI"
if defined DAK exit /b 0
>&2 echo ERROR: DelphiAIKit.exe not found. Set DAK_EXE to its full path or add it to PATH.
exit /b 2

:missing_env
>&2 echo ERROR: DAK_EXE points to missing file: %DAK_EXE%
exit /b 2
