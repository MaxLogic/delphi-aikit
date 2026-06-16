unit Dak.SourceContext;

interface

uses
  DelphiSemantics.ProjectContext, DelphiSemantics.SourceContext,
  Dak.Types;

type
  TSourceContextRunCache = class
  private
    fCache: TDelphiSemanticSourceContextCache;
    fProject: TDelphiSemanticProjectInfo;
  public
    constructor Create(const aLookup: TProjectSourceLookup); overload;
    constructor Create; overload;
    destructor Destroy; override;
    function TryResolve(const aFileToken: string; aLineNumber, aContextLines: Integer;
      out aContext: TSourceContextSnippet; out aError: string): Boolean;
    function TryResolveCandidate(const aFinding: string; aContextLines: Integer;
      out aContext: TSourceContextSnippet; out aToken: string; out aEnclosingSymbol: string;
      out aError: string): Boolean; overload;
    function TryResolveCandidate(const aFileToken: string; aLineNumber, aColumn, aContextLines: Integer;
      const aCandidateText: string; out aContext: TSourceContextSnippet; out aToken: string;
      out aEnclosingSymbol: string; out aError: string): Boolean; overload;
  end;

function ShouldEmitSourceContext(const aMode: TSourceContextMode; const aIsError: Boolean): Boolean;
function TryParseFindingLocation(const aFinding: string; out aFileToken: string; out aLineNumber: Integer): Boolean;
function TryParseFindingLocationWithColumn(const aFinding: string; out aFileToken: string; out aLineNumber,
  aColNumber: Integer): Boolean;
function TryResolveSourceContext(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFinding: string;
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aToken: string; out aEnclosingSymbol: string;
  out aError: string): Boolean; overload;
function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aColumn, aContextLines: Integer; const aCandidateText: string; out aContext: TSourceContextSnippet;
  out aToken: string; out aEnclosingSymbol: string; out aError: string): Boolean; overload;
function TryReadSourceContext(const aFilePath: string; aLineNumber, aContextLines: Integer;
  out aContext: TSourceContextSnippet; out aError: string): Boolean;
function FormatSourceContextLines(const aContext: TSourceContextSnippet): TArray<string>;

implementation

function ShouldEmitSourceContext(const aMode: TSourceContextMode; const aIsError: Boolean): Boolean;
begin
  case aMode of
    TSourceContextMode.scmOff:
      Result := False;
    TSourceContextMode.scmOn:
      Result := True;
  else
    Result := aIsError;
  end;
end;

function ProjectFromLookup(const aLookup: TProjectSourceLookup): TDelphiSemanticProjectInfo;
begin
  Result := Default(TDelphiSemanticProjectInfo);
  Result.ProjectFileName := aLookup.fProjectDproj;
  Result.ProjectDirectory := aLookup.fProjectDir;
  Result.MainSourceFileName := aLookup.fMainSourcePath;
  Result.Defines := aLookup.fDefines;
  Result.SearchPaths := aLookup.fSearchPaths;
end;

function DakSnippet(const aContext: TDelphiSemanticSourceContextSnippet): TSourceContextSnippet;
begin
  Result.fFilePath := aContext.FileName;
  Result.fTargetLine := aContext.TargetLine;
  Result.fStartLine := aContext.StartLine;
  Result.fLines := aContext.Lines;
end;

function SemanticSnippet(const aContext: TSourceContextSnippet): TDelphiSemanticSourceContextSnippet;
begin
  Result.FileName := aContext.fFilePath;
  Result.TargetLine := aContext.fTargetLine;
  Result.StartLine := aContext.fStartLine;
  Result.Lines := aContext.fLines;
end;

constructor TSourceContextRunCache.Create(const aLookup: TProjectSourceLookup);
begin
  inherited Create;
  fCache := TDelphiSemanticSourceContextCache.Create;
  fProject := ProjectFromLookup(aLookup);
end;

constructor TSourceContextRunCache.Create;
begin
  inherited Create;
  fCache := TDelphiSemanticSourceContextCache.Create;
  fProject := Default(TDelphiSemanticProjectInfo);
end;

destructor TSourceContextRunCache.Destroy;
begin
  fCache.Free;
  inherited;
end;

