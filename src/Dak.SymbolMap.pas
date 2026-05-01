unit Dak.SymbolMap;

interface

uses
  Dak.Types;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;

implementation

uses
  System.SysUtils,
  Dak.ExitCodes;

function SymbolMapOperationToText(const aOperation: TSymbolMapOperation): string;
begin
  case aOperation of
    TSymbolMapOperation.smoIndex:
      Result := 'index';
    TSymbolMapOperation.smoFindDefinition:
      Result := 'find-definition';
    TSymbolMapOperation.smoFindReferences:
      Result := 'find-references';
    TSymbolMapOperation.smoSearchSymbols:
      Result := 'search-symbols';
    TSymbolMapOperation.smoDescribeSymbol:
      Result := 'describe-symbol';
    TSymbolMapOperation.smoStats:
      Result := 'stats';
  else
    Result := 'none';
  end;
end;

function JsonEscape(const aValue: string): string;
var
  ch: Char;
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(aValue) do
  begin
    ch := aValue[i];
    case ch of
      '"':
        Result := Result + '\"';
      '\':
        Result := Result + '\\';
      #8:
        Result := Result + '\b';
      #9:
        Result := Result + '\t';
      #10:
        Result := Result + '\n';
      #12:
        Result := Result + '\f';
      #13:
        Result := Result + '\r';
    else
      if Ord(ch) < 32 then
        Result := Result + '\u' + IntToHex(Ord(ch), 4)
      else
        Result := Result + ch;
    end;
  end;
end;

procedure WriteSymbolMapJsonShell(const aOptions: TAppOptions);
var
  lOperation: string;
begin
  lOperation := SymbolMapOperationToText(aOptions.fSymbolMapOperation);
  WriteLn(
    '{"operation":"' + JsonEscape(lOperation) + '"' +
    ',"status":"ok"' +
    ',"project":{"path":"' + JsonEscape(aOptions.fDprojPath) + '","platform":"' +
      JsonEscape(aOptions.fPlatform) + '","config":"' + JsonEscape(aOptions.fConfig) + '"}' +
    ',"cache":{"centralRoot":"' + JsonEscape(aOptions.fSymbolMapCacheRoot) + '","projectRoot":""}' +
    ',"query":{}' +
    ',"result":{}' +
    ',"diagnostics":[]' +
    ',"timings":{"totalMs":0}}');
end;

procedure WriteSymbolMapTextShell(const aOptions: TAppOptions);
begin
  WriteLn('symbol-map ', SymbolMapOperationToText(aOptions.fSymbolMapOperation), ': ok');
  WriteLn('project: ', aOptions.fDprojPath);
  if aOptions.fSymbolMapCacheRoot <> '' then
    WriteLn('cache-root: ', aOptions.fSymbolMapCacheRoot);
end;

function RunSymbolMapCommand(const aOptions: TAppOptions): Integer;
begin
  if aOptions.fSymbolMapFormat = TSymbolMapFormat.smfText then
    WriteSymbolMapTextShell(aOptions)
  else
    WriteSymbolMapJsonShell(aOptions);

  Result := cExitSuccess;
end;

end.
