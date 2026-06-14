unit Dak.GlobalVars.Model;

interface

uses
  System.Generics.Collections,
  System.SysUtils;

type
  TGlobalVarKind = (gvkVar, gvkThreadVar, gvkTypedConst, gvkClassVar);
  TAccessKind = (akRead, akWrite, akReadWrite);

  TGlobalVarRef = record
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
  end;

  TGlobalVarAmbiguity = record
    Name: string;
    UnitName: string;
    RoutineName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    Access: TAccessKind;
    Candidates: string;
  end;

  TGlobalVarSymbol = class
  public
    Name: string;
    UnitName: string;
    FileName: string;
    Line: Integer;
    Column: Integer;
    TypeName: string;
    Kind: TGlobalVarKind;
    UsedBy: TList<TGlobalVarRef>;
    constructor Create;
    destructor Destroy; override;
  end;

  TProjectInfo = record
    ProjectPath: string;
    ProjectName: string;
    MainSourcePath: string;
    ContextMode: string;
    ContextNote: string;
    ParserDefines: string;
    ParserSearchPath: string;
    UnitAliases: TArray<string>;
    UnitScopes: TArray<string>;
    OutputPath: string;
    CachePath: string;
    ReportsPath: string;
    TempPath: string;
  end;

function AccessToText(const aAccess: TAccessKind): string;
function GlobalVarKindToText(const aKind: TGlobalVarKind): string;

implementation

constructor TGlobalVarSymbol.Create;
begin
  inherited Create;
  UsedBy := TList<TGlobalVarRef>.Create;
end;

destructor TGlobalVarSymbol.Destroy;
begin
  UsedBy.Free;
  inherited Destroy;
end;

function AccessToText(const aAccess: TAccessKind): string;
begin
  case aAccess of
    akRead:
      Result := 'read';
    akWrite:
      Result := 'write';
  else
    Result := 'readwrite';
  end;
end;

function GlobalVarKindToText(const aKind: TGlobalVarKind): string;
begin
  case aKind of
    gvkVar:
      Result := 'var';
    gvkThreadVar:
      Result := 'threadvar';
    gvkTypedConst:
      Result := 'typedconst';
  else
    Result := 'classvar';
  end;
end;

end.
