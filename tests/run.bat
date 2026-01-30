@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "TESTS_DIR=%~dp0"
for %%I in ("%TESTS_DIR%..") do set "ROOT=%%~fI"
set "FIXTURES=%TESTS_DIR%fixtures"
set "OUTDIR=%TESTS_DIR%out"

rem ---- Defaults (override via env vars) -------------------------------------
set "PLATFORM=Win32"
if defined DAK_PLATFORM set "PLATFORM=%DAK_PLATFORM%"
set "CONFIG=Release"
if defined DAK_CONFIG set "CONFIG=%DAK_CONFIG%"
set "DELPHI=23.0"
if defined DAK_DELPHI set "DELPHI=%DAK_DELPHI%"

rem Optional rsvars/envoptions overrides (kept compatible with existing names)
set "RSVARS_ARG="
if defined RSVARS set "RSVARS_ARG=--rsvars ""%RSVARS%"""
set "ENVOPTIONS_ARG="
if defined ENVOPTIONS set "ENVOPTIONS_ARG=--envoptions ""%ENVOPTIONS%"""

rem Optional Pascal Analyzer override
set "PA_PATH_ARG="
if defined PA_PATH set "PA_PATH_ARG=--pa-path ""%PA_PATH%"""

rem PALCMD threads (1..64), default to NUMBER_OF_PROCESSORS
set "PA_THREADS=1"
if defined NUMBER_OF_PROCESSORS set "PA_THREADS=%NUMBER_OF_PROCESSORS%"
set /a PA_THREADS=PA_THREADS
if %PA_THREADS% LSS 1 set "PA_THREADS=1"
if %PA_THREADS% GTR 64 set "PA_THREADS=64"

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

set "EXE=%ROOT%\bin\DelphiAIKit.exe"
set "DPROJ_SELF=%ROOT%\projects\DelphiAIKit.dproj"

if not exist "%EXE%" (
  echo [WARN] DelphiAIKit.exe not found:
  echo        "%EXE%"
  echo [INFO] Attempting to build it now...
  if not exist "%ROOT%\build-delphi.bat" (
    echo [ERROR] build-delphi.bat not found at:
    echo         "%ROOT%\build-delphi.bat"
    exit /b 2
  )
  call "%ROOT%\build-delphi.bat" "%ROOT%\projects\DelphiAIKit.dproj" -config %CONFIG% -platform %PLATFORM% -ver %DELPHI%
  if errorlevel 1 (
    echo [ERROR] build-delphi.bat failed.
    exit /b 2
  )
)
if not exist "%EXE%" (
  echo [ERROR] DelphiAIKit.exe still missing after build:
  echo         "%EXE%"
  exit /b 2
)
if not exist "%DPROJ_SELF%" (
  echo [ERROR] Self dproj not found:
  echo         "%DPROJ_SELF%"
  exit /b 3
)

echo [INFO] Using: "%EXE%"
echo [INFO] Self dproj: "%DPROJ_SELF%"
echo [INFO] Platform=%PLATFORM% Config=%CONFIG% Delphi=%DELPHI%
echo [INFO] OutDir: "%OUTDIR%"
echo.

rem ----------------------------------------------------------------------------
rem 0) Usage/help sanity (new flags are present)
rem ----------------------------------------------------------------------------
"%EXE%" --help > "%OUTDIR%\help.txt" 2>&1
call :AssertContains "%OUTDIR%\help.txt" "resolve" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "analyze" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "build" || exit /b 10

"%EXE%" resolve --help > "%OUTDIR%\help-resolve.txt" 2>&1
call :AssertContains "%OUTDIR%\help-resolve.txt" "--format" || exit /b 10
call :AssertContains "%OUTDIR%\help-resolve.txt" "--out-file" || exit /b 10
call :AssertContains "%OUTDIR%\help-resolve.txt" "--fi-output" || exit /b 10

