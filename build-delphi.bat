@echo off
REM Script Version 3

chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format o"') do set "BUILD_START=%%t"
for /f %%t in ('powershell -NoProfile -Command "([DateTimeOffset]::Parse('%BUILD_START%')).UtcTicks"') do set "BUILD_START_TICKS=%%t"

rem =============================================================================
rem v 1.4.5
rem =============================================================================

rem ---- CONFIG (avoid rsvars collisions)
set "DEFAULT_VER=23"
set "DEFAULT_BUILD_CONFIG=Release"
set "DEFAULT_BUILD_PLATFORM=Win32"
set "DEFAULT_MSBUILD_TARGET=Build"
set "DEFAULT_MAX_FINDINGS=5"
set "DEFAULT_BUILD_TIMEOUT_SEC=0"

set "ROOT="
set "EXITCODE=0"

set "PROJECT="
set "VER=%DEFAULT_VER%"
set "BUILD_CONFIG=%DEFAULT_BUILD_CONFIG%"
set "BUILD_PLATFORM=%DEFAULT_BUILD_PLATFORM%"
set "MSBUILD_TARGET=%DEFAULT_MSBUILD_TARGET%"
set "MAX_FINDINGS=%DEFAULT_MAX_FINDINGS%"
set "BUILD_TIMEOUT_SEC=%DEFAULT_BUILD_TIMEOUT_SEC%"
set "TEST_OUTPUT_DIR="
set "JSON_MODE="
set "RESULT_STATUS=internal_error"
set "BUILD_TIMED_OUT=0"
set "OUTPUT_STALE=0"
set "OUTPUT_MESSAGE="
set "BUILD_TARGET_EXE="
set "BUILD_OUTPUT_PRE_TICKS=0"
set "BUILD_OUTPUT_POST_TICKS=0"
set "MSBUILD_ENV_PROPS="
set "ERRCOUNT=0"
set "WARNCOUNT=0"
set "HINTCOUNT=0"

:parse_args
if "%~1"=="" goto args_done

