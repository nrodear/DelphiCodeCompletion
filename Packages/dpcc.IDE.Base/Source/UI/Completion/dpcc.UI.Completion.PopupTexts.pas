unit dpcc.UI.Completion.PopupTexts;

// Texte des Vervollständigungs-Popups (#410) in der Sprache der IDE: Marken, Detail, Art für die Sprachausgabe,
// Überschriften der Gruppen, Fußzeile und Warnleiste. Reine Funktionen über Einträge und Anzeigereihenfolge,
// ohne Fenster; das Popup (dpcc.UI.Completion.Popup) zeichnet sie nur.

interface

uses
  dpcc.Core.Completion.Contract,
  dpcc.Core.Completion.Presentation;

type
  /// <summary>Was die Fußzeile über die gezeigte Liste wissen muss.</summary>
  TDpccCompletionList = record
    Items: TDpccCompletionItems;
    /// <summary>Anzeigereihenfolge: Index in Items, Überschriften negativ.</summary>
    Order: TArray<Integer>;
    Pattern: string;
    /// <summary>Position der Überschrift „Weitere Einträge“ (#497); -1 ohne.</summary>
    RestFrom: Integer;
    /// <summary>Der Server indiziert noch (#492).</summary>
    Limited: Boolean;
    /// <summary>Aktives Ziel („Win32 · Debug“, #476); '' = keins bekannt.</summary>
    Target: string;
    /// <summary>Hinweis der Fußzeile (#458); '' ohne.</summary>
    Notice: string;
  end;

  /// <summary>Linker und rechter Text der Fußzeile.</summary>
  TDpccCompletionFooter = record
    Left: string;
    Right: string;
  end;

  TDpccCompletionTexts = class
  private
    /// <summary>Überschrift aus dem Eintrag nach der Überschrift an APosition.</summary>
    class function NextHeader(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): string; static;
    /// <summary>Gruppe im uses-Abschnitt (#469); '' ohne.</summary>
    class function UsesGroupText(const AGroup: string): string; static;
    /// <summary>Formular (#455), Felder zuweisen (#491), Interface (#466), Exceptions (#483); '' ohne.</summary>
    class function MarkedGroupText(const AItem: TDpccCompletionItem): string; static;
    /// <summary>Menge (#448), erwarteter Typ (#417, #444), nach dem Formular, geerbt (#419).</summary>
    class function TypedGroupText(const AItem: TDpccCompletionItem; AAfterForm: Boolean): string; static;
    /// <summary>Steht vor APosition eine Komponente des Formulars (#455)?</summary>
    class function AfterForm(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): Boolean; static;
    /// <summary>Ausgeblendete Units, abstrakte Methoden, gleichnamige Bezeichner; '' ohne.</summary>
    class function HiddenText(const AItems: TDpccCompletionItems): string; static;
    /// <summary>Die Tasten, oder das Ziel, sobald Einträge an Bedingungen hängen (#476).</summary>
    class function KeysText(const AList: TDpccCompletionList): string; static;
    class function HasCondition(const AList: TDpccCompletionList): Boolean; static;
    /// <summary>Einträge, die zum erwarteten Typ passen (#417), ohne Aktionen.</summary>
    class function FittingCount(const AList: TDpccCompletionList): Integer; static;
  public
    /// <summary>Text einer Marke (#446).</summary>
    class function TagText(const ATag: TDpccTag): string; static;
    /// <summary>Detail rechts: im uses-Abschnitt (#469) „bereits im interface-Teil“.</summary>
    class function DetailText(const AItem: TDpccCompletionItem): string; static;
    /// <summary>Art eines Eintrags in Worten für die Sprachausgabe.</summary>
    class function KindText(AKind: TDpccItemKind): string; static;
    /// <summary>Text der Überschrift an APosition (geerbt von, Weitere Einträge, …).</summary>
    class function HeaderText(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
      APosition: Integer): string; static;
    /// <summary>Rechts in der Fußzeile: „3 von 84“ bzw. mit erwartetem Typ „3 passend · 84 gesamt“ (#417).</summary>
    class function CountText(const AList: TDpccCompletionList): string; static;
    /// <summary>Links in der Fußzeile: Hinweis, ausgeblendete Einträge, Tasten oder Ziel (#476).</summary>
    class function FooterLeftText(const AList: TDpccCompletionList): string; static;
    /// <summary>Beide Texte der Fußzeile je nach Modus (Menge, Absichern, SQL, Typargumente).</summary>
    class function Footer(const AList: TDpccCompletionList): TDpccCompletionFooter; static;
    /// <summary>Fußzeile der schlichten Liste (S6): links wie Footer (Tasten, Hinweise), rechts keine Zählung;
    /// nur Mengenmodus, „eingeschränkt“ und „Keine Treffer“ bleiben.</summary>
    class function PlainFooter(const AList: TDpccCompletionList): TDpccCompletionFooter; static;
    /// <summary>Text der Warnleiste (#457) vor der Zeilenangabe.</summary>
    class function SyntaxLead(ATrust: TDpccSyntaxTrust): string; static;
    /// <summary>Zeilenangabe der Warnleiste; ALine 0-basiert.</summary>
    class function SyntaxLineText(ALine: Integer): string; static;
    /// <summary>Voller Text einer gekürzten Zeile für den Tooltip (#420).</summary>
    class function TipText(const AItem: TDpccCompletionItem; const ATags: TDpccTags): string; static;
  end;