"%EXE%" analyze --help > "%OUTDIR%\help-analyze.txt" 2>&1
call :AssertContains "%OUTDIR%\help-analyze.txt" "--fixinsight" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--pascal-analyzer" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--exclude-path-masks" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--ignore-warning-ids" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--pa-path" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--pa-output" || exit /b 10
call :AssertContains "%OUTDIR%\help-analyze.txt" "--pa-args" || exit /b 10

rem ----------------------------------------------------------------------------
rem 1) Resolver output generation (fixtures + self)
rem ----------------------------------------------------------------------------
if not exist "%FIXTURES%\*.dproj" (
  echo [ERROR] No .dproj files found in "%FIXTURES%".
  exit /b 11
)

echo [INFO] Generating outputs for fixture projects...
for %%F in ("%FIXTURES%\*.dproj") do (
  for %%K in (ini xml bat) do (
    set "OUTFILE=%OUTDIR%\fixture-%%~nF.%%K"
    "%EXE%" resolve --project "%%~fF" --platform %PLATFORM% --config Debug --delphi %DELPHI% --format %%K --out-file "!OUTFILE!" --verbose true !RSVARS_ARG! !ENVOPTIONS_ARG!
    if errorlevel 1 (
      echo [ERROR] Failed: %%~fF (%%K)
      exit /b 1
    )
    if not exist "!OUTFILE!" (
      echo [ERROR] Expected output missing: "!OUTFILE!"
      exit /b 1
    )
  )
)

echo [INFO] Generating outputs for self project...
for %%K in (ini xml bat) do (
  set "OUTFILE=%OUTDIR%\self.%%K"
  "%EXE%" resolve --project "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --format %%K --out-file "!OUTFILE!" --verbose true !RSVARS_ARG! !ENVOPTIONS_ARG!
  if errorlevel 1 (
    echo [ERROR] Failed: self project (%%K)
    exit /b 12
  )
  if not exist "!OUTFILE!" (
    echo [ERROR] Expected output missing: "!OUTFILE!"
    exit /b 12
  )
)

rem ----------------------------------------------------------------------------
rem 2) FixInsight end-to-end (self) + filtering (txt/xml/csv)
rem ----------------------------------------------------------------------------
echo [INFO] Running FixInsightCL (self) in txt/xml/csv...

set "FI_BASE_ROOT=%OUTDIR%\fi-self"
set "FI_BASE_TXT=%FI_BASE_ROOT%\fixinsight\fixinsight.txt"
set "FI_BASE_XML=%FI_BASE_ROOT%\fixinsight\fixinsight.xml"
set "FI_BASE_CSV=%FI_BASE_ROOT%\fixinsight\fixinsight.csv"

set "FIXINSIGHT_OUT=!FI_BASE_ROOT!"
call :RunFixInsight "%EXE%" "!FI_BASE_ROOT!" "" "" || exit /b 20

rem Extract 1-2 warning IDs from the baseline report to keep tests version-agnostic.
set "ID1="
set "ID2="
for /f "tokens=1" %%A in ('type "%FI_BASE_TXT%" ^| findstr /R /C:"^[ ]*[A-Z][0-9][0-9][0-9] "') do (
  if not defined ID1 (
    set "ID1=%%A"
  ) else if /I not "%%A"=="!ID1!" if not defined ID2 (
    set "ID2=%%A"
  )
)
if not defined ID1 (
  echo [ERROR] Could not extract any FixInsight warning IDs from:
  echo         "%FI_BASE_TXT%"
  exit /b 21
)
if not defined ID2 set "ID2=!ID1!"
echo [INFO] Sample warning IDs: !ID1! !ID2!

rem Extract a file name from baseline report for ExcludePathMasks tests.
set "EXCL_FILE="
for /f "tokens=1* delims=:" %%A in ('type "%FI_BASE_TXT%" ^| findstr /B /C:"File:"') do (
  if not defined EXCL_FILE (
    set "EXCL_FILE=%%B"
    for /f "tokens=* delims= " %%P in ("!EXCL_FILE!") do set "EXCL_FILE=%%P"
  )
)
if not defined EXCL_FILE (
  echo [ERROR] Could not extract any "File:" entries from:
  echo         "%FI_BASE_TXT%"
  exit /b 21
)
for %%F in ("!EXCL_FILE!") do set "EXCL_FILE_NAME=%%~nxF"
if not defined EXCL_FILE_NAME (
  echo [ERROR] Could not extract file name from:
  echo         "!EXCL_FILE!"
  exit /b 21
)
set "EXCL_MASKS=*%EXCL_FILE_NAME%"
set "MASK_NEEDLE=%EXCL_FILE_NAME%"
echo [INFO] ExcludePathMasks sample: %EXCL_MASKS%

