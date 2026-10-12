unit Dak.Consistency.Dfm;

interface

uses
  System.JSON,
  DelphiSemantics.Model, DelphiSemantics.ProjectContext;

procedure AppendDfmConsistency(const aProject: TDelphiSemanticProjectInfo;
  const aModels: TArray<TDelphiSemanticUnitModel>; const aEvents, aDiagnostics: TJSONArray;
  var aComplete: Boolean);

implementation

uses
  System.Classes, System.Generics.Collections, System.IOUtils, System.RegularExpressions, System.SysUtils,
  DelphiSemantics.Consistency.EventBindings, DelphiSemantics.Resolve.TypeResolver,
  DelphiSemantics.SemanticGraph,
  Dak.DfmText;

type
  TDfmBindingContext = record
    fModels: TArray<TDelphiSemanticUnitModel>;
    fTypes: TDelphiSemanticTypeIdentityIndex;
    fUnitName: string;
    fFormClass: string;
    fFileName: string;
    fFormFileName: string;
    fComponentUnit: string;
    fEvents: TJSONArray;
  end;

  TDfmLayer = class
  public
    fDocument: TDfmTextDocument;
    fFileName, fUnitName: string;
    destructor Destroy; override;
  end;

  TDfmAssignment = record
    fName, fValue, fFileName: string;
    fLine: Integer;
    fEventCandidate: Boolean;
  end;

  TDfmEffectiveComponent = class
  public
    fPath, fName, fClassName, fUnitName: string;
    fAssignments: TArray<TDfmAssignment>;
  end;

destructor TDfmLayer.Destroy;
begin
  fDocument.Free;
  inherited Destroy;
end;
function EvidenceJson(const aEvidence: TDelphiSemanticEventEvidence): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('unitName', aEvidence.UnitName);
  Result.AddPair('fileName', aEvidence.FileName);
  Result.AddPair('owner', aEvidence.OwnerName);
  Result.AddPair('name', aEvidence.Name);
  Result.AddPair('line', TJSONNumber.Create(aEvidence.Line));
  Result.AddPair('column', TJSONNumber.Create(aEvidence.Column));
end;

procedure AppendBinding(const aContext: TDfmBindingContext;
  const aBinding: TDelphiSemanticEventBinding; const aComponent: string; const aLine: Integer;
  var aComplete: Boolean);
var
  lResult: TDelphiSemanticEventBindingResult;
  lJson: TJSONObject;
begin
  lResult := TDelphiSemanticEventBindingResolver.ResolveInContext(
    aContext.fModels, aContext.fTypes, aBinding, aContext.fComponentUnit);
  if lResult.Status = 'not-event' then
    Exit;
  lJson := TJSONObject.Create;
  aContext.fEvents.AddElement(lJson);
  lJson.AddPair('fileName', aContext.fFileName);
  lJson.AddPair('formFileName', aContext.fFormFileName);
  lJson.AddPair('line', TJSONNumber.Create(aLine));
  lJson.AddPair('component', aComponent);
  lJson.AddPair('componentClass', aBinding.ComponentClassName);
  lJson.AddPair('formClass', aBinding.FormClassName);
  lJson.AddPair('event', aBinding.EventName);
  lJson.AddPair('handler', aBinding.HandlerName);
  lJson.AddPair('status', lResult.Status);
  lJson.AddPair('reason', lResult.Reason);
  lJson.AddPair('eventProperty', EvidenceJson(lResult.EventProperty));
  lJson.AddPair('eventType', EvidenceJson(lResult.EventType));
  lJson.AddPair('handlerDeclaration', EvidenceJson(lResult.Handler));
  if lResult.Status = 'unknown' then
    aComplete := False;
end;

procedure AddDfmUnknown(const aDiagnostics: TJSONArray; const aFileName, aReason, aMessage: string;
  out aComplete: Boolean);
var
  lJson: TJSONObject;
  lExisting: TJSONValue;
begin
  aComplete := False;
  // Ancestor traversal and the main model loop can discover the same gap.
  for lExisting in aDiagnostics do
    if SameText(lExisting.GetValue<string>('fileName'), aFileName) and
      (lExisting.GetValue<string>('reason') = aReason) and
      (lExisting.GetValue<string>('message') = aMessage) then
      Exit;
  lJson := TJSONObject.Create;
  aDiagnostics.AddElement(lJson);
  lJson.AddPair('reason', aReason);
  lJson.AddPair('fileName', aFileName);
  lJson.AddPair('message', aMessage);
