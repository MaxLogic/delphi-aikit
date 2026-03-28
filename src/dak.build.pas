unit Dak.Build;

interface

uses
  Dak.Build.Types, Dak.Types;

type
  TBuildSummaryOptions = Dak.Build.Types.TBuildSummaryOptions;
  TBuildSummary = Dak.Build.Types.TBuildSummary;
  IBuildProcessRunner = Dak.Build.Types.IBuildProcessRunner;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;
function TryRunBuild(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean; overload;
function TryRunBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean; overload;

implementation

uses
  Dak.Build.Runner, Dak.Build.Summary;

function ParseBuildLogs(const aOutLogPath, aErrLogPath: string;
  const aOptions: TBuildSummaryOptions): TBuildSummary;
begin
  Result := Dak.Build.Summary.ParseBuildLogs(aOutLogPath, aErrLogPath, aOptions);
end;

function BuildSummaryAsJson(const aProjectPath: string; const aOptions: TAppOptions;
  const aSummary: TBuildSummary; const aTarget: string; aTimeMs: Int64): string;
begin
  Result := Dak.Build.Summary.BuildSummaryAsJson(aProjectPath, aOptions, aSummary, aTarget, aTimeMs);
end;

function TryRunBuild(const aOptions: TAppOptions; out aExitCode: Integer; out aError: string): Boolean;
begin
  Result := Dak.Build.Runner.TryRunBuildInternal(aOptions, aExitCode, aError);
end;

function TryRunBuild(const aOptions: TAppOptions; const aRunner: IBuildProcessRunner;
  out aExitCode: Integer; out aError: string): Boolean;
begin
  Result := Dak.Build.Runner.TryRunBuildInternal(aOptions, aRunner, aExitCode, aError);
end;

end.