rem ---- ExcludePathMasks filtering (txt/xml/csv) ------------------------------
set "FI_EXCL_ROOT=%OUTDIR%\fi-self.excl"
set "FI_EXCL_TXT=%FI_EXCL_ROOT%\fixinsight\fixinsight.txt"
set "FI_EXCL_XML=%FI_EXCL_ROOT%\fixinsight\fixinsight.xml"
set "FI_EXCL_CSV=%FI_EXCL_ROOT%\fixinsight\fixinsight.csv"

call :AssertContains "%FI_BASE_TXT%" "%MASK_NEEDLE%" || exit /b 21
set "FIXINSIGHT_OUT=!FI_EXCL_ROOT!"
call :RunFixInsight "%EXE%" "!FI_EXCL_ROOT!" "%EXCL_MASKS%" "" || exit /b 22

call :AssertNotContains "%FI_EXCL_TXT%" "%MASK_NEEDLE%" || exit /b 23
call :AssertNotContains "%FI_EXCL_XML%" "%MASK_NEEDLE%" || exit /b 23
call :AssertNotContains "%FI_EXCL_CSV%" "%MASK_NEEDLE%" || exit /b 23

rem ---- Ignore warning IDs filtering (txt/xml/csv) ----------------------------
set "IGNORE_IDS=!ID1!;!ID2!"
set "FI_IDS_ROOT=%OUTDIR%\fi-self.ignore-ids"
set "FI_IDS_TXT=%FI_IDS_ROOT%\fixinsight\fixinsight.txt"
set "FI_IDS_XML=%FI_IDS_ROOT%\fixinsight\fixinsight.xml"
set "FI_IDS_CSV=%FI_IDS_ROOT%\fixinsight\fixinsight.csv"

call :AssertContains "%FI_BASE_TXT%" "!ID1!" || exit /b 21
set "FIXINSIGHT_OUT=!FI_IDS_ROOT!"
call :RunFixInsight "%EXE%" "!FI_IDS_ROOT!" "" "!IGNORE_IDS!" || exit /b 24

call :AssertNotContains "%FI_IDS_TXT%" "!ID1!" || exit /b 25
call :AssertNotContains "%FI_IDS_TXT%" "!ID2!" || exit /b 25
call :AssertNotContains "%FI_IDS_XML%" "!ID1!" || exit /b 25
call :AssertNotContains "%FI_IDS_XML%" "!ID2!" || exit /b 25
call :AssertNotContains "%FI_IDS_CSV%" ",!ID1!," || exit /b 25
call :AssertNotContains "%FI_IDS_CSV%" ",!ID2!," || exit /b 25

rem ----------------------------------------------------------------------------
rem 3) settings.ini behavior (sandboxed exe copy)
rem ----------------------------------------------------------------------------
echo [INFO] Testing settings.ini defaults/merge via sandboxed exe copy...

set "SANDBOX=%OUTDIR%\sandbox"
if not exist "%SANDBOX%" mkdir "%SANDBOX%" >nul 2>&1
copy /Y "%EXE%" "%SANDBOX%\DelphiAIKit.exe" >nul

(
  echo [FixInsightCL]
  echo Output=
  echo Ignore=
  echo Settings=
  echo Silent=false
  echo Xml=false
  echo Csv=false
  echo.
  echo [FixInsightIgnore]
  echo Warnings=!ID1!
  echo.
  echo [ReportFilter]
  echo ExcludePathMasks=%EXCL_MASKS%
  echo.
  echo [PascalAnalyzer]
  echo Path=
  echo Output=
  echo Args=
) > "%SANDBOX%\settings.ini"

