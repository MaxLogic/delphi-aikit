@echo off
setlocal EnableExtensions

rem ============================================================================
rem  Pascal Analyzer headless runner (via DelphiConfigResolver --run-pascal-analyzer)
rem
rem  What this script does:
rem    - Calls DelphiConfigResolver.exe to read a Delphi .dproj (and IDE settings)
rem      for a chosen platform/config/Delphi version.
rem    - Uses --run-pascal-analyzer to execute PALCMD directly
rem    - Captures all console output to a report file next to this script:
rem        pascal-analyzer-<ProjectName>-report.txt
rem
rem  Notes:
rem    - All paths are resolved relative to this script directory (%~dp0).
rem    - The report includes both DelphiConfigResolver diagnostics and PALCMD output.
rem ============================================================================

rem ---- Parameters (edit these) ----------------------------------------------
set "ML_DPROJ_REL=..\..\projects\DelphiConfigResolver.dproj"
set "ML_PLATFORM=Win32"
set "ML_CONFIG=Release"
set "ML_DELPHI_VER=23.0"

rem Optional: output root folder for PALCMD reports
set "ML_PA_OUTPUT_REL=Reports"

rem Optional troubleshooting
set "ML_VERBOSE=false"
set "ML_LOG_TEE=true"

rem Optional overrides (leave empty to use defaults)
set "ML_RSVARS_REL="
set "ML_ENVOPTIONS_REL="

rem Optional Pascal Analyzer overrides
rem - Path can be palcmd.exe/palcmd32.exe or a folder containing it.
rem - Args are passed verbatim to PALCMD.
set "ML_PA_PATH="
set "ML_PA_ARGS="

rem Resolver location: if next to this script, keep as exe name.
rem Otherwise set a relative path like: tools\DelphiConfigResolver.exe
set "ML_RESOLVER_EXE=..\..\bin\DelphiConfigResolver.exe"
rem ----------------------------------------------------------------------------

rem ---- Derived (do not edit unless needed) -----------------------------------
set "ML_SCRIPT_DIR=%~dp0"
set "ML_DPROJ=%ML_SCRIPT_DIR%%ML_DPROJ_REL%"

for %%F in ("%ML_DPROJ%") do (
  set "ML_DPROJ_DIR=%%~dpF"
  set "ML_DPROJ_BASE=%%~nF"
)

set "ML_REPORT_FILE=%ML_SCRIPT_DIR%pascal-analyzer-%ML_DPROJ_BASE%-report.txt"
set "ML_LOG_FILE=%ML_SCRIPT_DIR%pascal-analyzer-%ML_DPROJ_BASE%-resolver.log"
set "ML_INI_FILE=%ML_SCRIPT_DIR%pascal-analyzer-%ML_DPROJ_BASE%-params.ini"
set "ML_PA_OUTPUT=%ML_SCRIPT_DIR%%ML_PA_OUTPUT_REL%"

rem Optional override paths (if set, resolve relative to script dir)
set "ML_RSVARS="
if not "%ML_RSVARS_REL%"=="" set "ML_RSVARS=%ML_SCRIPT_DIR%%ML_RSVARS_REL%"

set "ML_ENVOPTIONS="
if not "%ML_ENVOPTIONS_REL%"=="" set "ML_ENVOPTIONS=%ML_SCRIPT_DIR%%ML_ENVOPTIONS_REL%"
rem ----------------------------------------------------------------------------

echo.
echo ============================================================
echo  Pascal Analyzer run (direct) via DelphiConfigResolver --run-pascal-analyzer
echo ============================================================
echo  Script dir : "%ML_SCRIPT_DIR%"
echo  DPROJ      : "%ML_DPROJ%"
echo  Platform   : "%ML_PLATFORM%"
echo  Config     : "%ML_CONFIG%"
echo  Delphi     : "%ML_DELPHI_VER%"
echo  Verbose    : "%ML_VERBOSE%"
if not "%ML_RSVARS%"==""     echo  RsVars     : "%ML_RSVARS%"
if not "%ML_ENVOPTIONS%"=="" echo  EnvOptions : "%ML_ENVOPTIONS%"
if not "%ML_PA_PATH%"==""    echo  PA Path    : "%ML_PA_PATH%"
if not "%ML_PA_ARGS%"==""    echo  PA Args    : "%ML_PA_ARGS%"
echo  Report TXT : "%ML_REPORT_FILE%"
echo  Log File   : "%ML_LOG_FILE%"
echo  INI Output : "%ML_INI_FILE%"
echo  PA Output  : "%ML_PA_OUTPUT%"
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

if not exist "%ML_PA_OUTPUT%" mkdir "%ML_PA_OUTPUT%"

rem ---- Write report header ---------------------------------------------------
(
  echo ============================================================
  echo Pascal Analyzer run report
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
  if not "%ML_PA_PATH%"==""    echo PA Path   : "%ML_PA_PATH%"
  if not "%ML_PA_ARGS%"==""    echo PA Args   : "%ML_PA_ARGS%"
  echo Log File : "%ML_LOG_FILE%"
  echo INI File : "%ML_INI_FILE%"
  echo PA Output: "%ML_PA_OUTPUT%"
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
echo [INFO] PA output root will be written to:
echo        "%ML_PA_OUTPUT%"
echo [INFO] Log tee enabled:
echo        "%ML_LOG_TEE%"
echo.

echo ============================================================
echo  Phase 1: DelphiConfigResolver prepares config + runs Pascal Analyzer
echo ============================================================
echo.

(
  echo ============================================================
  echo Phase 1: DelphiConfigResolver prepares config + runs Pascal Analyzer
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
  set "ML_OPT_ARGS=%ML_OPT_ARGS% --rsvars "%ML_RSVARS%""
)

if not "%ML_ENVOPTIONS%"=="" (
  if not exist "%ML_ENVOPTIONS%" (
    echo [ERROR] EnvOptions.proj override not found: "%ML_ENVOPTIONS%"
    exit /b 5
  )
  set "ML_OPT_ARGS=%ML_OPT_ARGS% --envoptions "%ML_ENVOPTIONS%""
)

if not "%ML_PA_PATH%"=="" set "ML_OPT_ARGS=%ML_OPT_ARGS% --pa-path "%ML_PA_PATH%""
if not "%ML_PA_ARGS%"=="" set "ML_OPT_ARGS=%ML_OPT_ARGS% --pa-args "%ML_PA_ARGS%""

rem ---- Execute ---------------------------------------------------------------
echo [INFO] Running:
echo        "%ML_RESOLVER_EXE%" --dproj "%ML_DPROJ%" --platform "%ML_PLATFORM%" --config "%ML_CONFIG%" --delphi "%ML_DELPHI_VER%" --run-pascal-analyzer --pa-output "%ML_PA_OUTPUT%" --logfile "%ML_LOG_FILE%" --out-kind ini --out "%ML_INI_FILE%" %ML_OPT_ARGS%
echo.

"%ML_RESOLVER_EXE%" ^
  --dproj "%ML_DPROJ%" ^
  --platform "%ML_PLATFORM%" ^
  --config "%ML_CONFIG%" ^
  --delphi "%ML_DELPHI_VER%" ^
  --run-pascal-analyzer ^
  --pa-output "%ML_PA_OUTPUT%" ^
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

echo [DONE] PA output root:
echo        "%ML_PA_OUTPUT%"

exit /b %ML_RC%