implementation

uses
  System.SysUtils,
  dpcc.Core.Completion.Ranking,
  dpcc.Core.Completion.Sets,
  dpcc.UI.Strings,
  dpcc.UI.Completion.Strings;

{ TDpccCompletionTexts }

class function TDpccCompletionTexts.TagText(const ATag: TDpccTag): string;
begin
  case ATag.Id of
    TDpccTagId.Recent: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.TagRecent);
    TDpccTagId.Frequent: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.TagFrequent);
    TDpccTagId.Cycle: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesCycleTag);
    TDpccTagId.SameParams: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.InheritedSameTag);
    TDpccTagId.Overload: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.InheritedOverloadTag);
    TDpccTagId.Active: Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.SameNameActiveTag);
    TDpccTagId.VariantBranch: Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.TagVariantBranch,
      [ATag.Arg]);
  else
    Result := ATag.Text;
  end;
end;

class function TDpccCompletionTexts.DetailText(const AItem: TDpccCompletionItem): string;
begin
  if AItem.UsesElsewhere = 'interface' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesInInterface);
  end
  else if AItem.UsesElsewhere = 'implementation' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesInImplementation);
  end
  else
  begin
    Result := TDpccItemPresentation.Detail(AItem);
  end;
end;

class function TDpccCompletionTexts.KindText(AKind: TDpccItemKind): string;
begin
  case AKind of
    TDpccItemKind.Method, TDpccItemKind.Function_, TDpccItemKind.Procedure_:
      Result := TDpccStrings.Text(TDpccTextId.KindMethod);
    TDpccItemKind.Constructor_, TDpccItemKind.Destructor_:
      Result := TDpccStrings.Text(TDpccTextId.KindConstructor);
    TDpccItemKind.Property_, TDpccItemKind.Event:
      Result := TDpccStrings.Text(TDpccTextId.KindProperty);
    TDpccItemKind.Field:
      Result := TDpccStrings.Text(TDpccTextId.KindField);
    TDpccItemKind.Variable, TDpccItemKind.Parameter:
      Result := TDpccStrings.Text(TDpccTextId.KindVariable);
    TDpccItemKind.Constant:
      Result := TDpccStrings.Text(TDpccTextId.KindConstant);
    TDpccItemKind.Type_:
      Result := TDpccStrings.Text(TDpccTextId.KindType);
    TDpccItemKind.Class_:
      Result := TDpccStrings.Text(TDpccTextId.KindClass);
    TDpccItemKind.Interface_:
      Result := TDpccStrings.Text(TDpccTextId.KindInterface);
    TDpccItemKind.Record_:
      Result := TDpccStrings.Text(TDpccTextId.KindRecord);
    TDpccItemKind.Enum:
      Result := TDpccStrings.Text(TDpccTextId.KindEnum);
    TDpccItemKind.EnumMember:
      Result := TDpccStrings.Text(TDpccTextId.KindEnumMember);
  else
    Result := '';
  end;
