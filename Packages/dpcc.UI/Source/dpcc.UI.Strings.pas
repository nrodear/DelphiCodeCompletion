unit dpcc.UI.Strings;

// Oberflächentexte von dpcc auf Deutsch und Englisch (#446). Die Sprache
// setzt die IDE-Schicht beim Laden nach der Sprache der IDE (Rückfall
// Englisch). Bezeichner, Signaturen und XMLDoc-Inhalte werden nie übersetzt.
// Statt resourcestring eine Tabelle: Die Sprache wechselt ohne Ressourcen-DLL.

interface

uses
  dpcc.Core.Documentation.Layout,
  dpcc.Core.Localization.Language,
  dpcc.Core.Signature.Format;

{$SCOPEDENUMS ON}

type
  /// <summary>Sprache der Oberfläche; dieselbe für Core (dpcc.Core.Localization.Language, #1458).</summary>
  TDpccLanguage = dpcc.Core.Localization.Language.TDpccLanguage;

  TDpccTextId = (
    OptionalDefault, NoOverloadWith, MoreOverloads, KindClass, KindClassRef, KindObject, KindRecord, KindInterface,
    KindHelper, KindEnum, KindType, KindMethod, KindConstructor, KindRoutine, KindProperty, KindField, KindVariable,
    KindConstant, KindEnumMember, ProblemsConfidence, ConfidenceHigh,
    ConfidenceMedium, ConfidenceLow, HelpInsightIdeOff, HelpInsightIdeOn, TooltipWatchesIdeOff, TooltipWatchesIdeOn,
    AccessSignature, AccessParameter, DocTypeParams, DocValue, DocExample, DocSeeAlso, DocParams, DocReturns,
    DocExceptions, DocRemarks, DocUndocumented, DocMore, DocLess, DocCountParam, DocCountParams, DocCountTypeParam,
    DocCountTypeParams, DocCountException, DocCountExceptions, DocItemReturns, DocItemValue, DocItemRemarks,
    DocItemExample, DocItemSeeAlso, StatusOpenLog, StatusRestartServer, BugReportMenu,
    // SettingsTabGeneral … SettingsTabInsert und SettingsFavoritesTitle gibt es seit OPT1 nicht mehr (eine Seite ohne
    // Reiter, keine Liste der angehefteten Favoriten).
    TypeArgHeader,
    TypeArgHeaderPlain, TypeArgOnlyClasses, TypeArgOnlyValues, TypeArgOnlyConstructible, TypeArgImplements,
    TypeArgDescends, TypeArgHiddenFooter, TypeArgKindClasses, TypeArgKindRecords, TypeArgKindInterfaces,
    TypeArgKindEnums, TypeArgKindBasic, UsesHiddenOne, UsesHiddenFew, UsesHiddenMore, UsesCycleDirect, UsesCycleChain,
    InheritedAbstractOne, InheritedAbstractMore, ProblemsCompilerConfirmed, ProblemsCompilerConfirmedCode,
    // Platzhalter im Parameter-Hint (#451).
    FormatPlaceholder, FormatWidth, FormatPrecision, FormatUnused, FormatInvalid, FormatTooMany, FormatConflict,
    FormatKindInteger, FormatKindUnsigned, FormatKindHex, FormatKindFloat, FormatKindMoney, FormatKindString,
    FormatKindPointer, FormatLiteralString, FormatLiteralChar, FormatLiteralInteger, FormatLiteralFloat,
    FormatLiteralBoolean, FormatLiteralOther,
    // Schranke für Hinweise und Warnungen (#530).
    BuildCountWarning, BuildCountWarnings, BuildCountHint, BuildCountHints, BuildCountJoin);

  TDpccStrings = class
  private
    class function GetLanguage: TDpccLanguage; static;
    class procedure SetLanguage(AValue: TDpccLanguage); static;
  public
    class function Text(AId: TDpccTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TDpccTextId; const AArgs: array of const): string; static;
    /// <summary>"Konfidenz: mittel" zu "high", "medium", "low" (#144); '' bei anderem Wert.</summary>
    class function Confidence(const AName: string): string; static;
    /// <summary>Überschrift über Typargumenten (#450): „T: class · nur Klassen“, ohne Constraint „Typargument T“.
    /// AHint ist der Code des Servers (classes, values, constructible, implements:X, descends:X).</summary>
    class function TypeArgHeading(const AParam, AConstraint, AHint: string): string; static;
    /// <summary>Fußzeile „Ausgeblendet: Records, Aufzählungen“ zu den Codes "records,enums"; '' ohne.</summary>
    class function TypeArgHidden(const AKinds: string): string; static;
    /// <summary>Fußzeile im uses-Abschnitt (#469) zu den schon eingebundenen Units: „X ist schon eingebunden und
    /// fehlt hier“, bis drei Namen aufgezählt, sonst „X, Y und n weitere …“; '' ohne.</summary>
    class function UsesHidden(const AUnits: TArray<string>): string; static;
    /// <summary>Zirkelbezug (#469) zur Kette "uA → uB → Haupt": „uA bindet diese Unit über uB im interface-Teil
    /// ein“; '' ohne.</summary>
    class function UsesCycle(const AChain: string): string; static;
    /// <summary>Zählung eines Builds (#530): „2 Warnungen, 1 Hinweis“, Einzahl bei 1; '' ohne beides.</summary>
    class function BuildCounts(AWarnings, AHints: Integer): string; static;
    /// <summary>Fußzeile nach "inherited " (#482) zu den ausgelassenen abstrakten Vorfahrmethoden
    /// ("TBasis.Zeichnen"): eine mit Namen, mehrere aufgezählt (höchstens drei, dann „…“); '' ohne.</summary>
    class function InheritedAbstract(const AMethods: TArray<string>): string; static;
    /// <summary>„vom Compiler bestätigt (E2035)“ (#1024); ohne AShowCode bzw. ohne Code nur „vom Compiler
    /// bestätigt“.</summary>
    class function CompilerConfirmed(const ACode: string; AShowCode: Boolean): string; static;
    /// <summary>Überschriften der XMLDoc-Abschnitte in der Sprache der Oberfläche; eine Stelle für Hover und
    /// Detailpanel.</summary>
    class function DocLabels: TDpccDocLabels; static;
    /// <summary>Zeile der Platzhalter im Parameter-Hint (#451); '' ohne.</summary>
    class function SignatureFormatLine(const ALine: TDpccFormatLine): string; static;
    /// <summary>Art eines Typbuchstabens (d → ganzzahlig, s → String …).</summary>
    class function FormatKind(AType: Char): string; static;
    /// <summary>Sprache aller Plugin-Texte (TDpccTextLanguage.Current).</summary>
    class property Language: TDpccLanguage read GetLanguage write SetLanguage;
  end;

