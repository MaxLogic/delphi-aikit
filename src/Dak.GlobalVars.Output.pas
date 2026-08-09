unit Dak.GlobalVars.Output;

interface

uses
  System.Generics.Collections,
  Dak.GlobalVars.Model,
  Dak.Types;

function BuildFilteredSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aOptions: TAppOptions): TObjectList<TGlobalVarSymbol>;
function BuildFilteredAmbiguities(const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aOptions: TAppOptions): TList<TGlobalVarAmbiguity>;
function BuildGlobalVarsSummary(const aAllSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aEmittedCount,
  aEmittedAmbiguityCount: Integer;
  const aRejectedImpossibleDeclarations: Integer = 0): TGlobalVarsSummary;
function RenderJson(const aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo; const aOptions: TAppOptions): string;
function RenderText(const aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo; const aOptions: TAppOptions): string;

implementation

uses
  System.Classes,
  System.JSON,
  System.Masks,
  System.SysUtils,
  Dak.GlobalVars.Cache;

function MatchPatternText(const aValue, aPattern: string): Boolean;
var
  lMask: string;
begin
  lMask := aPattern;
  if (Pos('*', lMask) = 0) and (Pos('?', lMask) = 0) then
    lMask := '*' + lMask + '*';
  Result := MatchesMask(UpperCase(aValue), UpperCase(lMask));
end;

function RefMatchesAccess(const aRef: TGlobalVarRef; const aOptions: TAppOptions): Boolean;
begin
  if aOptions.fGlobalVarsReadsOnly then
    Exit(aRef.Access in [akRead, akReadWrite]);
  if aOptions.fGlobalVarsWritesOnly then
    Exit(aRef.Access in [akWrite, akReadWrite]);
  Result := True;
end;

function AccessMatchesFilter(const aAccess: TAccessKind; const aOptions: TAppOptions): Boolean;
begin
  if aOptions.fGlobalVarsReadsOnly then
    Exit(aAccess in [akRead, akReadWrite]);
  if aOptions.fGlobalVarsWritesOnly then
    Exit(aAccess in [akWrite, akReadWrite]);
  Result := True;
end;

function SymbolMatchesFilters(const aSymbol: TGlobalVarSymbol;
  const aOptions: TAppOptions): Boolean;
var
  lRef: TGlobalVarRef;
begin
  Result := True;
  if aOptions.fHasGlobalVarsUnitFilter and
    not MatchPatternText(aSymbol.UnitName, aOptions.fGlobalVarsUnitFilter) then
    Exit(False);
  if aOptions.fHasGlobalVarsNameFilter and
    not MatchPatternText(aSymbol.Name, aOptions.fGlobalVarsNameFilter) then
    Exit(False);
  if aOptions.fGlobalVarsUnusedOnly then
    Exit(aSymbol.UsedBy.Count = 0);
  if aOptions.fGlobalVarsReadsOnly or aOptions.fGlobalVarsWritesOnly then
  begin
    for lRef in aSymbol.UsedBy do
      if RefMatchesAccess(lRef, aOptions) then
        Exit(True);
    Exit(False);
  end;
end;

function AmbiguityMatchesFilters(const aAmbiguity: TGlobalVarAmbiguity;
  const aOptions: TAppOptions): Boolean;
begin
  if aOptions.fHasGlobalVarsUnitFilter and
    not MatchPatternText(aAmbiguity.UnitName, aOptions.fGlobalVarsUnitFilter) then
    Exit(False);
  if aOptions.fHasGlobalVarsNameFilter and
    not MatchPatternText(aAmbiguity.Name, aOptions.fGlobalVarsNameFilter) then
    Exit(False);
  Result := AccessMatchesFilter(aAmbiguity.Access, aOptions);
end;

function GlobalVarsFilterText(const aOptions: TAppOptions): string;
var
  lParts: TStringList;
