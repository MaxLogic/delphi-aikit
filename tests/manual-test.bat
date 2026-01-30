@echo off
setlocal EnableExtensions
set "ROOT=F:\projects\MaxLogic\DelphiConfigResolver"
set "DAK=%ROOT%\bin\DelphiAIKit.exe"
set "PALCMD="C:\Program Files\Peganza\Pascal Analyzer 9\palcmd.exe""
set "PA_THREADS=1"
if defined NUMBER_OF_PROCESSORS set "PA_THREADS=%NUMBER_OF_PROCESSORS%"
set /a PA_THREADS=PA_THREADS
if %PA_THREADS% LSS 1 set "PA_THREADS=1"
if %PA_THREADS% GTR 64 set "PA_THREADS=64"

if exist "%ROOT%\_dak_pa_main" rmdir /S /Q "%ROOT%\_dak_pa_main"
if exist "%ROOT%\_dak_pa_tests" rmdir /S /Q "%ROOT%\_dak_pa_tests"
if exist "%ROOT%\_dak_pa_unit" rmdir /S /Q "%ROOT%\_dak_pa_unit"
if exist "%ROOT%\_palcmd_test" rmdir /S /Q "%ROOT%\_palcmd_test"

echo ============================================================
echo DAK analyze - main dproj
echo ============================================================
"%DAK%" analyze --project "%ROOT%\projects\DelphiAIKit.dproj" --platform Win32 --config Release --delphi 23.0 --fixinsight false --pascal-analyzer true --out "%ROOT%\_dak_pa_main" --log-file "%ROOT%\_dak_pa_main\diagnostics.log" --log-tee true
echo Exit=%ERRORLEVEL%
if exist "%ROOT%\_dak_pa_main\run.log" type "%ROOT%\_dak_pa_main\run.log"
if exist "%ROOT%\_dak_pa_main\pascal-analyzer\pascal-analyzer.log" type "%ROOT%\_dak_pa_main\pascal-analyzer\pascal-analyzer.log"

echo ============================================================
echo DAK analyze - tests dproj
echo ============================================================
"%DAK%" analyze --project "%ROOT%\tests\DelphiAIKit.Tests.dproj" --platform Win32 --config Debug --delphi 23.0 --fixinsight false --pascal-analyzer true --out "%ROOT%\_dak_pa_tests" --log-file "%ROOT%\_dak_pa_tests\diagnostics.log" --log-tee true
echo Exit=%ERRORLEVEL%
if exist "%ROOT%\_dak_pa_tests\run.log" type "%ROOT%\_dak_pa_tests\run.log"
if exist "%ROOT%\_dak_pa_tests\pascal-analyzer\pascal-analyzer.log" type "%ROOT%\_dak_pa_tests\pascal-analyzer\pascal-analyzer.log"

echo ============================================================
echo DAK analyze - single unit
echo ============================================================
"%DAK%" analyze --unit "%ROOT%\src\dak.types.pas" --delphi 23.0 --pascal-analyzer true --out "%ROOT%\_dak_pa_unit" --pa-args "/CD11W32 /F=X /Q /A+ /FA /T=%PA_THREADS%"
echo Exit=%ERRORLEVEL%
if exist "%ROOT%\_dak_pa_unit\run.log" type "%ROOT%\_dak_pa_unit\run.log"
if exist "%ROOT%\_dak_pa_unit\pascal-analyzer\pascal-analyzer.log" type "%ROOT%\_dak_pa_unit\pascal-analyzer\pascal-analyzer.log"

echo ============================================================
echo Direct PALCMD - main dproj
echo ============================================================
%PALCMD% "%ROOT%\projects\DelphiAIKit.dproj" /CD11W32 /BUILD=Release /R="%ROOT%\_palcmd_test\main" /F=X /Q /A+ /FA /T=%PA_THREADS%
echo Exit=%ERRORLEVEL%

echo ============================================================
echo Direct PALCMD - tests dproj
echo ============================================================
%PALCMD% "%ROOT%\tests\DelphiAIKit.Tests.dproj" /CD11W32 /BUILD=Debug /R="%ROOT%\_palcmd_test\tests" /F=X /Q /A+ /FA /T=%PA_THREADS%
echo Exit=%ERRORLEVEL%

echo ============================================================
echo Direct PALCMD - single unit
echo ============================================================
%PALCMD% "%ROOT%\src\dak.types.pas" /CD11W32 /FM /F=X /Q /R="%ROOT%\_palcmd_test\unit"
echo Exit=%ERRORLEVEL%

endlocal
