@echo off
setlocal EnableExtensions

rem ============================================================================
rem  FixInsight headless runner (via DelphiConfigResolver --run-fixinsight)
rem
rem  What this script does:
rem    - Calls DelphiConfigResolver.exe to read a Delphi .dproj (and IDE settings)
rem      for a chosen platform/config/Delphi version.
rem    - Uses --run-fixinsight to execute FixInsightCL directly (no temp runner bat).
rem    - Captures all console output to a report file next to this script:
rem        fixInsight-<ProjectName>-report.txt
rem
rem  Notes:
rem    - All paths are resolved relative to this script directory (%~dp0).
rem    - The report includes both DelphiConfigResolver diagnostics and FixInsight output.
rem ============================================================================

rem ---- Parameters (edit these) ----------------------------------------------
set "ML_DPROJ_REL=projects\DelphiConfigResolver.dproj"
set "ML_PLATFORM=Win32"
set "ML_CONFIG=Release"
set "ML_DELPHI_VER=23.0"

rem Optional: generate raw FixInsightCL reports (txt/xml/csv) under docs/ for post-processing tests
set "ML_GENERATE_SAMPLE_REPORTS=true"
set "ML_SAMPLE_DIR_REL=docs\sample-fix-insight-self-reports"

rem Optional troubleshooting
set "ML_VERBOSE=false"
set "ML_LOG_TEE=true"

rem Optional overrides (leave empty to use defaults)
set "ML_RSVARS_REL="
set "ML_ENVOPTIONS_REL="

rem Optional FixInsightCL pass-through (leave empty if not needed)
rem These are passed to DelphiConfigResolver, which forwards to FixInsightCL.
set "ML_FI_OUTPUT="
set "ML_FI_IGNORE="
set "ML_FI_SETTINGS="
set "ML_FI_SILENT="
set "ML_FI_XML="
set "ML_FI_CSV="

rem Resolver location: if next to this script, keep as exe name.
rem Otherwise set a relative path like: tools\DelphiConfigResolver.exe
set "ML_RESOLVER_EXE=bin\DelphiConfigResolver.exe"
rem ----------------------------------------------------------------------------

rem ---- Derived (do not edit unless needed) -----------------------------------
set "ML_SCRIPT_DIR=%~dp0"
set "ML_DPROJ=%ML_SCRIPT_DIR%%ML_DPROJ_REL%"

for %%F in ("%ML_DPROJ%") do (
  set "ML_DPROJ_DIR=%%~dpF"
  set "ML_DPROJ_BASE=%%~nF"
)

set "ML_REPORT_FILE=%ML_SCRIPT_DIR%fixInsight-%ML_DPROJ_BASE%-report.txt"
set "ML_LOG_FILE=%ML_SCRIPT_DIR%fixInsight-%ML_DPROJ_BASE%-resolver.log"
set "ML_INI_FILE=%ML_SCRIPT_DIR%fixInsight-%ML_DPROJ_BASE%-params.ini"

rem Optional override paths (if set, resolve relative to script dir)
set "ML_RSVARS="
if not "%ML_RSVARS_REL%"=="" set "ML_RSVARS=%ML_SCRIPT_DIR%%ML_RSVARS_REL%"

set "ML_ENVOPTIONS="
if not "%ML_ENVOPTIONS_REL%"=="" set "ML_ENVOPTIONS=%ML_SCRIPT_DIR%%ML_ENVOPTIONS_REL%"
rem ----------------------------------------------------------------------------

echo.
echo ============================================================
echo  FixInsight run (direct) via DelphiConfigResolver --run-fixinsight
echo ============================================================
echo  Script dir : "%ML_SCRIPT_DIR%"
echo  DPROJ      : "%ML_DPROJ%"
echo  Platform   : "%ML_PLATFORM%"
echo  Config     : "%ML_CONFIG%"
echo  Delphi     : "%ML_DELPHI_VER%"
echo  Verbose    : "%ML_VERBOSE%"
if not "%ML_RSVARS%"==""     echo  RsVars     : "%ML_RSVARS%"
if not "%ML_ENVOPTIONS%"=="" echo  EnvOptions : "%ML_ENVOPTIONS%"
echo  Report TXT : "%ML_REPORT_FILE%"
echo  Log File   : "%ML_LOG_FILE%"
echo  INI Output : "%ML_INI_FILE%"
echo  Log Tee    : "%ML_LOG_TEE%"
echo ============================================================
echo.