begin
  lParts := TStringList.Create;
  try
    if aOptions.fGlobalVarsUnusedOnly then
      lParts.Add('unused-only');
    if aOptions.fGlobalVarsReadsOnly then
      lParts.Add('reads-only');
    if aOptions.fGlobalVarsWritesOnly then
      lParts.Add('writes-only');
    if aOptions.fHasGlobalVarsUnitFilter then
      lParts.Add('unit=' + aOptions.fGlobalVarsUnitFilter);
    if aOptions.fHasGlobalVarsNameFilter then
      lParts.Add('name=' + aOptions.fGlobalVarsNameFilter);
    if lParts.Count = 0 then
      Result := 'all'
    else begin
      Result := StringReplace(Trim(lParts.Text), sLineBreak, ';', [rfReplaceAll]);
      if Result.EndsWith(';') then
        Delete(Result, Length(Result), 1);
    end;
  finally
    lParts.Free;
  end;
end;

function CountUnusedSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>): Integer;
var
  lSymbol: TGlobalVarSymbol;
begin
  Result := 0;
  for lSymbol in aSymbols do
    if lSymbol.UsedBy.Count = 0 then
      Inc(Result);
end;

function BuildFilteredSymbols(const aSymbols: TObjectList<TGlobalVarSymbol>;
  const aOptions: TAppOptions): TObjectList<TGlobalVarSymbol>;
var
  lRef: TGlobalVarRef;
  lRefMatches: Boolean;
  lSymbol: TGlobalVarSymbol;
  lSymbolCopy: TGlobalVarSymbol;
begin
  Result := TObjectList<TGlobalVarSymbol>.Create(True);
  try
    for lSymbol in aSymbols do
      if SymbolMatchesFilters(lSymbol, aOptions) then
      begin
        lSymbolCopy := TGlobalVarSymbol.Create;
        try
          lSymbolCopy.Name := lSymbol.Name;
          lSymbolCopy.UnitName := lSymbol.UnitName;
          lSymbolCopy.FileName := lSymbol.FileName;
          lSymbolCopy.Line := lSymbol.Line;
          lSymbolCopy.Column := lSymbol.Column;
          lSymbolCopy.TypeName := lSymbol.TypeName;
          lSymbolCopy.OwnerName := lSymbol.OwnerName;
          lSymbolCopy.DeclarationRole := lSymbol.DeclarationRole;
          lSymbolCopy.ScopeKind := lSymbol.ScopeKind;
          lSymbolCopy.OwnerScopeId := lSymbol.OwnerScopeId;
          lSymbolCopy.SymbolId := lSymbol.SymbolId;
          lSymbolCopy.Kind := lSymbol.Kind;
          for lRef in lSymbol.UsedBy do
          begin
            lRefMatches := not (aOptions.fGlobalVarsReadsOnly or aOptions.fGlobalVarsWritesOnly) or
              RefMatchesAccess(lRef, aOptions);
            if lRefMatches then
              lSymbolCopy.UsedBy.Add(lRef);
          end;
          Result.Add(lSymbolCopy);
          lSymbolCopy := nil;
        finally
          lSymbolCopy.Free;
        end;
      end;
  except
    Result.Free;
    raise;
  end;
end;

function BuildFilteredAmbiguities(const aAmbiguities: TList<TGlobalVarAmbiguity>;
  const aOptions: TAppOptions): TList<TGlobalVarAmbiguity>;
var
  lAmbiguity: TGlobalVarAmbiguity;
begin
  Result := TList<TGlobalVarAmbiguity>.Create;
  if aOptions.fGlobalVarsUnusedOnly then
    Exit;
  for lAmbiguity in aAmbiguities do
    if AmbiguityMatchesFilters(lAmbiguity, aOptions) then
      Result.Add(lAmbiguity);
end;

function BuildGlobalVarsSummary(const aAllSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aEmittedCount,
  aEmittedAmbiguityCount: Integer;
  const aRejectedImpossibleDeclarations: Integer): TGlobalVarsSummary;
begin
  Result.Total := aAllSymbols.Count;
  Result.Used := aAllSymbols.Count - CountUnusedSymbols(aAllSymbols);
  Result.Unused := CountUnusedSymbols(aAllSymbols);
  Result.Ambiguities := aAmbiguities.Count;
  Result.Emitted := aEmittedCount;
  Result.EmittedAmbiguities := aEmittedAmbiguityCount;
  Result.RejectedImpossibleDeclarations := aRejectedImpossibleDeclarations;
end;

