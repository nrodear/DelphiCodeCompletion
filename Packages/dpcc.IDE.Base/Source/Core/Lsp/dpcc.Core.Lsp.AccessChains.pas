unit dpcc.Core.Lsp.AccessChains;

// Zugriffsketten am Ausführungspunkt (#865), Plugin-Seite: Parameter von dpcc/accessChains und Lesen der
// Antwort (Ketten, Glieder mit Art, Typ, Aufruf, Index und Feldern samt geschätztem Versatz).

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  TDpccAvLinkKind = (Unknown, ClassRef, InterfaceRef, Pointer, DynArray);
  {$SCOPEDENUMS OFF}

  TDpccAvField = record
    Name: string;
    /// <summary>Geschätzt vom Server; -1 = unbekannt.</summary>
    Offset: Integer;
  end;

  TDpccAvLink = record
    Expression: string;
    Name: string;
    TypeName: string;
    Member: string;
    Kind: TDpccAvLinkKind;
    Call: Boolean;
    ImplicitSelf: Boolean;
    IndexText: string;
    IndexPlain: Boolean;
    /// <summary>Bereich im Quelltext, 0-basiert (Zeichen in UTF-16).</summary>
    StartLine, StartCharacter, EndLine, EndCharacter: Integer;
    NameLine, NameCharacter: Integer;
    Fields: TArray<TDpccAvField>;
  end;

  TDpccAvChain = record
    Text: string;
    Links: TArray<TDpccAvLink>;
  end;

  TDpccAvChains = record
    Found: Boolean;
    Statements: Integer;
    Chains: TArray<TDpccAvChain>;
  end;

  TDpccAvJson = class
  public const
    cMethod = 'dpcc/accessChains';
  public
    /// <summary>Parameter der Anfrage (ALine 0-basiert). Der Aufrufer übernimmt das Objekt.</summary>
    class function Params(const AFileName: string; ALine, APointerSize: Integer): TJSONObject; static;
    class function Parse(const AValue: TJSONValue): TDpccAvChains; static;
    /// <summary>8 für Win64 (auch Win64x), sonst 4.</summary>
    class function PointerSize(const APlatform: string): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.StrUtils,
  dpcc.Text.Uris;

{ TDpccAvJson }

class function TDpccAvJson.PointerSize(const APlatform: string): Integer;
begin
  if StartsText('win64', Trim(APlatform)) then
  begin
    Result := 8;
  end
  else
  begin
    Result := 4;
  end;
end;

class function TDpccAvJson.Params(const AFileName: string; ALine, APointerSize: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('textDocument', TJSONObject.Create(TJSONPair.Create('uri', TTextUris.FromPath(AFileName))));
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('pointerSize', TJSONNumber.Create(APointerSize));
end;

function KindOf(const AName: string): TDpccAvLinkKind;
begin
  if AName = 'class' then
  begin
    Result := TDpccAvLinkKind.ClassRef;
  end
  else if AName = 'interface' then
  begin
    Result := TDpccAvLinkKind.InterfaceRef;
  end
  else if AName = 'pointer' then
  begin
    Result := TDpccAvLinkKind.Pointer;
  end
  else if AName = 'dynArray' then
  begin
    Result := TDpccAvLinkKind.DynArray;
  end
  else
  begin
    Result := TDpccAvLinkKind.Unknown;
  end;
end;

procedure ReadPosition(AObject: TJSONObject; const AName: string; out ALine, ACharacter: Integer);
var
  mValue: TJSONValue;
begin
  ALine := 0;
  ACharacter := 0;
  if AObject.TryGetValue<TJSONValue>(AName, mValue) and (mValue is TJSONObject) then
  begin
    ALine := TJSONObject(mValue).GetValue<Integer>('line', 0);
    ACharacter := TJSONObject(mValue).GetValue<Integer>('character', 0);
  end;
end;

function ReadLink(AItem: TJSONObject): TDpccAvLink;
var
  mValue, mEntry: TJSONValue;
  mRange: TJSONObject;
  mField: TDpccAvField;
begin
  Result := Default(TDpccAvLink);
  Result.Expression := AItem.GetValue<string>('expression', '');
  Result.Name := AItem.GetValue<string>('name', '');
  Result.TypeName := AItem.GetValue<string>('typeName', '');
  Result.Member := AItem.GetValue<string>('member', '');
  Result.Kind := KindOf(AItem.GetValue<string>('kind', ''));
  Result.Call := AItem.GetValue<Boolean>('call', False);
  Result.ImplicitSelf := AItem.GetValue<Boolean>('implicitSelf', False);
  Result.IndexText := AItem.GetValue<string>('index', '');
  Result.IndexPlain := AItem.GetValue<Boolean>('indexPlain', False);
  if AItem.TryGetValue<TJSONValue>('range', mValue) and (mValue is TJSONObject) then
  begin
    mRange := TJSONObject(mValue);
    ReadPosition(mRange, 'start', Result.StartLine, Result.StartCharacter);
    ReadPosition(mRange, 'end', Result.EndLine, Result.EndCharacter);
  end;
  ReadPosition(AItem, 'namePosition', Result.NameLine, Result.NameCharacter);
  if AItem.TryGetValue<TJSONValue>('fields', mValue) and (mValue is TJSONArray) then
  begin
    for mEntry in TJSONArray(mValue) do
    begin
      if mEntry is TJSONObject then
      begin
        mField.Name := TJSONObject(mEntry).GetValue<string>('name', '');
        mField.Offset := TJSONObject(mEntry).GetValue<Integer>('offset', -1);
        Result.Fields := Result.Fields + [mField];
      end;
    end;
  end;
end;

function ReadChain(AItem: TJSONObject): TDpccAvChain;
var
  mValue, mEntry: TJSONValue;
begin
  Result := Default(TDpccAvChain);
  Result.Text := AItem.GetValue<string>('text', '');
  if not (AItem.TryGetValue<TJSONValue>('links', mValue) and (mValue is TJSONArray)) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(mValue) do
  begin
    if mEntry is TJSONObject then
    begin
      Result.Links := Result.Links + [ReadLink(TJSONObject(mEntry))];
    end;
  end;
end;

class function TDpccAvJson.Parse(const AValue: TJSONValue): TDpccAvChains;
var
  mResponse: TJSONObject;
  mValue, mEntry: TJSONValue;
  mChain: TDpccAvChain;
begin
  Result := Default(TDpccAvChains);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mResponse := TJSONObject(AValue);
  Result.Found := True;
  Result.Statements := mResponse.GetValue<Integer>('statements', 0);
  if not (mResponse.TryGetValue<TJSONValue>('chains', mValue) and (mValue is TJSONArray)) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(mValue) do
  begin
    if not (mEntry is TJSONObject) then
    begin
      Continue;
    end;
    mChain := ReadChain(TJSONObject(mEntry));
    if mChain.Links <> nil then
    begin
      Result.Chains := Result.Chains + [mChain];
    end;
  end;
end;

end.