set "FI_SETTINGS_ROOT=%OUTDIR%\fi-self.settings"
set "FI_SETTINGS_CSV=%FI_SETTINGS_ROOT%\fixinsight\fixinsight.csv"
call :RunFixInsight "%SANDBOX%\DelphiAIKit.exe" "%FI_SETTINGS_ROOT%" "" "!ID2!" || exit /b 30
call :AssertNotContains "%FI_SETTINGS_CSV%" "%MASK_NEEDLE%" || exit /b 31
call :AssertNotContains "%FI_SETTINGS_CSV%" ",!ID1!," || exit /b 31
call :AssertNotContains "%FI_SETTINGS_CSV%" ",!ID2!," || exit /b 31

rem Also verify ignore list merging (settings + CLI) via bat output.
set "SANDBOX2=%OUTDIR%\sandbox-ignore"
if not exist "%SANDBOX2%" mkdir "%SANDBOX2%" >nul 2>&1
copy /Y "%EXE%" "%SANDBOX2%\DelphiAIKit.exe" >nul
(
  echo [FixInsightCL]
  echo Output=
  echo Ignore=..\src\Dak.Cli.pas;..\src\Dak.Cli.pas
  echo Settings=
  echo Silent=false
  echo Xml=false
  echo Csv=false
) > "%SANDBOX2%\settings.ini"

set "BAT_OUT=%OUTDIR%\ignore-merged.bat"
"%SANDBOX2%\DelphiAIKit.exe" resolve --project "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --format bat --out-file "%BAT_OUT%" --fi-ignore "..\src\Dak.Output.pas;..\src\Dak.Cli.pas" !RSVARS_ARG! !ENVOPTIONS_ARG!
if errorlevel 1 (
  echo [ERROR] Failed to generate bat output for ignore merge test.
  exit /b 32
)
call :AssertContains "%BAT_OUT%" "..\src\Dak.Cli.pas;..\src\Dak.Output.pas" || exit /b 33

rem ----------------------------------------------------------------------------
rem 4) Pascal Analyzer end-to-end (self)
rem ----------------------------------------------------------------------------
echo [INFO] Running Pascal Analyzer (PALCMD) on self project...

if defined SKIP_PASCAL_ANALYZER (
  echo [INFO] SKIP_PASCAL_ANALYZER is set - skipping PALCMD tests.
  goto pa_done
)

set "PA_OUT_SETTINGS=%OUTDIR%\pa-self.settings"
if exist "%PA_OUT_SETTINGS%" rmdir /S /Q "%PA_OUT_SETTINGS%" >nul 2>&1
mkdir "%PA_OUT_SETTINGS%" >nul 2>&1

set "PA_OUT_CLI=%OUTDIR%\pa-self.cli"
if exist "%PA_OUT_CLI%" rmdir /S /Q "%PA_OUT_CLI%" >nul 2>&1
mkdir "%PA_OUT_CLI%" >nul 2>&1

rem Use settings.ini to feed PALCMD Output=... and (optionally) Path=...
set "SANDBOX_PA=%OUTDIR%\sandbox-pa"
if not exist "%SANDBOX_PA%" mkdir "%SANDBOX_PA%" >nul 2>&1
copy /Y "%EXE%" "%SANDBOX_PA%\DelphiAIKit.exe" >nul

set "PA_PATH_VALUE="
if defined PA_PATH set "PA_PATH_VALUE=%PA_PATH%"

(
  echo [FixInsightCL]
  echo Output=
  echo Ignore=
  echo Settings=
  echo Silent=false
  echo Xml=false
  echo Csv=false
  echo.
  echo [PascalAnalyzer]
  echo Path=%PA_PATH_VALUE%
  echo Output=%PA_OUT_SETTINGS%
  echo Args=
) > "%SANDBOX_PA%\settings.ini"

