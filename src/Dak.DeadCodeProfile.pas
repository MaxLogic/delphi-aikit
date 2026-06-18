unit Dak.DeadCodeProfile;

interface

function DefaultDeadCodeProfileName: string;
function DeadCodeAllowedProfileNamesText: string;
function TryNormalizeDeadCodeProfileName(const aValue: string; out aProfileName: string): Boolean; overload;
function TryNormalizeDeadCodeProfileName(const aValue: string; out aProfileName, aAllowedNames: string): Boolean; overload;

implementation

uses
  DelphiSemantics.DeadCode;

function DefaultDeadCodeProfileName: string;
begin
  Result := TDelphiSemanticDeadCodeProfiles.ToName(
    TDelphiSemanticDeadCodeProfiles.DefaultRemovalProfile);
end;

function DeadCodeAllowedProfileNamesText: string;
begin
  Result := TDelphiSemanticDeadCodeProfiles.AllowedNamesText;
end;

function TryNormalizeDeadCodeProfileName(const aValue: string; out aProfileName: string): Boolean;
var
  lAllowedNames: string;
begin
  Result := TryNormalizeDeadCodeProfileName(aValue, aProfileName, lAllowedNames);
end;

function TryNormalizeDeadCodeProfileName(const aValue: string; out aProfileName,
  aAllowedNames: string): Boolean;
var
  lProfile: TDelphiSemanticDeadCodeSafetyProfile;
begin
  aAllowedNames := DeadCodeAllowedProfileNamesText;
  if not TDelphiSemanticDeadCodeProfiles.TryParse(aValue, lProfile) then
  begin
    aProfileName := '';
    Exit(False);
  end;

  aProfileName := TDelphiSemanticDeadCodeProfiles.ToName(lProfile);
  Result := True;
end;

end.