function TSourceContextRunCache.TryResolve(const aFileToken: string; aLineNumber,
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
var
  lContext: TDelphiSemanticSourceContextSnippet;
begin
  aContext := Default(TSourceContextSnippet);
  Result := TDelphiSemanticSourceContext.TryResolve(fProject, aFileToken, aLineNumber,
    aContextLines, fCache, lContext, aError);
  if Result then
    aContext := DakSnippet(lContext);
end;

function TSourceContextRunCache.TryResolveCandidate(const aFinding: string;
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aToken: string;
  out aEnclosingSymbol: string; out aError: string): Boolean;
var
  lContext: TDelphiSemanticSourceContextSnippet;
begin
  aContext := Default(TSourceContextSnippet);
  Result := TDelphiSemanticSourceContext.TryResolveCandidate(fProject, aFinding,
    aContextLines, fCache, lContext, aToken, aEnclosingSymbol, aError);
  if Result then
    aContext := DakSnippet(lContext);
end;

function TSourceContextRunCache.TryResolveCandidate(const aFileToken: string; aLineNumber, aColumn,
  aContextLines: Integer; const aCandidateText: string; out aContext: TSourceContextSnippet; out aToken: string;
  out aEnclosingSymbol: string; out aError: string): Boolean;
var
  lContext: TDelphiSemanticSourceContextSnippet;
begin
  aContext := Default(TSourceContextSnippet);
  Result := TDelphiSemanticSourceContext.TryResolveCandidate(fProject, aFileToken, aLineNumber, aColumn,
    aContextLines, aCandidateText, fCache, lContext, aToken, aEnclosingSymbol, aError);
  if Result then
    aContext := DakSnippet(lContext);
end;

function TryParseFindingLocation(const aFinding: string; out aFileToken: string; out aLineNumber: Integer): Boolean;
var
  lColNumber: Integer;
begin
  Result := TryParseFindingLocationWithColumn(aFinding, aFileToken, aLineNumber, lColNumber);
end;

function TryParseFindingLocationWithColumn(const aFinding: string; out aFileToken: string; out aLineNumber,
  aColNumber: Integer): Boolean;
begin
  Result := TDelphiSemanticSourceContext.TryParseFindingLocationWithColumn(aFinding,
    aFileToken, aLineNumber, aColNumber);
end;

function TryResolveSourceContext(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aContextLines: Integer; out aContext: TSourceContextSnippet; out aError: string): Boolean;
var
  lCache: TSourceContextRunCache;
begin
  lCache := TSourceContextRunCache.Create(aLookup);
  try
    Result := lCache.TryResolve(aFileToken, aLineNumber, aContextLines, aContext, aError);
  finally
    lCache.Free;
  end;
end;

function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFinding: string;
  aContextLines: Integer; out aContext: TSourceContextSnippet; out aToken: string; out aEnclosingSymbol: string;
  out aError: string): Boolean;
var
  lCache: TSourceContextRunCache;
begin
  lCache := TSourceContextRunCache.Create(aLookup);
  try
    Result := lCache.TryResolveCandidate(aFinding, aContextLines, aContext, aToken,
      aEnclosingSymbol, aError);
  finally
    lCache.Free;
  end;
end;

function TryResolveSourceContextCandidate(const aLookup: TProjectSourceLookup; const aFileToken: string;
  aLineNumber, aColumn, aContextLines: Integer; const aCandidateText: string; out aContext: TSourceContextSnippet;
  out aToken: string; out aEnclosingSymbol: string; out aError: string): Boolean;
var
  lCache: TSourceContextRunCache;
begin
  lCache := TSourceContextRunCache.Create(aLookup);
  try
    Result := lCache.TryResolveCandidate(aFileToken, aLineNumber, aColumn, aContextLines, aCandidateText,
      aContext, aToken, aEnclosingSymbol, aError);
  finally
    lCache.Free;
  end;
end;

function TryReadSourceContext(const aFilePath: string; aLineNumber, aContextLines: Integer;
  out aContext: TSourceContextSnippet; out aError: string): Boolean;
var
  lCache: TSourceContextRunCache;
begin
  lCache := TSourceContextRunCache.Create;
  try
    Result := lCache.TryResolve(aFilePath, aLineNumber, aContextLines, aContext, aError);
  finally
    lCache.Free;
  end;
end;

function FormatSourceContextLines(const aContext: TSourceContextSnippet): TArray<string>;
begin
  Result := TDelphiSemanticSourceContext.FormatLines(SemanticSnippet(aContext));
end;

end.