implementation

uses
  dpcc.Core.Signature.Contract,
  System.SysUtils;

const
  cTexts: array[TDpccLanguage, TDpccTextId] of string = (
    ( 'optional, Standard %s',
     'Keine Überladung mit %d Parametern.', '… %d weitere',
     'Klasse', 'Klassenreferenz', 'Objekttyp', 'Record', 'Interface', 'Helfer', 'Aufzählung', 'Typ', 'Methode', 'Konstruktor', 'Routine', 'Property', 'Feld', 'Variable', 'Konstante', 'Aufzählungswert',
     'Konfidenz: %s', 'hoch', 'mittel', 'niedrig',
     'dpcc zeigt den Tooltip selbst und hat Help Insight der IDE abgeschaltet; wirkt nach dem ' +
       'nächsten Start von Delphi.',
     'dpcc hat Help Insight der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'dpcc zeigt Werte beim Debuggen im eigenen Tooltip und hat die Ausdrucksauswertung im Kurzhinweis der IDE ' +
       'abgeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'dpcc hat die Ausdrucksauswertung im Kurzhinweis der IDE wieder eingeschaltet; wirkt nach dem nächsten ' +
       'Start von Delphi.', 'dpcc Parameterhilfe', 'Parameter %d: %s',
     'TYPPARAMETER',
     'WERT',
     'BEISPIEL',
     'SIEHE AUCH',
     'PARAMETER',
     'RÜCKGABE',
     'AUSNAHMEN',
     'HINWEISE',
     'nicht dokumentiert',
     'Mehr anzeigen ▾',
     'Weniger anzeigen ▴',
     '%d Parameter',
     '%d Parameter',
     '%d Typparameter',
     '%d Typparameter',
     '%d Ausnahme',
     '%d Ausnahmen',
     'Rückgabe',
     'Wert',
     'Hinweis',
     'Beispiel',
     'Siehe auch',
     'Protokoll öffnen',
     'Server neu starten',
     'Fehlerbericht erstellen…',
     '%s: %s · %s', 'Typargument %s', 'nur Klassen',
     'nur Records und Grundtypen', 'nur Klassen mit parameterlosem Konstruktor', 'nur Typen, die %s implementieren',
     'nur Typen, die von %s abgeleitet sind', 'Ausgeblendet: %s', 'Klassen', 'Records', 'Interfaces',
     'Aufzählungen', 'Grundtypen',
     '%s ist schon eingebunden und fehlt hier',
     '%s sind schon eingebunden und fehlen hier',
     '%s und %d weitere sind schon eingebunden und fehlen hier',
     '%s bindet diese Unit im interface-Teil ein',
     '%s bindet diese Unit über %s im interface-Teil ein',
     '%s ist abstrakt und fehlt',
     'Abstrakte Vorfahrmethoden fehlen: %s',
     'vom Compiler bestätigt',
     'vom Compiler bestätigt (%s)',
     'Platzhalter %d von %d erwartet %s',
     'Breite für Platzhalter %d von %d (%s), ganzzahlig',
     'Genauigkeit für Platzhalter %d von %d (%s), ganzzahlig',
     'Argument %d kommt im Formatstring nicht vor (%d Platzhalter).',
     'Ungültiger Platzhalter %s: EConvertError zur Laufzeit.',
     'Mehr Argumente als Platzhalter: Argument %d wird nicht ausgegeben.',
     'Platzhalter %d (%s) erwartet %s, Argument %d ist %s: EConvertError zur Laufzeit.',
     'ganzzahlig', 'ganzzahlig ohne Vorzeichen', 'ganzzahlig (hexadezimal)', 'Gleitkomma', 'Gleitkomma (Währung)',
     'String', 'Zeiger', 'ein String', 'ein Zeichen', 'eine Ganzzahl', 'eine Gleitkommazahl', 'ein Wahrheitswert',
     'ein anderer Typ',
     '1 Warnung',
     '%d Warnungen',
     '1 Hinweis',
     '%d Hinweise',
     '%s, %s'),
    ( 'optional, default %s', 'No overload with %d parameters.', '… %d more',
     'Class', 'Class reference', 'Object type', 'Record', 'Interface', 'Helper', 'Enumeration', 'Type', 'Method', 'Constructor', 'Routine', 'Property', 'Field', 'Variable', 'Constant', 'Enumeration value',
     'Confidence: %s', 'high', 'medium', 'low',
     'dpcc shows the tooltip itself and switched off the IDE''s Help Insight; takes effect after ' +
       'the next start of Delphi.',
     'dpcc switched the IDE''s Help Insight back on; takes effect after the next start of Delphi.',
     'dpcc shows values while debugging in its own tooltip and switched off the IDE''s tooltip expression ' +
       'evaluation; takes effect after the next start of Delphi.',
     'dpcc switched the IDE''s tooltip expression evaluation back on; takes effect after the next start of ' +
       'Delphi.', 'dpcc parameter info', 'Parameter %d: %s',
     'TYPE PARAMETERS',
     'VALUE',
     'EXAMPLE',
     'SEE ALSO',
     'PARAMETERS',
     'RETURNS',
     'EXCEPTIONS',
     'REMARKS',
     'not documented',
     'Show more ▾',
     'Show less ▴',
     '%d parameter',
     '%d parameters',
     '%d type parameter',
     '%d type parameters',
     '%d exception',
     '%d exceptions',
     'Returns',
     'Value',
     'Remarks',
     'Example',
     'See also',
     'Open log',
     'Restart server',
     'Create bug report…',
     '%s: %s · %s',
     'Type argument %s', 'classes only', 'records and basic types only',
     'only classes with a parameterless constructor', 'only types implementing %s', 'only types descending from %s',
     'Hidden: %s', 'classes', 'records', 'interfaces', 'enumerations', 'basic types',
     '%s is already used and not listed',
     '%s are already used and not listed',
     '%s and %d more are already used and not listed',
     '%s uses this unit in its interface section',
     '%s uses this unit via %s in its interface section',
     '%s is abstract and not listed',
     'Abstract ancestor methods not listed: %s',
     'confirmed by the compiler',
     'confirmed by the compiler (%s)',
     'Placeholder %d of %d expects %s',
     'Width for placeholder %d of %d (%s), integer',
     'Precision for placeholder %d of %d (%s), integer',
     'Argument %d does not occur in the format string (%d placeholders).',
     'Invalid placeholder %s: EConvertError at run time.',
     'More arguments than placeholders: argument %d is not printed.',
     'Placeholder %d (%s) expects %s, argument %d is %s: EConvertError at run time.',
     'integer', 'unsigned integer', 'integer (hexadecimal)', 'floating point', 'floating point (currency)',
     'string', 'pointer', 'a string', 'a character', 'an integer', 'a floating-point number', 'a Boolean',
     'another type',
     '1 warning',
     '%d warnings',
     '1 hint',
     '%d hints',
     '%s, %s'));