rem ---- Sanity checks ---------------------------------------------------------
if not exist "%ML_DPROJ%" (
  echo [ERROR] .dproj not found: "%ML_DPROJ%"
  exit /b 2
)

where /Q "%ML_RESOLVER_EXE%"
if errorlevel 1 (
  if exist "%ML_SCRIPT_DIR%%ML_RESOLVER_EXE%" (
    set "ML_RESOLVER_EXE=%ML_SCRIPT_DIR%%ML_RESOLVER_EXE%"
  ) else (
    echo [ERROR] DelphiConfigResolver.exe not found on PATH and not next to script.
    echo         Looked for: "%ML_SCRIPT_DIR%DelphiConfigResolver.exe"
    exit /b 3
  )
)

rem ---- Write report header ---------------------------------------------------
(
  echo ============================================================
  echo FixInsight run report
  echo ============================================================
  echo Date/Time: %DATE% %TIME%
  echo Script   : "%~f0"
  echo DPROJ    : "%ML_DPROJ%"
  echo Platform : "%ML_PLATFORM%"
  echo Config   : "%ML_CONFIG%"
  echo Delphi   : "%ML_DELPHI_VER%"
  echo Verbose  : "%ML_VERBOSE%"
  if not "%ML_RSVARS%"==""     echo RsVars    : "%ML_RSVARS%"
  if not "%ML_ENVOPTIONS%"=="" echo EnvOptions: "%ML_ENVOPTIONS%"
  echo Log File : "%ML_LOG_FILE%"
  echo INI File : "%ML_INI_FILE%"
  echo Log Tee  : "%ML_LOG_TEE%"
  echo ============================================================
  echo.
) > "%ML_REPORT_FILE%"

echo [INFO] Report will be written to:
echo        "%ML_REPORT_FILE%"
echo [INFO] Resolver log will be written to:
echo        "%ML_LOG_FILE%"
echo [INFO] INI output will be written to:
echo        "%ML_INI_FILE%"
echo [INFO] Log tee enabled:
echo        "%ML_LOG_TEE%"
echo.

echo ============================================================
echo  Phase 1: DelphiConfigResolver prepares config + runs FixInsight
echo ============================================================
echo.

(
  echo ============================================================
  echo Phase 1: DelphiConfigResolver prepares config + runs FixInsight
  echo ============================================================
  echo.
) >> "%ML_REPORT_FILE%"

rem ---- Build optional arguments (only add when set) --------------------------
set "ML_OPT_ARGS="

if /I "%ML_VERBOSE%"=="true" set "ML_OPT_ARGS=%ML_OPT_ARGS% --verbose true"
if /I "%ML_LOG_TEE%"=="true" set "ML_OPT_ARGS=%ML_OPT_ARGS% --log-tee true"

if not "%ML_RSVARS%"=="" (
  if not exist "%ML_RSVARS%" (
    echo [ERROR] rsvars.bat override not found: "%ML_RSVARS%"
    exit /b 4
  )
  set "ML_OPT_ARGS=%ML_OPT_ARGS% --rsvars ""%ML_RSVARS%"""
)

if not "%ML_ENVOPTIONS%"=="" (
  if not exist "%ML_ENVOPTIONS%" (
    echo [ERROR] EnvOptions.proj override not found: "%ML_ENVOPTIONS%"
    exit /b 5
  )
  set "ML_OPT_ARGS=%ML_OPT_ARGS% --envoptions ""%ML_ENVOPTIONS%"""
)

