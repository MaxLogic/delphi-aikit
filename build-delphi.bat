@echo off
REM Script Version 3

chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
pushd "%~dp0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format o"') do set "BUILD_START=%%t"

rem =============================================================================
rem v 1.4.5
rem =============================================================================

rem ---- CONFIG (avoid rsvars collisions)
set "DEFAULT_VER=23"
set "DEFAULT_BUILD_CONFIG=Release"
set "DEFAULT_BUILD_PLATFORM=Win32"

set "ROOT="
set "EXITCODE=0"

set "PROJECT="
set "VER=%DEFAULT_VER%"
set "BUILD_CONFIG=%DEFAULT_BUILD_CONFIG%"
set "BUILD_PLATFORM=%DEFAULT_BUILD_PLATFORM%"

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
if /I "%~1"=="-keep-logs" set "KEEP_LOGS=1" & shift & goto parse_args
if /I "%~1"=="-show-warnings-on-success" (
  set "SHOW_WARN_ON_SUCCESS=1"
  set "SHOW_HINT_ON_SUCCESS=1"
  shift & goto parse_args
)
if /I "%~1"=="-show-warnings" set "SHOW_WARN_ON_SUCCESS=1" & shift & goto parse_args
if /I "%~1"=="-show-hints" set "SHOW_HINT_ON_SUCCESS=1" & shift & goto parse_args
if /I "%~1"=="-ai" set "AI_MODE=1" & set "NO_BRAND=1" & shift & goto parse_args
if /I "%~1"=="-no-brand" set "NO_BRAND=1" & shift & goto parse_args

if not defined PROJECT (
  if exist "%~1" (
    set "PROJECT=%~1"
  ) else if exist "%~dp0%~1" (
    set "PROJECT=%~dp0%~1"
  ) else (
    echo ERROR: Project not found: %~1
    set "EXITCODE=2"
    goto usage_fail
  )
  shift & goto parse_args
)

shift & goto parse_args

:args_done
if not defined PROJECT (
  echo ERROR: No project ^(.dproj^) specified.
  set "EXITCODE=2"
  goto usage_fail
)

for %%p in ("%PROJECT%") do set "PROJECT=%%~fp"

rem ---- Choose output root for path normalization
rem Prefer VCS root (.git/.svn) above the target project; fallback to the .dproj directory.
for /f "usebackq delims=" %%r in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p=[IO.Path]::GetFullPath('%PROJECT%'); $dir=[IO.Path]::GetDirectoryName($p); $cur=$dir; $found=$false; while($cur){ if((Test-Path (Join-Path $cur '.git') -PathType Container) -or (Test-Path (Join-Path $cur '.svn') -PathType Container)){ $found=$true; break }; $parent=[IO.Directory]::GetParent($cur); if($parent -eq $null){ break }; $cur=$parent.FullName }; if(-not $found){ $cur=$dir }; Write-Output $cur"`) do set "ROOT=%%r"
if not defined ROOT for %%d in ("%PROJECT%") do set "ROOT=%%~dpd"