{ TDpccStrings }

class function TDpccStrings.GetLanguage: TDpccLanguage;
begin
  Result := TDpccTextLanguage.Current;
end;

class procedure TDpccStrings.SetLanguage(AValue: TDpccLanguage);
begin
  TDpccTextLanguage.Current := AValue;
end;

class function TDpccStrings.Text(AId: TDpccTextId): string;
begin
  Result := cTexts[TDpccTextLanguage.Current, AId];
end;

class function TDpccStrings.Fmt(AId: TDpccTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TDpccTextLanguage.Current, AId], AArgs);
end;

class function TDpccStrings.FormatKind(AType: Char): string;
begin
  case AType of
    'd':
      Result := Text(TDpccTextId.FormatKindInteger);
    'u':
      Result := Text(TDpccTextId.FormatKindUnsigned);
    'x':
      Result := Text(TDpccTextId.FormatKindHex);
    'e', 'f', 'g', 'n':
      Result := Text(TDpccTextId.FormatKindFloat);
    'm':
      Result := Text(TDpccTextId.FormatKindMoney);
    's':
      Result := Text(TDpccTextId.FormatKindString);
    'p':
      Result := Text(TDpccTextId.FormatKindPointer);
  else
    Result := Text(TDpccTextId.FormatKindInteger);
  end;
