[Deutsch](../de/lsp-server.md) | [English](../en/lsp-server.md) | Français

# Serveur LSP (dpcc.LspServer.exe)

[Vue d’ensemble](index.md) › Serveur LSP

`dpcc.LspServer.exe` est dpcc sous forme de serveur de langage autonome. Il parle le Language Server Protocol sur
stdin/stdout et remplace `DelphiLSP.exe` dans l’IDE Delphi. À l’intérieur tourne le même serveur que dans le plugin
(index, complétion, survol, aide aux paramètres, cibles de saut) ; s’y ajoutent la vue structure et le format attendu
par l’IDE.

C’est le plugin qui l’intègre à l’IDE : dans le [mode Server](#mode-server). Le serveur intégré du plugin (mode
Plugin) et l’EXE ne fonctionnent jamais en même temps.

## Ce qu’il fait

| Requête | Résultat |
|---|---|
| `textDocument/completion`, `completionItem/resolve` | liste avec genre, nom et signature comme DelphiLSP |
| `textDocument/hover` | déclaration et documentation ; pour RAD Studio en HTML comme DelphiLSP (voir plus bas) |
| `textDocument/signatureHelp` | signatures avec le paramètre courant |
| `textDocument/definition`, `declaration`, `typeDefinition` | saut vers implémentation, déclaration, type |
| `textDocument/implementation` | seulement pour RAD Studio : même cible que `definition` |
| `textDocument/documentSymbol` | vue structure : sections, types avec champs, propriétés et méthodes, routines |
| `didOpen`, `didChange` (texte entier ou plages), `didClose` | documents en mémoire |
| `workspace/didChangeConfiguration` | données de projet de l’IDE, voir plus bas |

Ce qu’il ne sait pas faire reçoit l’erreur -32601 (méthode introuvable), par exemple `textDocument/references`
(pour les clients autres que RAD Studio aussi `textDocument/implementation`). Il n’y a pas de diagnostics de code (Error Insight reste vide) ni de transmission à
DelphiLSP.

## Appel

```
dpcc.LspServer.exe [--cache-root <dossier>] [--log-level debug|info|warning|error] [--no-log] [--version] [--help]
```

Les autres paramètres sont ignorés. Le serveur répond tout de suite à `initialize` et charge projet et index en
arrière-plan ; tant que l’index n’est pas prêt, les réponses sont vides ou incomplètes au lieu de l’attendre. Il se
termine après `exit` (notification ou requête avec id), à la fin de l’entrée ou quand le processus indiqué par
`processId` dans `initialize` se termine. Le dossier de travail ne joue aucun rôle.

L’EXE existe en Win32 et Win64 ; les deux servent Delphi 12 et Delphi 13. Elle ne dépend d’aucune BPL. L’IDE 32 bits
lance aussi l’EXE 64 bits.

## Mode Server

Dans le mode Server, l’IDE reste en fonctionnement LSP (fournisseur DelphiLSP) et affiche ses propres fenêtres :
liste, aide, infobulle au survol, vue structure et Ctrl+clic. Lorsqu’elle lance `DelphiLSP.exe`, le plugin lance à sa
place `dpcc.LspServer.exe` avec les mêmes paramètres ; indicateurs, handles, environnement et dossier de travail
restent tels que l’IDE les règle. Pour cela, le plugin détourne dans l’IDE en cours l’appel de `kernel32!CreateProcessW`
dans le module `IDELSP290.bpl` (Delphi 12) ou `IDELSP370.bpl` (Delphi 13) (hook dans la table d’importation). Il ne
modifie rien dans le dossier d’installation de Delphi et n’a pas besoin de droits d’administrateur.

### Activer