rem ---- Make header stable by showing project path relative to ROOT (when possible)
set "PRJ_NAME=%PROJECT%"
for /f "usebackq delims=" %%r in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$proj=[IO.Path]::GetFullPath('%PROJECT%'); $root=[IO.Path]::GetFullPath('%ROOT%'); if(-not $root.EndsWith('\')){ $root=$root+'\' }; if($proj.ToLower().StartsWith($root.ToLower())){ $proj.Substring($root.Length) } else { $proj }"`) do set "PRJ_NAME=%%r"

rem ---- ASCII header (pipes escaped)
if not defined AI_MODE (
  echo +================================================================================+
  echo ^| BUILD   : %PRJ_NAME%
  echo ^| PATH    : %PRJ_NAME%
  echo ^| CONFIG  : %BUILD_CONFIG%    PLATFORM: %BUILD_PLATFORM%    DELPHI: %VER%
  echo +================================================================================+
  echo.
)

rem ---- Load BuildIgnore lists (tool defaults + project tree)
set "INI_BUILD_IGNORE_WARNINGS="
set "INI_BUILD_IGNORE_HINTS="
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$paths=New-Object 'System.Collections.Generic.List[string]'; $toolIni=[IO.Path]::Combine('%~dp0','bin','dak.ini'); if(Test-Path -LiteralPath $toolIni){ $paths.Add([IO.Path]::GetFullPath($toolIni)) }; $proj=[IO.Path]::GetFullPath('%PROJECT%'); $projDir=[IO.Path]::GetDirectoryName($proj); $root=[IO.Path]::GetFullPath('%ROOT%'); $chain=New-Object 'System.Collections.Generic.List[string]'; $cur=$projDir; while($cur){ $chain.Add($cur); if($cur.TrimEnd('\') -ieq $root.TrimEnd('\')){ break }; $parent=[IO.Directory]::GetParent($cur); if($parent -eq $null){ break }; $cur=$parent.FullName }; $chain.Reverse(); foreach($d in $chain){ $ini=[IO.Path]::Combine($d,'dak.ini'); if(Test-Path -LiteralPath $ini){ $paths.Add([IO.Path]::GetFullPath($ini)) } }; $warn=New-Object 'System.Collections.Generic.List[string]'; $hint=New-Object 'System.Collections.Generic.List[string]'; $warnSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); $hintSet=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($ini in $paths){ $section=''; foreach($line in Get-Content -LiteralPath $ini -ErrorAction SilentlyContinue){ $t=$line.Trim(); if(-not $t -or $t.StartsWith(';')){ continue }; if($t -match '^\\[(.+)\\]$'){ $section=$Matches[1]; continue }; if($section -ne 'BuildIgnore'){ continue }; $m=[regex]::Match($t,'^(Warnings|Hints)\\s*=\\s*(.*)$'); if(-not $m.Success){ continue }; $key=$m.Groups[1].Value; $val=$m.Groups[2].Value; foreach($part in $val.Split(';')){ $x=$part.Trim(); if(-not $x){ continue }; if($key -eq 'Warnings'){ if($warnSet.Add($x)){ $warn.Add($x) } } else { if($hintSet.Add($x)){ $hint.Add($x) } } } } }; 'INI_BUILD_IGNORE_WARNINGS=' + ($warn -join ';'); 'INI_BUILD_IGNORE_HINTS=' + ($hint -join ';')"`) do set "%%a"
set "BUILD_IGNORE_WARNINGS=%INI_BUILD_IGNORE_WARNINGS%"
if defined CLI_BUILD_IGNORE_WARNINGS (
  if defined BUILD_IGNORE_WARNINGS (set "BUILD_IGNORE_WARNINGS=%BUILD_IGNORE_WARNINGS%;%CLI_BUILD_IGNORE_WARNINGS%") else set "BUILD_IGNORE_WARNINGS=%CLI_BUILD_IGNORE_WARNINGS%"
)
set "BUILD_IGNORE_HINTS=%INI_BUILD_IGNORE_HINTS%"
if defined CLI_BUILD_IGNORE_HINTS (
  if defined BUILD_IGNORE_HINTS (set "BUILD_IGNORE_HINTS=%BUILD_IGNORE_HINTS%;%CLI_BUILD_IGNORE_HINTS%") else set "BUILD_IGNORE_HINTS=%CLI_BUILD_IGNORE_HINTS%"
)

rem ---- 1) Delphi root
set "BDS_ROOT="
if exist "C:\Program Files (x86)\Embarcadero\Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\Studio\%VER%.0"
) else if exist "C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0\bin\rsvars.bat" (
  set "BDS_ROOT=C:\Program Files (x86)\Embarcadero\RAD Studio\%VER%.0"
) else (
  call :print_elapsed
  echo FAILED - Delphi %VER%.0 not found
  set "EXITCODE=1"
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
  call :print_elapsed
  echo FAILED - MSBuild.exe not found
  set "EXITCODE=1"
  goto cleanup
)

rem ---- 3) Logs
for /f %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TS=%%i"
set "LOGDIR=%~dp0"
set "FULLLOG=%LOGDIR%build_%TS%.log"
set "OUTLOG=%LOGDIR%out_%TS%.log"
set "ERRLOG=%LOGDIR%errors_%TS%.log"

rem ---- 4) Build
set "ARGS=/t:Build /p:Config=%BUILD_CONFIG% /p:Platform=%BUILD_PLATFORM% /p:DCC_Quiet=true /p:DCC_UseMSBuildExternally=true /p:DCC_UseResponseFile=1 /p:DCC_UseCommandFile=1 /nologo /v:m /fl /m"
set "ARGS=%ARGS% /flp:logfile=%FULLLOG%;verbosity=normal"
set "ARGS=%ARGS% /flp1:logfile=%ERRLOG%;errorsonly;verbosity=quiet"

cmd /c ""%MSBUILD%" "%PROJECT%" %ARGS% > "%OUTLOG%" 2>&1"
set "RC=%ERRORLEVEL%"

rem ---- 5) Detect errors
set "ERRCOUNT=0"
set "HAS_ERRORS="

if exist "%ERRLOG%" for %%A in ("%ERRLOG%") do if %%~zA GTR 0 set "HAS_ERRORS=1"

