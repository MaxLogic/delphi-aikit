unit Dak.Build.Types;

interface

uses
  Dak.Types;

type
  TBuildDiagnostic = record
    fSeverity: string;
    fRawLine: string;
    fNormalizedLine: string;
    fFileToken: string;
    fLine: Integer;
    fColumn: Integer;
    fCode: string;
    fMessage: string;
  end;

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
    fErrorDiagnostics: TArray<TBuildDiagnostic>;
    fWarnings: TArray<string>;
    fWarningsRaw: TArray<string>;
    fWarningDiagnostics: TArray<TBuildDiagnostic>;
    fHints: TArray<string>;
    fHintsRaw: TArray<string>;
    fHintDiagnostics: TArray<TBuildDiagnostic>;
    fOutputPath: string;
    fOutputStale: Boolean;
    fOutputMessage: string;
    fTimedOut: Boolean;
  end;

  IBuildProcessRunner = interface
    ['{98F53F02-06E8-4684-9316-B5472C4FD666}']
    function RunProcess(const aExePath, aArguments, aWorkDir, aStdOutPath, aStdErrPath: string;
      const aEnvironmentBlock: string; aTimeoutSec: Integer; out aExitCode: Integer;
      out aTimedOut: Boolean; out aError: string): Boolean;
  end;

  TBuildDfmCheckRunner = reference to function(const aOptions: TAppOptions): Integer;

implementation

end.