1. Mettre l’EXE à disposition : choisir le composant « LSP server » dans l’installateur (par défaut), la placer depuis
   le ZIP à l’un des [emplacements](#où-dpcc-cherche-lexe) ou la compiler soi-même (voir
   [Installation](installation.md#serveur-lsp)).
2. **Tools › Options › Third Party › dpcc**, choisir le mode « Server – dpcc.LspServer.exe instead of DelphiLSP »
   (Server – dpcc.LspServer.exe à la place de DelphiLSP) et fermer avec **OK**. dpcc règle alors le fournisseur Code
   Insight de l’IDE sur DelphiLSP.
3. Si le changement vient du mode Plugin (ou si un autre fournisseur était choisi), redémarrer Delphi. S’il vient du
   mode Off, fermer puis rouvrir le groupe de projets : l’IDE lance son serveur lorsque la première unité d’un groupe
   de projets est affichée, un par groupe, et un serveur lancé reste jusqu’à la fermeture du groupe.

Le mode s’applique par version de Delphi (voir [Réglages](settings.md#mode-de-fonctionnement)). À chaque lancement de
DelphiLSP, le hook le relit dans le registre ; on revient donc au DelphiLSP d’origine avec « Off » et une nouvelle
ouverture du groupe de projets. Si l’EXE manque, « Server » est grisé sur la page avec la remarque « Not available:
dpcc.LspServer.exe is not installed … » (non disponible : dpcc.LspServer.exe n’est pas installé). Si Server est déjà
choisi, il le reste, et le lancement revient au DelphiLSP d’origine. L’infobulle du bouton indique l’emplacement
trouvé.

### Où dpcc cherche l’EXE

Par rapport au plugin chargé, dans cet ordre ; sous Windows 64 bits, chaque fois d’abord l’EXE 64 bits (`win64`,
`Win64`), puis l’EXE 32 bits :

| Organisation | Plugin | EXE |
|---|---|---|
| installateur | `{app}\bpl\d12` ou `{app}\bpl\d13` (`{app}` = `%LOCALAPPDATA%\Programs\dpcc`) | `{app}\server\win64\dpcc.LspServer.exe`, puis `{app}\server\win32\dpcc.LspServer.exe` |
| compilation propre | `Output\Win32\<configuration>\Bpl` | `Output\Win64\<configuration>\Bin`, à défaut `Output\Win64\Debug\Bin` et `Output\Win64\Release\Bin`, puis les mêmes sous `Output\Win32` |
| en dernier | quelconque | à côté du plugin, par exemple déposée là depuis le ZIP |

Pour une compilation propre sous Delphi 12 (configuration D12), cela donne : d’abord `Output\Win64\D12\Bin`, puis
`Output\Win64\Debug\Bin` et `…\Release\Bin`, puis les mêmes sous `Output\Win32`.

### Journal

Chaque étape figure sur une ligne de `dpcc.log` (`%LOCALAPPDATA%\dpcc\Logs`) ; les lignes du journal sont toujours en
allemand :

| Ligne | Signification |
|---|---|
| `LSP-Umleitung: Hook beim Anmelden (37.0): 1 Eintrag/Einträge in IDELSP370.bpl umgebogen; Betriebsart jetzt Server; EXE: …` | Le hook est en place. Si `IDELSP` n’était pas encore chargé à l’enregistrement, dpcc rattrape l’installation (« Hook nachgeholt nach n ms … », pendant 5 minutes au plus). |
| `LSP-Umleitung: #1 DelphiLSP umgeleitet auf <EXE> (PID n)` | L’IDE a lancé son serveur ; c’est `dpcc.LspServer.exe` qui a été lancé. |
| `LSP-Umleitung: #2 Start von DelphiLSP nicht umgeleitet (<Grund>)` | Le DelphiLSP d’origine démarre. Raisons : `Betriebsart Aus`, `Betriebsart Plugin`, `dpcc.LspServer.exe nicht gefunden`, `dpcc.LspServer.exe fehlt: <Pfad>`. |
| `LSP-Umleitung: #3 Start von dpcc.LspServer.exe fehlgeschlagen (Fehler n), Originalaufruf` | L’EXE n’a pas pu être lancée (code d’erreur Windows n) ; c’est le DelphiLSP d’origine qui démarre. |
| `LSP-Umleitung: Hook abgebaut: …` | Au déchargement du plugin, y compris dans l’IDE en cours. Ensuite, c’est de nouveau l’original qui démarre. |
| `Eingebauter Server: startet nicht (Betriebsart Server)` | À l’enregistrement du plugin : dans les modes Off et Server, le serveur intégré ne démarre pas pendant cette session (en mode Plugin : `… startet bei Bedarf (Betriebsart Plugin); keine Umleitung von DelphiLSP`). |
| `Eingebauter Server nicht gestartet: …` | Le serveur intégré du plugin reste arrêté, avec la raison (mode ou redirection antérieure, voir plus bas). |

Le journal propre de l’EXE se trouve sous son [stockage](#stockage).

### Exclusion mutuelle

- Le serveur intégré du plugin ne démarre que dans le mode Plugin.
- Si le hook a déjà redirigé une fois vers `dpcc.LspServer.exe` dans cette session de l’IDE, le serveur intégré ne
  démarre plus jusqu’au redémarrage de Delphi, même si Plugin est choisi ensuite.
- Dans le mode Plugin, le hook ne redirige jamais ; l’IDE n’appelle de toute façon pas DelphiLSP.

### Limites

- Error Insight reste vide : le serveur ne fournit pas de diagnostics de code. dpcc ne règle pas `ErrorInsightLevel`.
- Non pris en charge : l’IDE 64 bits de Delphi 13 (`bin64\bds.exe`, `Known Packages x64`). Le plugin est en 32 bits
  et ne s’y charge pas.
- Si l’EXE manque ou si son lancement échoue, c’est le DelphiLSP d’origine qui démarre ; une ligne figure dans le
  journal.
- Le plantage de Delphi 12 à l’affichage d’une unité contenant un nombre à virgule flottante ne se produit pas en
  fonctionnement LSP (voir
  [Dépannage](troubleshooting.md#plantage-de-delphi-12-à-laffichage-dune-unité-avec-un-nombre-à-virgule-flottante)).

## Stockage

| Ordre | Emplacement |
|---|---|
| 1 | `--cache-root <dossier>` |
| 2 | variable d’environnement `DPCC_LSPSERVER_CACHE_ROOT` |
| 3 | `%LOCALAPPDATA%\dpcc.LspServer` |

On y trouve, comme pour le plugin, `Index\<version de Delphi>\…` (caches), `projektauswahl.json` et
`Logs\Diagnose` (journal de diagnostic anonyme), ainsi que le journal de l’EXE dans
`Logs\LspServer\lsp-<date>-<processus>.log` (un fichier par processus, supprimé après 14 jours). Le dossier du
plugin (`%LOCALAPPDATA%\dpcc`) n’est pas touché ; une variable `DPCC_CACHE_ROOT` ne vaut pas pour l’EXE. Les réglages
sont lus comme dans le plugin depuis `%APPDATA%\dpcc\settings.json` et `dpcc.json`, mais jamais écrits.

Le serveur écrit les caches dans un fichier intermédiaire puis le renomme ; un arrêt brutal (l’IDE termine le
processus après `shutdown` sans `exit`) ne laisse donc jamais de cache à moitié écrit.

## Données de projet de l’IDE

L’IDE annonce le projet actif par `workspace/didChangeConfiguration`. Le serveur en lit :

| Champ | Usage |
|---|---|
| `project` | fichier principal (.dpr/.dpk) ; le .dproj voisin devient espace de travail si les fichiers ouverts ne le donnent pas déjà |
| `dllname` | version de Delphi (`dcc32290.dll` → 23.0, `dcc32370.dll` → 37.0) et plateforme (`dcc32` Win32, `dcc64` Win64) |
| `dccOptions` | `-D` symboles, `-NS` espaces de noms, `-U` chemins : dans les dossiers d’installation ou Studio comme bibliothèque, sinon comme chemin de recherche du projet |
| `browsingPaths` | chemin de navigation de l’IDE (sources de la bibliothèque) |
| `CommonAppData` | profil de l’IDE (`bds -r`) dont le serveur lit variables et chemins |

Sans ces données (autres clients), le serveur déduit les projets des fichiers ouverts : le .dproj dans le dossier du
fichier ou au-dessus.

## Clients

Si le client se présente comme `RAD Studio` dans `initialize`, le serveur répond sous la forme du DelphiLSP
d’origine et n’envoie aucune notification propre. Tout autre client reçoit du LSP standard.

### Forme des réponses pour RAD Studio

Mesurée le 27.11.2026 dans Delphi 12 et 13 sur le DelphiLSP d’origine (dans l’IDE en cours d’exécution) ; les
fenêtres de l’IDE ont donc le même aspect qu’avec l’original, seul le contenu peut différer.

| Requête | Forme |
|---|---|
| hover | `contents` est **une** chaîne HTML dans le cadre de Help Insight (`HelpInsight.css`) : un titre comme `function TProbe.Twice(const A: Integer): Integer`, un lien `fichier (ligne)`, puis résumé, paramètres, valeur de retour et remarques tirés du XMLDoc. Les versions précédentes envoyaient du texte brut, que l’IDE affichait comme du HTML (les lignes se collaient). |
| signatureHelp | une entrée par paramètre avec son type (`A: Integer`, les groupes comme `A, B: Integer` résolus), `documentation` en HTML (`kind` html), par paramètre `kind` xml |
| definition, declaration, typeDefinition, implementation | **un** objet Location (pas de tableau) ; fichiers ouverts avec la même écriture d’URI que dans `didOpen` |
| completion | `kibitzkind` 2 après `.`, 7 sans point, 15 dans la clause uses ; `sortText` hexadécimal ; surcharges en entrées séparées ; `kind`, `detail` et `DCC_Flags` par genre de symbole comme DelphiLSP ; les branches `{$IFDEF}` inactives sont omises |
| completionItem/resolve | la même entrée que dans la liste, avec `DCC_Flags`, sans `documentation` |
| documentSymbol | avec une section uses et ses unités ; énumérations et alias de type comme les records (kind 23), constructeurs comme les méthodes (kind 6), propriété avec sa partie d’accès comme `detail` |

Différences de contenu connues : le titre de l’aide aux paramètres ne nomme ni la classe ni l’unité (`function Add(…)` au lieu de `function TProbe.Add(…)` ; invisible dans l’indication de paramètres de l’IDE) ; Ctrl+clic sur une routine de la RTL saute à sa déclaration, DelphiLSP à son implémentation ; les mots-clés et les unités de la clause uses ne figurent dans la liste que si le serveur les fournit.

## Voir aussi

- [Réglages › Mode de fonctionnement](settings.md#mode-de-fonctionnement)
- [Architecture](architecture.md) : serveur, index et parcours d’une requête
- [Index et cache](index-cache.md)
