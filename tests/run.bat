@echo off
setlocal EnableDelayedExpansion

set "ROOT=%~dp0.."
set "FIXTURES=%~dp0fixtures"
set "OUTDIR=%~dp0out"
set "PLATFORM=Win32"
set "CONFIG=Debug"
set "DELPHI=23.0"
set "RSVARS_ARG="
if defined RSVARS set "RSVARS_ARG=--rsvars ""%RSVARS%"""
set "ENVOPTIONS_ARG="
if defined ENVOPTIONS set "ENVOPTIONS_ARG=--envoptions ""%ENVOPTIONS%"""

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

set "EXE=%ROOT%\bin\DelphiConfigResolver.exe"

if not exist "%FIXTURES%\*.dproj" (
  echo No .dproj files found in "%FIXTURES%".
  exit /b 1
)

echo Using: %EXE%

for %%F in ("%FIXTURES%\*.dproj") do (
  for %%K in (ini xml bat) do (
    set "OUTFILE=%OUTDIR%\%%~nF.%%K"
    "%EXE%" --dproj "%%~fF" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --out-kind %%K --out "!OUTFILE!" --verbose true !RSVARS_ARG! !ENVOPTIONS_ARG!
    if errorlevel 1 (
      echo Failed: %%~fF (%%K)
      exit /b 1
    )
  )
)

echo Tests completed.
exit /b 0