function BuildJsonProvenance(const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo): TJSONObject;
var
  lCompilerContext: TJSONObject;
  lDak: TJSONObject;
  lDelphiSemantics: TJSONObject;
  lDiagnostic: TGlobalVarsDiagnostic;
  lDiagnosticJson: TJSONObject;
  lDiagnostics: TJSONArray;
  lGlobalVars: TJSONObject;
begin
  Result := TJSONObject.Create;
  lDak := TJSONObject.Create;
  Result.AddPair('dak', lDak);
  lDak.AddPair('executableVersion', aProject.DakExecutableVersion);
  lDak.AddPair('executableSha256', aProject.DakExecutableHash);
  lDak.AddPair('sourceRevision', aProject.DakSourceRevision);
  lDak.AddPair('sourceRevisionSource', aProject.DakSourceRevisionSource);

  lDelphiSemantics := TJSONObject.Create;
  Result.AddPair('delphiSemantics', lDelphiSemantics);
  lDelphiSemantics.AddPair('parserVersion', aProject.SemanticParserVersion);
  lDelphiSemantics.AddPair('modelVersion', aProject.SemanticModelVersion);
  lDelphiSemantics.AddPair('cacheSchemaVersion', aProject.SemanticCacheSchemaVersion);
  lDelphiSemantics.AddPair('sourceRevision', aProject.SemanticSourceRevision);
  lDelphiSemantics.AddPair('sourceRevisionSource',
    aProject.SemanticSourceRevisionSource);
  lDelphiSemantics.AddPair('factSource', aProject.SemanticFactSource);
  lDelphiSemantics.AddPair('snapshotUnitCount',
    TJSONNumber.Create(aProject.SemanticSnapshotUnitCount));
  lDelphiSemantics.AddPair('verifiedScopeUnitCount',
    TJSONNumber.Create(aProject.SemanticVerifiedScopeUnitCount));
  lDelphiSemantics.AddPair('modelFallbackUnitCount',
    TJSONNumber.Create(aProject.SemanticModelFallbackUnitCount));
  lDelphiSemantics.AddPair('heuristicFallbackUnitCount',
    TJSONNumber.Create(aProject.SemanticHeuristicFallbackUnitCount));
  lDelphiSemantics.AddPair('rejectedDeclarationCount',
    TJSONNumber.Create(aProject.SemanticRejectedDeclarationCount));
  lDelphiSemantics.AddPair('diagnosticCount',
    TJSONNumber.Create(Length(aProject.SemanticDiagnostics)));
  lDiagnostics := TJSONArray.Create;
  lDelphiSemantics.AddPair('diagnostics', lDiagnostics);
  for lDiagnostic in aProject.SemanticDiagnostics do
  begin
    lDiagnosticJson := TJSONObject.Create;
    lDiagnostics.AddElement(lDiagnosticJson);
    lDiagnosticJson.AddPair('code', lDiagnostic.Code);
    lDiagnosticJson.AddPair('message', lDiagnostic.Message);
    lDiagnosticJson.AddPair('file', lDiagnostic.FileName);
    lDiagnosticJson.AddPair('line', TJSONNumber.Create(lDiagnostic.Line));
  end;

  lCompilerContext := TJSONObject.Create;
  Result.AddPair('compilerContext', lCompilerContext);
  lCompilerContext.AddPair('mode', aProject.ContextMode);
  lCompilerContext.AddPair('delphiVersion', aProject.CompilerDelphiVersion);
  lCompilerContext.AddPair('platform', aProject.CompilerPlatform);
  lCompilerContext.AddPair('configuration', aProject.CompilerConfiguration);
  lCompilerContext.AddPair('decisionGrade', TJSONBool.Create(aProject.DecisionGrade));

  lGlobalVars := TJSONObject.Create;
  Result.AddPair('globalVars', lGlobalVars);
  lGlobalVars.AddPair('cacheSchemaVersion', cGlobalVarsCacheSchemaVersion);
  lGlobalVars.AddPair('rejectedImpossibleDeclarations',
    TJSONNumber.Create(aSummary.RejectedImpossibleDeclarations));
end;