end;

type
  TResourceFormDisposition = (rfdNone, rfdResourceOnly, rfdAncestryUnknown);

function RootUnitForType(const aName: string): string;
begin
  Result := '';
  if SameText(aName, 'TForm') or SameText(aName, 'TCustomForm') or
    SameText(aName, 'TFrame') or SameText(aName, 'TCustomFrame') then
    Result := 'Vcl.Forms'
  else if SameText(aName, 'TDataModule') then
    Result := 'System.Classes';
end;

function ModelIndexForUnit(const aModels: TArray<TDelphiSemanticUnitModel>;
  const aUnitName: string): Integer;
var
  i: Integer;
begin
  Result := -1;
  for i := 0 to High(aModels) do
    if SameText(aModels[i].UnitName, aUnitName) then
    begin
      if Result >= 0 then
        Exit(-1);
      Result := i;
    end;
end;

function ResourceEdgeImportOrderUnproved(const aModels: TArray<TDelphiSemanticUnitModel>;
  const aClass, aBase: TDelphiSemanticTypeIdentity): Boolean;
var
  lModelIndex, lInterfaceCount, lImportCount: Integer;
  lRootUnit, lImport: string;
  lResolvedSeen: Boolean;
  i: Integer;
begin
  Result := False;
  // Qualified names and declarations in the same unit do not use import order.
  lRootUnit := RootUnitForType(aClass.BaseTypeName);
  if (lRootUnit = '') or SameText(aBase.UnitName, lRootUnit) or
    SameText(aClass.UnitName, aBase.UnitName) then
    Exit;
  lModelIndex := ModelIndexForUnit(aModels, aClass.UnitName);
  if lModelIndex < 0 then
    Exit(True);
  lInterfaceCount := Length(aModels[lModelIndex].InterfaceUses);
  lImportCount := lInterfaceCount;
  // Implementation imports are visible only to implementation declarations;
  // they take precedence over interface imports, in their own clause order.
  if SameText(aClass.SectionKind, 'implementation') then
    Inc(lImportCount, Length(aModels[lModelIndex].ImplementationUses));
  lResolvedSeen := False;
  for i := 0 to lImportCount - 1 do
  begin
    if i < lInterfaceCount then
      lImport := aModels[lModelIndex].InterfaceUses[i]
    else
      lImport := aModels[lModelIndex].ImplementationUses[i - lInterfaceCount];
    if SameText(lImport, aBase.UnitName) then
    begin
      lResolvedSeen := True;
      Result := False;
    end else if lResolvedSeen and
      (SameText(lImport, lRootUnit) or
      SameText(lImport, Copy(lRootUnit, LastDelimiter('.', lRootUnit) + 1, MaxInt)) or
      (ModelIndexForUnit(aModels, lImport) < 0)) then
      Result := True;
  end;
  // An imported identity absent from the clause cannot prove this edge either.
  Result := Result or not lResolvedSeen;
end;

function ResourceAncestryStartsAtDeclaration(const aModel: TDelphiSemanticUnitModel;
  const aDeclaration: TDelphiSemanticDeclaration;
  const aIdentity: TDelphiSemanticTypeIdentity): Boolean;
var
  lFileName: string;
begin
  lFileName := aDeclaration.FileName;
  if lFileName = '' then
    lFileName := aModel.FileName;
  Result := SameText(aIdentity.UnitName, aModel.UnitName) and
    SameText(aIdentity.Name, aDeclaration.Name) and
    SameText(aIdentity.SectionKind, aDeclaration.SectionKind) and
    SameText(aIdentity.SourceRange.FileName, lFileName) and
    (aDeclaration.Offset > 0) and (aIdentity.SourceRange.Offset = aDeclaration.Offset) and
    (aDeclaration.Line > 0) and (aIdentity.SourceRange.Line = aDeclaration.Line) and
    (aDeclaration.Column > 0) and (aIdentity.SourceRange.Column = aDeclaration.Column);
end;

function ResourceFormDisposition(const aModel: TDelphiSemanticUnitModel;
  const aModels: TArray<TDelphiSemanticUnitModel>;
  const aTypes: TDelphiSemanticTypeIdentityIndex): TResourceFormDisposition;
var
  lDeclaration: TDelphiSemanticDeclaration;
  lAncestry: TDelphiSemanticClassAncestry;
  lClass: TDelphiSemanticTypeIdentity;
  lBaseName, lRootUnit: string;
  lModelIndex: Integer;
  lImport: string;
  lImported: Boolean;
  lUnproved: Boolean;
  i: Integer;