if /I "%~1"=="-ver" (
  if "%~2"=="" ( echo ERROR: -ver requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "VER=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-config" (
  if /I "%~2"=="Debug" ( set "BUILD_CONFIG=Debug" ) else if /I "%~2"=="Release" ( set "BUILD_CONFIG=Release" ) else (
    echo ERROR: -config must be Debug or Release.& set "EXITCODE=2" & goto usage_fail
  )
  shift & shift & goto parse_args
)
if /I "%~1"=="-platform" (
  if "%~2"=="" ( echo ERROR: -platform requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "BUILD_PLATFORM=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-target" (
  if "%~2"=="" ( echo ERROR: -target requires a value.& set "EXITCODE=2" & goto usage_fail )
  if /I "%~2"=="Build" (
    set "MSBUILD_TARGET=Build"
  ) else if /I "%~2"=="Rebuild" (
    set "MSBUILD_TARGET=Rebuild"
  ) else (
    echo ERROR: -target must be Build or Rebuild.& set "EXITCODE=2" & goto usage_fail
  )
  shift & shift & goto parse_args
)
if /I "%~1"=="-rebuild" (
  set "MSBUILD_TARGET=Rebuild"
  shift & goto parse_args
)
if /I "%~1"=="-max-findings" (
  if "%~2"=="" ( echo ERROR: -max-findings requires a value.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set "TMP_NUM=%~2"
  set "TMP_NONNUM="
  for /f "delims=0123456789" %%A in ("!TMP_NUM!") do set "TMP_NONNUM=%%A"
  if defined TMP_NONNUM ( echo ERROR: -max-findings must be an integer ^>= 1.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set /a TMP_VAL=!TMP_NUM!+0 >nul 2>&1
  if "!TMP_VAL!"=="0" ( echo ERROR: -max-findings must be an integer ^>= 1.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  if !TMP_VAL! LSS 1 ( echo ERROR: -max-findings must be an integer ^>= 1.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set "MAX_FINDINGS=!TMP_VAL!"
  shift & shift & goto parse_args
)
if /I "%~1"=="-build-timeout-sec" (
  if "%~2"=="" ( echo ERROR: -build-timeout-sec requires a value.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set "TMP_NUM=%~2"
  set "TMP_NONNUM="
  for /f "delims=0123456789" %%A in ("!TMP_NUM!") do set "TMP_NONNUM=%%A"
  if defined TMP_NONNUM ( echo ERROR: -build-timeout-sec must be an integer ^>= 0.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set /a TMP_VAL=!TMP_NUM!+0 >nul 2>&1
  if "!TMP_VAL!"=="0" (
    if not "!TMP_NUM!"=="0" ( echo ERROR: -build-timeout-sec must be an integer ^>= 0.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  )
  if !TMP_VAL! LSS 0 ( echo ERROR: -build-timeout-sec must be an integer ^>= 0.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set "BUILD_TIMEOUT_SEC=!TMP_VAL!"
  shift & shift & goto parse_args
)
if /I "%~1"=="-test-output-dir" (
  if "%~2"=="" ( echo ERROR: -test-output-dir requires a value.& set "EXITCODE=2" & set "RESULT_STATUS=invalid" & goto usage_fail )
  set "TEST_OUTPUT_DIR=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-ignore-warnings" (
  if "%~2"=="" ( echo ERROR: -ignore-warnings requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "CLI_BUILD_IGNORE_WARNINGS=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-ignore-hints" (
  if "%~2"=="" ( echo ERROR: -ignore-hints requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "CLI_BUILD_IGNORE_HINTS=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-exclude-path-masks" (
  if "%~2"=="" ( echo ERROR: -exclude-path-masks requires a value.& set "EXITCODE=2" & goto usage_fail )
  set "CLI_BUILD_EXCLUDE_PATH_MASKS=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="-keep-logs" set "KEEP_LOGS=1" & shift & goto parse_args
if /I "%~1"=="-show-warnings-on-success" (
  set "SHOW_WARN_ON_SUCCESS=1"
  set "SHOW_HINT_ON_SUCCESS=1"
  shift & goto parse_args
)
if /I "%~1"=="-show-warnings" set "SHOW_WARN_ON_SUCCESS=1" & shift & goto parse_args
if /I "%~1"=="-show-hints" set "SHOW_HINT_ON_SUCCESS=1" & shift & goto parse_args
if /I "%~1"=="-ai" set "AI_MODE=1" & set "NO_BRAND=1" & shift & goto parse_args
if /I "%~1"=="-json" set "JSON_MODE=1" & set "NO_BRAND=1" & shift & goto parse_args
if /I "%~1"=="-no-brand" set "NO_BRAND=1" & shift & goto parse_args

if not defined PROJECT (
  if exist "%~1" (
    set "PROJECT=%~1"
  ) else if exist "%~dp0%~1" (
    set "PROJECT=%~dp0%~1"
  ) else (
    echo ERROR: Project not found: %~1
    set "EXITCODE=2"
    set "RESULT_STATUS=invalid"
    goto usage_fail
  )
  shift & goto parse_args
)

shift & goto parse_args

:args_done
if not defined PROJECT (
  echo ERROR: No project ^(.dproj^) specified.
  set "EXITCODE=2"
  set "RESULT_STATUS=invalid"
  goto usage_fail
)

for %%p in ("%PROJECT%") do set "PROJECT=%%~fp"

if defined TEST_OUTPUT_DIR (
  for /f "usebackq delims=" %%r in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%TEST_OUTPUT_DIR%'; if([IO.Path]::IsPathRooted($p)){ [IO.Path]::GetFullPath($p) } else { $projDir=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath('%PROJECT%')); [IO.Path]::GetFullPath((Join-Path $projDir $p)) }"`) do set "TEST_OUTPUT_DIR=%%r"
)

rem ---- Choose output root for path normalization
rem Prefer VCS root (.git/.svn) above the target project; fallback to the .dproj directory.
for /f "usebackq delims=" %%r in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[IO.Path]::GetFullPath('%PROJECT%'); $dir=[IO.Path]::GetDirectoryName($p); $cur=$dir; $found=$false; while($cur){ if((Test-Path (Join-Path $cur '.git') -PathType Container) -or (Test-Path (Join-Path $cur '.svn') -PathType Container)){ $found=$true; break }; $parent=[IO.Directory]::GetParent($cur); if($parent -eq $null){ break }; $cur=$parent.FullName }; if(-not $found){ $cur=$dir }; Write-Output $cur"`) do set "ROOT=%%r"
if not defined ROOT for %%d in ("%PROJECT%") do set "ROOT=%%~dpd"

rem ---- Make header stable by showing project path relative to ROOT (when possible)
set "PRJ_NAME=%PROJECT%"
for /f "usebackq delims=" %%r in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$proj=[IO.Path]::GetFullPath('%PROJECT%'); $root=[IO.Path]::GetFullPath('%ROOT%'); if(-not $root.EndsWith('\')){ $root=$root+'\' }; if($proj.ToLower().StartsWith($root.ToLower())){ $proj.Substring($root.Length) } else { $proj }"`) do set "PRJ_NAME=%%r"

rem ---- ASCII header (pipes escaped)
if not defined AI_MODE if not defined JSON_MODE (
  echo +================================================================================+
  echo ^| BUILD   : %PRJ_NAME%
  echo ^| PATH    : %PRJ_NAME%
  echo ^| CONFIG  : %BUILD_CONFIG%    PLATFORM: %BUILD_PLATFORM%    TARGET: %MSBUILD_TARGET%    DELPHI: %VER%
  echo ^| FINDINGS: %MAX_FINDINGS%    TIMEOUT: %BUILD_TIMEOUT_SEC%s
  if defined TEST_OUTPUT_DIR echo ^| OUTDIR  : %TEST_OUTPUT_DIR%
  echo +================================================================================+
  echo.
)

rem ---- Load BuildIgnore lists + madExcept settings (tool defaults + project tree)
set "INI_BUILD_IGNORE_WARNINGS="
set "INI_BUILD_IGNORE_HINTS="
set "INI_BUILD_EXCLUDE_PATH_MASKS="
set "INI_MADEXCEPT_PATH="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$paths=New-Object 'System.Collections.Generic.List[string]'; $toolIni=[IO.Path]::Combine('%~dp0','bin','dak.ini'); if(Test-Path -LiteralPath $toolIni){ $paths.Add([IO.Path]::GetFullPath($toolIni)) }; $proj=[IO.Path]::GetFullPath('%PROJECT%'); $projDir=[IO.Path]::GetDirectoryName($proj); $root=[IO.Path]::GetFullPath('%ROOT%'); $chain=New-Object 'System.Collections.Generic.List[string]'; $cur=$projDir; while($cur){ $chain.Add($cur); if($cur.TrimEnd('\') -ieq $root.TrimEnd('\')){ break }; $parent=[IO.Directory]::GetParent($cur); if($parent -eq $null){ break }; $cur=$parent.FullName }; $chain.Reverse(); foreach($d in $chain){ $ini=[IO.Path]::Combine($d,'dak.ini'); if(Test-Path -LiteralPath $ini){ $paths.Add([IO.Path]::GetFullPath($ini)) } }; $warn=New-Object 'System.Collections.Generic.List[string]'; $hint=New-Object 'System.Collections.Generic.List[string]'; $mask=New-Object 'System.Collections.Generic.List[string]'; $warnSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); $hintSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); $maskSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($ini in $paths){ $section=''; foreach($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue){ $t=$line.Trim(); if(-not $t -or $t.StartsWith(';')){ continue }; if($t -match '^\\[(.+)\\]$'){ $section=$Matches[1]; continue }; if($section -eq 'BuildIgnore'){ $m=[regex]::Match($t,'^(Warnings|Hints|ExcludePathMasks)\\s*=\\s*(.*)$'); if(-not $m.Success){ continue }; $key=$m.Groups[1].Value; $val=$m.Groups[2].Value; foreach($part in $val.Split(';')){ $x=$part.Trim(); if(-not $x){ continue }; if($key -eq 'Warnings'){ if($warnSet.Add($x)){ $warn.Add($x) } } elseif($key -eq 'Hints'){ if($hintSet.Add($x)){ $hint.Add($x) } } else { if($maskSet.Add($x)){ $mask.Add($x) } } } ; continue }; if($section -eq 'ReportFilter'){ $m=[regex]::Match($t,'^ExcludePathMasks\\s*=\\s*(.*)$'); if(-not $m.Success){ continue }; $val=$m.Groups[1].Value; foreach($part in $val.Split(';')){ $x=$part.Trim(); if(-not $x){ continue }; if($maskSet.Add($x)){ $mask.Add($x) } } ; continue } } }; 'INI_BUILD_IGNORE_WARNINGS=' + ($warn -join ';'); 'INI_BUILD_IGNORE_HINTS=' + ($hint -join ';'); 'INI_BUILD_EXCLUDE_PATH_MASKS=' + ($mask -join ';')"`) do set "%%a"
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$paths=New-Object 'System.Collections.Generic.List[string]'; $toolIni=[IO.Path]::Combine('%~dp0','bin','dak.ini'); if(Test-Path -LiteralPath $toolIni){ $paths.Add([IO.Path]::GetFullPath($toolIni)) }; $proj=[IO.Path]::GetFullPath('%PROJECT%'); $projDir=[IO.Path]::GetDirectoryName($proj); $root=[IO.Path]::GetFullPath('%ROOT%'); $chain=New-Object 'System.Collections.Generic.List[string]'; $cur=$projDir; while($cur){ $chain.Add($cur); if($cur.TrimEnd('\') -ieq $root.TrimEnd('\')){ break }; $parent=[IO.Directory]::GetParent($cur); if($parent -eq $null){ break }; $cur=$parent.FullName }; $chain.Reverse(); foreach($d in $chain){ $ini=[IO.Path]::Combine($d,'dak.ini'); if(Test-Path -LiteralPath $ini){ $paths.Add([IO.Path]::GetFullPath($ini)) } }; $mad=''; foreach($ini in $paths){ $section=''; foreach($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue){ $t=$line.Trim(); if(-not $t -or $t.StartsWith(';')){ continue }; if($t -match '^\\[(.+)\\]$'){ $section=$Matches[1]; continue }; if($section -eq 'MadExcept'){ $m=[regex]::Match($t,'^Path\\s*=\\s*(.*)$'); if(-not $m.Success){ continue }; $val=[Environment]::ExpandEnvironmentVariables($m.Groups[1].Value.Trim()); if($val){ if(-not [IO.Path]::IsPathRooted($val)){ $val=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $ini) $val)) }; $mad=$val } } } }; 'INI_MADEXCEPT_PATH=' + $mad"`) do set "%%a"
set "BUILD_IGNORE_WARNINGS=%INI_BUILD_IGNORE_WARNINGS%"
if defined CLI_BUILD_IGNORE_WARNINGS (
  if defined BUILD_IGNORE_WARNINGS (set "BUILD_IGNORE_WARNINGS=%BUILD_IGNORE_WARNINGS%;%CLI_BUILD_IGNORE_WARNINGS%") else set "BUILD_IGNORE_WARNINGS=%CLI_BUILD_IGNORE_WARNINGS%"
)
set "BUILD_IGNORE_HINTS=%INI_BUILD_IGNORE_HINTS%"
if defined CLI_BUILD_IGNORE_HINTS (
  if defined BUILD_IGNORE_HINTS (set "BUILD_IGNORE_HINTS=%BUILD_IGNORE_HINTS%;%CLI_BUILD_IGNORE_HINTS%") else set "BUILD_IGNORE_HINTS=%CLI_BUILD_IGNORE_HINTS%"
)
set "BUILD_EXCLUDE_PATH_MASKS=%INI_BUILD_EXCLUDE_PATH_MASKS%"
if defined CLI_BUILD_EXCLUDE_PATH_MASKS (
  if defined BUILD_EXCLUDE_PATH_MASKS (set "BUILD_EXCLUDE_PATH_MASKS=%BUILD_EXCLUDE_PATH_MASKS%;%CLI_BUILD_EXCLUDE_PATH_MASKS%") else set "BUILD_EXCLUDE_PATH_MASKS=%CLI_BUILD_EXCLUDE_PATH_MASKS%"
)
set "MADEXCEPT_PATH_SETTING=%INI_MADEXCEPT_PATH%"

rem ---- 1) Delphi root
set "BDS_ROOT="
if exist "C:\Program Files (x86)\Embarcadero\Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\Studio\%VER%.0"
) else if exist "C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0"
) else (
  if not defined JSON_MODE (
    call :print_elapsed
    echo FAILED - Delphi %VER%.0 not found
  )
  set "EXITCODE=1"
  set "RESULT_STATUS=internal_error"
  goto cleanup
)
call "%BDS_ROOT%\bin\rsvars.bat"

rem ---- 2) MSBuild
set "MSBUILD="
if exist "%BDS_ROOT%\bin\msbuild.exe" set "MSBUILD=%BDS_ROOT%\bin\msbuild.exe"
if not defined MSBUILD (
  set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
  if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%i in (`
      "%VSWHERE%" -latest -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe"
    `) do if not defined MSBUILD set "MSBUILD=%%i"
  )
)
if not defined MSBUILD if exist "%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe" set "MSBUILD=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe"
if not defined MSBUILD if exist "%WINDIR%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"   set "MSBUILD=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
if not defined MSBUILD (
  if not defined JSON_MODE (
    call :print_elapsed
    echo FAILED - MSBuild.exe not found
  )
  set "EXITCODE=1"
  set "RESULT_STATUS=internal_error"
  goto cleanup
)

rem ---- 2b) Resolve environment.proj properties for command-line MSBuild
set "MSBUILD_ENV_SCRIPT=%~dp0scripts\build-delphi-envprops.ps1"
if exist "%MSBUILD_ENV_SCRIPT%" (
  for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%MSBUILD_ENV_SCRIPT%" -BdsRoot "%BDS_ROOT%"`) do set "%%a"
)

rem ---- 3) Resolve madExcept patch prerequisites + build output path
set "MADEXCEPT_PATCH_REQUIRED=0"
set "MADEXCEPT_PATCH_REASON="
set "MADEXCEPT_DPR="
set "MADEXCEPT_MES="
set "MADEXCEPT_TARGET_EXE="
set "MADEXCEPT_DCC_DEFINE="
set "MADEXCEPT_PATCH_EXE="
set "MADEXCEPT_PATCH_SETTING_INVALID="
set "MADEXCEPT_PROBE_SCRIPT=%~dp0scripts\build-delphi-madexcept-probe.ps1"
if not exist "%MADEXCEPT_PROBE_SCRIPT%" (
  if not defined JSON_MODE (
    call :print_elapsed
    echo FAILED - madExcept probe script not found: %MADEXCEPT_PROBE_SCRIPT%
  )
  set "EXITCODE=1"
  set "RESULT_STATUS=internal_error"
  goto cleanup
)
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%MADEXCEPT_PROBE_SCRIPT%" -Project "%PROJECT%" -Config "%BUILD_CONFIG%" -Platform "%BUILD_PLATFORM%"`) do set "%%a"
set "BUILD_TARGET_EXE=%MADEXCEPT_TARGET_EXE%"
if defined TEST_OUTPUT_DIR (
  if not exist "%TEST_OUTPUT_DIR%" mkdir "%TEST_OUTPUT_DIR%" >nul 2>&1
  if defined BUILD_TARGET_EXE (
    for %%f in ("!BUILD_TARGET_EXE!") do set "BUILD_TARGET_EXE=%TEST_OUTPUT_DIR%\%%~nxf"
  ) else (
    for %%f in ("%PROJECT%") do set "BUILD_TARGET_EXE=%TEST_OUTPUT_DIR%\%%~nf.exe"
  )
  set "MADEXCEPT_TARGET_EXE=!BUILD_TARGET_EXE!"
)
if defined BUILD_TARGET_EXE (
  for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='!BUILD_TARGET_EXE!'; if(Test-Path -LiteralPath $p -PathType Leaf){ (Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks } else { 0 }"`) do set "BUILD_OUTPUT_PRE_TICKS=%%a"
)

if "%MADEXCEPT_PATCH_REQUIRED%"=="1" (
  set "MADEXCEPT_TOOL_SCRIPT=%~dp0scripts\build-delphi-madexcept-resolve-tool.ps1"
  if not exist "!MADEXCEPT_TOOL_SCRIPT!" (
    if not defined JSON_MODE (
      call :print_elapsed
      echo FAILED - madExcept tool resolver script not found: !MADEXCEPT_TOOL_SCRIPT!
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=internal_error"
    goto cleanup
  )
  for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -File "!MADEXCEPT_TOOL_SCRIPT!" -SettingPath "!MADEXCEPT_PATH_SETTING!"`) do set "%%a"

  if defined MADEXCEPT_PATCH_SETTING_INVALID if not defined AI_MODE if not defined JSON_MODE (
    echo WARNING: [MadExcept] Path is set but not found: !MADEXCEPT_PATH_SETTING!
  )

  if not defined MADEXCEPT_PATCH_EXE (
    if defined JSON_MODE (
      rem keep JSON payload as the only stdout output
    ) else if defined AI_MODE (
      echo FAILED. madExcept patch is required but madExceptPatch.exe was not found.
    ) else (
      echo(
      call :print_elapsed
      echo Build FAILED. madExcept patch is required but madExceptPatch.exe was not found.
      echo Set [MadExcept] Path in dak.ini or install madExcept tools.
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=internal_error"
    goto cleanup
  )

  if not defined AI_MODE if not defined JSON_MODE (
    echo madExcept patch enabled.
    echo    dpr : !MADEXCEPT_DPR!
    echo    mes : !MADEXCEPT_MES!
    echo    cli : !MADEXCEPT_PATCH_EXE!
    echo.
  )
) else (
  if not defined AI_MODE if not defined JSON_MODE if defined MADEXCEPT_PATCH_REASON (
    if /I not "%MADEXCEPT_PATCH_REASON%"=="enabled" (
      echo madExcept patch skipped: %MADEXCEPT_PATCH_REASON%.
      echo.
    )
  )
)

rem ---- 4) Logs
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "LOGDIR=%~dp0"
set "FULLLOG=%LOGDIR%build_%TS%.log"
set "OUTLOG=%LOGDIR%out_%TS%.log"
set "ERRLOG=%LOGDIR%errors_%TS%.log"

rem ---- 5) Build
set "ARGS=/t:%MSBUILD_TARGET% /p:Config=%BUILD_CONFIG% /p:Platform=%BUILD_PLATFORM% /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true /p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /nologo /v:m /fl /m"
set "ARGS=!ARGS! /flp:logfile=%FULLLOG%;verbosity=normal"
set "ARGS=!ARGS! /flp1:logfile=%ERRLOG%;errorsonly;verbosity=quiet"
if defined TEST_OUTPUT_DIR (
  set "ARGS=!ARGS! /p:DCC_ExeOutput=""%TEST_OUTPUT_DIR%"" /p:DCC_UnitOutputDirectory=""%TEST_OUTPUT_DIR%"" /p:DCC_BplOutput=""%TEST_OUTPUT_DIR%"" /p:DCC_DcpOutput=""%TEST_OUTPUT_DIR%"""
)
if defined MSBUILD_ENV_PROPS (
  set "ARGS=!ARGS! !MSBUILD_ENV_PROPS!"
)
set "RUN_MSBUILD_SCRIPT=%~dp0scripts\build-delphi-run-msbuild.ps1"
set "MSBUILD_ARGS_FILE=%TEMP%\dak-msbuild-args-%RANDOM%-%RANDOM%.txt"
set "DAK_MSBUILD_ARGS=!ARGS!"
powershell -NoProfile -ExecutionPolicy Bypass -Command "[IO.File]::WriteAllText('%MSBUILD_ARGS_FILE%', [Environment]::GetEnvironmentVariable('DAK_MSBUILD_ARGS'))"
if exist "%RUN_MSBUILD_SCRIPT%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%RUN_MSBUILD_SCRIPT%" -MsBuild "%MSBUILD%" -Project "%PROJECT%" -ArgsFile "%MSBUILD_ARGS_FILE%" -OutLog "%OUTLOG%" -TimeoutSec %BUILD_TIMEOUT_SEC%
  set "RC=%ERRORLEVEL%"
) else (
  cmd /c ""%MSBUILD%" "%PROJECT%" !ARGS! > "%OUTLOG%" 2>&1"
  set "RC=%ERRORLEVEL%"
)
if exist "%MSBUILD_ARGS_FILE%" del /q "%MSBUILD_ARGS_FILE%" >nul 2>&1
if "%RC%"=="124" set "BUILD_TIMED_OUT=1"

rem ---- 6) Detect errors
set "ERRCOUNT=0"
set "HAS_ERRORS="

if "%BUILD_TIMED_OUT%"=="1" (
  set "HAS_ERRORS=1"
  set "ERRCOUNT=1"
)

if exist "%ERRLOG%" for %%A in ("%ERRLOG%") do if %%~zA GTR 0 set "HAS_ERRORS=1"

if not defined HAS_ERRORS if not "%RC%"=="0" (
  for /f %%E in ('findstr /I /C:": error " /C:": fatal " "%OUTLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
  if not "!ERRCOUNT!"=="0" set "HAS_ERRORS=1"
)

if defined HAS_ERRORS (
  if "%BUILD_TIMED_OUT%"=="1" (
    if defined JSON_MODE (
      set "EXITCODE=1"
      set "RESULT_STATUS=timeout"
      goto cleanup
    )
    if defined AI_MODE (
      echo FAILED. Build timed out after %BUILD_TIMEOUT_SEC%s.
      set "EXITCODE=1"
      set "RESULT_STATUS=timeout"
      goto cleanup
    )
    echo(
    call :print_elapsed
    echo Build FAILED. Timed out after %BUILD_TIMEOUT_SEC%s.
    set "EXITCODE=1"
    set "RESULT_STATUS=timeout"
    goto cleanup
  )

  if defined JSON_MODE (
    if "!ERRCOUNT!"=="0" (
      if exist "%ERRLOG%" for /f %%E in ('type "%ERRLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=error"
    goto cleanup
  )

  if defined AI_MODE (
    if exist "%ERRLOG%" (
      if "!ERRCOUNT!"=="0" for /f %%E in ('type "%ERRLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
      echo FAILED. Errors: !ERRCOUNT!
      call :print_errors_top "%ERRLOG%"
    ) else (
      echo FAILED. No error log generated.
      call :print_errors_top "%OUTLOG%"
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=error"
    goto cleanup
  )
  if exist "%ERRLOG%" (
    if "!ERRCOUNT!"=="0" for /f %%E in ('type "%ERRLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
    echo(
    call :print_elapsed
    echo Build FAILED. Errors: !ERRCOUNT!
    call :print_sanitized "%ERRLOG%"
  ) else (
    echo(
    call :print_elapsed
    echo Build FAILED. No error log generated.
    call :print_sanitized "%OUTLOG%"
  )
  set "EXITCODE=1"
  set "RESULT_STATUS=error"
  goto cleanup
)

rem ---- 7) madExcept patch (optional)
if "%MADEXCEPT_PATCH_REQUIRED%"=="1" (
  if not exist "!MADEXCEPT_MES!" (
    if defined JSON_MODE (
      set "EXITCODE=1"
      set "RESULT_STATUS=internal_error"
      goto cleanup
    ) else if defined AI_MODE (
      echo FAILED. madExcept patch is required but .mes file is missing.
    ) else (
      echo(
      call :print_elapsed
      echo Build FAILED. madExcept patch is required but .mes file is missing:
      echo !MADEXCEPT_MES!
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=internal_error"
    goto cleanup
  )

  if not exist "!MADEXCEPT_TARGET_EXE!" (
    for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$target='!MADEXCEPT_TARGET_EXE!'; $proj=[IO.Path]::GetFullPath('%PROJECT%'); $projDir=[IO.Path]::GetDirectoryName($proj); $projParent=[IO.Path]::GetDirectoryName($projDir); $platform='%BUILD_PLATFORM%'; $cfg='%BUILD_CONFIG%'; $dpr='!MADEXCEPT_DPR!'; $names=New-Object 'System.Collections.Generic.List[string]'; function AddName([string]$n){ if(-not [string]::IsNullOrWhiteSpace($n) -and -not $names.Contains($n)){ $names.Add($n) } }; AddName ([IO.Path]::GetFileNameWithoutExtension($target)); AddName ([IO.Path]::GetFileNameWithoutExtension($proj)); AddName ([IO.Path]::GetFileNameWithoutExtension($dpr)); $cands=New-Object 'System.Collections.Generic.List[string]'; function AddCand([string]$p){ if(-not [string]::IsNullOrWhiteSpace($p) -and -not $cands.Contains($p)){ $cands.Add($p) } }; foreach($n in $names){ AddCand (Join-Path $projDir ($n + '.exe')); AddCand (Join-Path $projDir ('bin\' + $n + '.exe')); AddCand (Join-Path $projParent ('bin\' + $n + '.exe')); AddCand (Join-Path $projDir (Join-Path $platform (Join-Path $cfg ($n + '.exe')))); AddCand (Join-Path $projDir (Join-Path $cfg ($n + '.exe'))) }; foreach($c in $cands){ if(Test-Path -LiteralPath $c -PathType Leaf){ Write-Output ([IO.Path]::GetFullPath($c)); exit 0 } }; $all=Get-ChildItem -LiteralPath $projDir -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending; foreach($f in $all){ if($names.Contains([IO.Path]::GetFileNameWithoutExtension($f.Name))){ Write-Output $f.FullName; exit 0 } }"`) do set "MADEXCEPT_TARGET_EXE=%%a"
  )

  if not exist "!MADEXCEPT_TARGET_EXE!" (
    if defined JSON_MODE (
      set "EXITCODE=1"
      set "RESULT_STATUS=internal_error"
      goto cleanup
    ) else if defined AI_MODE (
      echo FAILED. madExcept patch is required but built EXE was not found.
    ) else (
      echo(
      call :print_elapsed
      echo Build FAILED. madExcept patch is required but built EXE was not found.
      echo Expected: !MADEXCEPT_TARGET_EXE!
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=internal_error"
    goto cleanup
  )

  set "MADEXCEPT_PATCH_LOG=%LOGDIR%madexcept_%TS%.log"
  cmd /c ""!MADEXCEPT_PATCH_EXE!" "!MADEXCEPT_TARGET_EXE!" "!MADEXCEPT_MES!" > "!MADEXCEPT_PATCH_LOG!" 2>&1"
  set "MADEXCEPT_RC=!ERRORLEVEL!"
  if not "!MADEXCEPT_RC!"=="0" (
    if defined JSON_MODE (
      set "EXITCODE=1"
      set "RESULT_STATUS=internal_error"
      goto cleanup
    ) else if defined AI_MODE (
      echo FAILED. madExcept patch step failed.
    ) else (
      echo(
      call :print_elapsed
      echo Build FAILED. madExcept patch step failed ^(exit !MADEXCEPT_RC!^).
      echo.
    )
    if exist "!MADEXCEPT_PATCH_LOG!" (
      powershell -NoProfile -ExecutionPolicy Bypass -Command "$max=5; [void][int]::TryParse($env:MAX_FINDINGS, [ref]$max); if($max -lt 1){$max=5}; Get-Content -LiteralPath '!MADEXCEPT_PATCH_LOG!' -ErrorAction SilentlyContinue | Select-Object -First $max"
    )
    set "EXITCODE=1"
    set "RESULT_STATUS=internal_error"
    goto cleanup
  ) else (
    if not defined AI_MODE if not defined JSON_MODE (
      echo madExcept patch applied:
      echo    exe : !MADEXCEPT_TARGET_EXE!
      echo    mes : !MADEXCEPT_MES!
      echo.
    )
  )
)

rem ---- 8) Success
set "WARNCOUNT=0"
set "HINTCOUNT=0"

for /f "usebackq tokens=1,2 delims=," %%w in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; $warn=0; $hint=0; foreach($s in Get-Content -LiteralPath '%OUTLOG%' -ErrorAction SilentlyContinue){ $sn=$s -replace ('(?i)'+$rx),''; $sn=$sn -replace ('(?i)\['+$rx),'['; if(IsExcluded $sn){ continue }; if($sn -match ':\\s+warning\\s+(W\\d+):'){ if(-not $iw.Contains($Matches[1])){ $warn++ } } elseif($sn -match ' hint warning\\s+(H\\d+):'){ if(-not $ih.Contains($Matches[1])){ $hint++ } } elseif($sn -match ':\\s+hint\\s+(H\\d+):'){ if(-not $ih.Contains($Matches[1])){ $hint++ } } }; Write-Output ($warn.ToString() + ',' + $hint.ToString())"` ) do (
  set "WARNCOUNT=%%w"
  set "HINTCOUNT=%%x"
)

if defined BUILD_TARGET_EXE (
  for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='!BUILD_TARGET_EXE!'; if(Test-Path -LiteralPath $p -PathType Leaf){ (Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks } else { 0 }"`) do set "BUILD_OUTPUT_POST_TICKS=%%a"
  for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$post=[int64]'!BUILD_OUTPUT_POST_TICKS!'; $start=[int64]'%BUILD_START_TICKS%'; if(($post -gt 0) -and ($post -lt $start)){ 1 } else { 0 }"`) do set "OUTPUT_STALE=%%a"
  if "%OUTPUT_STALE%"=="1" (
    set "OUTPUT_MESSAGE=Compilation succeeded but output file timestamp was not updated. The executable may be locked by another process."
  )
)

if "%OUTPUT_STALE%"=="1" (
  set "RESULT_STATUS=output_locked"
) else if not "%WARNCOUNT%"=="0" (
  set "RESULT_STATUS=warnings"
) else if not "%HINTCOUNT%"=="0" (
  set "RESULT_STATUS=hints"
) else (
  set "RESULT_STATUS=ok"
)

if defined JSON_MODE (
  set "EXITCODE=0"
  goto cleanup
)

if defined AI_MODE (
  echo SUCCESS. Warnings: !WARNCOUNT!, Hints: !HINTCOUNT!
  if "%OUTPUT_STALE%"=="1" (
    echo WARNING. !OUTPUT_MESSAGE!
  )
  if defined SHOW_WARN_ON_SUCCESS (
    if defined SHOW_HINT_ON_SUCCESS (
      call :print_findings_top "%OUTLOG%"
    ) else (
      call :print_warnings_top "%OUTLOG%"
    )
  ) else if defined SHOW_HINT_ON_SUCCESS (
    call :print_hints_top "%OUTLOG%"
  )
) else (
  if defined SHOW_WARN_ON_SUCCESS (
    if defined SHOW_HINT_ON_SUCCESS (
      call :print_sanitized "%OUTLOG%"
    ) else (
      call :print_sanitized_no_hints "%OUTLOG%"
    )
    echo(
    call :print_elapsed
    echo SUCCESS. Warnings: !WARNCOUNT!, Hints: !HINTCOUNT!
  ) else if defined SHOW_HINT_ON_SUCCESS (
    call :print_sanitized_no_warnings "%OUTLOG%"
    echo(
    call :print_elapsed
    echo SUCCESS. Warnings: !WARNCOUNT!, Hints: !HINTCOUNT!
  ) else (
    call :print_sanitized_filtered "%OUTLOG%"
    echo(
    call :print_elapsed
    echo SUCCESS.
    if "%OUTPUT_STALE%"=="1" (
      echo WARNING. !OUTPUT_MESSAGE!
    )
  )
)

set "EXITCODE=0"
goto cleanup

:usage_fail
if /I "%RESULT_STATUS%"=="internal_error" set "RESULT_STATUS=invalid"
if not defined JSON_MODE (
  echo.
  echo Usage: %~nx0 ^<project.dproj^> [-ver N] [-config Debug^|Release] [-platform Platform] [-target Build^|Rebuild] [-rebuild] [-max-findings N] [-build-timeout-sec N] [-test-output-dir Path] [-json] [-ignore-warnings List] [-ignore-hints List] [-exclude-path-masks List] [-keep-logs] [-ai] [-show-warnings] [-show-hints] [-show-warnings-on-success] [-no-brand]
)
goto cleanup

:print_elapsed
for /f %%t in ('powershell -NoProfile -Command "$s=[datetime]::Parse('%BUILD_START%'); ((Get-Date) - $s).ToString('hh\:mm\:ss\.fff')"') do set "ELAPSED=%%t"
echo done in !ELAPSED!
exit /b 0

:print_warnings_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=5; [void][int]::TryParse($env:MAX_FINDINGS, [ref]$max); if($max -lt 1){$max=5}; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -notmatch ':\s+warning\s+(W\d+):'){ return }; if($iw.Contains($Matches[1])){ return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if(IsExcluded $s){ return }; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_hints_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=5; [void][int]::TryParse($env:MAX_FINDINGS, [ref]$max); if($max -lt 1){$max=5}; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $code=$null; if($s -match ' hint warning\s+(H\d+):'){ $code=$Matches[1] } elseif($s -match ':\s+hint\s+(H\d+):'){ $code=$Matches[1] } else { return }; if($code -and $ih.Contains($code)){ return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if(IsExcluded $s){ return }; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_findings_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=5; [void][int]::TryParse($env:MAX_FINDINGS, [ref]$max); if($max -lt 1){$max=5}; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1])){ return } } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1])){ return } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1])){ return } } else { return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if(IsExcluded $s){ return }; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_errors_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=5; [void][int]::TryParse($env:MAX_FINDINGS, [ref]$max); if($max -lt 1){$max=5}; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -match ':\s+error ' -or $s -match ':\s+fatal '){ $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); $s } } | Select-Object -First $max"
endlocal & exit /b 0

:print_sanitized
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_no_hints
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ' hint warning ' -or $s -match ':\s+hint ') { } elseif($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_no_warnings
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $ex=@(); foreach($x in '%BUILD_EXCLUDE_PATH_MASKS%'.Split(';')){ $t=$x.Trim(); if($t){ $ex += (($t -replace '/', '\\').TrimStart('.','\')) } }; function IsExcluded([string]$line){ if($ex.Count -eq 0){ return $false }; $m=[regex]::Match($line, '^(?<f>.+?)\(\d+'); if(-not $m.Success){ return $false }; $f=($m.Groups['f'].Value -replace '/', '\\').Trim(); $f=$f.TrimStart('.','\'); foreach($p in $ex){ if($f -like $p){ return $true } }; return $false }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s=[regex]::Replace($s, '^[A-Za-z]:\\(?:[^\\]+\\)*([^\\]+\([^\\)]*\):)', '$1'); if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif(($s -match ':\s+warning ') -and -not ($s -match ' hint warning ')) { } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1]) -or (IsExcluded $s)){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_filtered
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ':\s+warning ' -or $s -match ' hint warning ' -or $s -match ':\s+hint ') { } else { $s } }"
endlocal & exit /b 0

:cleanup
if defined JSON_MODE (
  set "JSON_INCLUDE_WARN=0"
  set "JSON_INCLUDE_HINT=0"
  if defined SHOW_WARN_ON_SUCCESS set "JSON_INCLUDE_WARN=1"
  if defined SHOW_HINT_ON_SUCCESS set "JSON_INCLUDE_HINT=1"
  set "JSON_SCRIPT=%~dp0scripts\build-delphi-emit-json.ps1"
  if exist "!JSON_SCRIPT!" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!JSON_SCRIPT!" -Project "%PROJECT%" -Config "%BUILD_CONFIG%" -Platform "%BUILD_PLATFORM%" -Target "%MSBUILD_TARGET%" -ExitCode %EXITCODE% -ErrorCount %ERRCOUNT% -WarningCount %WARNCOUNT% -HintCount %HINTCOUNT% -MaxFindings %MAX_FINDINGS% -BuildStart "%BUILD_START%" -OutputPath "!BUILD_TARGET_EXE!" -OutputStale "%OUTPUT_STALE%" -OutputMessage "!OUTPUT_MESSAGE!" -OutLog "%OUTLOG%" -ErrLog "%ERRLOG%" -IncludeWarnings "!JSON_INCLUDE_WARN!" -IncludeHints "!JSON_INCLUDE_HINT!" -TimedOut "%BUILD_TIMED_OUT%" -Status "%RESULT_STATUS%"
  ) else (
    echo {"status":"internal_error","error":"JSON emitter script missing"} 
  )
)
if defined KEEP_LOGS (
  if not defined JSON_MODE echo (Logs kept due to -keep-logs^)
) else (
  if defined FULLLOG if exist "%FULLLOG%" del /q "%FULLLOG%" >nul 2>&1
  if defined OUTLOG  if exist "%OUTLOG%"  del /q "%OUTLOG%"  >nul 2>&1
  if defined ERRLOG  if exist "%ERRLOG%"  del /q "%ERRLOG%"  >nul 2>&1
  if defined MADEXCEPT_PATCH_LOG if exist "%MADEXCEPT_PATCH_LOG%" del /q "%MADEXCEPT_PATCH_LOG%" >nul 2>&1
)
set "code=%EXITCODE%"
popd
endlocal & exit /b %code%