if not defined HAS_ERRORS if not "%RC%"=="0" (
  for /f %%E in ('findstr /I /C:": error " /C:": fatal " "%OUTLOG%" ^| find /c /v ""') do set "ERRCOUNT=%%E"
  if not "!ERRCOUNT!"=="0" set "HAS_ERRORS=1"
)

if defined HAS_ERRORS (
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
  goto cleanup
)

rem ---- 6) Success
set "WARNCOUNT=0"
set "HINTCOUNT=0"

for /f "usebackq tokens=1,2 delims=," %%w in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; $warn=0; $hint=0; foreach($s in Get-Content -LiteralPath '%OUTLOG%' -ErrorAction SilentlyContinue){ if($s -match ':\s+warning\s+(W\d+):'){ if(-not $iw.Contains($Matches[1])){ $warn++ } } elseif($s -match ' hint warning\s+(H\d+):'){ if(-not $ih.Contains($Matches[1])){ $hint++ } } elseif($s -match ':\s+hint\s+(H\d+):'){ if(-not $ih.Contains($Matches[1])){ $hint++ } } }; Write-Output ($warn.ToString() + ',' + $hint.ToString())"` ) do (
  set "WARNCOUNT=%%w"
  set "HINTCOUNT=%%x"
)

if defined AI_MODE (
  echo SUCCESS. Warnings: !WARNCOUNT!, Hints: !HINTCOUNT!
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
  )
)

set "EXITCODE=0"
goto cleanup

:usage_fail
echo.
echo Usage: %~nx0 ^<project.dproj^> [-ver N] [-config Debug^|Release] [-platform Platform] [-ignore-warnings List] [-ignore-hints List] [-keep-logs] [-ai] [-show-warnings] [-show-hints] [-show-warnings-on-success] [-no-brand]
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
  "$max=50; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -notmatch ':\s+warning\s+(W\d+):'){ return }; if($iw.Contains($Matches[1])){ return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_hints_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=50; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $code=$null; if($s -match ' hint warning\s+(H\d+):'){ $code=$Matches[1] } elseif($s -match ':\s+hint\s+(H\d+):'){ $code=$Matches[1] } else { return }; if($code -and $ih.Contains($code)){ return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_findings_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=50; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1])){ return } } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1])){ return } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1])){ return } } else { return }; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s } | Select-Object -First $max"
endlocal & exit /b 0

:print_errors_top
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$max=50; $root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; if($s -match ':\s+error ' -or $s -match ':\s+fatal '){ $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; $s } } | Select-Object -First $max"
endlocal & exit /b 0

:print_sanitized
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1])){ } else { $s } } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1])){ } else { $s } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1])){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_no_hints
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $iw=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_WARNINGS%'.Split(';')){ $t=$x.Trim(); if($t){ $iw.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ' hint warning ' -or $s -match ':\s+hint ') { } elseif($s -match ':\s+warning\s+(W\d+):'){ if($iw.Contains($Matches[1])){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_no_warnings
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; $ih=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase); foreach($x in '%BUILD_IGNORE_HINTS%'.Split(';')){ $t=$x.Trim(); if($t){ $ih.Add($t) | Out-Null } }; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif(($s -match ':\s+warning ') -and -not ($s -match ' hint warning ')) { } elseif($s -match ' hint warning\s+(H\d+):'){ if($ih.Contains($Matches[1])){ } else { $s } } elseif($s -match ':\s+hint\s+(H\d+):'){ if($ih.Contains($Matches[1])){ } else { $s } } else { $s } }"
endlocal & exit /b 0

:print_sanitized_filtered
set "PFILE=%~1"
if not exist "%PFILE%" exit /b 0
setlocal DisableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$root=[IO.Path]::GetFullPath('%ROOT%')+'\'; $rx=[regex]::Escape($root); $nobrand=$env:NO_BRAND -ne $null; Get-Content -LiteralPath '%PFILE%' | ForEach-Object { $s=$_; $s=$s -replace ('(?i)'+$rx),''; $s=$s -replace ('(?i)\['+$rx),'['; if($nobrand -and ($s -match '^(Embarcadero\s+Delphi\b|Copyright\s*\(c\))')) { } elseif($s -match ':\s+warning ' -or $s -match ' hint warning ' -or $s -match ':\s+hint ') { } else { $s } }"
endlocal & exit /b 0

:cleanup
if defined KEEP_LOGS (
  echo (Logs kept due to -keep-logs^)
) else (
  if defined FULLLOG if exist "%FULLLOG%" del /q "%FULLLOG%" >nul 2>&1
  if defined OUTLOG  if exist "%OUTLOG%"  del /q "%OUTLOG%"  >nul 2>&1
  if defined ERRLOG  if exist "%ERRLOG%"  del /q "%ERRLOG%"  >nul 2>&1
)
set "code=%EXITCODE%"
popd
endlocal & exit /b %code%