end;

class function TDpccCompletionTexts.HeaderText(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): string;
begin
  // Überschrift einer Gruppe geerbter Member (#419): Klasse des nächsten Eintrags;
  // mit erwartetem Typ (#417, #444) „Passt zu …“ bzw. „Weitere“.
  if AOrder[APosition] = TDpccRanking.cTypoHeader then
  begin
    // Tippfehler-Treffer (#485).
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.DidYouMean);
  end
  else if AOrder[APosition] = TDpccRanking.cRestHeader then
  begin
    // Rest der Liste ohne Treffer (#497).
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.CompletionRestHeader);
  end
  else if (APosition < High(AOrder)) and (AOrder[APosition + 1] >= 0) then
  begin
    Result := NextHeader(AItems, AOrder, APosition);
  end
  else
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.InheritedPlain);
  end;
end;

class function TDpccCompletionTexts.NextHeader(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): string;
var
  mItem: TDpccCompletionItem;
begin
  mItem := AItems[AOrder[APosition + 1]];
  if AOrder[APosition] = TDpccRanking.cUnknownHeader then
  begin
    // Unbekannter Name (#471): „TotalCount ist unbekannt“.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.UnknownHeader, [mItem.Unknown]);
  end
  else if (APosition = 0) and (mItem.Sender <> '') then
  begin
    // Sender mit Typumwandlung (#480): „Sender ist TButton · btnSave, btnLoad“ über der Liste; weitere
    // Überschriften darin sind die der geerbten Gruppen.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SenderHeader, [mItem.Sender, mItem.SenderOf]);
  end
  else if mItem.TypeParam <> '' then
  begin
    // Typargumente (#450): „T: class · nur Klassen“.
    Result := TDpccStrings.TypeArgHeading(mItem.TypeParam, mItem.Constraint, mItem.ConstraintHint);
  end
  else
  begin
    Result := UsesGroupText(mItem.UsesGroup);
    if Result = '' then
    begin
      Result := MarkedGroupText(mItem);
    end;
    if Result = '' then
    begin
      Result := TypedGroupText(mItem, AfterForm(AItems, AOrder, APosition));
    end;
  end;
end;

class function TDpccCompletionTexts.UsesGroupText(const AGroup: string): string;
begin
  // uses-Abschnitt (#469): Projekt, RTL/VCL, Drittanbieter.
  if AGroup = 'project' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesGroupProject);
  end
  else if AGroup = 'rtl' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesGroupRtl);
  end
  else if AGroup = 'library' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.UsesGroupLibrary);
  end
  else
  begin
    Result := '';
  end;
end;

class function TDpccCompletionTexts.MarkedGroupText(const AItem: TDpccCompletionItem): string;
begin
  if AItem.Form <> '' then
  begin
    // Komponenten aus dem Formular (#455): „Formular frmMain“.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.FormHeader, [AItem.Form]);
  end
  else if AItem.Assign then
  begin
    // Alle Felder zuweisen (#491): „Alle Felder zuweisen · TOptions“.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.AssignHeader, [AItem.SetOf]);
  end
  else if AItem.Batch then
  begin
    // Interface implementieren (#466): „Fehlende Methoden von IExporter, IFlush“.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.BatchHeader, [AItem.SetOf]);
  end
  else if AItem.ExceptionGroup = 'try' then
  begin
    // Exception-Klassen nach "on E: " (#483): „Aus dem try-Block“ und „Allgemein“.
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.ExceptionGroupTry);
  end
  else if AItem.ExceptionGroup = 'general' then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.ExceptionGroupGeneral);
  end
  else
  begin
    Result := '';
  end;
end;

