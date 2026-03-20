unit Dak.Diagnostics;
interface


uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.SysUtils,
  maxLogic.StrUtils,
  Dak.Messages;

type
  TDiagnosticsEmitProc = reference to procedure(const aMessage: string);

  TStringSet = class
  private
    fItems: TList<string>;
    fSet: THashSet<string>;
  public
    constructor Create(const aComparer: IEqualityComparer<string>);
    destructor Destroy; override;
    function Add(const aValue: string): Boolean;
    function Contains(const aValue: string): Boolean;
    function Count: Integer;
    function ToArray: TArray<string>;
  end;

  TDiagnostics = class
  private
    fUnknownMacros: TStringSet;
    fCycleMacros: TStringSet;
    fMissingPaths: TStringSet;
    fIgnoreUnknownMacros: TStringSet;
    fIgnoreMissingPathMasks: TStringSet;
    fWarnings: TList<string>;
    fVerbose: Boolean;
    fLogWriter: TStreamWriter;
    fLogStream: TFileStream;
    fLogEncoding: TEncoding;
    fLogToStderr: Boolean;
    procedure WriteLine(const aMessage: string);
    function ShouldIgnoreUnknownMacro(const aName: string): Boolean;
    function ShouldIgnoreMissingPath(const aPath: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function TryOpenLogFile(const aPath: string; out aError: string): Boolean;
    procedure AddUnknownMacro(const aName: string);
    procedure AddCycleMacro(const aName: string);
    procedure AddMissingPath(const aPath: string);
    procedure AddIgnoreUnknownMacros(const aList: string);
    procedure AddIgnoreMissingPathMasks(const aList: string);
    procedure AddWarning(const aMessage: string);
    procedure AddNote(const aMessage: string);
    procedure AddInfo(const aMessage: string);
    procedure EmitWarnings(const aEmit: TDiagnosticsEmitProc);
    procedure WriteToStderr;
    property Verbose: Boolean read fVerbose write fVerbose;
    property LogToStderr: Boolean read fLogToStderr write fLogToStderr;
  end;

implementation

{ TStringSet }

procedure IgnoreBool(const aValue: Boolean); inline;
begin
  // Intentionally ignored: we only care about the side-effect (updating the set).
  if aValue then
    Exit;
end;

constructor TStringSet.Create(const aComparer: IEqualityComparer<string>);
begin
  inherited Create;
  fItems := TList<string>.Create;
  fSet := THashSet<string>.Create(aComparer);
end;

destructor TStringSet.Destroy;
begin
  fSet.Free;
  fItems.Free;
  inherited;
end;

function TStringSet.Add(const aValue: string): Boolean;
begin
  Result := fSet.Add(aValue);
  if Result then
    fItems.Add(aValue);
end;

function TStringSet.Contains(const aValue: string): Boolean;
begin
  Result := fSet.Contains(aValue);
end;

function TStringSet.Count: Integer;
begin
  Result := fItems.Count;
end;

function TStringSet.ToArray: TArray<string>;
begin
  Result := fItems.ToArray;
end;

{ TDiagnostics }

function SplitList(const aValue: string): TArray<string>;
var
  lRaw: TArray<string>;
  lList: TList<string>;
  lPart: string;
  lItem: string;
begin
  Result := nil;
  if aValue = '' then
    Exit;
  lRaw := aValue.Split([';']);
  lList := TList<string>.Create;
  try
    for lPart in lRaw do
    begin
      lItem := Trim(lPart);
      if lItem <> '' then
        lList.Add(lItem);
    end;
    Result := lList.ToArray;
  finally
    lList.Free;
  end;
end;

function NormalizeSlashes(const aValue: string): string;
begin
  Result := aValue.Replace('/', '\', [rfReplaceAll]);
end;

function MatchesMaskCI(const aText: string; const aMask: string): Boolean;
var
  t: string;
  m: string;
  i: Integer;
  j: Integer;
  star: Integer;
  lMark: Integer;
begin
  t := UpperCase(aText);
  m := UpperCase(aMask);

  i := 1;
  j := 1;
  star := 0;
  lMark := 0;
  while i <= Length(t) do
  begin
    if (j <= Length(m)) and ((m[j] = '?') or (m[j] = t[i])) then
    begin
      Inc(i);
      Inc(j);
      Continue;
    end;

    if (j <= Length(m)) and (m[j] = '*') then
    begin
      star := j;
      lMark := i;
      Inc(j);
      Continue;
    end;

    if star <> 0 then
    begin
      j := star + 1;
      Inc(lMark);
      i := lMark;
      Continue;
    end;

    Exit(False);
  end;

  while (j <= Length(m)) and (m[j] = '*') do
    Inc(j);
  Result := j > Length(m);
end;

constructor TDiagnostics.Create;
begin
  inherited Create;
  fUnknownMacros := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fCycleMacros := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fMissingPaths := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fIgnoreUnknownMacros := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fIgnoreMissingPathMasks := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fWarnings := TList<string>.Create;
  fLogWriter := nil;
  fLogStream := nil;
  fLogEncoding := nil;
  fLogToStderr := True;
end;

destructor TDiagnostics.Destroy;
begin
  fLogWriter.Free;
  fLogStream.Free;
  fLogEncoding.Free;
  fWarnings.Free;
  fMissingPaths.Free;
  fCycleMacros.Free;
  fUnknownMacros.Free;
  fIgnoreMissingPathMasks.Free;
  fIgnoreUnknownMacros.Free;
  inherited;
end;

function TDiagnostics.TryOpenLogFile(const aPath: string; out aError: string): Boolean;
var
  lDir: string;
begin
  Result := False;
  aError := '';
  fLogWriter.Free;
  fLogWriter := nil;
  fLogStream.Free;
  fLogStream := nil;
  fLogEncoding.Free;
  fLogEncoding := nil;

  if aPath = '' then
  begin
    aError := Format(SLogFileOpenFailed, ['<empty>']);
    Exit(False);
  end;
  lDir := ExtractFilePath(aPath);
  if (lDir <> '') and (not DirectoryExists(lDir)) then
    ForceDirectories(lDir);
  try
    fLogEncoding := TUTF8Encoding.Create(False);
    fLogStream := TFileStream.Create(aPath, fmCreate or fmShareDenyNone);
    fLogWriter := TStreamWriter.Create(fLogStream, fLogEncoding);
    fLogWriter.AutoFlush := True;
    Result := True;
  except
    on E: Exception do
    begin
      fLogWriter.Free;
      fLogWriter := nil;
      fLogStream.Free;
      fLogStream := nil;
      fLogEncoding.Free;
      fLogEncoding := nil;
      aError := Format(SLogFileOpenFailed, [E.Message]);
      Exit(False);
    end;
  end;
end;

procedure TDiagnostics.WriteLine(const aMessage: string);
begin
  if aMessage = '' then
    Exit;
  if fLogWriter <> nil then
    fLogWriter.WriteLine(aMessage);
  if fLogToStderr then
    WriteLn(ErrOutput, aMessage);
end;

procedure TDiagnostics.AddUnknownMacro(const aName: string);
begin
  if aName = '' then
    Exit;
  if ShouldIgnoreUnknownMacro(aName) then
    Exit;
  IgnoreBool(fUnknownMacros.Add(aName));
end;

procedure TDiagnostics.AddCycleMacro(const aName: string);
begin
  if aName = '' then
    Exit;
  IgnoreBool(fCycleMacros.Add(aName));
end;

procedure TDiagnostics.AddMissingPath(const aPath: string);
begin
  if aPath = '' then
    Exit;
  if ShouldIgnoreMissingPath(aPath) then
    Exit;
  IgnoreBool(fMissingPaths.Add(aPath));
end;

procedure TDiagnostics.AddIgnoreUnknownMacros(const aList: string);
var
  lItem: string;
begin
  for lItem in SplitList(aList) do
    IgnoreBool(fIgnoreUnknownMacros.Add(lItem));
end;

procedure TDiagnostics.AddIgnoreMissingPathMasks(const aList: string);
var
  lItem: string;
begin
  for lItem in SplitList(aList) do
    IgnoreBool(fIgnoreMissingPathMasks.Add(NormalizeSlashes(lItem)));
end;

function TDiagnostics.ShouldIgnoreUnknownMacro(const aName: string): Boolean;
begin
  if fIgnoreUnknownMacros.Count = 0 then
    Exit(False);
  if fIgnoreUnknownMacros.Contains('*') then
    Exit(True);
  Result := fIgnoreUnknownMacros.Contains(aName);
end;

function TDiagnostics.ShouldIgnoreMissingPath(const aPath: string): Boolean;
var
  lMask: string;
  lPath: string;
begin
  if fIgnoreMissingPathMasks.Count = 0 then
    Exit(False);
  lPath := NormalizeSlashes(aPath);
  for lMask in fIgnoreMissingPathMasks.ToArray do
    if MatchesMaskCI(lPath, NormalizeSlashes(lMask)) then
      Exit(True);
  Result := False;
end;

procedure TDiagnostics.AddWarning(const aMessage: string);
begin
  if aMessage = '' then
    Exit;
  fWarnings.Add(aMessage);
end;

procedure TDiagnostics.AddNote(const aMessage: string);
begin
  if aMessage = '' then
    Exit;
  WriteLine(aMessage);
end;

procedure TDiagnostics.AddInfo(const aMessage: string);
begin
  if (not fVerbose) or (aMessage = '') then
    Exit;
  WriteLine(aMessage);
end;

procedure TDiagnostics.EmitWarnings(const aEmit: TDiagnosticsEmitProc);
var
  lItem: string;
begin
  if not Assigned(aEmit) then
    Exit;
  for lItem in fWarnings do
    aEmit(lItem);
end;

procedure TDiagnostics.WriteToStderr;
var
  lItem: string;
  lItems: TArray<string>;
  i: Integer;
begin
  for lItem in fWarnings do
    WriteLine(lItem);

  lItems := fUnknownMacros.ToArray;
  for i := 0 to High(lItems) do
    WriteLine(Format(SUnknownMacro, [lItems[i]]));

  lItems := fCycleMacros.ToArray;
  for i := 0 to High(lItems) do
    WriteLine(Format(SCycleMacro, [lItems[i]]));

  lItems := fMissingPaths.ToArray;
  for i := 0 to High(lItems) do
    WriteLine(Format(SMissingDirectory, [lItems[i]]));
end;

end.