begin
  Result := TResourceFormDisposition.rfdNone;
  for lDeclaration in aModel.Declarations do
  begin
    if not SameText(lDeclaration.Kind, 'type') or
      not SameText(lDeclaration.TypeName, 'class') or
      (not SameText(lDeclaration.DeclarationRole, 'declaration') and
      not SameText(lDeclaration.DeclarationRole, 'forward')) then
      Continue;
    lAncestry := TDelphiSemanticEventBindingResolver.InspectClassAncestry(
      aModels, aTypes, aModel.UnitName, lDeclaration.Name);
    // Unqualified lookup can bind an imported homonym instead of this declaration.
    // Do not accept either complete ancestry or an external-root tail for that class.
    if Length(lAncestry.Classes) = 0 then
    begin
      Result := TResourceFormDisposition.rfdAncestryUnknown;
      Continue;
    end;
    if not ResourceAncestryStartsAtDeclaration(aModel, lDeclaration, lAncestry.Classes[0]) then
    begin
      Result := TResourceFormDisposition.rfdAncestryUnknown;
      Continue;
    end;
    if lAncestry.Complete then
    begin
      lUnproved := False;
      for i := 0 to High(lAncestry.Classes) - 1 do
        lUnproved := lUnproved or ResourceEdgeImportOrderUnproved(
          aModels, lAncestry.Classes[i], lAncestry.Classes[i + 1]);
      if lUnproved then
      begin
        Result := TResourceFormDisposition.rfdAncestryUnknown;
        Continue;
      end;
      for lClass in lAncestry.Classes do
        if (RootUnitForType(lClass.Name) <> '') and
          SameText(RootUnitForType(lClass.Name), lClass.UnitName) then
          Exit(TResourceFormDisposition.rfdResourceOnly);
      // Every resolved class and import edge is proved; none is a standard root.
      Continue;
    end;
    Result := TResourceFormDisposition.rfdAncestryUnknown;
    if (lAncestry.Reason <> 'ancestry.type-unresolved') or (Length(lAncestry.Classes) = 0) then
      Continue;
    // Only the final unresolved edge may refer to an external VCL root.
    // Earlier edges have already bound to the next source identity.
    lClass := lAncestry.Classes[High(lAncestry.Classes)];
    lModelIndex := ModelIndexForUnit(aModels, lClass.UnitName);
    if lModelIndex < 0 then
      Continue;
    lBaseName := lClass.BaseTypeName;
    if Pos('.', lBaseName) > 0 then
    begin
      lRootUnit := Copy(lBaseName, 1, LastDelimiter('.', lBaseName) - 1);
      lBaseName := Copy(lBaseName, LastDelimiter('.', lBaseName) + 1, MaxInt);
    end else
      lRootUnit := '';
    if (RootUnitForType(lBaseName) = '') or
      ((lRootUnit <> '') and not SameText(lRootUnit, RootUnitForType(lBaseName))) then
      Continue;
    lImported := False;
    for lImport in aModels[lModelIndex].InterfaceUses do
      lImported := lImported or SameText(lImport, RootUnitForType(lBaseName));
    if lImported and (lRootUnit <> '') then
      Exit(TResourceFormDisposition.rfdResourceOnly);
  end;
end;

procedure CheckResourceCoverage(const aModel: TDelphiSemanticUnitModel;
  const aModels: TArray<TDelphiSemanticUnitModel>;
  const aTypes: TDelphiSemanticTypeIdentityIndex;
  const aDiagnostics: TJSONArray; var aComplete: Boolean);
var
  lMatch: TMatch;
  lResource, lPath: string;
  lDisposition: TResourceFormDisposition;