class function TDpccCompletionTexts.TypedGroupText(const AItem: TDpccCompletionItem; AAfterForm: Boolean): string;
begin
  if AItem.SetOf <> '' then
  begin
    // Mengenmodus (#448): „TAnchors · Menge von TAnchorKind“, bei "X in [" nur „Menge von …“.
    if AItem.ExpectedType.StartsWith('set of ') then
    begin
      Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SetHeaderPlain, [AItem.SetOf]);
    end
    else
    begin
      Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SetHeader, [AItem.ExpectedType, AItem.SetOf]);
    end;
  end
  else if AItem.ExpectedType <> '' then
  begin
    if AItem.Fits then
    begin
      Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.FitsType, [AItem.ExpectedType]);
    end
    else
    begin
      Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.OtherGroup);
    end;
  end
  else if AAfterForm then
  begin
    // Direkt nach den Komponenten des Formulars (#455) beginnt die übrige Liste.
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.OtherGroup);
  end
  else if AItem.DeclaringClass <> '' then
  begin
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.InheritedFrom, [AItem.DeclaringClass]);
  end
  else
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.InheritedPlain);
  end;
end;

class function TDpccCompletionTexts.AfterForm(const AItems: TDpccCompletionItems; const AOrder: TArray<Integer>;
  APosition: Integer): Boolean;
begin
  Result := (APosition > 0) and (AOrder[APosition - 1] >= 0) and (AItems[AOrder[APosition - 1]].Form <> '');
end;

class function TDpccCompletionTexts.HiddenText(const AItems: TDpccCompletionItems): string;
begin
  if Length(TDpccItemPresentation.UsesHidden(AItems)) > 0 then
  begin
    // uses-Abschnitt (#469): welche Units schon eingebunden sind und deshalb fehlen.
    Result := TDpccStrings.UsesHidden(TDpccItemPresentation.UsesHidden(AItems));
  end
  else if Length(TDpccItemPresentation.InheritedAbstract(AItems)) > 0 then
  begin
    // Nach "inherited " (#482): welche abstrakten Vorfahrmethoden fehlen.
    Result := TDpccStrings.InheritedAbstract(TDpccItemPresentation.InheritedAbstract(AItems));
  end
  else if Length(TDpccItemPresentation.SameNameHidden(AItems)) > 0 then
  begin
    // Gleichnamige Bezeichner (#475): ausgeblendete FireMonkey-Varianten.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SameNameHiddenFooter,
      [string.Join(', ', TDpccItemPresentation.SameNameHidden(AItems))]);
  end
  else
  begin
    Result := '';
  end;
end;

class function TDpccCompletionTexts.HasCondition(const AList: TDpccCompletionList): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex in AList.Order do
  begin
    if (mIndex >= 0) and (AList.Items[mIndex].Condition <> '') then
    begin
      Exit(True);
    end;
  end;
end;

class function TDpccCompletionTexts.KeysText(const AList: TDpccCompletionList): string;
begin
  if (AList.Target <> '') and HasCondition(AList) then
  begin
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.TargetFooter, [AList.Target]);
  end
  else
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.FooterKeys);
  end;
end;

class function TDpccCompletionTexts.FooterLeftText(const AList: TDpccCompletionList): string;
begin
  // Hinweis zu den Favoriten (#458) hat Vorrang.
  Result := AList.Notice;
  if Result = '' then
  begin
    Result := HiddenText(AList.Items);
  end;
  if Result = '' then
  begin
    Result := KeysText(AList);
  end;
end;

class function TDpccCompletionTexts.FittingCount(const AList: TDpccCompletionList): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex in AList.Order do
  begin
    if (mIndex >= 0) and AList.Items[mIndex].Fits and not AList.Items[mIndex].IsAction then
    begin
      Inc(Result);
    end;
  end;
end;

class function TDpccCompletionTexts.CountText(const AList: TDpccCompletionList): string;
var
  mFitting: Integer;
