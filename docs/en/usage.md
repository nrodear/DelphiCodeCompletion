[Deutsch](../de/usage.md) | English | [Français](../fr/usage.md)

# Usage

[Overview](index.md) › Usage

## Keys in the editor

| Key | Effect |
|---|---|
| Ctrl+Space | open dpcc completion |
| Ctrl+Shift+Space | open the dpcc parameter hint |

dpcc assigns these two keys with its own key binding (“dpcc Code Completion”). It takes them only if it serves the
file: extension `.pas`, `.dpr`, `.dpk` or `.inc`, master switch on, and the feature not switched off by the safety
fuse (see [Troubleshooting](troubleshooting.md)). Otherwise the keys go to the IDE. A second Ctrl+Space also goes
to the IDE if the dpcc list stayed empty at the same position (see [below](#ide-list-when-dpcc-finds-nothing)).

dpcc does not take any other keys permanently. It takes the arrow keys, Enter, Tab and Esc only while one of its
windows is open and needs the key.

## Interaction with DelphiLSP

Delphi 13 passes automatic triggers (typing “.”, “(”, “,”) only to the Code Insight provider that is selected for
Delphi in the IDE options. The default is DelphiLSP. As a result:

- The list that opens by itself after “.” comes from DelphiLSP.
- Ctrl+Space and Ctrl+Shift+Space come from dpcc.
- Settings that only apply to automatic opening have no effect with this default. They are marked under
  [Settings](settings.md).

dpcc writes the selected provider to the log at startup (line “Code Insight für Delphi-Dateien: gewählt …”, Code
Insight for Delphi files: selected …).

### IDE list when dpcc finds nothing

If the list stays empty after Ctrl+Space, its footer reads “Press Ctrl+Space again for the IDE list”. A second
Ctrl+Space at the same position then opens the IDE list (DelphiLSP) instead of the dpcc list. Empty here means:
nothing found, no suitable context, an error or the server time limit.

- This only applies while the cursor is still at the same position (file, line, column) and nothing was typed in
  between. Esc in between does not change this; switching the tab does.
- While the dpcc answer is still pending, another Ctrl+Space asks dpcc again.
- Afterwards it starts over: the next Ctrl+Space asks dpcc again.
- dpcc never switches to the IDE list by itself.

The IDE list comes from the Code Insight provider selected for Delphi in the IDE options (default DelphiLSP).

## The list

Ctrl+Space opens the list at the cursor. The word before the cursor is taken as the start of what you are looking
for.

Layout of a row:

- on the left the kind as a word, dimmed (`procedure`, `function`, `type`, `property` …);
- the name in bold, the typed characters underlined;
- after it the signature, or a dimmed detail;
- on the right, dimmed, “+” and the name of the unit (for example “+ System.SysUtils”) if the unit is not yet in
  `uses`, and warnings as text.

The footer shows the keys or a hint.

### Keys in the open list

| Key | Effect |
|---|---|
| ↑ / ↓ | move the selection |
| Page Up / Page Down | move by page |
| Home / End | first / last entry |
| Enter or Tab | accept the selected entry |
| Esc | close the list |
| keep typing | filter the list |
| Backspace | loosen the filter; if the word is shorter than at the time of the request, dpcc asks again |
| “(”, “;”, “.” | accept if the selected entry is an unambiguous match; the character stays (commit characters, can be switched off) |
| Ctrl+D | pin or unpin the selected entry as a favorite |
| Space | only in set mode: check or uncheck a value |

The list also closes when the cursor leaves the word or the line, the editor loses focus, the IDE becomes inactive,
the editor scrolls or the view changes.

After closing with Esc, an automatic start in the same word does not open the list again. Ctrl+Space opens it and
lifts this block.

### Filtering and order

While you keep typing, dpcc filters the existing list itself, without a new request. Order of the matches:

1. exact name,
2. prefix with the same case,
3. prefix,
4. word starts (`TSL` finds `TStringList`),
5. substring,
6. subsequence.

Depending on the settings, in addition:

- **Favorites** come before all others if they match what you typed.
- **Frequently and recently chosen entries** get a bonus. A better match still stays in front.
- **Expected type**: Matching entries are at the top under the heading “Matches …”, the others below.
- **Inherited members**: Without a typed prefix, the class's own members come first, then one group “Inherited from
  …” per ancestor.
- **List mode**: Optionally, entries without a match stay visible while typing. If there is then no match at the
  top, nothing is selected; Enter belongs to the editor, an arrow key selects the first entry.

If you accept in the middle of a word, dpcc replaces the whole word.

### Width and height

- The number of visible rows is adjustable (5 to 20).
- You can drag the right edge with the mouse. A double-click at the bottom right restores the automatic width.
- Without a dragged width, the list grows with the widest entry. It does not shrink during a session, so that it
  does not jump while filtering.
- Truncated rows show the full text when the mouse rests on them for 600 ms.

### Hints in the list

| Display | Meaning |
|---|---|
| “No matches for “…”” | Nothing matches. Only Esc belongs to the list; arrow keys and Enter go to the editor. |
| “No suggestions here” | There is nothing to offer at this position. |
| Footer “Press Ctrl+Space again for the IDE list” | The list after Ctrl+Space is empty; a second Ctrl+Space at the same position opens the IDE list (see [above](#ide-list-when-dpcc-finds-nothing)). |
| “limited (index is being built)” | The index is not finished yet; the list may be incomplete. |
| Bar “Results may be incomplete · syntax error in line n” | There is a syntax error before the cursor in the current routine or class. |
| Bar “Context unclear · syntax error in line n” | as above, and there are no entries. |

### Preview

With the setting “Preview of the selected entry in the editor”, the missing part of the selected name appears in
italics and dimmed after the cursor. It is only drawn; the file and the undo list stay untouched. The preview
appears only if the name starts with what you typed and nothing follows the cursor. Default: off.

## What the list offers

What appears depends on the position. The server checks the cases in a fixed order; the first matching one answers.

| Position | Offer |
|---|---|
| after `Expression.` | members of the type including inherited ones; for units their interface symbols |
| after `Expression.` with a known type | in addition postfix templates (see below) |
| otherwise | all visible names: local, own class, own unit, units from `uses` |
| from two typed characters on | also symbols from units that are not yet in `uses`, with “+” and the name of the unit; project units before libraries |
| in the `uses` section | known units in groups: Project, RTL/VCL, Third party; a hint if a unit is already in the other section; tag “Circular reference” |
| after `inherited ` | methods of the ancestors; the method with the same name first, with arguments from the own parameters |
| after `class(`, `is`, `as`, after `:` in declarations | types only |
| after `<` of a generic type | type arguments, filtered by the constraints |
| in `[…]` before a declaration | attribute classes, without the `Attribute` suffix |
| after `raise ` and `on E: ` | exception classes; after `on E:` first those that the try block can raise according to XMLDoc |
| comparison, `case` branch, assignment with an enumeration type | values of the enumeration first |
| in a set constructor `[…]` | set mode (see below) |
| on an empty line of a class with an interface | missing methods of the interface to check |
| in a class declaration after `procedure ` or `function ` | overridable methods |
| after `property … read` / `write` | matching fields and methods |
| after `Object.Event := ` | matching methods and “New method …” |
| where a method reference type is expected | skeleton of an anonymous method with a matching signature |
| at the name position of a declaration | name suggestions |
| after `{$`, `{$IFDEF ` etc. | compiler directives and conditional symbols |
| after `{$I ` or `{$INCLUDE ` | names of the `.inc` files in the folder of the file (or in the typed subfolder) and in the folders of the include files the unit already includes |
| in a `///` comment whose parameters no longer match | “Synchronize parameters” |
| in the unit of a form | components of the form as a separate group “Form …” |
| `Sender.` in an event handler | members of the common type of the components to which the method is assigned in the form |
| in `FieldByName('…')`, `FindField('…')`, `ParamByName('…')` | field or parameter names of the dataset |
| name declared in several units | the variant that the compiler chooses first, with “active”, the others with their unit |

### Expressions before the dot

After the dot the list knows the type not only for chains of names (`List.Items.`) but also after expressions:

- index and default property: `List[i].`, `Items[0].`, `FArray[0].`, also with `array of T`, static arrays and
  fields or local variables of an anonymous array type
- parentheses, typecast and `as`: `(Sender as TButton).`, `TButton(Sender).`
- pointers: `P^.`, and `P.` for a pointer to a record
- literals: `'abc'.`, `42.` (members of the helpers of `string` and `Integer`)
- calls: `Foo(1).` with the matching overload, calls through procedural types and `reference to` (`FOnGet(1).`),
  generic routines without type arguments (`Max(A, B).`, `T` from the arguments)
- nested types as the type of a member: `Dict.Values.`, `List.GetEnumerator.Current.`

Inline variables without a type get the type of their expression also for operators (`var S := A + IntToStr(1);`
is a `string`, `I / 2` an `Extended`, comparisons and `not` a `Boolean`), for `class operator` of records, for `@X`
(pointer to the type of `X`), `P^`, set constructors and anonymous methods. The variable of a `for … in` loop
without a type has the element type: the element of an array, `Char` for a `string`, otherwise
`GetEnumerator.Current`.

After a type name (`TFoo.`) the list only shows what can be called through the type: class methods, constructors,
`class var`, `class property`, constants, nested types and the values of an enumeration. After `TFoo.Create.`,
`TFoo(X).` and `Self.` all members appear.

### “+ Unit”

If an identifier is in a unit that is not yet in `uses`, the row shows “+” and the name of that unit on the right,
for example “+ System.SysUtils” for `FreeAndNil`. So “+ Unit” is not a fixed text; in this documentation “Unit”
stands for the name. When accepting, dpcc adds the unit to `uses` (setting “Add the unit to uses automatically when
accepting”). The name and the `uses` entry are a single undo step.

“+ Unit” also offers values of enumerations (for example `fsBold` from `Vcl.Graphics`). Generic types show their type
parameters (`TList<T>`); only the name is inserted. If a `<` already follows the word, they come before types of the
same name without type parameters, otherwise after them. See [Index and cache](index-cache.md#content-per-declaration).

### FieldByName and forms

For this, dpcc reads the form file (DFM) of the unit. For open forms it takes the current state from the designer,
even unsaved; changes in the designer go to the server after 500 ms.

Sources for field names, in this order:

1. persistent fields of the dataset,
2. columns of the SQL statement from `SQL.Strings` or `CommandText` (aliases apply; with `*` no columns),
3. for `ParamByName`: the `:placeholders` of the statement and the entries of the Params collection.

Without a form file, or without the dataset in it, there are no names. For datasets of other data modules
(`DM.qryOrders`), dpcc looks up the global variable in the index and reads the form file of its unit.

### Postfix templates

After `Expression.`, the list offers, after the members, abbreviations that transform the expression. Only what fits
the type is offered. Statements are offered only if the expression starts the line.

| Abbreviation | Result | Type |
|---|---|---|
| `for`, `forin` | `for var Item in List do` | enumerable |
| `tryf` | `try … finally Obj.Free; end;` | class |
| `ifa`, `notnil` | `if Assigned(X) then` | class, interface, pointer |
| `nil` | `if not Assigned(X) then` | class, interface, pointer |
| `not` | `not B` | Boolean |
| `if` | `if B then` | Boolean |
| `fmt` | `Format(S, [])` | string |
| `free` | `FreeAndNil(Obj);` | class |
| `try` | `var Foo := TFoo.Create; try … finally Foo.Free; end;` | constructor call |
| `var` | `var Name := X;` | known type |
| `exit` | `Exit(X);` | in a function |

## Placeholders

Some entries insert text with placeholders, for example postfix templates or the skeleton of an anonymous method.
dpcc handles the placeholders itself:

| Key | Effect |
|---|---|
| typing | replaces the default of the current placeholder |
| Tab | next placeholder; after the last one, to the end position |
| Shift+Tab | previous placeholder |
| Enter | finish and jump to the end position |
| Esc | finish in place |

The current placeholder has a solid frame, linked ones a dashed frame, the others a dotted frame. After the line,
“Placeholder 1 / 3 · Tab next · Esc done” is shown. dpcc keeps linked placeholders with the same number in sync. A
change outside or a change of view ends the mode.

If the mode ends normally (Esc, Enter, Tab after the last one), a single Ctrl+Z undoes the whole insertion in one
step.

## Set mode

In a set constructor (`Anchors := [akLeft, |`), the list shows all values of the element type with check boxes.
Values that are already in the brackets are checked. The heading reads, for example, “TAnchors · set of
TAnchorKind”.

| Key | Effect |
|---|---|
| Space | check or uncheck the selected value |
| Enter or Tab after Space was pressed in this list | rewrite the whole bracket: exactly the checked values in declaration order, `[]` if none is checked; with `{$SCOPEDENUMS ON}` with a type prefix |
| Enter or Tab without Space having been pressed in this list | also check the selected value and rewrite the bracket as above: the existing values plus the selected one |
| Esc | discard |

The footer shows “Space selects · Enter inserts · Esc discards” and the number of selected values.

The same list is used for “Implement interface”: missing methods, all checked; Enter inserts the checked ones.

## Favorites

With the setting “Pin favorites” (default: on), Ctrl+D in the open list pins or unpins the selected entry.

- A favorite applies to a pair of type and member. The type is the declaring class, at unit level the unit. A
  favorite `TDataSet.Open` therefore applies to every dataset.
- At most 5 favorites per type. Another one does not replace any; the footer reports “Already 5 favorites for …”.
- Pinned entries are at the top if they match what you typed.
- dpcc saves immediately to `%APPDATA%\dpcc\favorites.json`.
- The list of favorites with “Remove” and “Remove all” is under [Settings](settings.md#completion).

## Accepting

What happens when accepting is configurable (area “Insertion”, see [Settings](settings.md#insertion)):

- **Parentheses**: For methods, dpcc adds the parentheses. If you type a “)” directly before the automatically
  inserted closing parenthesis, dpcc skips the automatic one instead of producing “))”.
- **Case**: `showmessage` becomes `ShowMessage`.
- **Unit in uses**: see “+ Unit”.
- **Commit characters**: “(”, “;” and “.” accept.

## Parameter hint

Ctrl+Shift+Space in a call shows the signatures of the called routine at the opening parenthesis.

- All overloads are listed one below the other. In the selected one, the active parameter is bold and underlined.
  Overloads with too few parameters are dimmed.
- Preselected is the first overload that the arguments so far match. Literals, names and the type of expressions
  such as `Liefere(1)`, `List[i]` or `A + 1` count.
- A click selects an overload; Alt+↑ / Alt+↓ switches between them.
- For nested calls, a path line at the top shows the outer calls, for example “ShowMessage › Format”.
- Below are the name and description of the active parameter from the XMLDoc (without `<param>`: “not
  documented”), default values (“optional, default …”) and the description of the method.
- If no overload allows that many arguments, it shows “No overload with n parameters.”
- If the completion list is open or there is no room below, the parameter hint is shown above the line.
- Esc closes it. It also closes when the cursor leaves the call (also through “)”), on loss of focus, scrolling or
  a change of tab.
- If the closing parenthesis is removed and the cursor is then inside a call, the hint appears again; not for a
  call whose hint was closed with Esc.

### Which calls it knows

- **Inherited overloads**: If a method of the descendant carries `overload`, the methods of the same name in the
  ancestors are listed as well (`TDerived.Add(const S: string)` and the inherited `Add(A: Integer)`). Without
  `overload`, the descendant hides them, as with the compiler.
- **Procedural types**: Calls through variables, fields, properties and parameters of a procedural type show its
  signature, for example `FOnChange(Self` (`TNotifyEvent`), `Callback(1` or `AProc(` with `AProc: TProc<Integer>`.
  For generic types the type arguments are substituted (`TProc<Integer> = reference to procedure (Arg1: Integer)`).
- **Type arguments before the parenthesis**: `Foo<Integer>(` shows only the generic overload, with the type
  argument substituted.
- **Index properties**: `List.Items[` and `List[` (default property) show the index parameters, with
  Ctrl+Shift+Space or at the comma. If the square bracket is inside a call (`Foo(List[`), the hint stays with that
  call's signatures; for an array instead of a property nothing appears.

### Format placeholders

For `Format` and other format routines, a line names the placeholder for the argument at the cursor, for example
“Placeholder 2 of 2 expects integer”. It warns about surplus arguments, invalid placeholders and type conflicts with
literals. Placeholder and argument get the same background color in the editor while the parameter hint is open.
Can be switched off with “Match and colour Format placeholders in the parameter hint”.

## Hover

When the mouse rests over an identifier for 500 ms, dpcc shows a tooltip below it. The IDE never waits for the
server.

Contents, from top to bottom (empty sections are omitted):

| Section | Contents |
|---|---|
| Value in the debugger | expression and value while the program is paused, “evaluating …” until the answer arrives |
| Header | kind and signature, complete even across several lines |
| Origin, location | kind in words, library, origin; file and line |
| Value, deprecation | value of a constant, also of simple expressions; `deprecated`, `platform`, `experimental`; inactive branch |
| XMLDoc | summary, parameters, return value, exceptions, remarks, example, see also; `<inheritdoc/>` is resolved; without `///`, the plain comment (see below) |
| Published members | for component classes, properties and events including inherited ones |
| Inheritance | inheritance chain, or target type of a class reference |

If the tooltip is taller than the available space or than the configured number of lines, the XMLDoc scrolls with
the mouse wheel.

The tooltip closes 300 ms after the mouse has left the identifier and the tooltip, immediately on Esc and any other
key (except Shift, Ctrl, Alt alone), on a mouse click, scrolling, resizing and when the IDE becomes inactive. If a
completion list, a parameter hint or a menu is open, no tooltip appears.

### Signature, comments and values

- **Signature:** If a declaration spans several lines, the header shows it completely (parameters, result and
  directives such as `virtual` or `stdcall`) as one line without comments. For classes, records and interfaces it
  stays with the first line. Very long headers are shortened after 1000 characters with “…”.
- **Inferred type:** For inline variables without a type (`var X := TFoo.Create;`, `for var I := 0 to …`), dpcc
  inserts the type that follows from the expression: `var X: TFoo := TFoo.Create;`. If the type cannot be determined
  reliably, the line stays as in the source.
- **Comments as documentation:** XMLDoc with `///` takes precedence. Without it, dpcc shows the plain comment block
  directly above the declaration (`//`, `{ }` or `(* *)`, with no blank line in between) and the comment at the end
  of the line with the name. Not documentation: file and license headers (a block at the start of the file or with
  words such as Copyright, License, Lizenz), blocks after a blank line, separator lines such as `//-----`, a single
  name such as `{ TFoo }` and commented-out code (lines with `:=`, statements ending in `;`, `begin`/`end` …); a block
  that consists mostly of code is dropped entirely. The header no longer shows the end-of-line comment.
- **Values:** Constants show their value for simple expressions too: integers with
  `+ - * div mod and or xor not shl shr`, signs and parentheses, strings with `+` and references to other constants
  of the unit or from the index (`cMax = cBase * 2`). Anything dpcc cannot compute reliably (floating point,
  functions such as `High` or `Ord`, comparisons, cycles) shows no value.
- **Inactive branches:** Over a declaration in a branch that does not apply to the current configuration
  (`{$IFDEF …}`), the hover shows its header and comment from the file with the note “Inactive” and the condition.

Comments are not stored in the index; the hover reads them on demand from the one file of the declaration.

### Values while debugging

If the program is paused and the setting “Values in the hover while debugging” is on, dpcc evaluates the expression
under the mouse through the IDE's debugger. The evaluation does not call anything in the program. The value is at
the very top.

### Help Insight

As long as the dpcc tooltip is on, dpcc switches off the IDE's Help Insight so that two tooltips do not appear.
Details under [Settings](settings.md#what-dpcc-changes-in-the-ide).

## Language

dpcc's texts are in German if the IDE is German, otherwise in English. Identifiers, signatures and XMLDoc are never
translated.