function BuildJsonSummary(const aSummary: TGlobalVarsSummary; const aProject: TProjectInfo;
  const aOptions: TAppOptions): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('total', TJSONNumber.Create(aSummary.Total));
  Result.AddPair('used', TJSONNumber.Create(aSummary.Used));
  Result.AddPair('unused', TJSONNumber.Create(aSummary.Unused));
  Result.AddPair('ambiguities', TJSONNumber.Create(aSummary.Ambiguities));
  Result.AddPair('emitted', TJSONNumber.Create(aSummary.Emitted));
  Result.AddPair('emittedAmbiguities', TJSONNumber.Create(aSummary.EmittedAmbiguities));
  Result.AddPair('filter', GlobalVarsFilterText(aOptions));
  Result.AddPair('contextMode', aProject.ContextMode);
  if aProject.ContextNote <> '' then
    Result.AddPair('contextNote', aProject.ContextNote);
end;

function RenderJson(const aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo; const aOptions: TAppOptions): string;
var
  lAmbiguities: TJSONArray;
  lAmbiguity: TGlobalVarAmbiguity;
  lJson: TJSONObject;
  lRef: TGlobalVarRef;
  lRefs: TJSONArray;
  lSymbols: TJSONArray;
  lSymbol: TGlobalVarSymbol;
begin
  lJson := TJSONObject.Create;
  try
    lJson.AddPair('summary', BuildJsonSummary(aSummary, aProject, aOptions));
    lJson.AddPair('provenance', BuildJsonProvenance(aSummary, aProject));
    lSymbols := TJSONArray.Create;
    lJson.AddPair('symbols', lSymbols);
    for lSymbol in aFilteredSymbols do
    begin
      var lItem := TJSONObject.Create;
      lSymbols.AddElement(lItem);
      lItem.AddPair('name', lSymbol.Name);
      lItem.AddPair('declaringUnit', lSymbol.UnitName);
      lItem.AddPair('fileName', lSymbol.FileName);
      lItem.AddPair('type', lSymbol.TypeName);
      lItem.AddPair('kind', GlobalVarKindToText(lSymbol.Kind));
      lItem.AddPair('owner', lSymbol.OwnerName);
      lItem.AddPair('declarationRole', lSymbol.DeclarationRole);
      lItem.AddPair('scopeKind', lSymbol.ScopeKind);
      lItem.AddPair('ownerScopeId', lSymbol.OwnerScopeId);
      lItem.AddPair('symbolId', lSymbol.SymbolId);
      lItem.AddPair('line', TJSONNumber.Create(lSymbol.Line));
      lItem.AddPair('column', TJSONNumber.Create(lSymbol.Column));
      lRefs := TJSONArray.Create;
      lItem.AddPair('usedBy', lRefs);
      for lRef in lSymbol.UsedBy do
      begin
        var lRefJson := TJSONObject.Create;
        lRefs.AddElement(lRefJson);
        lRefJson.AddPair('unit', lRef.UnitName);
        lRefJson.AddPair('routine', lRef.RoutineName);
        lRefJson.AddPair('routineScopeId', lRef.RoutineScopeId);
        lRefJson.AddPair('file', lRef.FileName);
        lRefJson.AddPair('line', TJSONNumber.Create(lRef.Line));
        lRefJson.AddPair('column', TJSONNumber.Create(lRef.Column));
        lRefJson.AddPair('access', AccessToText(lRef.Access));
      end;
    end;
    lAmbiguities := TJSONArray.Create;
    lJson.AddPair('ambiguities', lAmbiguities);
    for lAmbiguity in aAmbiguities do
    begin
      var lItem := TJSONObject.Create;
      lAmbiguities.AddElement(lItem);
      lItem.AddPair('name', lAmbiguity.Name);
      lItem.AddPair('unit', lAmbiguity.UnitName);
      lItem.AddPair('routine', lAmbiguity.RoutineName);
      lItem.AddPair('file', lAmbiguity.FileName);
      lItem.AddPair('line', TJSONNumber.Create(lAmbiguity.Line));
      lItem.AddPair('column', TJSONNumber.Create(lAmbiguity.Column));
      lItem.AddPair('access', AccessToText(lAmbiguity.Access));
      lItem.AddPair('candidates', lAmbiguity.Candidates);
    end;
    Result := lJson.Format(2);
  finally
    lJson.Free;
  end;