begin
  // This is a conservative discovery guard, not a second preprocessor. Includes
  // and nonstandard resource layouts remain explicit unknowns until mapped.
  if Length(aModel.IncludeFileNames) > 0 then
    AddDfmUnknown(aDiagnostics, aModel.FileName, 'dfm.include-resource-coverage-unknown',
      'Resource directives in included source are not yet mapped to form modules.', aComplete);
  for lMatch in TRegEx.Matches(aModel.SourceText,
    '(?is)(?:\{\$|\(\*\$)\s*(?:R|RESOURCE)\s+(.+?)(?:\}|\*\))') do
  begin
    lResource := Trim(lMatch.Groups[1].Value).Trim(['''', '"']);
    if SameText(ExtractFileExt(lResource), '.res') then
    begin
      lPath := ChangeFileExt(aModel.FileName, '.dfm');
      if not FileExists(lPath) then
      begin
        lDisposition := ResourceFormDisposition(aModel, aModels, aTypes);
        if lDisposition = TResourceFormDisposition.rfdResourceOnly then
          AddDfmUnknown(aDiagnostics, aModel.FileName, 'dfm.resource-only-unsupported',
            lResource, aComplete)
        else if lDisposition = TResourceFormDisposition.rfdAncestryUnknown then
          AddDfmUnknown(aDiagnostics, aModel.FileName, 'dfm.resource-ancestry-unknown',
            lResource, aComplete);
      end;
      Continue;
    end;
    if SameText(ExtractFileExt(lResource), '.dcr') then
      Continue;
    lPath := ChangeFileExt(aModel.FileName, '.dfm');
    if not SameText(lResource, '*.dfm') and not SameText(lResource, ExtractFileName(lPath)) then
      AddDfmUnknown(aDiagnostics, aModel.FileName, 'dfm.resource-layout-unsupported', lResource, aComplete)
    else if not FileExists(lPath) then
      AddDfmUnknown(aDiagnostics, lPath, 'dfm.resource-unavailable', lResource, aComplete);
  end;
end;

function LoadLayer(const aFileName, aUnitName: string;
  const aLayers: TObjectList<TDfmLayer>; const aDiagnostics: TJSONArray;
  var aComplete: Boolean): Boolean;
var
  lLayer: TDfmLayer;
  lDocument: TDfmTextDocument;
  lBytes: TBytes;
  lError: string;
begin
  Result := False;
  lBytes := TFile.ReadAllBytes(aFileName);
  if (Length(lBytes) >= 4) and (lBytes[0] = Ord('T')) and (lBytes[1] = Ord('P')) and
    (lBytes[2] = Ord('F')) and (lBytes[3] = Ord('0')) then
  begin
    AddDfmUnknown(aDiagnostics, aFileName, 'dfm.binary-unsupported',
      'Semantic binding inspection requires text DFM; use dfm-check for binary streaming.', aComplete);
    Exit;
  end;
  lLayer := TDfmLayer.Create;
  aLayers.Add(lLayer);
  lLayer.fFileName := aFileName;
  lLayer.fUnitName := aUnitName;
  if not TryLoadDfmTextDocument(aFileName, lDocument, lError) then
  begin
    AddDfmUnknown(aDiagnostics, aFileName, 'dfm.parse-failed', lError, aComplete);
    Exit;
  end;
  lLayer.fDocument := lDocument;
  Result := lLayer.fDocument.Root <> nil;
  if not Result then
    AddDfmUnknown(aDiagnostics, aFileName, 'dfm.ancestry-unavailable', 'Missing form root.', aComplete);
end;

function HasAncestorResourceCoverage(const aContext: TDfmBindingContext;
  const aUnitName: string; const aDiagnostics: TJSONArray): Boolean;
var
  lModel: TDelphiSemanticUnitModel;
begin
  Result := False;
  for lModel in aContext.fModels do
    if SameText(lModel.UnitName, aUnitName) then
    begin
      Result := True;
      CheckResourceCoverage(lModel, aContext.fModels, aContext.fTypes, aDiagnostics, Result);
      Exit;
    end;
end;
function CollectAncestors(const aContext: TDfmBindingContext;
  const aLayers: TObjectList<TDfmLayer>; const aDiagnostics: TJSONArray;
  var aComplete: Boolean): Boolean;
var
  lAncestry: TDelphiSemanticClassAncestry;
  i: Integer;
  lFileName: string;
  lRoot: TDfmTextComponent;
begin
  Result := False;
  lRoot := aLayers[0].fDocument.Root;
  if SameText(lRoot.HeaderKind, 'object') then
    Exit(True);
  if not SameText(lRoot.HeaderKind, 'inherited') then
    Exit;
  lAncestry := TDelphiSemanticEventBindingResolver.InspectClassAncestry(
    aContext.fModels, aContext.fTypes, aContext.fUnitName, aContext.fFormClass);
  // Only a missing external base may be cut off by an ordinary DFM resource.
  // Cycles and incomplete declarations cannot certify any merged hierarchy.
  if not lAncestry.Complete and (lAncestry.Reason <> 'ancestry.type-unresolved') then
    Exit;
  for i := 0 to High(lAncestry.Classes) do
  begin
    if not HasAncestorResourceCoverage(aContext, lAncestry.Classes[i].UnitName, aDiagnostics) then
      Exit;
    if i = 0 then
      Continue;
    lFileName := ChangeFileExt(lAncestry.Classes[i].SourceRange.FileName, '.dfm');
    if not FileExists(lFileName) then
      Continue;
    if not LoadLayer(lFileName, lAncestry.Classes[i].UnitName, aLayers, aDiagnostics, aComplete) then
      Exit;
    lRoot := aLayers.Last.fDocument.Root;
    if not SameText(lRoot.DfmClassName, lAncestry.Classes[i].Name) then
      Exit;
    if SameText(lRoot.HeaderKind, 'object') then
      Exit(True);
    if not SameText(lRoot.HeaderKind, 'inherited') then
      Exit;
  end;
end;

function ComponentPath(const aComponent: TDfmTextComponent): string;
begin
  if aComponent.Parent = nil then
    Exit('');
  Result := ComponentPath(aComponent.Parent) + '/' + LowerCase(aComponent.Name);
end;

procedure MergeAssignments(const aComponent: TDfmTextComponent;
  const aFileName: string; const aTarget: TDfmEffectiveComponent);
var
  lNames: TStringList;
  i, j, lLine: Integer;
  lAssignment: TDfmAssignment;
begin
  lNames := TStringList.Create;
  try
    lNames.Assign(aComponent.Properties);
    lNames.AddStrings(aComponent.Events);
    for i := 0 to lNames.Count - 1 do
    begin
      lAssignment := Default(TDfmAssignment);
      lAssignment.fName := lNames.Names[i];
      lAssignment.fEventCandidate := aComponent.Events.IndexOfName(lAssignment.fName) >= 0;
      lAssignment.fValue := lNames.ValueFromIndex[i];
      lAssignment.fFileName := aFileName;
      if not aComponent.TryGetPropertyLine(lAssignment.fName, lLine) then
        lLine := aComponent.StartLine;
      lAssignment.fLine := lLine;
      j := 0;
      while (j < Length(aTarget.fAssignments)) and
        not SameText(aTarget.fAssignments[j].fName, lAssignment.fName) do
        Inc(j);
      if j = Length(aTarget.fAssignments) then
        SetLength(aTarget.fAssignments, j + 1);
      aTarget.fAssignments[j] := lAssignment;
    end;
  finally
    lNames.Free;
  end;
end;

function MergeComponent(const aComponent: TDfmTextComponent; const aLayer: TDfmLayer;
  const aComponents: TObjectList<TDfmEffectiveComponent>): Boolean;
var
  lTarget, lCandidate: TDfmEffectiveComponent;
  lPath: string;
begin
  Result := False;
  lPath := ComponentPath(aComponent);
  lTarget := nil;
  for lCandidate in aComponents do
    if lCandidate.fPath = lPath then
      lTarget := lCandidate;
  if SameText(aComponent.HeaderKind, 'inherited') then
  begin
    if lTarget = nil then
      Exit;
    if (lPath <> '') and not SameText(lTarget.fClassName, aComponent.DfmClassName) then
      Exit;
  end else if SameText(aComponent.HeaderKind, 'object') then
  begin
    if lTarget <> nil then
      Exit;
    lTarget := TDfmEffectiveComponent.Create;
    aComponents.Add(lTarget);
    lTarget.fPath := lPath;
    lTarget.fClassName := aComponent.DfmClassName;
    lTarget.fUnitName := aLayer.fUnitName;
  end else
    Exit;
  lTarget.fName := aComponent.Name;
  // The root is the selected descendant; nested components keep their original
  // declaration class/unit even when an inherited block overrides a property.
  if lPath = '' then
  begin
    lTarget.fClassName := aComponent.DfmClassName;
    lTarget.fUnitName := aLayer.fUnitName;
  end;
  MergeAssignments(aComponent, aLayer.fFileName, lTarget);
  Result := True;
end;

function MergeLayers(const aLayers: TObjectList<TDfmLayer>;
  const aComponents: TObjectList<TDfmEffectiveComponent>; const aDiagnostics: TJSONArray;
  var aComplete: Boolean): Boolean;
var
  i: Integer;
  lComponent: TDfmTextComponent;
begin
  Result := False;
  for i := aLayers.Count - 1 downto 0 do
    for lComponent in aLayers[i].fDocument.Components do
      if not MergeComponent(lComponent, aLayers[i], aComponents) then
      begin
        AddDfmUnknown(aDiagnostics, aLayers[i].fFileName, 'dfm.ancestry-unavailable',
          'Missing, conflicting or unsupported component: ' + lComponent.Name, aComplete);
        Exit;
      end;
  Result := True;
end;

procedure AppendEffectiveBindings(const aContext: TDfmBindingContext;
  const aComponents: TObjectList<TDfmEffectiveComponent>; var aComplete: Boolean);
var
  lComponent: TDfmEffectiveComponent;
  lAssignment: TDfmAssignment;
  lContext: TDfmBindingContext;
  lBinding: TDelphiSemanticEventBinding;
begin
  lContext := aContext;
  lBinding := Default(TDelphiSemanticEventBinding);
  lBinding.UnitName := aContext.fUnitName;
  lBinding.FormClassName := aContext.fFormClass;
  for lComponent in aComponents do
  begin
    lBinding.ComponentClassName := lComponent.fClassName;
    lContext.fComponentUnit := lComponent.fUnitName;
    for lAssignment in lComponent.fAssignments do
    begin
      if SameText(lAssignment.fValue, 'nil') or
        (not lAssignment.fEventCandidate and not IsValidIdent(lAssignment.fValue)) then
        Continue;
      lBinding.EventName := lAssignment.fName;
      lBinding.HandlerName := lAssignment.fValue;
      lContext.fFileName := lAssignment.fFileName;
      AppendBinding(lContext, lBinding, lComponent.fName, lAssignment.fLine, aComplete);
    end;
  end;
end;

procedure InspectDfm(const aModel: TDelphiSemanticUnitModel;
  const aModels: TArray<TDelphiSemanticUnitModel>; const aTypes: TDelphiSemanticTypeIdentityIndex;
  const aFileName: string; const aEvents, aDiagnostics: TJSONArray; var aComplete: Boolean);
var
  lContext: TDfmBindingContext;
  lLayers: TObjectList<TDfmLayer>;
  lComponents: TObjectList<TDfmEffectiveComponent>;
begin
  lLayers := TObjectList<TDfmLayer>.Create(True);
  lComponents := TObjectList<TDfmEffectiveComponent>.Create(True);
  try
    if not LoadLayer(aFileName, aModel.UnitName, lLayers, aDiagnostics, aComplete) then
      Exit;
    lContext := Default(TDfmBindingContext);
    lContext.fModels := aModels;
    lContext.fTypes := aTypes;
    lContext.fUnitName := aModel.UnitName;
    lContext.fFormClass := lLayers[0].fDocument.Root.DfmClassName;
    lContext.fFormFileName := aFileName;
    lContext.fEvents := aEvents;
    if not CollectAncestors(lContext, lLayers, aDiagnostics, aComplete) then
    begin
      AddDfmUnknown(aDiagnostics, aFileName, 'dfm.ancestry-unavailable',
        'No complete supported DFM hierarchy reaches an ordinary object resource.', aComplete);
      Exit;
    end;
    if MergeLayers(lLayers, lComponents, aDiagnostics, aComplete) then
      AppendEffectiveBindings(lContext, lComponents, aComplete);
  finally
    lComponents.Free;
    lLayers.Free;
  end;
end;
procedure AppendDfmConsistency(const aProject: TDelphiSemanticProjectInfo;
  const aModels: TArray<TDelphiSemanticUnitModel>; const aEvents, aDiagnostics: TJSONArray;
  var aComplete: Boolean);
var
  lGraph: TDelphiSemanticSemanticGraph;
  lTypes: TDelphiSemanticTypeIdentityIndex;
  lModel: TDelphiSemanticUnitModel;
  lFileName: string;
begin
  lGraph := TDelphiSemanticSemanticGraphBuilder.Build(aProject, aModels);
  try
    lTypes := TDelphiSemanticTypeResolver.BuildIndex(lGraph);
    for lModel in aModels do
    begin
      CheckResourceCoverage(lModel, aModels, lTypes, aDiagnostics, aComplete);
      lFileName := ChangeFileExt(lModel.FileName, '.dfm');
      if FileExists(lFileName) then
        InspectDfm(lModel, aModels, lTypes, lFileName, aEvents, aDiagnostics, aComplete);
    end;
  finally
    lGraph.Free;
  end;
end;

end.
