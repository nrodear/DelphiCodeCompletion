[Deutsch](../de/settings.md) | [English](../en/settings.md) | Français

# Réglages

[Vue d'ensemble](index.md) › Réglages

Les options se trouvent sous **Tools › Options › Third Party › dpcc**. La page porte le titre « Completion, parameter
hint and tooltip by dpcc » (complétion, aide aux paramètres et infobulle de dpcc).

L'interface de dpcc n'existe qu'en allemand et en anglais ; une IDE française affiche cette page en anglais. Les
noms d'options sont donc cités ici en anglais, avec une traduction française entre parenthèses.

## La page

- À gauche, une arborescence avec les zones **General** (général), **Completion** (complétion), **Insertion**
  (insertion) et **Hints** (infobulles).
- Au-dessus de l'arborescence, un champ de recherche « Search settings … » (rechercher un réglage …). Entrée saute au
  premier résultat, la flèche vers le bas passe dans la liste des résultats.
- Si une valeur diffère de la valeur par défaut, un point « ● » précède le libellé. Un clic droit propose « Reset to
  default » (rétablir la valeur par défaut) et « Reset the whole page to default » (rétablir toute la page par défaut).
- En bas, la ligne « Filter: » (filtre) avec « All » (tous), « Changed » (modifiés) et « Experimental only »
  (expérimentaux uniquement). Il n'existe actuellement pas d'options expérimentales sur cette page.
- Si une option dépend d'une autre, elle est verrouillée tant que l'autre est désactivée. La raison est indiquée à
  côté, par exemple « locked: “…” (…) is off » (verrouillé : « … » (…) est désactivé). Toutes les options de la
  complétion et l'infobulle dépendent de l'interrupteur principal.

L'enregistrement se fait avec **OK**. Exceptions : « Reset history » (réinitialiser l'historique), « Remove » (retirer)
et « Remove all » (tout retirer) pour les favoris, ainsi que « Rebuild index » (reconstruire l'index), agissent
immédiatement.

La colonne « Valeur de registre » donne le nom sous `HKCU\Software\dpcc\IdePlugin`, la colonne « Clé » le nom que dpcc
utilise dans les remarques et dans `settings.json`. « – » sous « Valeur de registre » : l'option n'est pas enregistrée
dans le registre, mais dans `settings.json` (voir [Stockage](#stockage)).

## General

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Code Insight by dpcc (off: built-in Code Insight of the IDE) (Code Insight de dpcc ; désactivé : Code Insight intégré de l'IDE) | `Enabled` | `completion.enabled` | activé | Interrupteur principal. Désactivé : dpcc ferme sa liste, son aide aux paramètres et son infobulle ; Ctrl+Espace et Ctrl+Maj+Espace vont à l'IDE. Activé : dpcc démarre la session et le serveur s'ils ne tournent pas. Agit sans redémarrage de l'IDE. Le serveur continue de tourner lors de la désactivation. |
| Bouton « Rebuild index » (reconstruire l'index) | – | – | – | Demande confirmation, supprime tous les caches d'index et reconstruit l'index. Voir [Index et cache](index-cache.md#reconstruire-lindex). |
| Pre-index Office type libraries and WinRT (more memory; “+ Unit” suggests their symbols) (pré-indexer les bibliothèques de types Office et WinRT ; plus de mémoire ; « + Unit » propose leurs symboles) | – | `index.officeAndWinRt` | désactivé | Activé : l'index lit aussi à l'avance les unités sous `$(BDS)\OCX\Servers` (Excel, Word, Outlook, Access, MSHTML) et `$(BDS)\source\rtl\win\winrt` ; « + Unit » propose alors aussi leurs symboles. Cela coûte environ 140 Mo dans l'index. Désactivé : les unités restent accessibles par les `uses` existants ; seul « + Unit » ne les connaît pas. Enregistré dans `settings.json`, pas dans le registre ; le serveur reconstruit l'index sans redémarrage. Voir [Index et cache](index-cache.md#bibliothèques-de-types-office-et-winrt). |

## Completion

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Visible rows of the list: (lignes visibles de la liste) | `VisibleRows` | `completion.visibleRows` | 9 | 5 à 20 lignes. |
| Automatic list width (largeur automatique de la liste) | `ListWidth` | `completion.listWidth` | activé (`ListWidth` = 0) | Activé : la liste s'élargit avec l'entrée la plus large. Désactivé : la dernière largeur tirée (240 à 720). Tirer le bord droit de la liste définit aussi la largeur. |
| Delay before opening (ms): (délai avant ouverture, en ms) | `OpenDelayMs` | `completion.openDelayMs` | 150 | 0 à 2000 ; 0 = immédiatement. Ne vaut que pour l'ouverture automatique, pas pour Ctrl+Espace. Sans effet lorsque DelphiLSP est le fournisseur choisi (voir [Utilisation](usage.md#interaction-avec-delphilsp)). |
| Frequently and recently chosen entries first (entrées choisies fréquemment et récemment en tête) | `Learning` | `completion.learning` | activé | Pondération apprise : les entrées acceptées reçoivent un bonus dans le classement. À partir de 5 acceptations, une entrée est considérée comme « frequent » (fréquente). Enregistré dans `%APPDATA%\dpcc\usage.json`, au plus 5 000 entrées. |
| Pin favorites (Ctrl+D) (épingler les favoris : Ctrl+D) | `Favorites` | `completion.favorites` | activé | Ctrl+D dans la liste ouverte épingle ou détache. Voir [Utilisation](usage.md#favoris). |
| Inherited members ranked lower and grouped by class (membres hérités relégués et groupés par classe) | `GroupInherited` | `completion.groupInherited` | activé | Sans début saisi : membres propres d'abord, puis un groupe « Inherited from … » (hérité de …) par ancêtre. Avec un début, à qualité égale, le membre propre passe avant le membre hérité. |
| Show the branch of variant record fields (afficher la branche des champs de record variants) | `CompletionVariantBranch` | `completion.variantBranch` | activé | Pour les champs de la partie variante d'un record (`case … of`), la marque « branch 0 », « branch 1 », etc. (branche 0, branche 1) est affichée. |
| While typing, show: (pendant la saisie, afficher) | `CompletionListMode` | `completion.listMode` | Only matches | « Only matches » (`filter`, uniquement les résultats), « All entries, matches on top » (`all`, toutes les entrées, résultats en haut), « Matches, then the rest dimmed » (`rest`, résultats, puis le reste atténué, sous l'en-tête « More entries », autres entrées). |
| Applies to: (s'applique à) | `CompletionListScope` | `completion.listMode.scope` | Member lists after “.” | Où le mode de liste s'applique : « Member lists after “.” » (`members`, listes des membres après « . ») ou « All lists » (`everywhere`, toutes les listes). |
| Preview of the selected entry in the editor (aperçu de l'entrée sélectionnée dans l'éditeur) | `Preview` | `completion.preview` | désactivé | La partie manquante du nom sélectionné apparaît en italique et atténuée derrière le curseur. |
| Bouton « Reset history » (réinitialiser l'historique) | – | – | – | Vide immédiatement la pondération apprise. |
| Bouton « Reset widths » (réinitialiser les largeurs) | – | – | – | Ramène la largeur de la liste à la valeur par défaut (automatique) ; enregistré avec OK. |

### Pinned favorites (at most 5 per type)

Sous les options figure la liste des favoris épinglés (« Pinned favorites (at most 5 per type) », favoris épinglés, au
plus 5 par type). Sans favoris, on y lit « No pinned favorites. » (aucun favori épinglé).

| Bouton | Effet |
|---|---|
| Remove (retirer) | détache les favoris sélectionnés, immédiatement |
| Remove all (tout retirer) | détache tous les favoris, immédiatement |

Les favoris se trouvent dans `%APPDATA%\dpcc\favorites.json`.

## Insertion

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Add parentheses when accepting methods (ajouter les parenthèses lors de l'acceptation de méthodes) | `AutoParentheses` | `completion.autoParentheses` | activé | Ajoute les parenthèses ; un « ) » tapé juste devant fait sauter la parenthèse automatique. |
| Fix the case when accepting (showmessage → ShowMessage) (corriger la casse lors de l'acceptation) | `FixCase` | `completion.fixCase` | activé | Remplace le mot saisi par la graphie de la déclaration. |
| Accept with "(", ";" and "." (commit characters) (accepter avec « ( », « ; » et « . », caractères de validation) | `CommitCharacters` | `completion.commitCharacters` | activé | Si l'entrée sélectionnée correspond de façon univoque, l'un de ces caractères l'accepte ; le caractère reste en place. Sinon, seul le caractère reste et la liste se ferme. |
| Add the unit to uses automatically when accepting (ajouter automatiquement l'unité à uses lors de l'acceptation) | `AutoUses` | `completion.autoUses` | activé | Pour les entrées qui affichent à droite « + » et le nom d'une unité (par exemple « + System.SysUtils »), dpcc ajoute cette unité dans `uses`, dans la même étape d'annulation. |
| Parameter hint on "(" and "," (aide aux paramètres sur « ( » et « , ») | `ParameterHints` | `completion.parameterHints` | activé | Désactivé : pas d'aide aux paramètres de dpcc, pas même via Ctrl+Maj+Espace. L'ouverture automatique sur « ( » et « , » n'atteint dpcc que si l'IDE appelle dpcc comme fournisseur (voir [Utilisation](usage.md#interaction-avec-delphilsp)). |
| Match and colour Format placeholders in the parameter hint (associer et colorer les espaces réservés de Format dans l'aide aux paramètres) | `FormatPlaceholders` | `completion.formatPlaceholders` | activé | Ligne indiquant l'espace réservé sous le curseur, avertissements, même couleur pour l'espace réservé et l'argument. Verrouillé tant que « Parameter hint on "(" and "," » est désactivé. |

## Hints

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Own tooltip when hovering identifiers (infobulle propre au survol des identificateurs) | `HoverTooltip` | `editor.hoverTooltip` | activé | Infobulle de dpcc. Tant qu'elle est activée, dpcc désactive Help Insight de l'IDE. Verrouillé tant que l'interrupteur principal est désactivé. |
| Values in the hover while debugging (turns off the IDE's value tooltip) (valeurs dans le survol pendant le débogage ; désactive l'infobulle de valeur de l'IDE) | `DebugHoverValues` | `debug.hoverValues` | activé | Lorsque le programme est arrêté, la valeur de l'expression figure en haut de l'infobulle. Qui veut l'infobulle de valeur de l'IDE désactive cette option. |
| XMLDoc when opened (XMLDoc à l'ouverture) | – | `hints.xmlDocExpand` | as last time | « always collapsed » (`collapsed`, toujours replié), « as last time » (`last`, comme la dernière fois), « always expanded » (`expanded`, toujours déplié). Dans l'état actuel, l'infobulle affiche toujours le XMLDoc en entier ; le choix est enregistré, mais n'a pas d'effet visible. Se trouve dans `settings.json`, pas dans le registre. |
| XMLDoc: max. lines before scrolling (0 = screen) (XMLDoc : nombre maximal de lignes sans défilement, 0 = écran) | – | `hints.xmlDocMaxLines` | 0 | 0 à 50. Au-delà, l'infobulle défile avec la molette de la souris. 0 : seule la place à l'écran limite. Se trouve dans `settings.json`, pas dans le registre. |

## Stockage

| Emplacement | Contenu |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | toutes les options sauf `hints.*`. Interrupteurs et nombres en DWORD (interrupteurs 0/1), choix en texte (`filter`, `members` …). En plus, les marqueurs pour les réglages de l'IDE (plus bas) et `PathOverrideBackup` de `Tools\IdePath.ps1`. |
| `%APPDATA%\dpcc\settings.json` | `hints.xmlDocExpand`, `hints.xmlDocMaxLines`, `index.officeAndWinRt`. Le serveur dans le processus de l'IDE lit lui-même le fichier et le surveille. Les valeurs de registre `XmlDocExpand` et `XmlDocMaxLines` d'une version antérieure sont reprises une fois, tant que le fichier ne contient pas encore les clés ; ensuite, seul `settings.json` compte. |
| `%APPDATA%\dpcc\settings-history.json` | états antérieurs des réglages ; avant chaque modification enregistrée, dpcc y dépose l'ancien état |
| `%APPDATA%\dpcc\usage.json` | historique de la pondération apprise |
| `%APPDATA%\dpcc\favorites.json` | favoris épinglés |

Un fichier `usage.json` ou `favorites.json` inutilisable est déplacé par dpcc à côté, sous le nom `….defekt`, et dpcc
repart de zéro. Un fichier verrouillé n'est pas écrasé.

Tout remettre aux valeurs par défaut : fermer l'IDE et supprimer la clé `HKCU\Software\dpcc\IdePlugin` ainsi que
`settings.json`. Auparavant, désactiver l'interrupteur principal et confirmer avec OK, afin que dpcc rende les
réglages de l'IDE (voir plus bas).

## Ce que dpcc modifie dans l'IDE

Il n'existe pas d'Open Tools API pour Help Insight et l'infobulle de valeur du débogueur. Ces réglages se trouvent
dans le registre de l'IDE et sont lus au démarrage de l'IDE. dpcc les y écrit et note sous
`HKCU\Software\dpcc\IdePlugin` ce qu'il a lui-même désactivé. Il ne réactive que cela.

| Réglage de l'IDE | Valeur de registre de l'IDE | dpcc désactive tant que | dpcc synchronise | Marqueur |
|---|---|---|---|---|
| Help Insight | `Help Insight` | interrupteur principal activé et « Own tooltip … » activé | au chargement du plugin, après chaque modification des réglages et après OK dans la boîte de dialogue des options | `IdeHelpInsightDisabled <version> <emplacement>` |
| Tooltip expression evaluation (infobulle de valeur du débogueur) | `ToolTip Watches` | interrupteur principal, infobulle et « Values in the hover while debugging » activés | uniquement après OK dans la boîte de dialogue des options de dpcc | `IdeTooltipWatchesDisabled <version> <emplacement>` |

- Emplacement des valeurs :
  `HKCU\Software\Embarcadero\BDS\37.0\Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` (Delphi 13),
  plus toute autre sous-clé de `Code Insight` qui porte déjà la valeur.
- L'IDE ne lit les valeurs qu'au prochain démarrage. D'ici là, deux infobulles peuvent apparaître. La fenêtre Messages
  signale chaque modification, par exemple « dpcc shows the tooltip itself and switched off the IDE's Help Insight;
  takes effect after the next start of Delphi. » (dpcc affiche lui-même l'infobulle et a désactivé Help Insight de
  l'IDE ; prend effet au prochain démarrage de Delphi).
- L'infobulle de valeur n'est synchronisée qu'après OK dans la boîte de dialogue des options, parce que l'IDE, à la
  fermeture avec OK, réécrit ses options d'éditeur depuis la mémoire. Après l'installation, elle n'est donc
  désactivée qu'une fois la page dpcc fermée avec OK et l'IDE redémarrée.
- dpcc ne modifie ni Error Insight, ni la mise en évidence de structure, ni le choix du fournisseur Code Insight.
- En outre, dpcc enregistre son propre gestionnaire Code Insight et la liaison de touches « dpcc Code Completion »
  pour Ctrl+Espace et Ctrl+Maj+Espace. Il supprime les deux au déchargement.