end;

function RenderText(const aFilteredSymbols: TObjectList<TGlobalVarSymbol>;
  const aAmbiguities: TList<TGlobalVarAmbiguity>; const aSummary: TGlobalVarsSummary;
  const aProject: TProjectInfo; const aOptions: TAppOptions): string;
var
  lAmbiguity: TGlobalVarAmbiguity;
  lBuilder: TStringBuilder;
  lRef: TGlobalVarRef;
  lSymbol: TGlobalVarSymbol;
begin
  lBuilder := TStringBuilder.Create;
  try
    lBuilder.AppendLine(Format('Summary: total=%d used=%d unused=%d ambiguities=%d emitted=%d filter=%s',
      [aSummary.Total, aSummary.Used, aSummary.Unused, aSummary.Ambiguities,
      aSummary.Emitted, GlobalVarsFilterText(aOptions)]));
    lBuilder.AppendLine('Context: ' + aProject.ContextMode);
    if aProject.ContextNote <> '' then
      lBuilder.AppendLine('Context note: ' + aProject.ContextNote);
    lBuilder.AppendLine(Format(
      'Provenance: DAK=%s exeSha256=%s source=%s semanticsParser=%s semanticsModel=%s ' +
      'semanticsSchema=%s semanticsSource=%s factSource=%s snapshotUnits=%d ' +
      'verifiedScopeUnits=%d modelFallbackUnits=%d heuristicFallbackUnits=%d ' +
      'rejectedDeclarations=%d diagnostics=%d globalVarsCacheSchema=%s rejectedImpossible=%d',
      [aProject.DakExecutableVersion, aProject.DakExecutableHash,
      aProject.DakSourceRevision, aProject.SemanticParserVersion,
      aProject.SemanticModelVersion, aProject.SemanticCacheSchemaVersion,
      aProject.SemanticSourceRevision, aProject.SemanticFactSource,
      aProject.SemanticSnapshotUnitCount, aProject.SemanticVerifiedScopeUnitCount,
      aProject.SemanticModelFallbackUnitCount, aProject.SemanticHeuristicFallbackUnitCount,
      aProject.SemanticRejectedDeclarationCount, Length(aProject.SemanticDiagnostics),
      cGlobalVarsCacheSchemaVersion, aSummary.RejectedImpossibleDeclarations]));
    for lSymbol in aFilteredSymbols do
    begin
      lBuilder.AppendLine(Format('%s.%s: %s [%s] (%s:%d)', [lSymbol.UnitName,
        lSymbol.Name, lSymbol.TypeName, GlobalVarKindToText(lSymbol.Kind), lSymbol.FileName,
        lSymbol.Line]));
      lBuilder.AppendLine(Format('  declaration: role=%s scope=%s ownerScope=%s symbol=%s',
        [lSymbol.DeclarationRole, lSymbol.ScopeKind, lSymbol.OwnerScopeId,
        lSymbol.SymbolId]));
      if lSymbol.UsedBy.Count = 0 then
        lBuilder.AppendLine('  used by: none')
      else begin
        lBuilder.AppendLine('  used by:');
        for lRef in lSymbol.UsedBy do
          lBuilder.AppendLine(Format('    %s.%s [%s] (%s:%d)',
            [lRef.UnitName, lRef.RoutineName, AccessToText(lRef.Access), lRef.FileName,
            lRef.Line]));
      end;
    end;
    if aAmbiguities.Count > 0 then
    begin
      lBuilder.AppendLine;
      lBuilder.AppendLine('Ambiguities:');
      for lAmbiguity in aAmbiguities do
        lBuilder.AppendLine(Format('  %s in %s.%s [%s] (%s:%d) candidates=%s',
          [lAmbiguity.Name, lAmbiguity.UnitName, lAmbiguity.RoutineName,
          AccessToText(lAmbiguity.Access), lAmbiguity.FileName, lAmbiguity.Line,
          lAmbiguity.Candidates]));
    end;
    Result := TrimRight(lBuilder.ToString);
  finally
    lBuilder.Free;
  end;
end;

end.
