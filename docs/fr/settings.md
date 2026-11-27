[Deutsch](../de/settings.md) | [English](../en/settings.md) | Français

# Réglages

[Vue d'ensemble](index.md) › Réglages

Les options se trouvent sous **Tools › Options › Third Party › dpcc**. C'est une seule page, sans sous-pages.

L'interface de dpcc n'existe qu'en allemand et en anglais ; une IDE française affiche cette page en anglais. Les
noms d'options sont donc cités ici en anglais, avec une traduction française entre parenthèses.

## La page

- En haut figure le mode de fonctionnement avec trois boutons radio, suivi des sections **Completion** (complétion),
  **When accepting** (lors de l'acceptation), **Parameter hint and tooltip** (aide aux paramètres et infobulle),
  **Index** (index) et **IDE**.
- Les options situées en dessous ne valent que pour le mode Plugin. Dans les modes Off et Server, elles et le bouton
  « Reset history » (réinitialiser l'historique) sont grisés. « Rebuild index » (reconstruire l'index), « Check now »
  (vérifier maintenant) et « Log the flow (log file) » (journaliser le déroulement) restent utilisables.
- « Show values while debugging » (afficher les valeurs pendant le débogage) est grisé tant que « Own tooltip when
  hovering identifiers » (infobulle propre au survol des identificateurs) est désactivé.

L'enregistrement se fait avec **OK**. Exceptions : « Reset history » et « Rebuild index » agissent immédiatement,
« Check now » ne fait que lire. « Log the flow (log file) » agit après OK sans redémarrage.

Certaines anciennes options ne figurent plus sur la page et ont une valeur fixe (voir
[Valeurs fixes](#valeurs-fixes)).

La colonne « Valeur de registre » donne le nom sous `HKCU\Software\dpcc\IdePlugin`, la colonne « Clé » le nom que dpcc
utilise dans les remarques et dans `settings.json`. « – » sous « Valeur de registre » : l'option n'est pas enregistrée
dans le registre, mais dans `settings.json` (voir [Stockage](#stockage)).

## Mode de fonctionnement

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Mode (mode de fonctionnement, trois boutons radio) | `OperatingMode 23.0` (Delphi 12) ou `OperatingMode 37.0` (Delphi 13) | `operatingMode` | Plugin | Séparément pour chaque version de Delphi : `off`, `plugin` ou `server`. Remplace l'ancien interrupteur principal « Code Insight by dpcc » (Code Insight de dpcc, `Enabled`, commun à toutes les versions). À l'exécution, un seul mode s'applique ; le serveur intégré du plugin et `dpcc.LspServer.exe` ne fonctionnent jamais en même temps. Un passage depuis ou vers Plugin bascule le fournisseur Code Insight de l'IDE et prend effet après le redémarrage de Delphi ; entre Off et Server, il prend effet à la prochaine ouverture d'un groupe de projets. Voir [Basculer](#basculer). La liste, l'aide aux paramètres et l'infobulle de dpcc suivent le choix immédiatement après OK (hors du mode Plugin, Ctrl+Espace et Ctrl+Maj+Espace vont à l'IDE) ; un serveur intégré déjà lancé continue de tourner. |

Les trois boutons radio et leur texte sur la page :

| Bouton radio | Texte en dessous |
|---|---|
| « Off – Delphi works without dpcc » (Off – Delphi fonctionne sans dpcc) | « Delphi uses its own Code Insight provider (DelphiLSP); dpcc shows no windows and redirects nothing. » (Delphi utilise son propre fournisseur Code Insight (DelphiLSP) ; dpcc n'affiche aucune fenêtre et ne redirige rien.) |
| « Plugin – Code Insight by dpcc in the editor (default) » (Plugin – Code Insight de dpcc dans l'éditeur, par défaut) | « dpcc becomes the IDE's Code Insight provider, with its own list, tooltip and parameter hint. Switching to or from Plugin takes effect after restarting Delphi. » (dpcc devient le fournisseur Code Insight de l'IDE, avec sa propre liste, son infobulle et son aide aux paramètres. Le passage depuis ou vers Plugin prend effet après le redémarrage de Delphi.) |
| « Server – dpcc.LspServer.exe instead of DelphiLSP » (Server – dpcc.LspServer.exe à la place de DelphiLSP) | « Delphi stays in LSP mode and shows its own windows; the answers come from dpcc.LspServer.exe instead of DelphiLSP.exe. The IDE's error marks (Error Insight) stay empty. Switching to or from Plugin takes effect after restarting Delphi, between Off and Server the next time a project group is opened. » (Delphi reste en fonctionnement LSP et affiche ses propres fenêtres ; les réponses viennent de dpcc.LspServer.exe au lieu de DelphiLSP.exe. Les marques d'erreur de l'IDE (Error Insight) restent vides. Le passage depuis ou vers Plugin prend effet après le redémarrage de Delphi, entre Off et Server à la prochaine ouverture d'un groupe de projets.) |

- **Off** (auparavant « interrupteur principal désactivé ») : Delphi travaille avec son propre fournisseur Code
  Insight (DelphiLSP, `Insight Manager` = `Borland.CodeInsight.LSP.Pascal`). dpcc n'affiche aucune fenêtre et ne
  redirige rien.
- **Plugin** (par défaut après l'installation, auparavant « interrupteur principal activé ») : dpcc est le fournisseur
  Code Insight (`dpcc.CodeInsight`), avec son serveur intégré, sa propre liste, son infobulle et son aide aux
  paramètres.
- **Server** : l'IDE reste en fonctionnement LSP (fournisseur DelphiLSP). Lorsqu'elle lance `DelphiLSP.exe`, le
  plugin lance `dpcc.LspServer.exe` à sa place. Le serveur intégré et les fenêtres de dpcc sont désactivés. Voir
  [Mode Server](#mode-server).

### Mode Server

- La liste, l'aide, l'infobulle au survol, la vue Structure et Ctrl+clic sont ceux de l'IDE ; les réponses viennent
  de `dpcc.LspServer.exe`. La liste, l'infobulle et l'aide aux paramètres de dpcc n'apparaissent pas, Ctrl+Espace et
  Ctrl+Maj+Espace vont à l'IDE.
- Les marques d'erreur de l'IDE (Error Insight) restent vides : `dpcc.LspServer.exe` ne fournit pas de diagnostics
  de code. dpcc ne règle pas `ErrorInsightLevel`.
- La redirection se fait depuis le plugin (hook sur `CreateProcessW` dans le module `IDELSP290.bpl` ou
  `IDELSP370.bpl`). dpcc ne modifie rien dans le dossier d'installation de Delphi et n'a pas besoin de droits
  d'administrateur. Détails, emplacements de l'EXE et lignes du journal : [Serveur LSP](lsp-server.md#mode-server).
- « Server » ne peut être choisi que si dpcc trouve l'EXE. Sinon, le bouton est grisé et le texte en dessous indique
  « Not available: dpcc.LspServer.exe is not installed (select the component “LSP server” in the setup). » (non
  disponible : dpcc.LspServer.exe n'est pas installé ; choisir le composant « LSP server » dans l'installateur). Si
  Server est déjà choisi, il le reste ; le lancement revient alors au DelphiLSP d'origine. L'infobulle du bouton
  indique l'emplacement trouvé de l'EXE (« Program: … », programme).
- Non pris en charge : l'IDE 64 bits de Delphi 13 (`bin64\bds.exe`). Le plugin est en 32 bits.

## Completion

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Open on typing from characters (0 = never): (ouvrir lors de la saisie à partir de … caractères ; 0 = jamais) | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 à 10 ; par défaut 0 = désactivé (comme avant l'ouverture pendant la saisie), pour l'activer régler par exemple 5. Lorsqu'on saisit un nom sans point devant, la liste ne s'ouvre que lorsque le mot situé avant le curseur compte ce nombre de caractères ; en dessous, dpcc n'interroge pas le serveur. 0 = la saisie ne l'ouvre jamais. Ctrl+Espace l'ouvre quelle que soit la longueur ; rien ne change après « . » ni pour les autres déclencheurs. Pour que l'IDE n'ouvre pas en plus sa propre liste pendant la saisie, dpcc règle `Auto Invoke Delay` = -1 dans le mode Plugin (voir [plus bas](#ce-que-dpcc-modifie-dans-lide)). Voir [Utilisation](usage.md#ouverture-pendant-la-saisie). |
| While typing, show: (pendant la saisie, afficher) | `CompletionListMode` | `completion.listMode` | Only matches | « Only matches » (`filter`, uniquement les résultats), « All entries, matches on top » (`all`, toutes les entrées, résultats en haut), « Matches, then the rest dimmed » (`rest`, résultats, puis le reste atténué, sous l'en-tête « More entries », autres entrées). S'applique aux listes des membres après « . » (valeur fixe). |
| Visible rows of the list: (lignes visibles de la liste) | `VisibleRows` | `completion.visibleRows` | 9 | 5 à 20 lignes. |
| Automatic width (largeur automatique) | `ListWidth` | `completion.listWidth` | activé (`ListWidth` = 0) | Sur la même ligne que « Visible rows of the list ». Activé : la liste s'élargit avec l'entrée la plus large. Désactivé : la dernière largeur tirée (240 à 720). Tirer le bord droit de la liste définit aussi la largeur. |
| Frequently and recently chosen entries first (entrées choisies fréquemment et récemment en tête) | `Learning` | `completion.learning` | activé | Pondération apprise : les entrées acceptées reçoivent un bonus dans le classement. À partir de 5 acceptations, une entrée est considérée comme « frequent » (fréquente). Enregistré dans `%APPDATA%\dpcc\usage.json`, au plus 5 000 entrées. |
| Bouton « Reset history » (réinitialiser l'historique) | – | – | – | À droite de « Frequently and recently chosen entries first ». Vide immédiatement la pondération apprise ; le bouton reste ensuite grisé jusqu'à la fermeture de la boîte de dialogue. |

## When accepting

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Add parentheses to methods (ajouter les parenthèses aux méthodes) | `AutoParentheses` | `completion.autoParentheses` | activé | Ajoute les parenthèses lors de l'acceptation d'une méthode ; un « ) » tapé juste devant fait sauter la parenthèse automatique. |
| Accept with “(”, “;” and “.” (accepter avec « ( », « ; » et « . ») | `CommitCharacters` | `completion.commitCharacters` | activé | Caractères de validation : si l'entrée sélectionnée correspond de façon univoque, l'un de ces caractères l'accepte ; le caractère reste en place. Sinon, seul le caractère reste et la liste se ferme. |
| Add the unit to uses automatically (ajouter automatiquement l'unité à uses) | `AutoUses` | `completion.autoUses` | activé | Pour les entrées qui affichent à droite « + » et le nom d'une unité (par exemple « + System.SysUtils »), dpcc ajoute cette unité dans `uses` lors de l'acceptation, dans la même étape d'annulation. |

## Parameter hint and tooltip

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Parameter hint on “(” and “,” (aide aux paramètres sur « ( » et « , ») | `ParameterHints` | `completion.parameterHints` | activé | Désactivé : pas d'aide aux paramètres de dpcc, pas même via Ctrl+Maj+Espace. L'ouverture automatique sur « ( » et « , » n'atteint dpcc que si l'IDE appelle dpcc comme fournisseur (voir [Utilisation](usage.md#interaction-avec-delphilsp)). |
| Own tooltip when hovering identifiers (infobulle propre au survol des identificateurs) | `HoverTooltip` | `editor.hoverTooltip` | activé | Infobulle de dpcc. Tant qu'elle est activée, dpcc désactive, dans le mode Plugin, Help Insight et l'infobulle Symbol Insight de l'IDE (`Help Insight`, `Declaration Information`) et masque immédiatement, sans redémarrage, une fenêtre Help Insight qui apparaît quand même. Verrouillé hors du mode Plugin. |
| Show values while debugging (turns off the IDE's value tooltip) (afficher les valeurs pendant le débogage ; désactive l'infobulle de valeur de l'IDE) | `DebugHoverValues` | `debug.hoverValues` | activé | En retrait sous l'infobulle. Lorsque le programme est arrêté, la valeur de l'expression figure en haut de l'infobulle ; dpcc désactive alors l'évaluation d'expressions dans l'infobulle de l'IDE (`ToolTip Watches`). Qui veut l'infobulle de valeur de l'IDE désactive cette option. Verrouillé tant que « Own tooltip … » est désactivé. |
| Popup appearance: (apparence des fenêtres contextuelles) | `PopupLook` | `editor.popupLook` | Subtle | « Intense » (`intense`, intense), « Subtle » (`subtle`, discret), « Plain » (`plain`, sobre). Détermine l'intensité des couleurs des fenêtres de dpcc : liste de complétion, infobulle et aide aux paramètres, ainsi que les marques d'espaces réservés dans l'éditeur. Ce que change chaque niveau est décrit sous [Apparence des fenêtres contextuelles](#apparence-des-fenêtres-contextuelles). Après OK, s'applique dès la prochaine ouverture d'une fenêtre. Une valeur inconnue dans le registre compte comme Subtle. Verrouillé hors du mode Plugin. |

### Apparence des fenêtres contextuelles

| Niveau | Effet |
|---|---|
| Intense (intense) | Les zones mises en évidence – la ligne sélectionnée de la liste, l'en-tête de l'infobulle et la surcharge sélectionnée de l'aide aux paramètres – ont l'aspect du niveau Subtle et reçoivent en plus une barre épaisse dans la couleur d'accentuation, placée tout en haut de la fenêtre de l'infobulle, à gauche de la ligne dans la liste et au bord gauche dans l'aide aux paramètres. En dehors de ces zones, la colonne du type d'entrée affiche une couleur par groupe, les marques à droite sont en couleur (y compris « + Unit » pour une unité manquante), les noms de types et de paramètres ont leur propre couleur et le paramètre actif repose sur un fond d'accentuation. |
| Subtle (discret, par défaut) | Les mêmes éléments, atténués : fond d'accentuation léger pour la ligne sélectionnée et l'en-tête, noms de types et de paramètres dans une couleur atténuée. La colonne du type d'entrée est estompée ; seuls les avertissements et les erreurs sont en couleur. |
| Plain (sobre) | Presque sans couleur : ligne sélectionnée et en-tête sur fond gris clair, noms de types et de paramètres dans la couleur du texte, mots-clés des signatures seulement en gras. Les erreurs restent en rouge. |

Les lignes d'erreur gardent la couleur d'erreur aux trois niveaux. Les fenêtres propres à l'IDE ne sont pas
concernées : l'infobulle Symbol Insight de l'IDE (lorsque l'infobulle propre est désactivée), la liste Code Insight de
l'IDE et la fenêtre des messages. Là, c'est l'IDE qui décide des couleurs.

## Index

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Additional source folders (separated by “;”, including subfolders): (dossiers source supplémentaires, séparés par « ; », sous-dossiers compris) | – | `index.extraSourceFolders` | vide | Dossiers contenant le code source de bibliothèques qui n'existent sinon qu'en `.dcu` (DUnitX, DUnit, FireDAC, composants). Les sous-dossiers comptent aussi (sans `.git`, `__history`, `__recovery`) ; `$(Nom)` et `%Nom%` sont résolus. « + Unit » propose leurs unités ; elles sont chargées à la demande et ont leur propre cache. Enregistré dans `%APPDATA%\dpcc\settings.json` (dans le fichier aussi sous forme de liste), pas dans le registre ; le serveur reconstruit l'index sans redémarrage. Remplace l'ancien interrupteur `index.officeAndWinRt` : les bibliothèques de types Office et WinRT figurent toujours dans le catalogue. Voir [Index et cache](index-cache.md#dossiers-source-supplémentaires). |
| Bouton « Rebuild index » (reconstruire l'index) | – | – | – | Demande confirmation, supprime tous les caches d'index et reconstruit l'index. Ne dépend pas du mode de fonctionnement. Voir [Index et cache](index-cache.md#reconstruire-lindex). |

## IDE

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Bouton « Check now » (vérifier maintenant) | – | – | – | À sa droite, jusqu'à quatre lignes : mode et fournisseur, si un changement attend encore le redémarrage de Delphi, ce que dpcc a réglé dans l'IDE et le résultat de la vérification (par exemple « 1 difference: Auto Code Completions »). Lu à l'ouverture de la page ; le bouton relit. Lit seulement, ne modifie rien ; ne dépend pas du mode de fonctionnement. Voir [Ce que dpcc modifie dans l'IDE](#ce-que-dpcc-modifie-dans-lide). |
| Log the flow (log file) (journaliser le déroulement) | `Diagnose` | – | désactivé | Pour chaque action (Ctrl+clic ou « Find Declaration », complétion, survol, aide aux paramètres), écrit chaque étape, de l'appel de l'IDE jusqu'au résultat, dans le journal de diagnostic à côté du BPL du plugin. Aucun code source, sauf le mot à la position. Le même DWORD que l'ancien `Diagnose` = 1 réglé à la main : une valeur réglée ainsi apparaît cochée. Agit immédiatement après OK, sans redémarrage ; la fenêtre Messages nomme alors le fichier, l'infobulle de la case aussi. Ne dépend pas du mode de fonctionnement. Voir [Dépannage](troubleshooting.md#journal-du-déroulement). |

## Valeurs fixes

Ces options ne figurent plus sur la page. Elles ont une valeur fixe, leur ancienne valeur par défaut :

- **Delay before automatic opening (délai avant l'ouverture automatique, par exemple après « . ») : 150 ms**
  (`OpenDelayMs`, `completion.openDelayMs`). Ne vaut que pour l'ouverture automatique (après « . » et pendant la
  saisie), pas pour Ctrl+Espace. dpcc n'ouvre automatiquement que dans le mode Plugin ; dans les modes Off et
  Server, dpcc n'ouvre aucune liste (voir [Utilisation](usage.md#interaction-avec-delphilsp)).
- **Pin favorites with Ctrl+D (épingler les favoris avec Ctrl+D) : activé** (`Favorites`, `completion.favorites`).
  Ctrl+D dans la liste ouverte épingle ou détache ; les favoris restent enregistrés dans
  `%APPDATA%\dpcc\favorites.json`. Voir [Utilisation](usage.md#favoris).
- **Inherited members ranked lower and grouped by class (membres hérités relégués et groupés par classe) : activé**
  (`GroupInherited`, `completion.groupInherited`). Sans début saisi : membres propres d'abord, puis un groupe
  « Inherited from … » (hérité de …) par ancêtre. Avec un début, à qualité égale, le membre propre passe avant le
  membre hérité.
- **Show the branch of variant record fields (afficher la branche des champs de record variants) : activé**
  (`CompletionVariantBranch`, `completion.variantBranch`). Pour les champs de la partie variante d'un record
  (`case … of`), la marque « branch 0 », « branch 1 », etc. (branche 0, branche 1) est affichée.
- **List mode applies to (le mode de liste s'applique à) : member lists after “.” (listes des membres après « . »)**
  (`CompletionListScope`, `completion.listMode.scope` = `members`). « While typing, show » n'agit que là.
- **Preview of the selected entry in the editor (aperçu de l'entrée sélectionnée dans l'éditeur) : supprimé**
  (auparavant `Preview`, `completion.preview`, en dernier lieu désactivé de façon fixe). Depuis le nettoyage des
  réglages, le code correspondant a lui aussi disparu.
- **Fix the case when accepting (corriger la casse lors de l'acceptation ; showmessage → ShowMessage) : activé**
  (`FixCase`, `completion.fixCase`). Remplace le mot saisi par la graphie de la déclaration.
- **Match and colour Format placeholders in the parameter hint (associer et colorer les espaces réservés de Format
  dans l'aide aux paramètres) : activé** (`FormatPlaceholders`, `completion.formatPlaceholders`). Ligne indiquant
  l'espace réservé sous le curseur, avertissements, même couleur pour l'espace réservé et l'argument ; seulement tant
  que « Parameter hint on “(” and “,” » est activé.
- **XMLDoc: max. lines before scrolling (XMLDoc : nombre maximal de lignes sans défilement) : 0 = écran**
  (`XmlDocMaxLines`, `hints.xmlDocMaxLines`). 0 à 50. Au-delà, l'infobulle défile avec la molette de la souris.
  0 : seule la place à l'écran limite. Ne figure plus sur la page, mais reste réglable via `hints.xmlDocMaxLines`
  dans `%APPDATA%\dpcc\settings.json` ; le serveur lit lui-même le fichier.

## Après la mise à jour

- L'ancienne répartition en **General**, **Completion**, **Insertion** et **Hints** n'existe plus, pas plus que
  l'arborescence, le champ de recherche, la ligne « Filter: » (filtre), le marquage des valeurs modifiées avec
  « Reset to default » (rétablir la valeur par défaut) par clic droit, la liste « Pinned favorites » (favoris
  épinglés), le bouton « Reset widths » (réinitialiser les largeurs) et l'interrupteur « Allow experimental
  features » (autoriser les fonctions expérimentales ; la clé `experimental.enabled` dans `settings.json` reste
  valable).
- « XMLDoc when opened » (XMLDoc à l'ouverture, `hints.xmlDocExpand`, auparavant `hints.xmlDocFull`) a été
  supprimé : l'infobulle affiche toujours le XMLDoc déplié. Une ancienne valeur dans `settings.json` reste en place
  et est ignorée sans message ; dpcc n'écrit plus la clé.
- Qui avait modifié l'une des options désormais [fixes](#valeurs-fixes) perd cette modification sans message. Les
  anciennes valeurs sous `HKCU\Software\dpcc\IdePlugin` restent en place et sont ignorées.
- L'interrupteur principal « Code Insight by dpcc » a cédé la place au [mode de fonctionnement](#mode-de-fonctionnement) :
  activé correspond à Plugin, désactivé à Off ; Server est nouveau. Le mode s'applique par version de Delphi ; dpcc
  reprend l'ancienne valeur `Enabled` au premier démarrage (voir [Stockage](#stockage)).
- OK n'enregistre plus que les valeurs de la page : le mode de fonctionnement de la version de Delphi en cours et
  douze options dans le registre,
  `index.extraSourceFolders` dans `settings.json`. Auparavant, chaque OK écrivait environ 600 valeurs de registre
  (y compris des réglages masqués d'anciens onglets, des raccourcis, des interrupteurs de modules et des
  interrupteurs expérimentaux) ainsi que des clés du serveur dans `settings.json` : `slashCommands.enabled`,
  `codeLens.metrics`, `metrics`, `experimental.enabled`, `compiler.onSave`, `architecture.*`, `query.enabled`,
  `ruleChecks.enabled`, `hotspots.*`, `references.*`, `navigation.*`, `tests.*`, `issues.*` et `vcs.*`. Toutes ces
  valeurs restent en place : dpcc ne lit plus les anciennes valeurs de registre, et le serveur continue de lire les
  clés de `settings.json` sans message. En leur absence, ses valeurs par défaut s'appliquent ; elles correspondent à
  celles que le plugin écrivait auparavant.
- « Show values while debugging » (afficher les valeurs pendant le débogage) ne dépend plus que de sa propre option
  (et, sur la page, de l'infobulle propre). L'ancien interrupteur de module masqué `debug.enabled` (valeur de
  registre `DebugEnabled`) ne la désactive plus.
- dpcc n'écrit plus l'historique des réglages `%APPDATA%\dpcc\settings-history.json`. Un fichier existant reste en
  place et peut être supprimé.
- Nouveau dans la section **IDE** : « Log the flow (log file) » (journaliser le déroulement). Il active le même
  journal de diagnostic que la valeur de registre `Diagnose` = 1, réglée jusqu'ici uniquement à la main, désormais
  sans redémarrage. Depuis, OK écrit aussi `Diagnose` ; si vous aviez réglé la valeur à la main, la case apparaît
  cochée.

## Stockage

| Emplacement | Contenu |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | toutes les options de la page sauf `index.extraSourceFolders`. Interrupteurs et nombres en DWORD (interrupteurs 0/1), choix en texte (`CompletionListMode` : `filter`, `all`, `rest` ; `PopupLook` : `intense`, `subtle`, `plain` ; le mode de fonctionnement par version sous `OperatingMode 23.0` ou `OperatingMode 37.0` : `off`, `plugin`, `server`). L'ancien interrupteur principal `Enabled` (DWORD, commun à toutes les versions) n'est plus que lu, voir plus bas. En plus, les marqueurs pour les réglages de l'IDE (plus bas) et `PathOverrideBackup` de `Tools\IdePath.ps1`. Lu seulement, jamais écrit : l'interrupteur de support `LogNames` (voir [Dépannage](troubleshooting.md)). `Diagnose` (« Log the flow (log file) ») fait désormais partie des valeurs de la page ; OK l'écrit sous forme 0 ou 1, une valeur réglée à la main reste valable. Les anciennes valeurs des options fixes et des options supprimées restent en place, mais sans effet ; dpcc ne les écrit plus. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` (depuis la page) et `hints.xmlDocMaxLines` (réglable uniquement dans le fichier). Le serveur dans le processus de l'IDE lit lui-même le fichier et le surveille. dpcc lit seulement `hints.xmlDocMaxLines` et n'écrit jamais la clé ; si elle manque dans le fichier, une valeur de registre `XmlDocMaxLines` d'une version antérieure s'applique, sinon 0. dpcc ne touche pas aux autres clés du fichier. Une ancienne valeur `hints.xmlDocExpand` ou `hints.xmlDocFull` reste sans effet. |
| `%APPDATA%\dpcc\settings-history.json` | uniquement issu de versions antérieures : états antérieurs des réglages. dpcc n'écrit ni ne lit plus ce fichier ; il peut être supprimé. |
| `%APPDATA%\dpcc\usage.json` | historique de la pondération apprise |
| `%APPDATA%\dpcc\favorites.json` | favoris épinglés |

Un fichier `usage.json` ou `favorites.json` inutilisable est déplacé par dpcc à côté, sous le nom `….defekt`, et dpcc
repart de zéro. Un fichier verrouillé n'est pas écrasé.

Mode de fonctionnement au premier démarrage d'une version :

- Si la version de Delphi n'a pas encore sa propre valeur `OperatingMode <version>`, l'ancien `Enabled` s'applique :
  0 → Off, toute autre valeur → Plugin. Si `Enabled` manque aussi, Plugin s'applique. Une valeur illisible compte
  comme une valeur manquante.
- dpcc écrit aussitôt le résultat sous le nom de la version au premier démarrage. `Enabled` reste ensuite en place
  sans changement et n'est plus écrit.
- S'il n'existe ni valeur propre ni `Enabled` (premier démarrage après l'installation), Plugin s'applique et dpcc
  bascule le fournisseur Code Insight de l'IDE sur dpcc, même si DelphiLSP était choisi. Cela prend effet après le
  redémarrage de Delphi.

Tout remettre aux valeurs par défaut : fermer l'IDE et supprimer la clé `HKCU\Software\dpcc\IdePlugin` ainsi que
`settings.json`. Auparavant, choisir le mode Off, confirmer avec OK et redémarrer Delphi une fois, afin que dpcc rende
le fournisseur et les réglages de l'IDE (voir plus bas). Au démarrage suivant, la valeur par défaut Plugin s'applique
de nouveau, et dpcc bascule de nouveau le fournisseur sur dpcc.

## Ce que dpcc modifie dans l'IDE

dpcc fonctionne, pour chaque version de Delphi, dans l'un de trois [modes de fonctionnement](#mode-de-fonctionnement)
qui s'excluent. Le mode se choisit sur la page ; au démarrage de Delphi, dpcc l'accorde avec le fournisseur Code
Insight choisi pour Delphi dans les options de l'IDE (valeur `Insight Manager` sous
`HKCU\<base>\Editor\Source Options\Borland.EditOptions.Pascal`). C'est identique pour Delphi 12
(`<base>` = `Software\Embarcadero\BDS\23.0`) et Delphi 13 (`…\BDS\37.0`).

| Mode | Fournisseur de l'IDE | dpcc | Ce que dpcc modifie dans l'IDE |
|---|---|---|---|
| Off | DelphiLSP (par défaut de l'IDE) ou un autre fournisseur | aucune fenêtre, aucune redirection | Il annule ce qu'il a lui-même modifié. Il ne fait que vérifier les valeurs dont DelphiLSP a besoin et écrit le résultat dans le journal. |
| Plugin | dpcc (`dpcc.CodeInsight`) | serveur intégré, liste, infobulle et aide aux paramètres propres | Il règle les options du tableau [Réglages dans le mode Plugin](#réglages-dans-le-mode-plugin). |
| Server | DelphiLSP (`Borland.CodeInsight.LSP.Pascal`) | pas de serveur intégré, aucune fenêtre ; le lancement de `DelphiLSP.exe` est redirigé vers `dpcc.LspServer.exe` | Comme pour Off. Avec OK, il règle le fournisseur sur DelphiLSP. La redirection se trouve dans le processus de l'IDE, pas dans le registre. |

Il n'existe pas d'Open Tools API pour ces réglages : ils se trouvent dans le registre de l'IDE et sont lus au
démarrage de l'IDE. dpcc les y lit et les y écrit, indépendamment de la version, via la clé de base de l'IDE en cours.

### Basculer

- **Plugin** et OK : dpcc bascule le fournisseur de l'IDE sur dpcc (`Insight Manager` = `dpcc.CodeInsight`) et règle
  les options. Le fournisseur précédent est mémorisé.
- **Off** et OK, alors que Plugin s'appliquait : dpcc rétablit le fournisseur (celui mémorisé, sinon DelphiLSP) et
  annule ses autres modifications.
- **Server** et OK : dpcc règle dans tous les cas le fournisseur sur DelphiLSP (même depuis un autre fournisseur, et
  non sur la valeur mémorisée) et annule ses réglages Code Insight comme pour Off.
- Depuis ou vers **Plugin**, le fournisseur change ; cela ne prend effet qu'après le redémarrage de Delphi (voir plus
  bas).
- **Entre Off et Server** (l'IDE est déjà en fonctionnement LSP), aucun redémarrage n'est nécessaire. L'IDE lance son
  serveur lorsque la première unité d'un groupe de projets est affichée, un par groupe de projets ; un serveur lancé
  reste jusqu'à la fermeture du groupe. La redirection relit le mode à chaque lancement de DelphiLSP. Donc : fermer
  puis rouvrir le groupe de projets.
- **Au démarrage de Delphi**, le mode suit le fournisseur choisi : si dpcc est choisi, Plugin s'applique. Si DelphiLSP
  est choisi (ou aucun fournisseur n'est inscrit), un mode Server enregistré reste en place, sinon Off s'applique. Si
  un autre fournisseur est choisi, Off s'applique ; si Server était choisi, la fenêtre Messages le signale. Exception :
  le premier démarrage sans valeur enregistrée (voir [Stockage](#stockage)).
- **Dans les options de l'IDE** (Code Insight), choisir un fournisseur : dpcc → Plugin ; un autre fournisseur alors que
  Plugin s'applique → Off (comme avant) ; DelphiLSP alors que Server s'applique → Server reste. Si l'IDE signale ce
  choix à dpcc, le mode suit immédiatement ; sinon le choix s'applique au prochain démarrage.
- L'IDE ne lit le fournisseur et les réglages qu'au démarrage. Après un changement, dpcc signale une fois dans la
  fenêtre Messages « … takes effect after restarting Delphi » (prend effet après le redémarrage de Delphi). D'ici là,
  l'IDE appelle le fournisseur précédent.
- Comme l'IDE réécrit ses options d'éditeur depuis la mémoire avec OK, dpcc n'écrit qu'après la boîte de dialogue,
  vérifie ensuite et écrit encore une fois l'état voulu à la fermeture de Delphi.
- Il en va de même lorsqu'on choisit dpcc ou un autre fournisseur dans la boîte de dialogue Code Insight de l'IDE et
  qu'on valide avec OK : l'IDE réécrit ensuite ses options d'éditeur depuis la mémoire et peut écraser des valeurs de
  dpcc. dpcc vérifie donc encore une fois après la fermeture de la boîte de dialogue des options (dès qu'aucune fenêtre
  modale n'est plus ouverte, pendant 10 minutes au plus) et réécrit les valeurs écrasées, comme après OK sur la page
  dpcc. La réparation à la fermeture de Delphi demeure.
- Si le passage à dpcc n'aboutit malgré tout pas (l'IDE a réécrit son choix), dpcc est désactivé au prochain démarrage
  et la fenêtre Messages le signale. Choisir alors de nouveau le mode Plugin ou choisir dpcc dans les options de
  l'IDE.
- Chaque décision figure sur une ligne du journal, par exemple « IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal →
  dpcc aus; Betriebsart Server; … » ou « IDE-Kontext (Hauptschalter an): … → dpcc an; Betriebsart Plugin (geändert);
  Anbieter → dpcc.CodeInsight (wirkt nach dem Neustart); gesetzt: … » (les lignes du journal sont toujours en
  allemand). Le motif entre parenthèses s'appelle toujours « Hauptschalter an » (Plugin), « Hauptschalter aus » (Off)
  ou « Betriebsart Server ». Un changement sur la page figure en plus sous la forme « IDE-Kontext: Betriebsart mit OK
  umgestellt: Aus → Server ».

### Réglages dans le mode Plugin

Emplacement, sauf indication contraire : les emplacements du mode Plugin sous `HKCU\<base>\Code Insight` (voir
[Emplacements des clés selon la version](#emplacements-des-clés-selon-la-version)). Sous Delphi 12 comme sous
Delphi 13, c'est chacun de `Borland.EditOptions.Pascal` et `Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` qui
existe.

| Option de l'IDE | Valeur de registre | Attendu | Quand | Raison |
|---|---|---|---|---|
| Fournisseur Code Insight pour Delphi | `Insight Manager` (sous `Editor\Source Options\Borland.EditOptions.Pascal`) | `dpcc.CodeInsight` | toujours | dpcc sert lui-même les fichiers Delphi. |
| Code completion (complétion de code) | `Auto Code Completions` | `True` | toujours | Désactivé : aucune liste ne s'ouvre après « . ». |
| Auto invoke (appel automatique) | `Auto Invoke` | `True` | toujours | Désactivé : l'IDE n'appelle pas d'elle-même la complétion après « . ». |
| Code completion: Delay (complétion de code : délai) | `Auto Invoke Delay` | `-1` | toujours | À partir de 0, l'IDE ouvre en plus sa propre liste pendant la saisie. |
| Code parameters: Auto invoke (paramètres : appel automatique) | `Auto Code Parameters` | `True` | toujours | Désactivé : l'aide aux paramètres ne s'ouvre pas d'elle-même sur « ( » et « , ». |
| Tooltip help insight (infobulle Help Insight) | `Help Insight` | `False` | « Own tooltip … » activé | Sinon l'IDE affiche Help Insight à côté de l'infobulle de dpcc. En plus, dpcc masque la fenêtre à l'exécution (voir ci-dessous). |
| Tooltip symbol insight (infobulle Symbol Insight) | `Declaration Information` | `False` | « Own tooltip … » activé | Sinon l'IDE affiche son infobulle à côté de celle de dpcc. |
| Tooltip expression evaluation (évaluation d'expressions dans l'infobulle) | `ToolTip Watches` | `False` | infobulle et « Show values while debugging » activés | Sinon deux infobulles de valeur pendant le débogage. |
| Ouvrir la complétion avec Parameter Insight | `AutoInvokeCompletionOnParameterInsight` (sous `InsightGlobalOptions`) | `False` | toujours | Sinon l'IDE ouvre en plus sa liste avec l'aide aux paramètres. |

Une valeur manquante s'applique avec la valeur par défaut de l'IDE (options activées, délai -1). Si elle convient
déjà, dpcc n'écrit rien. Les noms d'options sont ceux de l'IDE anglaise, abrégés ; seule la valeur de registre fait
foi.

Help Insight à l'exécution : indépendamment de la valeur de registre, dpcc masque la fenêtre Help Insight de l'IDE dès
qu'elle devient visible, tant que le mode Plugin s'applique et que soit « Own tooltip … » est activé (alors toujours), soit la
liste de complétion de dpcc est ouverte (alors aussi avec l'infobulle propre désactivée, pour que la fenêtre ne
recouvre pas la liste). Cela prend effet immédiatement, sans redémarrer Delphi ; dans les modes Off et Server,
Help Insight de l'IDE reste intact. Le premier masquage de chaque session figure dans le journal (« Help Insight der IDE: Fenster
THelpInsightWindow verborgen … »), avec « Log the flow (log file) » chaque masquage avec sa raison. Au démarrage, le
journal contient aussi une ligne « Help Insight in der Registry (…) » avec la valeur lue à l'emplacement de
DelphiLSP, dans `Borland.EditOptions.Pascal` et dans `Borland.EditOptions.HTML` (les lignes du journal sont toujours
en allemand).

### Vérification dans les modes Off et Server

Avec DelphiLSP, dpcc vérifie au démarrage, mais ne modifie rien. Le résultat figure dans le journal et dans la section
[IDE](#ide) de la page.

| Option de l'IDE | Valeur de registre | Attendu | Raison |
|---|---|---|---|
| Code completion | `Auto Code Completions` | `True` | Désactivé : aucune liste ne s'ouvre après « . » (voir [Dépannage](troubleshooting.md#aucune-liste-ne-souvre-après-le-point)). |
| Auto invoke | `Auto Invoke` | `True` | Désactivé : l'IDE n'appelle pas d'elle-même la complétion après « . » (voir [Dépannage](troubleshooting.md#aucune-liste-ne-souvre-après-le-point)). |
| Code parameters: Auto invoke | `Auto Code Parameters` | `True` | Désactivé : pas d'aide aux paramètres d'elle-même. |
| Error Insight | `Error Insight` | `True` (manquant = activé) | Désactivé : les marques d'erreur de DelphiLSP manquent dans l'éditeur. Dans le mode Server, elles restent vides de toute façon. |

#### Emplacements des clés selon la version

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| Modes Off et Server (DelphiLSP) | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |
| Mode Plugin | chacun de `Code Insight\Borland.EditOptions.Pascal` et `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` qui existe | chacun de `Code Insight\Borland.EditOptions.Pascal` et `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` qui existe |

Ni pour Delphi 12 ni pour Delphi 13, on ne sait avec certitude quel emplacement l'IDE lit avec dpcc comme
fournisseur ; sous Delphi 12, Help Insight restait actif même avec `False` à l'emplacement de DelphiLSP. dpcc traite
donc les deux versions de la même façon : il règle et vérifie chacun des deux emplacements qui existe et n'en crée
aucun qui manque ; s'ils manquent tous les deux, il prend l'emplacement de DelphiLSP. Les anciens marqueurs pour
`Borland.EditOptions.Pascal` sous Delphi 12 comptent ainsi de nouveau comme marqueurs propres de dpcc et ne sont plus
nettoyés comme « ancien emplacement » ; « aufgeräumt (alter Ort) » n'apparaît plus que pour un marqueur à un
emplacement qui n'est pas un emplacement du mode Plugin. En plus, dpcc masque la fenêtre Help Insight à l'exécution
(voir [Réglages dans le mode Plugin](#réglages-dans-le-mode-plugin)).
Si la clé vérifiée manque entièrement, le
résultat indique « key missing (IDE default) » (clé manquante, valeur par défaut de l'IDE) ; ce n'est pas une erreur.
La ligne du journal ressemble à « IDE-Einstellungen: 1 Abweichung: Auto Code Completions; Anbieter
„Borland.CodeInsight.LSP.Pascal“, geprüft … ».

### Marqueurs et retour en arrière

- dpcc note chaque modification sous `HKCU\Software\dpcc\IdePlugin`, séparément par version :
  `IdeSet <version> <clé>\<valeur>` avec la valeur écrite et la valeur antérieure (ou le fait qu'il n'y en avait pas).
- Seul ce qui est encore tel que dpcc l'a écrit est annulé. Si l'utilisateur ou l'IDE a modifié la valeur entre-temps,
  elle reste ; seul le marqueur disparaît. Si la valeur n'existait pas auparavant, dpcc la supprime de nouveau.
- Les anciens marqueurs (`IdeHelpInsightDisabled …`, `IdeTooltipWatchesDisabled …`) restent valables : lors de la
  synchronisation suivante, dpcc les annule ou les remplace par les nouveaux.
- dpcc ne modifie jamais Error Insight ni la mise en évidence de structure.
- dpcc ne règle pas non plus `ErrorInsightLevel`, pas même dans le mode Server.
- Avant la désinstallation : mode Off, OK, redémarrer Delphi. Sinon `dpcc.CodeInsight` reste
  le fournisseur choisi et les réglages de dpcc restent en place.
- En outre, dpcc enregistre son propre gestionnaire Code Insight et la liaison de touches « dpcc Code Completion »
  pour Ctrl+Espace et Ctrl+Maj+Espace. Il supprime les deux au déchargement.
