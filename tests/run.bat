@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "TESTS_DIR=%~dp0"
for %%I in ("%TESTS_DIR%..") do set "ROOT=%%~fI"
set "FIXTURES=%TESTS_DIR%fixtures"
set "OUTDIR=%TESTS_DIR%out"

rem ---- Defaults (override via env vars) -------------------------------------
set "PLATFORM=Win32"
if defined DCR_PLATFORM set "PLATFORM=%DCR_PLATFORM%"
set "CONFIG=Release"
if defined DCR_CONFIG set "CONFIG=%DCR_CONFIG%"
set "DELPHI=23.0"
if defined DCR_DELPHI set "DELPHI=%DCR_DELPHI%"

rem Optional rsvars/envoptions overrides (kept compatible with existing names)
set "RSVARS_ARG="
if defined RSVARS set "RSVARS_ARG=--rsvars ""%RSVARS%"""
set "ENVOPTIONS_ARG="
if defined ENVOPTIONS set "ENVOPTIONS_ARG=--envoptions ""%ENVOPTIONS%"""

rem Optional Pascal Analyzer override
set "PA_PATH_ARG="
if defined PA_PATH set "PA_PATH_ARG=--pa-path ""%PA_PATH%"""

if not exist "%OUTDIR%" mkdir "%OUTDIR%" >nul 2>&1

set "EXE=%ROOT%\bin\DelphiConfigResolver.exe"
set "DPROJ_SELF=%ROOT%\projects\DelphiConfigResolver.dproj"

