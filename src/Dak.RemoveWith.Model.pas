unit Dak.RemoveWith.Model;

interface

uses
  DelphiAST.ProjectIndexer,
  Dak.Types;

type
  TRemoveWithProjectModel = class
  private
    fContext: TProjectAnalysisContext;
    fIndexer: TProjectIndexer;
    fIndexCount: Integer;
    fProjectPath: string;
  public
    constructor Create(const aProjectPath: string; const aContext: TProjectAnalysisContext);
    destructor Destroy; override;
    procedure Index;
    function ParsedUnitCount: Integer;
    function ProblemCount: Integer;
    property Context: TProjectAnalysisContext read fContext;
    property IndexCount: Integer read fIndexCount;
    property Indexer: TProjectIndexer read fIndexer;
    property ProjectPath: string read fProjectPath;
  end;

function BuildRemoveWithProjectModel(const aOptions: TAppOptions; const aProjectPath: string;
  out aModel: TRemoveWithProjectModel; out aError: string): Boolean;

implementation

uses
  Dak.Project;

constructor TRemoveWithProjectModel.Create(const aProjectPath: string; const aContext: TProjectAnalysisContext);
begin
  inherited Create;
  fProjectPath := aProjectPath;
  fContext := aContext;
  fIndexer := TProjectIndexer.Create;
  fIndexer.Defines := fContext.fParserDefines;
  fIndexer.SearchPath := fContext.fParserSearchPath;
end;

destructor TRemoveWithProjectModel.Destroy;
begin
  fIndexer.Free;
  inherited;
end;

procedure TRemoveWithProjectModel.Index;
begin
  fIndexer.Index(fContext.fMainSourcePath);
  Inc(fIndexCount);
end;

function TRemoveWithProjectModel.ParsedUnitCount: Integer;
var
  lUnit: TProjectIndexer.TUnitInfo;
begin
  Result := 0;
  for lUnit in fIndexer.ParsedUnits do
    Inc(Result);
end;

function TRemoveWithProjectModel.ProblemCount: Integer;
var
  lProblem: TProjectIndexer.TProblemInfo;
begin
  Result := 0;
  for lProblem in fIndexer.Problems do
    Inc(Result);
end;

function BuildRemoveWithProjectModel(const aOptions: TAppOptions; const aProjectPath: string;
  out aModel: TRemoveWithProjectModel; out aError: string): Boolean;
var
  lContext: TProjectAnalysisContext;
begin
  aModel := nil;
  aError := '';
  if not TryBuildProjectAnalysisContext(aOptions, lContext, aError) then
    Exit(False);

  aModel := TRemoveWithProjectModel.Create(aProjectPath, lContext);
  try
    aModel.Index;
  except
    aModel.Free;
    aModel := nil;
    raise;
  end;
  Result := True;
end;

end.
