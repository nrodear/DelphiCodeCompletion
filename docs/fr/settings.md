[Deutsch](../de/settings.md) | [English](../en/settings.md) | Français

# Réglages

[Vue d'ensemble](index.md) › Réglages

Les options se trouvent sous **Tools › Options › Third Party › dpcc**. C'est une seule page, sans sous-pages.

L'interface de dpcc n'existe qu'en allemand et en anglais ; une IDE française affiche cette page en anglais. Les
noms d'options sont donc cités ici en anglais, avec une traduction française entre parenthèses.

## La page

- En haut figure l'interrupteur principal, suivi des sections **Completion** (complétion), **When accepting** (lors
  de l'acceptation), **Parameter hint and tooltip** (aide aux paramètres et infobulle) et **Index** (index).
- Si l'interrupteur principal est désactivé, toutes les options situées en dessous et le bouton « Reset history »
  (réinitialiser l'historique) sont grisés. « Rebuild index » (reconstruire l'index) reste utilisable.
- « Show values while debugging » (afficher les valeurs pendant le débogage) est grisé tant que « Own tooltip when
  hovering identifiers » (infobulle propre au survol des identificateurs) est désactivé.

L'enregistrement se fait avec **OK**. Exceptions : « Reset history » et « Rebuild index » agissent immédiatement.

Certaines anciennes options ne figurent plus sur la page et ont une valeur fixe (voir
[Valeurs fixes](#valeurs-fixes)).

La colonne « Valeur de registre » donne le nom sous `HKCU\Software\dpcc\IdePlugin`, la colonne « Clé » le nom que dpcc
utilise dans les remarques et dans `settings.json`. « – » sous « Valeur de registre » : l'option n'est pas enregistrée
dans le registre, mais dans `settings.json` (voir [Stockage](#stockage)).

## Interrupteur principal

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Code Insight by dpcc (off: built-in Code Insight of the IDE) (Code Insight de dpcc ; désactivé : Code Insight intégré de l'IDE) | `Enabled` | `completion.enabled` | activé | Interrupteur principal. Désactivé : dpcc ferme sa liste, son aide aux paramètres et son infobulle ; Ctrl+Espace et Ctrl+Maj+Espace vont à l'IDE. Activé : dpcc démarre la session et le serveur s'ils ne tournent pas. Agit sans redémarrage de l'IDE. Le serveur continue de tourner lors de la désactivation. |

## Completion

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Open on typing from characters (0 = never): (ouvrir lors de la saisie à partir de … caractères ; 0 = jamais) | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 à 10 ; par défaut 0 = désactivé (comme avant l'ouverture pendant la saisie), pour l'activer régler par exemple 5. Lorsqu'on saisit un nom sans point devant, la liste ne s'ouvre que lorsque le mot situé avant le curseur compte ce nombre de caractères ; en dessous, dpcc n'interroge pas le serveur. 0 = la saisie ne l'ouvre jamais. Ctrl+Espace l'ouvre quelle que soit la longueur ; rien ne change après « . » ni pour les autres déclencheurs. Agit aussi lorsque DelphiLSP est le fournisseur choisi. Voir [Utilisation](usage.md#ouverture-pendant-la-saisie). |
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
| Own tooltip when hovering identifiers (infobulle propre au survol des identificateurs) | `HoverTooltip` | `editor.hoverTooltip` | activé | Infobulle de dpcc. Tant qu'elle est activée, dpcc désactive Help Insight de l'IDE. Verrouillé tant que l'interrupteur principal est désactivé. |
| Show values while debugging (turns off the IDE's value tooltip) (afficher les valeurs pendant le débogage ; désactive l'infobulle de valeur de l'IDE) | `DebugHoverValues` | `debug.hoverValues` | activé | En retrait sous l'infobulle. Lorsque le programme est arrêté, la valeur de l'expression figure en haut de l'infobulle. Qui veut l'infobulle de valeur de l'IDE désactive cette option. Verrouillé tant que « Own tooltip … » est désactivé. |

## Index

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Additional source folders (separated by “;”, including subfolders): (dossiers source supplémentaires, séparés par « ; », sous-dossiers compris) | – | `index.extraSourceFolders` | vide | Dossiers contenant le code source de bibliothèques qui n'existent sinon qu'en `.dcu` (DUnitX, DUnit, FireDAC, composants). Les sous-dossiers comptent aussi (sans `.git`, `__history`, `__recovery`) ; `$(Nom)` et `%Nom%` sont résolus. « + Unit » propose leurs unités ; elles sont chargées à la demande et ont leur propre cache. Enregistré dans `%APPDATA%\dpcc\settings.json` (dans le fichier aussi sous forme de liste), pas dans le registre ; le serveur reconstruit l'index sans redémarrage. Remplace l'ancien interrupteur `index.officeAndWinRt` : les bibliothèques de types Office et WinRT figurent toujours dans le catalogue. Voir [Index et cache](index-cache.md#dossiers-source-supplémentaires). |
| Bouton « Rebuild index » (reconstruire l'index) | – | – | – | Demande confirmation, supprime tous les caches d'index et reconstruit l'index. Ne dépend pas de l'interrupteur principal. Voir [Index et cache](index-cache.md#reconstruire-lindex). |

## Valeurs fixes

Ces options ne figurent plus sur la page. Elles ont une valeur fixe, leur ancienne valeur par défaut :

- **Delay before automatic opening (délai avant l'ouverture automatique, par exemple après « . ») : 150 ms**
  (`OpenDelayMs`, `completion.openDelayMs`). Ne vaut que pour l'ouverture automatique, pas pour Ctrl+Espace. Lorsque
  DelphiLSP est le fournisseur choisi, ne vaut que pour l'ouverture pendant la saisie, que dpcc déclenche lui-même
  (voir [Utilisation](usage.md#interaction-avec-delphilsp)).
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
- **Preview of the selected entry in the editor (aperçu de l'entrée sélectionnée dans l'éditeur) : désactivé**
  (`Preview`, `completion.preview`).
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

## Stockage

| Emplacement | Contenu |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | toutes les options de la page sauf `index.extraSourceFolders`. Interrupteurs et nombres en DWORD (interrupteurs 0/1), choix en texte (`filter`, `all`, `rest`). En plus, les marqueurs pour les réglages de l'IDE (plus bas) et `PathOverrideBackup` de `Tools\IdePath.ps1`. Les anciennes valeurs des options fixes restent en place, mais sans effet. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` (depuis la page) et `hints.xmlDocMaxLines` (réglable uniquement dans le fichier). Le serveur dans le processus de l'IDE lit lui-même le fichier et le surveille. La valeur de registre `XmlDocMaxLines` d'une version antérieure est reprise une fois, tant que le fichier ne contient pas encore la clé ; ensuite, seul `settings.json` compte. Une ancienne valeur `hints.xmlDocExpand` ou `hints.xmlDocFull` reste sans effet. |
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
| Tooltip expression evaluation (infobulle de valeur du débogueur) | `ToolTip Watches` | interrupteur principal, infobulle et « Show values while debugging » activés | uniquement après OK dans la boîte de dialogue des options de dpcc | `IdeTooltipWatchesDisabled <version> <emplacement>` |

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
