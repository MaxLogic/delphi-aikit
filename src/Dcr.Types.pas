unit Dcr.Types;

interface

{$SCOPEDENUMS ON}

type
  TOutputKind = (okIni, okXml, okBat);

  TPropertySource = (psUnknown, psDproj, psOptset, psRegistry, psEnvOptions);

  TAppOptions = record
    fDprojPath: string;
    fPlatform: string;
    fConfig: string;
    fDelphiVersion: string;
    fOutKind: TOutputKind;
    fOutPath: string;
    fHasOutPath: Boolean;
    fHasOutKind: Boolean;
    fVerbose: Boolean;
    fRsVarsPath: string;
    fHasRsVarsPath: Boolean;
    fEnvOptionsPath: string;
    fHasEnvOptionsPath: Boolean;
    fFixOutput: string;
    fHasFixOutput: Boolean;
    fFixIgnore: string;
    fHasFixIgnore: Boolean;
    fFixSettings: string;
    fHasFixSettings: Boolean;
    fFixSilent: Boolean;
    fHasFixSilent: Boolean;
    fFixXml: Boolean;
    fHasFixXml: Boolean;
    fFixCsv: Boolean;
    fHasFixCsv: Boolean;
    fRunFixInsight: Boolean;
  end;

  TFixInsightExtraOptions = record
    fExePath: string;
    fOutput: string;
    fIgnore: string;
    fSettings: string;
    fSilent: Boolean;
    fXml: Boolean;
    fCsv: Boolean;
  end;

  TFixInsightParams = record
    fProjectDpr: string;
    fFixInsightExe: string;
    fFixOutput: string;
    fFixIgnore: string;
    fFixSettings: string;
    fFixSilent: Boolean;
    fFixXml: Boolean;
    fFixCsv: Boolean;
    fDefines: TArray<string>;
    fUnitSearchPath: TArray<string>;
    fLibraryPath: TArray<string>;
    fUnitScopes: TArray<string>;
    fUnitAliases: TArray<string>;
    fDelphiVersion: string;
    fPlatform: string;
    fConfig: string;
    fLibrarySource: TPropertySource;
    fDefineSource: TPropertySource;
    fSearchPathSource: TPropertySource;
    fUnitScopesSource: TPropertySource;
    fUnitAliasesSource: TPropertySource;
  end;

implementation

end.
