unit Dak.Build.Types;

interface

type
  TBuildSummaryOptions = record
    fProjectRoot: string;
    fIgnoreWarnings: string;
    fIgnoreHints: string;
    fExcludePathMasks: string;
    fMaxFindings: Integer;
    fIncludeWarnings: Boolean;
    fIncludeHints: Boolean;
  end;

  TBuildSummary = record
    fStatus: string;
    fExitCode: Integer;
    fErrorCount: Integer;
    fWarningCount: Integer;
    fHintCount: Integer;
    fErrors: TArray<string>;
    fErrorsRaw: TArray<string>;
    fWarnings: TArray<string>;
    fWarningsRaw: TArray<string>;
    fHints: TArray<string>;
    fHintsRaw: TArray<string>;
    fOutputPath: string;
    fOutputStale: Boolean;
    fOutputMessage: string;
    fTimedOut: Boolean;
  end;

  IBuildProcessRunner = interface
    ['{98F53F02-06E8-4684-9316-B5472C4FD666}']
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      aTimeoutSec: Integer; out aExitCode: Integer; out aTimedOut: Boolean; out aError: string): Boolean;
  end;

implementation

end.