if not exist "%EXE%" (
  echo [WARN] DelphiConfigResolver.exe not found:
  echo        "%EXE%"
  echo [INFO] Attempting to build it now...
  if not exist "%ROOT%\build-delphi.bat" (
    echo [ERROR] build-delphi.bat not found at:
    echo         "%ROOT%\build-delphi.bat"
    exit /b 2
  )
  call "%ROOT%\build-delphi.bat" "%ROOT%\projects\DelphiConfigResolver.dproj" -config %CONFIG% -platform %PLATFORM% -ver %DELPHI%
  if errorlevel 1 (
    echo [ERROR] build-delphi.bat failed.
    exit /b 2
  )
)
if not exist "%EXE%" (
  echo [ERROR] DelphiConfigResolver.exe still missing after build:
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
call :AssertContains "%OUTDIR%\help.txt" "--exclude-path-masks" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "--ignore-warning-ids" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "--run-pascal-analyzer" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "--pa-path" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "--pa-output" || exit /b 10
call :AssertContains "%OUTDIR%\help.txt" "--pa-args" || exit /b 10

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
    "%EXE%" --dproj "%%~fF" --platform %PLATFORM% --config Debug --delphi %DELPHI% --out-kind %%K --out "!OUTFILE!" --verbose true !RSVARS_ARG! !ENVOPTIONS_ARG!
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
  "%EXE%" --dproj "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --out-kind %%K --out "!OUTFILE!" --verbose true !RSVARS_ARG! !ENVOPTIONS_ARG!
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

set "FI_BASE_TXT=%OUTDIR%\fi-self.txt"
set "FI_BASE_XML=%OUTDIR%\fi-self.xml"
set "FI_BASE_CSV=%OUTDIR%\fi-self.csv"

call :RunFixInsight "%EXE%" txt "%FI_BASE_TXT%" "" "" || exit /b 20
call :RunFixInsight "%EXE%" xml "%FI_BASE_XML%" "" "" || exit /b 20
call :RunFixInsight "%EXE%" csv "%FI_BASE_CSV%" "" "" || exit /b 20

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
set "FI_EXCL_TXT=%OUTDIR%\fi-self.excl.txt"
set "FI_EXCL_XML=%OUTDIR%\fi-self.excl.xml"
set "FI_EXCL_CSV=%OUTDIR%\fi-self.excl.csv"

call :AssertContains "%FI_BASE_TXT%" "%MASK_NEEDLE%" || exit /b 21
call :RunFixInsight "%EXE%" txt "%FI_EXCL_TXT%" "%EXCL_MASKS%" "" || exit /b 22
call :RunFixInsight "%EXE%" xml "%FI_EXCL_XML%" "%EXCL_MASKS%" "" || exit /b 22
call :RunFixInsight "%EXE%" csv "%FI_EXCL_CSV%" "%EXCL_MASKS%" "" || exit /b 22

call :AssertNotContains "%FI_EXCL_TXT%" "%MASK_NEEDLE%" || exit /b 23
call :AssertNotContains "%FI_EXCL_XML%" "%MASK_NEEDLE%" || exit /b 23
call :AssertNotContains "%FI_EXCL_CSV%" "%MASK_NEEDLE%" || exit /b 23

rem ---- Ignore warning IDs filtering (txt/xml/csv) ----------------------------
set "IGNORE_IDS=!ID1!;!ID2!"
set "FI_IDS_TXT=%OUTDIR%\fi-self.ignore-ids.txt"
set "FI_IDS_XML=%OUTDIR%\fi-self.ignore-ids.xml"
set "FI_IDS_CSV=%OUTDIR%\fi-self.ignore-ids.csv"

call :AssertContains "%FI_BASE_TXT%" "!ID1!" || exit /b 21
call :RunFixInsight "%EXE%" txt "%FI_IDS_TXT%" "" "%IGNORE_IDS%" || exit /b 24
call :RunFixInsight "%EXE%" xml "%FI_IDS_XML%" "" "%IGNORE_IDS%" || exit /b 24
call :RunFixInsight "%EXE%" csv "%FI_IDS_CSV%" "" "%IGNORE_IDS%" || exit /b 24

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
copy /Y "%EXE%" "%SANDBOX%\DelphiConfigResolver.exe" >nul

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

set "FI_SETTINGS_CSV=%OUTDIR%\fi-self.settings.csv"
call :RunFixInsight "%SANDBOX%\DelphiConfigResolver.exe" csv "%FI_SETTINGS_CSV%" "" "!ID2!" || exit /b 30
call :AssertNotContains "%FI_SETTINGS_CSV%" "%MASK_NEEDLE%" || exit /b 31
call :AssertNotContains "%FI_SETTINGS_CSV%" ",!ID1!," || exit /b 31
call :AssertNotContains "%FI_SETTINGS_CSV%" ",!ID2!," || exit /b 31

rem Also verify ignore list merging (settings + CLI) via bat output.
set "SANDBOX2=%OUTDIR%\sandbox-ignore"
if not exist "%SANDBOX2%" mkdir "%SANDBOX2%" >nul 2>&1
copy /Y "%EXE%" "%SANDBOX2%\DelphiConfigResolver.exe" >nul
(
  echo [FixInsightCL]
  echo Output=
  echo Ignore=..\src\Dcr.Cli.pas;..\src\Dcr.Cli.pas
  echo Settings=
  echo Silent=false
  echo Xml=false
  echo Csv=false
) > "%SANDBOX2%\settings.ini"

set "BAT_OUT=%OUTDIR%\ignore-merged.bat"
"%SANDBOX2%\DelphiConfigResolver.exe" --dproj "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --out-kind bat --out "%BAT_OUT%" --ignore "..\src\Dcr.Output.pas;..\src\Dcr.Cli.pas" !RSVARS_ARG! !ENVOPTIONS_ARG!
if errorlevel 1 (
  echo [ERROR] Failed to generate bat output for ignore merge test.
  exit /b 32
)
call :AssertContains "%BAT_OUT%" "..\src\Dcr.Cli.pas;..\src\Dcr.Output.pas" || exit /b 33

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
copy /Y "%EXE%" "%SANDBOX_PA%\DelphiConfigResolver.exe" >nul

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
"%SANDBOX_PA%\DelphiConfigResolver.exe" --dproj "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --run-pascal-analyzer !RSVARS_ARG! !ENVOPTIONS_ARG!
if errorlevel 1 (
  echo [ERROR] PALCMD run (settings.ini) failed. If PALCMD is not installed, set PA_PATH or SKIP_PASCAL_ANALYZER=1.
  exit /b 40
)
call :AssertAnyMatch "%PA_OUT_SETTINGS%\*.xml" || exit /b 41

rem CLI-driven run (tests overrides)
"%EXE%" --dproj "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --run-pascal-analyzer !PA_PATH_ARG! --pa-output "%PA_OUT_CLI%" --pa-args "/F=X /Q /A+ /FR /T=1" !RSVARS_ARG! !ENVOPTIONS_ARG!
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
rem args: <exe> <fmt:txt|xml|csv> <outFile> <excludeMasks> <ignoreIds>
set "RUN_EXE=%~1"
set "FMT=%~2"
set "OUT_FILE=%~3"
set "MASKS=%~4"
set "IDS=%~5"

set "FMT_ARGS="
if /I "%FMT%"=="xml" set "FMT_ARGS=--xml true"
if /I "%FMT%"=="csv" set "FMT_ARGS=--csv true"

set "MASK_ARG="
if not "%MASKS%"=="" set "MASK_ARG=--exclude-path-masks ""%MASKS%"""
set "IDS_ARG="
if not "%IDS%"=="" set "IDS_ARG=--ignore-warning-ids ""%IDS%"""

"%RUN_EXE%" --dproj "%DPROJ_SELF%" --platform %PLATFORM% --config %CONFIG% --delphi %DELPHI% --run-fixinsight %FMT_ARGS% --output "%OUT_FILE%" %MASK_ARG% %IDS_ARG% %RSVARS_ARG% %ENVOPTIONS_ARG%
if errorlevel 1 (
  echo [ERROR] FixInsight run failed: fmt=%FMT% out="%OUT_FILE%"
  exit /b 1
)
if not exist "%OUT_FILE%" (
  echo [ERROR] Expected FixInsight report missing:
  echo         "%OUT_FILE%"
  exit /b 1
)
for %%I in ("%OUT_FILE%") do if %%~zI EQU 0 (
  echo [ERROR] FixInsight report is empty:
  echo         "%OUT_FILE%"
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