rem Settings-driven run (tests Output from settings.ini + our default args)
"%SANDBOX_PA%\DelphiAIKit.exe" analyze --project "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --fixinsight false --pascal-analyzer true !RSVARS_ARG! !ENVOPTIONS_ARG!
if errorlevel 1 (
  echo [ERROR] PALCMD run (settings.ini) failed. If PALCMD is not installed, set PA_PATH or SKIP_PASCAL_ANALYZER=1.
  exit /b 40
)
call :AssertAnyMatch "%PA_OUT_SETTINGS%\*.xml" || exit /b 41

rem CLI-driven run (tests overrides)
"%EXE%" analyze --project "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --fixinsight false --pascal-analyzer true !PA_PATH_ARG! --pa-output "%PA_OUT_CLI%" --pa-args "/F=X /Q /A+ /FA /T=%PA_THREADS%" !RSVARS_ARG! !ENVOPTIONS_ARG!
if errorlevel 1 (
  echo [ERROR] PALCMD run (CLI overrides) failed. If PALCMD is not installed, set PA_PATH or SKIP_PASCAL_ANALYZER=1.
  exit /b 42
)
call :AssertAnyMatch "%PA_OUT_CLI%\*.xml" || exit /b 43

:pa_done
echo.
echo [OK] Tests completed.
exit /b 0

rem ----------------------------------------------------------------------------
rem Helpers
rem ----------------------------------------------------------------------------
:RunFixInsight
rem args: <exe> <outRoot> <excludeMasks> <ignoreIds>
set "RUN_EXE=%~1"
if "%~2"=="" (
  set "OUT_ROOT=%FIXINSIGHT_OUT%"
) else (
  set "OUT_ROOT=%~2"
)
set "MASKS=%~3"
set "IDS=%~4"

set "MASK_ARG="
if not "%MASKS%"=="" set "MASK_ARG=--exclude-path-masks ""%MASKS%"""
set "IDS_ARG="
if not "%IDS%"=="" set "IDS_ARG=--ignore-warning-ids ""%IDS%"""

"%RUN_EXE%" analyze --project "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --out "%OUT_ROOT%" --fixinsight true --pascal-analyzer false --fi-formats all %MASK_ARG% %IDS_ARG% %RSVARS_ARG% %ENVOPTIONS_ARG%
if errorlevel 1 (
  echo [ERROR] FixInsight analyze failed: out="%OUT_ROOT%"
  exit /b 1
)
if not exist "%OUT_ROOT%\fixinsight\fixinsight.txt" (
  echo [ERROR] Expected FixInsight report missing:
  echo         "%OUT_ROOT%\fixinsight\fixinsight.txt"
  exit /b 1
)
if not exist "%OUT_ROOT%\fixinsight\fixinsight.xml" (
  echo [ERROR] Expected FixInsight report missing:
  echo         "%OUT_ROOT%\fixinsight\fixinsight.xml"
  exit /b 1
)
if not exist "%OUT_ROOT%\fixinsight\fixinsight.csv" (
  echo [ERROR] Expected FixInsight report missing:
  echo         "%OUT_ROOT%\fixinsight\fixinsight.csv"
  exit /b 1
)
for %%I in ("%OUT_ROOT%\fixinsight\fixinsight.txt") do if %%~zI EQU 0 (
  echo [ERROR] FixInsight report is empty:
  echo         "%OUT_ROOT%\fixinsight\fixinsight.txt"
  exit /b 1
)
exit /b 0

:AssertContains
rem args: <file> <needle>
findstr /C:"%~2" "%~1" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Expected to find "%~2" in:
  echo         "%~1"
  exit /b 1
)
exit /b 0

:AssertNotContains
rem args: <file> <needle>
findstr /C:"%~2" "%~1" >nul 2>&1
if not errorlevel 1 (
  echo [ERROR] Expected NOT to find "%~2" in:
  echo         "%~1"
  exit /b 1
)
exit /b 0

:AssertAnyMatch
rem args: <glob pattern>
dir /b /s "%~1" >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Expected at least one file matching:
  echo         "%~1"
  exit /b 1
)
exit /b 0
