[Deutsch](../de/settings.md) | [English](../en/settings.md) | Français

# Réglages

[Vue d'ensemble](index.md) › Réglages

Les options se trouvent sous **Tools › Options › Third Party › dpcc**. C'est une seule page, sans sous-pages.

L'interface de dpcc n'existe qu'en allemand et en anglais ; une IDE française affiche cette page en anglais. Les
noms d'options sont donc cités ici en anglais, avec une traduction française entre parenthèses.

## La page

- En haut figure l'interrupteur principal, suivi des sections **Completion** (complétion), **When accepting** (lors
  de l'acceptation), **Parameter hint and tooltip** (aide aux paramètres et infobulle), **Index** (index) et **IDE**.
- Si l'interrupteur principal est désactivé, toutes les options situées en dessous et le bouton « Reset history »
  (réinitialiser l'historique) sont grisés. « Rebuild index » (reconstruire l'index) et « Check now » (vérifier
  maintenant) restent utilisables.
- « Show values while debugging » (afficher les valeurs pendant le débogage) est grisé tant que « Own tooltip when
  hovering identifiers » (infobulle propre au survol des identificateurs) est désactivé.

L'enregistrement se fait avec **OK**. Exceptions : « Reset history » et « Rebuild index » agissent immédiatement,
« Check now » ne fait que lire.

Certaines anciennes options ne figurent plus sur la page et ont une valeur fixe (voir
[Valeurs fixes](#valeurs-fixes)).

La colonne « Valeur de registre » donne le nom sous `HKCU\Software\dpcc\IdePlugin`, la colonne « Clé » le nom que dpcc
utilise dans les remarques et dans `settings.json`. « – » sous « Valeur de registre » : l'option n'est pas enregistrée
dans le registre, mais dans `settings.json` (voir [Stockage](#stockage)).

## Interrupteur principal

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Code Insight by dpcc (switches the IDE's Code Insight provider to dpcc; off = DelphiLSP) (Code Insight de dpcc ; bascule le fournisseur Code Insight de l'IDE sur dpcc ; désactivé = DelphiLSP) | `Enabled` | `completion.enabled` | activé | Interrupteur principal et mode de fonctionnement. Activé avec OK : dpcc bascule le fournisseur Code Insight de l'IDE sur dpcc et règle les options de l'IDE dont il a besoin ; désactivé avec OK : retour au fournisseur précédent (par défaut DelphiLSP), ses propres modifications sont annulées. Le changement de fournisseur prend effet après le redémarrage de Delphi. Au démarrage de Delphi, le fournisseur choisi décide : si DelphiLSP est choisi, dpcc se désactive. Voir [Ce que dpcc modifie dans l'IDE](#ce-que-dpcc-modifie-dans-lide). La liste, l'aide aux paramètres et l'infobulle de dpcc suivent l'interrupteur immédiatement (désactivé : Ctrl+Espace et Ctrl+Maj+Espace vont à l'IDE) ; le serveur continue de tourner lors de la désactivation. |

## Completion

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Open on typing from characters (0 = never): (ouvrir lors de la saisie à partir de … caractères ; 0 = jamais) | `AutoMinChars` | `completion.autoMinChars` | 0 | 0 à 10 ; par défaut 0 = désactivé (comme avant l'ouverture pendant la saisie), pour l'activer régler par exemple 5. Lorsqu'on saisit un nom sans point devant, la liste ne s'ouvre que lorsque le mot situé avant le curseur compte ce nombre de caractères ; en dessous, dpcc n'interroge pas le serveur. 0 = la saisie ne l'ouvre jamais. Ctrl+Espace l'ouvre quelle que soit la longueur ; rien ne change après « . » ni pour les autres déclencheurs. Pour que l'IDE n'ouvre pas en plus sa propre liste pendant la saisie, dpcc règle `Auto Invoke Delay` = -1 dans le mode dpcc (voir [plus bas](#ce-que-dpcc-modifie-dans-lide)). Voir [Utilisation](usage.md#ouverture-pendant-la-saisie). |
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
| Own tooltip when hovering identifiers (infobulle propre au survol des identificateurs) | `HoverTooltip` | `editor.hoverTooltip` | activé | Infobulle de dpcc. Tant qu'elle est activée, dpcc désactive, dans le mode dpcc, Help Insight et l'infobulle Symbol Insight de l'IDE (`Help Insight`, `Declaration Information`). Verrouillé tant que l'interrupteur principal est désactivé. |
| Show values while debugging (turns off the IDE's value tooltip) (afficher les valeurs pendant le débogage ; désactive l'infobulle de valeur de l'IDE) | `DebugHoverValues` | `debug.hoverValues` | activé | En retrait sous l'infobulle. Lorsque le programme est arrêté, la valeur de l'expression figure en haut de l'infobulle ; dpcc désactive alors l'évaluation d'expressions dans l'infobulle de l'IDE (`ToolTip Watches`). Qui veut l'infobulle de valeur de l'IDE désactive cette option. Verrouillé tant que « Own tooltip … » est désactivé. |

## Index

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Additional source folders (separated by “;”, including subfolders): (dossiers source supplémentaires, séparés par « ; », sous-dossiers compris) | – | `index.extraSourceFolders` | vide | Dossiers contenant le code source de bibliothèques qui n'existent sinon qu'en `.dcu` (DUnitX, DUnit, FireDAC, composants). Les sous-dossiers comptent aussi (sans `.git`, `__history`, `__recovery`) ; `$(Nom)` et `%Nom%` sont résolus. « + Unit » propose leurs unités ; elles sont chargées à la demande et ont leur propre cache. Enregistré dans `%APPDATA%\dpcc\settings.json` (dans le fichier aussi sous forme de liste), pas dans le registre ; le serveur reconstruit l'index sans redémarrage. Remplace l'ancien interrupteur `index.officeAndWinRt` : les bibliothèques de types Office et WinRT figurent toujours dans le catalogue. Voir [Index et cache](index-cache.md#dossiers-source-supplémentaires). |
| Bouton « Rebuild index » (reconstruire l'index) | – | – | – | Demande confirmation, supprime tous les caches d'index et reconstruit l'index. Ne dépend pas de l'interrupteur principal. Voir [Index et cache](index-cache.md#reconstruire-lindex). |

## IDE

| Option | Valeur de registre | Clé | Par défaut | Effet |
|---|---|---|---|---|
| Bouton « Check now » (vérifier maintenant) | – | – | – | À sa droite, jusqu'à quatre lignes : mode et fournisseur, si un changement attend encore le redémarrage de Delphi, ce que dpcc a réglé dans l'IDE et le résultat de la vérification (par exemple « 1 difference: Auto Code Completions »). Lu à l'ouverture de la page ; le bouton relit. Lit seulement, ne modifie rien ; ne dépend pas de l'interrupteur principal. Voir [Ce que dpcc modifie dans l'IDE](#ce-que-dpcc-modifie-dans-lide). |

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
- OK n'enregistre plus que les valeurs de la page : l'interrupteur principal et onze options dans le registre,
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

## Stockage

| Emplacement | Contenu |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | toutes les options de la page sauf `index.extraSourceFolders`. Interrupteurs et nombres en DWORD (interrupteurs 0/1), choix en texte (`filter`, `all`, `rest`). En plus, les marqueurs pour les réglages de l'IDE (plus bas) et `PathOverrideBackup` de `Tools\IdePath.ps1`. Lu seulement, jamais écrit : l'interrupteur de support `LogNames` (voir [Dépannage](troubleshooting.md)). Les anciennes valeurs des options fixes et des options supprimées restent en place, mais sans effet ; dpcc ne les écrit plus. |
| `%APPDATA%\dpcc\settings.json` | `index.extraSourceFolders` (depuis la page) et `hints.xmlDocMaxLines` (réglable uniquement dans le fichier). Le serveur dans le processus de l'IDE lit lui-même le fichier et le surveille. dpcc lit seulement `hints.xmlDocMaxLines` et n'écrit jamais la clé ; si elle manque dans le fichier, une valeur de registre `XmlDocMaxLines` d'une version antérieure s'applique, sinon 0. dpcc ne touche pas aux autres clés du fichier. Une ancienne valeur `hints.xmlDocExpand` ou `hints.xmlDocFull` reste sans effet. |
| `%APPDATA%\dpcc\settings-history.json` | uniquement issu de versions antérieures : états antérieurs des réglages. dpcc n'écrit ni ne lit plus ce fichier ; il peut être supprimé. |
| `%APPDATA%\dpcc\usage.json` | historique de la pondération apprise |
| `%APPDATA%\dpcc\favorites.json` | favoris épinglés |

Un fichier `usage.json` ou `favorites.json` inutilisable est déplacé par dpcc à côté, sous le nom `….defekt`, et dpcc
repart de zéro. Un fichier verrouillé n'est pas écrasé.

Tout remettre aux valeurs par défaut : fermer l'IDE et supprimer la clé `HKCU\Software\dpcc\IdePlugin` ainsi que
`settings.json`. Auparavant, désactiver l'interrupteur principal, confirmer avec OK et redémarrer Delphi une fois,
afin que dpcc rende le fournisseur et les réglages de l'IDE (voir plus bas).

## Ce que dpcc modifie dans l'IDE

dpcc fonctionne dans l'un de deux modes qui s'excluent. dpcc décide lui-même lequel s'applique au démarrage de Delphi,
d'après le fournisseur Code Insight choisi pour Delphi dans les options de l'IDE (valeur `Insight Manager` sous
`HKCU\<base>\Editor\Source Options\Borland.EditOptions.Pascal`). C'est identique pour Delphi 12
(`<base>` = `Software\Embarcadero\BDS\23.0`) et Delphi 13 (`…\BDS\37.0`).

| Mode | Fournisseur choisi | dpcc | Ce que dpcc modifie dans l'IDE |
|---|---|---|---|
| IDE | DelphiLSP (par défaut) ou un autre fournisseur | désactivé : dpcc désactive son interrupteur principal au démarrage | Il annule ce qu'il a lui-même modifié. Il ne fait que vérifier les valeurs dont DelphiLSP a besoin et écrit le résultat dans le journal. |
| dpcc | dpcc (`dpcc.CodeInsight`) | activé : dpcc active son interrupteur principal au démarrage | Il règle les options du tableau [Réglages dans le mode dpcc](#réglages-dans-le-mode-dpcc). |

Il n'existe pas d'Open Tools API pour ces réglages : ils se trouvent dans le registre de l'IDE et sont lus au
démarrage de l'IDE. dpcc les y lit et les y écrit, indépendamment de la version, via la clé de base de l'IDE en cours.

### Basculer

- **Interrupteur principal activé** et OK : dpcc bascule le fournisseur de l'IDE sur dpcc (`Insight Manager` =
  `dpcc.CodeInsight`) et règle les options. Le fournisseur précédent est mémorisé.
- **Interrupteur principal désactivé** et OK : dpcc rétablit le fournisseur (celui mémorisé, sinon DelphiLSP) et annule
  ses autres modifications.
- **Dans les options de l'IDE** (Code Insight), choisir DelphiLSP ou dpcc : si l'IDE signale ce choix à dpcc,
  l'interrupteur principal suit immédiatement ; sinon le choix s'applique au prochain démarrage.
- L'IDE ne lit le fournisseur et les réglages qu'au démarrage. Après un changement, dpcc signale une fois dans la
  fenêtre Messages « … takes effect after restarting Delphi » (prend effet après le redémarrage de Delphi). D'ici là,
  l'IDE appelle le fournisseur précédent.
- Comme l'IDE réécrit ses options d'éditeur depuis la mémoire avec OK, dpcc n'écrit qu'après la boîte de dialogue,
  vérifie ensuite et écrit encore une fois l'état voulu à la fermeture de Delphi.
- Si le passage à dpcc n'aboutit malgré tout pas (l'IDE a réécrit son choix), dpcc est désactivé au prochain démarrage
  et la fenêtre Messages le signale. Réactiver alors l'interrupteur principal ou choisir dpcc dans les options de
  l'IDE.
- Chaque décision figure sur une ligne du journal, par exemple « IDE-Kontext (Start): Borland.CodeInsight.LSP.Pascal →
  dpcc aus; zurückgedreht: Help Insight » (les lignes du journal sont toujours en allemand).

### Réglages dans le mode dpcc

Identiques pour Delphi 12 et 13. Emplacement, sauf indication contraire :
`HKCU\<base>\Code Insight\Borland.EditOptions.Pascal` (l'ensemble d'options du gestionnaire dpcc).

| Option de l'IDE | Valeur de registre | Attendu | Quand | Raison |
|---|---|---|---|---|
| Fournisseur Code Insight pour Delphi | `Insight Manager` (sous `Editor\Source Options\Borland.EditOptions.Pascal`) | `dpcc.CodeInsight` | toujours | dpcc sert lui-même les fichiers Delphi. |
| Code completion: Auto invoke (complétion de code : appel automatique) | `Auto Code Completions` | `True` | toujours | Désactivé : aucune liste ne s'ouvre après « . ». |
| Code completion: Delay (complétion de code : délai) | `Auto Invoke Delay` | `-1` | toujours | À partir de 0, l'IDE ouvre en plus sa propre liste pendant la saisie. |
| Code parameters: Auto invoke (paramètres : appel automatique) | `Auto Code Parameters` | `True` | toujours | Désactivé : l'aide aux paramètres ne s'ouvre pas d'elle-même sur « ( » et « , ». |
| Tooltip help insight (infobulle Help Insight) | `Help Insight` | `False` | « Own tooltip … » activé | Sinon l'IDE affiche Help Insight à côté de l'infobulle de dpcc. |
| Tooltip symbol insight (infobulle Symbol Insight) | `Declaration Information` | `False` | « Own tooltip … » activé | Sinon l'IDE affiche son infobulle à côté de celle de dpcc. |
| Tooltip expression evaluation (évaluation d'expressions dans l'infobulle) | `ToolTip Watches` | `False` | infobulle et « Show values while debugging » activés | Sinon deux infobulles de valeur pendant le débogage. |
| Ouvrir la complétion avec Parameter Insight | `AutoInvokeCompletionOnParameterInsight` (sous `InsightGlobalOptions`) | `False` | toujours | Sinon l'IDE ouvre en plus sa liste avec l'aide aux paramètres. |

Une valeur manquante s'applique avec la valeur par défaut de l'IDE (options activées, délai -1). Si elle convient
déjà, dpcc n'écrit rien. Les noms d'options sont ceux de l'IDE anglaise, abrégés ; seule la valeur de registre fait
foi.

### Vérification dans le mode IDE

Avec DelphiLSP, dpcc vérifie au démarrage, mais ne modifie rien. Le résultat figure dans le journal et dans la section
[IDE](#ide) de la page.

| Option de l'IDE | Valeur de registre | Attendu | Raison |
|---|---|---|---|
| Code completion: Auto invoke | `Auto Code Completions` | `True` | Désactivé : aucune liste ne s'ouvre après « . » (voir [Dépannage](troubleshooting.md#aucune-liste-ne-souvre-après-le-point)). |
| Code parameters: Auto invoke | `Auto Code Parameters` | `True` | Désactivé : pas d'aide aux paramètres d'elle-même. |
| Error Insight | `Error Insight` | `True` (manquant = activé) | Désactivé : les marques d'erreur de DelphiLSP manquent dans l'éditeur. |

Emplacements des clés selon la version :

| | Delphi 12 (BDS 23.0) | Delphi 13 (BDS 37.0) |
|---|---|---|
| DelphiLSP | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` ; s'il manque, `Code Insight\Borland.EditOptions.Pascal` | `Code Insight\Borland.EditOptions.Borland.CodeInsight.LSP.Pascal` |
| dpcc | `Code Insight\Borland.EditOptions.Pascal` | `Code Insight\Borland.EditOptions.Pascal` |

Sous Delphi 12, la machine de test n'avait que l'emplacement de DelphiLSP (plus HTML et StyleSheet), pas de
`Borland.EditOptions.Pascal` ; dpcc le crée au besoin dans le mode dpcc. Si la clé vérifiée manque entièrement, le
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
- Avant la désinstallation : interrupteur principal désactivé, OK, redémarrer Delphi. Sinon `dpcc.CodeInsight` reste
  le fournisseur choisi et les réglages de dpcc restent en place.
- En outre, dpcc enregistre son propre gestionnaire Code Insight et la liaison de touches « dpcc Code Completion »
  pour Ctrl+Espace et Ctrl+Maj+Espace. Il supprime les deux au déchargement.