end;

function LiteralKind(const AKind: string): string;
begin
  if AKind = 'string' then
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralString);
  end
  else if AKind = 'char' then
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralChar);
  end
  else if AKind = 'integer' then
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralInteger);
  end
  else if AKind = 'float' then
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralFloat);
  end
  else if AKind = 'boolean' then
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralBoolean);
  end
  else
  begin
    Result := TDpccStrings.Text(TDpccTextId.FormatLiteralOther);
  end;
end;

class function TDpccStrings.SignatureFormatLine(const ALine: TDpccFormatLine): string;
begin
  case ALine.Kind of
    TDpccFormatLineKind.Placeholder:
      Result := Fmt(TDpccTextId.FormatPlaceholder, [ALine.Placeholder + 1, ALine.Count, FormatKind(ALine.TypeChar)]);
    TDpccFormatLineKind.Width:
      Result := Fmt(TDpccTextId.FormatWidth, [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TDpccFormatLineKind.Precision:
      Result := Fmt(TDpccTextId.FormatPrecision, [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TDpccFormatLineKind.Unused:
      Result := Fmt(TDpccTextId.FormatUnused, [ALine.Argument + 1, ALine.Count]);
    TDpccFormatLineKind.Problem:
      case ALine.Problem of
        TDpccFormatProblem.Invalid:
          Result := Fmt(TDpccTextId.FormatInvalid, [ALine.PlaceholderText]);
        TDpccFormatProblem.TooManyArguments:
          Result := Fmt(TDpccTextId.FormatTooMany, [ALine.Argument + 1]);
        TDpccFormatProblem.TypeConflict:
          Result := Fmt(TDpccTextId.FormatConflict, [ALine.Placeholder + 1, ALine.PlaceholderText,
            FormatKind(ALine.TypeChar), ALine.Argument + 1, LiteralKind(ALine.ProblemKind)]);
      else
        Result := '';
      end;
  else
    Result := '';
  end;
end;

class function TDpccStrings.DocLabels: TDpccDocLabels;
begin
  // Begründung (Rationale) steht nur in der Grundtabelle; die übrigen Beschriftungen kommen aus Texts.
  Result := TDpccDocLabels.Current;
  Result.Params := Text(TDpccTextId.DocParams);
  Result.TypeParams := Text(TDpccTextId.DocTypeParams);
  Result.Returns := Text(TDpccTextId.DocReturns);
  Result.Value := Text(TDpccTextId.DocValue);
  Result.Exceptions := Text(TDpccTextId.DocExceptions);
  Result.Remarks := Text(TDpccTextId.DocRemarks);
  Result.Example := Text(TDpccTextId.DocExample);
  Result.SeeAlso := Text(TDpccTextId.DocSeeAlso);
  Result.Undocumented := Text(TDpccTextId.DocUndocumented);
  Result.More := Text(TDpccTextId.DocMore);
  Result.Less := Text(TDpccTextId.DocLess);
  Result.CountParam := Text(TDpccTextId.DocCountParam);
  Result.CountParams := Text(TDpccTextId.DocCountParams);
  Result.CountTypeParam := Text(TDpccTextId.DocCountTypeParam);
  Result.CountTypeParams := Text(TDpccTextId.DocCountTypeParams);
  Result.CountException := Text(TDpccTextId.DocCountException);
  Result.CountExceptions := Text(TDpccTextId.DocCountExceptions);
  Result.ItemReturns := Text(TDpccTextId.DocItemReturns);
  Result.ItemValue := Text(TDpccTextId.DocItemValue);
  Result.ItemRemarks := Text(TDpccTextId.DocItemRemarks);
  Result.ItemExample := Text(TDpccTextId.DocItemExample);
  Result.ItemSeeAlso := Text(TDpccTextId.DocItemSeeAlso);
end;

class function TDpccStrings.TypeArgHeading(const AParam, AConstraint, AHint: string): string;
var
  mExplanation: string;
begin
  if AHint = 'classes' then
  begin
    mExplanation := Text(TDpccTextId.TypeArgOnlyClasses);
  end
  else if AHint = 'values' then
  begin
    mExplanation := Text(TDpccTextId.TypeArgOnlyValues);
  end
  else if AHint = 'constructible' then
  begin
    mExplanation := Text(TDpccTextId.TypeArgOnlyConstructible);
  end
  else if AHint.StartsWith('implements:') then
  begin
    mExplanation := Fmt(TDpccTextId.TypeArgImplements, [Copy(AHint, Length('implements:') + 1, MaxInt)]);
  end
  else if AHint.StartsWith('descends:') then
  begin
    mExplanation := Fmt(TDpccTextId.TypeArgDescends, [Copy(AHint, Length('descends:') + 1, MaxInt)]);
  end
  else
  begin
    mExplanation := '';
  end;
  if (AConstraint = '') or (mExplanation = '') then
  begin
    Exit(Fmt(TDpccTextId.TypeArgHeaderPlain, [AParam]));
  end;
  Result := Fmt(TDpccTextId.TypeArgHeader, [AParam, AConstraint, mExplanation]);
end;

class function TDpccStrings.TypeArgHidden(const AKinds: string): string;
var
  mKind: string;
  mNames: TArray<string>;
begin
  mNames := nil;
  for mKind in AKinds.Split([',']) do
  begin
    if mKind = 'classes' then
    begin
      mNames := mNames + [Text(TDpccTextId.TypeArgKindClasses)];
    end
    else if mKind = 'records' then
    begin
      mNames := mNames + [Text(TDpccTextId.TypeArgKindRecords)];
    end
    else if mKind = 'interfaces' then
    begin
      mNames := mNames + [Text(TDpccTextId.TypeArgKindInterfaces)];
    end
    else if mKind = 'enums' then
    begin
      mNames := mNames + [Text(TDpccTextId.TypeArgKindEnums)];
    end
    else if mKind = 'basic' then
    begin
      mNames := mNames + [Text(TDpccTextId.TypeArgKindBasic)];
    end;
  end;
  if Length(mNames) = 0 then
  begin
    Exit('');
  end;
  Result := Fmt(TDpccTextId.TypeArgHiddenFooter, [string.Join(', ', mNames)]);
end;

class function TDpccStrings.UsesHidden(const AUnits: TArray<string>): string;
begin
  case Length(AUnits) of
    0: Result := '';
    1: Result := Fmt(TDpccTextId.UsesHiddenOne, [AUnits[0]]);
    2, 3: Result := Fmt(TDpccTextId.UsesHiddenFew, [string.Join(', ', AUnits)]);
  else
    Result := Fmt(TDpccTextId.UsesHiddenMore, [string.Join(', ', Copy(AUnits, 0, 2)), Length(AUnits) - 2]);
  end;
end;

class function TDpccStrings.InheritedAbstract(const AMethods: TArray<string>): string;
begin
  case Length(AMethods) of
    0: Result := '';
    1: Result := Fmt(TDpccTextId.InheritedAbstractOne, [AMethods[0]]);
    2, 3: Result := Fmt(TDpccTextId.InheritedAbstractMore, [string.Join(', ', AMethods)]);
  else
    Result := Fmt(TDpccTextId.InheritedAbstractMore, [string.Join(', ', Copy(AMethods, 0, 3)) + ', …']);
  end;
end;

class function TDpccStrings.CompilerConfirmed(const ACode: string; AShowCode: Boolean): string;
begin
  if AShowCode and (ACode <> '') then
  begin
    Result := Fmt(TDpccTextId.ProblemsCompilerConfirmedCode, [ACode]);
  end
  else
  begin
    Result := Text(TDpccTextId.ProblemsCompilerConfirmed);
  end;
end;

class function TDpccStrings.UsesCycle(const AChain: string): string;
var
  mParts: TArray<string>;
begin
  mParts := AChain.Split([' → ']);
  if Length(mParts) < 2 then
  begin
    Exit('');
  end;
  if Length(mParts) = 2 then
  begin
    Exit(Fmt(TDpccTextId.UsesCycleDirect, [mParts[0]]));
  end;
  Result := Fmt(TDpccTextId.UsesCycleChain, [mParts[0], string.Join(', ', Copy(mParts, 1, Length(mParts) - 2))]);
end;

class function TDpccStrings.BuildCounts(AWarnings, AHints: Integer): string;
var
  mWarnings, mHints: string;
begin
  mWarnings := '';
  mHints := '';
  if AWarnings = 1 then
  begin
    mWarnings := Text(TDpccTextId.BuildCountWarning);
  end
  else if AWarnings > 1 then
  begin
    mWarnings := Fmt(TDpccTextId.BuildCountWarnings, [AWarnings]);
  end;
  if AHints = 1 then
  begin
    mHints := Text(TDpccTextId.BuildCountHint);
  end
  else if AHints > 1 then
  begin
    mHints := Fmt(TDpccTextId.BuildCountHints, [AHints]);
  end;
  if (mWarnings <> '') and (mHints <> '') then
  begin
    Result := Fmt(TDpccTextId.BuildCountJoin, [mWarnings, mHints]);
  end
  else
  begin
    Result := mWarnings + mHints;
  end;
end;

class function TDpccStrings.Confidence(const AName: string): string;
var
  mLevel: TDpccTextId;
begin
  if SameText(AName, 'high') then
  begin
    mLevel := TDpccTextId.ConfidenceHigh;
  end
  else if SameText(AName, 'medium') then
  begin
    mLevel := TDpccTextId.ConfidenceMedium;
  end
  else if SameText(AName, 'low') then
  begin
    mLevel := TDpccTextId.ConfidenceLow;
  end
  else
  begin
    Exit('');
  end;
  Result := Fmt(TDpccTextId.ProblemsConfidence, [Text(mLevel)]);
end;

initialization
  TDpccStrings.Language := TDpccLanguage.German;

end.
