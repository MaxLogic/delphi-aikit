# Unattended crash reports

Set `MAXLOGIC_MADEXCEPT_AI=1` for a DAK process run by an agent, CI job, or script. In madExcept-enabled builds, DAK removes a stale `bugreport.txt` beside the executable at startup. If an exception reaches the registered madExcept handler, DAK writes a fresh report there and exits with code 207. The report includes the exception and DAK call stack. The exception and please-wait windows are suppressed for that run.

For example, in PowerShell:

```powershell
$env:MAXLOGIC_MADEXCEPT_AI = '1'
& .\DelphiAIKit.exe --help
```

Leave the variable unset for normal interactive madExcept settings. A healthy run with the opt-in set exits normally and leaves no `bugreport.txt`. The deliberate `DAK_TEST_UNHANDLED_EXCEPTION` crash entry exists only in Debug builds and requires the AI opt-in; it is for focused verification, not normal commands.