if not "%ML_FI_OUTPUT%"==""   set "ML_OPT_ARGS=%ML_OPT_ARGS% --output ""%ML_FI_OUTPUT%"""
if not "%ML_FI_IGNORE%"==""   set "ML_OPT_ARGS=%ML_OPT_ARGS% --ignore ""%ML_FI_IGNORE%"""
if not "%ML_FI_SETTINGS%"=="" set "ML_OPT_ARGS=%ML_OPT_ARGS% --settings ""%ML_FI_SETTINGS%"""
if not "%ML_FI_SILENT%"==""   set "ML_OPT_ARGS=%ML_OPT_ARGS% --silent %ML_FI_SILENT%"
if not "%ML_FI_XML%"==""      set "ML_OPT_ARGS=%ML_OPT_ARGS% --xml %ML_FI_XML%"
if not "%ML_FI_CSV%"==""      set "ML_OPT_ARGS=%ML_OPT_ARGS% --csv %ML_FI_CSV%"

rem ---- Execute ---------------------------------------------------------------
echo [INFO] Running:
echo        "%ML_RESOLVER_EXE%" --dproj "%ML_DPROJ%" --platform "%ML_PLATFORM%" --config "%ML_CONFIG%" --delphi "%ML_DELPHI_VER%" --run-fixinsight --logfile "%ML_LOG_FILE%" --out-kind ini --out "%ML_INI_FILE%" %ML_OPT_ARGS%
echo.

"%ML_RESOLVER_EXE%" ^
  --dproj "%ML_DPROJ%" ^
  --platform "%ML_PLATFORM%" ^
  --config "%ML_CONFIG%" ^
  --delphi "%ML_DELPHI_VER%" ^
  --run-fixinsight ^
  --logfile "%ML_LOG_FILE%" ^
  --out-kind ini ^
  --out "%ML_INI_FILE%" ^
  %ML_OPT_ARGS% >> "%ML_REPORT_FILE%" 2>&1

set "ML_RC=%ERRORLEVEL%"

echo [INFO] Finished with exit code: %ML_RC%
echo.

(
  echo.
  echo ============================================================
  echo Exit code: %ML_RC%
  echo ============================================================
) >> "%ML_REPORT_FILE%"

echo [DONE] Report saved to:
echo        "%ML_REPORT_FILE%"

rem ---- Optional: capture raw FixInsightCL outputs (txt/xml/csv) --------------
if not "%ML_RC%"=="0" goto samples_done
if /I not "%ML_GENERATE_SAMPLE_REPORTS%"=="true" goto samples_done

set "ML_SAMPLE_DIR=%ML_SCRIPT_DIR%%ML_SAMPLE_DIR_REL%"
if not exist "%ML_SAMPLE_DIR%" mkdir "%ML_SAMPLE_DIR%"

echo.
echo ============================================================
echo  Generating raw FixInsightCL reports: txt/xml/csv
echo ============================================================
echo  Dir: "%ML_SAMPLE_DIR%"
echo.

rem TXT
"%ML_RESOLVER_EXE%" --dproj "%ML_DPROJ%" --platform "%ML_PLATFORM%" --config "%ML_CONFIG%" --delphi "%ML_DELPHI_VER%" --run-fixinsight --output "%ML_SAMPLE_DIR%\fixinsight-self.txt" --log-tee false --verbose false >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to generate TXT sample report.
  exit /b 10
)

rem XML
"%ML_RESOLVER_EXE%" --dproj "%ML_DPROJ%" --platform "%ML_PLATFORM%" --config "%ML_CONFIG%" --delphi "%ML_DELPHI_VER%" --run-fixinsight --xml true --output "%ML_SAMPLE_DIR%\fixinsight-self.xml" --log-tee false --verbose false >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to generate XML sample report.
  exit /b 11
)

rem CSV
"%ML_RESOLVER_EXE%" --dproj "%ML_DPROJ%" --platform "%ML_PLATFORM%" --config "%ML_CONFIG%" --delphi "%ML_DELPHI_VER%" --run-fixinsight --csv true --output "%ML_SAMPLE_DIR%\fixinsight-self.csv" --log-tee false --verbose false >nul 2>&1
if errorlevel 1 (
  echo [ERROR] Failed to generate CSV sample report.
  exit /b 12
)

echo [DONE] Raw reports saved under:
echo        "%ML_SAMPLE_DIR%"

:samples_done
exit /b %ML_RC%
