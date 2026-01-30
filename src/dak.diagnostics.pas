unit Dak.Diagnostics;
interface


uses
  System.Classes, System.Generics.Collections, System.Generics.Defaults, System.SysUtils,
  maxLogic.StrUtils,
  Dak.Messages;

type
  TStringSet = class
  private
    fItems: TList<string>;
    fSet: THashSet<string>;
  public
    constructor Create(const aComparer: IEqualityComparer<string>);
    destructor Destroy; override;
    function Add(const aValue: string): Boolean;
    function Count: Integer;
    function ToArray: TArray<string>;
  end;

  TDiagnostics = class
  private
    fUnknownMacros: TStringSet;
    fCycleMacros: TStringSet;
    fMissingPaths: TStringSet;
    fWarnings: TList<string>;
    fVerbose: Boolean;
    fLogWriter: TStreamWriter;
    fLogStream: TFileStream;
    fLogEncoding: TEncoding;
    fLogToStderr: Boolean;
    procedure WriteLine(const aMessage: string);
  public
    constructor Create;
    destructor Destroy; override;
    function TryOpenLogFile(const aPath: string; out aError: string): Boolean;
    procedure AddUnknownMacro(const aName: string);
    procedure AddCycleMacro(const aName: string);
    procedure AddMissingPath(const aPath: string);
    procedure AddWarning(const aMessage: string);
    procedure AddNote(const aMessage: string);
    procedure AddInfo(const aMessage: string);
    procedure WriteToStderr;
    property Verbose: Boolean read fVerbose write fVerbose;
    property LogToStderr: Boolean read fLogToStderr write fLogToStderr;
  end;

implementation

{ TStringSet }

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

function TStringSet.Count: Integer;
begin
  Result := fItems.Count;
end;

function TStringSet.ToArray: TArray<string>;
begin
  Result := fItems.ToArray;
end;

{ TDiagnostics }

constructor TDiagnostics.Create;
begin
  inherited Create;
  fUnknownMacros := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fCycleMacros := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
  fMissingPaths := TStringSet.Create(TFastCaseAwareComparer.OrdinalIgnoreCase);
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
  inherited;
end;

function TDiagnostics.TryOpenLogFile(const aPath: string; out aError: string): Boolean;
var
  lDir: string;
begin
  Result := False;
  aError := '';
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
  fUnknownMacros.Add(aName);
end;

procedure TDiagnostics.AddCycleMacro(const aName: string);
begin
  if aName = '' then
    Exit;
  fCycleMacros.Add(aName);
end;

procedure TDiagnostics.AddMissingPath(const aPath: string);
begin
  if aPath = '' then
    Exit;
  fMissingPaths.Add(aPath);
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