begin
  // Mengenmodus (#448): wie viele Werte angehakt sind.
  if TDpccCompletionSets.Active(AList.Items) then
  begin
    Exit(TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SetChosen,
      [TDpccCompletionSets.CheckedCount(AList.Items)]));
  end;
  mFitting := FittingCount(AList);
  if TDpccRanking.OnlyTypos(AList.Order) or (AList.RestFrom = 0) then
  begin
    // Nur ähnliche Namen (#485) bzw. nur der Rest (#497): kein echter Treffer für das Getippte.
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.NoMatchesFor, [AList.Pattern]);
  end
  else if AList.RestFrom > 0 then
  begin
    // Treffer, darunter der gedämpfte Rest (#497).
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.CountHitsRest,
      [TDpccRanking.ItemCount(Copy(AList.Order, 0, AList.RestFrom)),
      TDpccRanking.ItemCount(Copy(AList.Order, AList.RestFrom, MaxInt))]);
  end
  else if mFitting > 0 then
  begin
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.CountFits, [mFitting,
      TDpccRanking.ItemCount(AList.Order)]);
  end
  else
  begin
    Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.CountOf, [TDpccRanking.ItemCount(AList.Order),
      Length(AList.Items)]);
  end;
  if AList.Limited then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.CompletionLimited) + ' · ' + Result;
  end;
end;

class function TDpccCompletionTexts.Footer(const AList: TDpccCompletionList): TDpccCompletionFooter;
begin
  Result.Right := CountText(AList);
  if TDpccCompletionSets.Active(AList.Items) then
  begin
    Result.Left := TDpccCompletionStrings.Text(TDpccCompletionTextId.SetFooterKeys);
  end
  else if TDpccItemPresentation.Guarding(AList.Items) then
  begin
    // Freigabe absichern (#489).
    Result.Left := TDpccCompletionStrings.Text(TDpccCompletionTextId.GuardFooterKeys);
    Result.Right := '';
  end
  else if TDpccItemPresentation.DataSource(AList.Items) <> '' then
  begin
    // Feld- und Parameternamen (#461): die SQL-Anweisung als Quellenangabe.
    Result.Left := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.DataSourceFooter,
      [TDpccItemPresentation.DataSource(AList.Items)]);
  end
  else if TDpccItemPresentation.HiddenKinds(AList.Items) <> '' then
  begin
    // Typargumente (#450): „Ausgeblendet: Records, Aufzählungen“.
    Result.Left := TDpccStrings.TypeArgHidden(TDpccItemPresentation.HiddenKinds(AList.Items));
  end
  else
  begin
    // Tasten, oder das aktive Ziel bei Einträgen mit Bedingung (#476).
    Result.Left := FooterLeftText(AList);
  end;
end;

class function TDpccCompletionTexts.PlainFooter(const AList: TDpccCompletionList): TDpccCompletionFooter;
begin
  Result := Footer(AList);
  if not TDpccCompletionSets.Active(AList.Items) and not AList.Limited and not TDpccRanking.OnlyTypos(AList.Order)
    and (AList.RestFrom <> 0) then
  begin
    Result.Right := '';
  end;
end;

class function TDpccCompletionTexts.SyntaxLead(ATrust: TDpccSyntaxTrust): string;

begin
  if ATrust = TDpccSyntaxTrust.Unknown then
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.SyntaxUnknown);
  end
  else
  begin
    Result := TDpccCompletionStrings.Text(TDpccCompletionTextId.SyntaxLimited);
  end;
end;

class function TDpccCompletionTexts.SyntaxLineText(ALine: Integer): string;
begin
  Result := TDpccCompletionStrings.Fmt(TDpccCompletionTextId.SyntaxLine, [ALine + 1]);
end;

class function TDpccCompletionTexts.TipText(const AItem: TDpccCompletionItem; const ATags: TDpccTags): string;
var
  mDetail: string;
  mTag: TDpccTag;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create(AItem.Name);
  try
    mDetail := DetailText(AItem);
    if mDetail <> '' then
    begin
      mBuilder.Append('   ').Append(mDetail);
    end;
    for mTag in ATags do
    begin
      mBuilder.Append('   [').Append(TagText(mTag)).Append(']');
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
