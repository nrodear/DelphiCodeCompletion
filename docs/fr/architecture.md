[Deutsch](../de/architecture.md) | [English](../en/architecture.md) | Français

# Architecture

[Vue d'ensemble](index.md) › Architecture

## Vue d'ensemble

dpcc se compose d'un plugin (paquet de conception) et d'un serveur de complétion. Les deux s'exécutent dans le
processus de l'IDE. Ils communiquent selon le Language Server Protocol (LSP) via JSON-RPC. La liaison est assurée par
deux tubes mémoire ; il n'y a pas de processus serveur distinct.

```
IDE (bds.exe)
 ├─ dpcc.IDE.Base370.bpl   plugin : Open Tools API, touches, éditeur, page d'options
 │    ├─ dpcc.UI.bpl       fenêtres : liste, infobulle, aide aux paramètres, page d'options
 │    └─ dpcc.Core.bpl     logique : client LSP, déroulement, classement, réglages
 │          │  LSP via JSON-RPC, deux tubes mémoire
 │          ▼
 └─ dpcc.Server.bpl        serveur de complétion sur son propre thread
      └─ dpcc.Common.bpl   analyseur, résolution de noms, index, fonctions LSP
```

Le thread principal de l'IDE n'attend jamais le serveur. Une écriture ne fait que déposer un message dans le tube ;
un thread de lecture transmet les réponses au client, et les résultats arrivent dans le thread principal par une file
d'attente dédiée.

## Paquets

| Paquet | `requires` (hors RTL/VCL) | Rôle |
|---|---|---|
| `dpcc.Text` | – | utilitaires de texte sans Windows : lignes, caractères, encodage, comparaison approximative, JSON, URI, version |
| `dpcc.WinBase` | – | utilitaires de processus via l'API Windows |
| `dpcc.Common` | Text | noyau du langage et fonctions du serveur, sans Windows ni VCL |
| `dpcc.Windows` | WinBase, Common | adaptateurs spécifiques à Windows : surveillance de fichiers, chemins, installation de Delphi, sortie de débogage |
| `dpcc.Server` | Text, WinBase, Common, Windows | enveloppe du serveur de complétion ; sources dans `Application\Source\Shell` |
| `dpcc.Core` | Text, WinBase, Common, Windows, Server | logique du plugin, sans VCL ni ToolsAPI |
| `dpcc.UI` | Text, WinBase, Common, Windows, Server, Core ; `vcl` | interface VCL, sans ToolsAPI |
| `dpcc.IDE.Base` | tous les précédents ; `vcl`, `vclwinx`, `designide` | le plugin ; seul paquet de conception, suffixe selon la version (`370`) |
| `dpcc.Completion.Tests` | lie les DCU | programme de test DUnitX |

Tous les paquets sauf `dpcc.IDE.Base` sont des paquets d'exécution (`{$RUNONLY}`). L'ordre dans
`dpcc_d13.groupproj` suit les dépendances.

### Règles des couches

- Les dépendances ne pointent que vers le bas dans le tableau.
- `dpcc.Common` et `dpcc.Text` n'ont besoin ni d'unités Windows ni de la VCL.
- `dpcc.Core` ne connaît ni la VCL ni la ToolsAPI. Ce dont il a besoin de l'IDE, il l'obtient par des interfaces et
  des points d'accroche que `dpcc.IDE.Base` installe.
- `dpcc.UI` connaît la VCL, mais pas la ToolsAPI.
- Seul `dpcc.IDE.Base` communique avec l'IDE.

## dpcc.Common

| Dossier | Contenu |
|---|---|
| `Pascal` | analyseur lexical, analyseur syntaxique, arbre syntaxique, préprocesseur, fichiers d'inclusion, XMLDoc, routines de formatage |
| `Semantics` | résolution de noms : types, surcharges, génériques, class helpers, `with`, visibilité |
| `Index` | index de symboles avec un catalogue de toutes les unités, chargement à la demande et éviction de la bibliothèque, statistiques d'utilisation ; recherche d'unités ; cache sur disque (format 35 : un bloc par unité, répertoire à la fin) ; extracteur avec types cibles, attributs, indications de DLL et contraintes dans les directives ; signature complète depuis la source (`TIndexFiles.SourceSignature`) |
| `Projects` | lecture des `.dproj`, des groupes de projets et des paquets ; recherche d'unités |
| `Dfm` | fichiers de fiche |
| `Lsp` | complétion, survol, aide aux paramètres, synchronisation des documents, cycle de vie |
| `JsonRpc` | messages, transport, répartiteur, pool de workers, watchdog |
| `Configuration` | `settings.json` et `dpcc.json` : lecture, emplacements des clés, valeurs par défaut |
| `Documents`, `Editing` | documents, encodage, fragments de texte comme les modèles postfixes et les noms de champs |

## Serveur (dpcc.Server)

Les sources se trouvent dans `Application\Source\Shell`.

| Unité | Rôle |
|---|---|
| `Shell.Composition.InProcess` | démarre le serveur sur son propre thread dans le processus de l'IDE, connecte les tubes mémoire, le démonte dans un ordre fixe |
| `Shell.Composition.CompletionServer` | racine de composition du serveur : relie protocole, session, documents, index, complétion, survol et aide aux paramètres |
| `Shell.Composition.Configuration` | surveille `settings.json` et `dpcc.json` |
| `Shell.Workspace.*` | espaces de travail : charger les projets, construire l'index, verrouiller et nettoyer le cache |

Le serveur n'a ni diagnostics, ni compilateur, ni refactorisations, ni commandes ; il ne sert qu'à la complétion, au
survol et à l'aide aux paramètres.

Si le serveur se bloque lors du déchargement, `Shell.Composition.InProcess` maintient le code de `dpcc.Server` et de
ses dépendances chargé jusqu'à la fin de l'IDE. Ainsi, aucun thread ne saute dans du code déchargé.

## dpcc.Core

| Dossier | Contenu |
|---|---|
| `Lsp` | client LSP, session (initialize, synchronisation des documents, requêtes), adaptateur vers le serveur dans le processus, gestion des plantages |
| `Completion` | déroulement de la liste (`TDpccCompletionController`), filtrage, classement, favoris, historique, mode ensemble, espaces réservés |
| `Hover`, `Signature`, `Documentation` | contenu de l'infobulle et de l'aide aux paramètres, présentation du XMLDoc |
| `Settings` | réglages du plugin (`TDpccPluginSettings` : exactement les valeurs de la page, plus deux en lecture seule), stockage dans le registre et `settings.json` (`dpcc.Core.Settings.Scopes`), structure de la page d'options et valeurs fixes (`dpcc.Core.Settings.CompletionView`), interrupteur principal sans redémarrage |
| `Diagnostics` | fusible de sécurité (`TDpccGuard`), journal, file d'attente vers le thread principal, démontage |
| `Localization` | langue des textes |

## dpcc.UI

| Dossier | Contenu |
|---|---|
| `Completion` | liste (popup), dessin, textes |
| `Hover` | infobulle |
| `Signature` | aide aux paramètres |
| `Settings` | page d'options « dpcc » |
| `Popup`, `Documentation` | base commune des fenêtres, accessibilité, vue XMLDoc |

## dpcc.IDE.Base

| Dossier | Contenu |
|---|---|
| `Completion` | racine `dpcc.IDE.Completion.Register`, complétion dans l'éditeur (chaîne State → Open → Commit → Editor), espaces réservés, favoris, historique, notificateur d'enregistrement |
| `CodeInsight` | gestionnaire Code Insight (chaîne State → Session → Commands → Crashes → Manager) |
| `Hover` | infobulle dans l'éditeur, valeurs via le débogueur |
| `Signature` | aide aux paramètres dans l'éditeur, couleurs des espaces réservés de Format |
| `Forms` | fiches du concepteur vers le serveur |
| `Projects` | contexte de projet issu de l'IDE |
| `Settings` | enregistrement de la page d'options |
| `Foundation` | réglages dans le registre et `settings.json`, réglages de l'IDE, hook clavier, accès à l'éditeur, écran de démarrage |

## Enregistrement et démontage

`dpcc.IDE.Completion.Register` est la racine de composition. `Register` enregistre successivement : fusible de
sécurité et journal, langue, écran de démarrage, mode de fonctionnement (contexte IDE), gestionnaire Code Insight,
liaison de touches, fiches, notificateur d'enregistrement, interrupteur principal, page d'options. Chaque étape
s'exécute séparément ; une erreur ne coûte que cette étape et figure dans le journal.

Le mode de fonctionnement (dpcc est le fournisseur Code Insight ou désactivé) est décidé par
`dpcc.Core.Settings.IdeCheck` sans le registre (`TDpccIdeContext.Plan` : actions d'écriture et marqueurs,
`TDpccIdeCheck.Evaluate` : vérification) ; la lecture se fait dans `dpcc.IDE.Foundation.IdeSettingsCheck`, l'écriture
dans `dpcc.IDE.Foundation.InsightSwitch` (au démarrage avant le gestionnaire, après OK dans la boîte de dialogue des
options, lors du choix dans la boîte de dialogue Code Insight de l'IDE via `IOTACodeInsightManagerEnvOptions` et à
la fermeture). Voir [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).

`Unregister` démonte dans l'ordre inverse, lui aussi étape par étape. Il s'exécute lors de la destruction de la
fenêtre principale de l'IDE ou lors de la finalisation, selon ce qui arrive en premier. À la fin, la ligne
« dpcc entladen in n ms … » (dpcc déchargé en n ms …) figure dans le journal.

## Déroulement : Ctrl+Espace

1. La liaison de touches `TDpccCompletionKeys` intercepte Ctrl+Espace. Si dpcc ne traite pas le fichier, la touche
   reste à l'IDE.
2. `TDpccCodeInsightManager.OpenCompletion` démarre si nécessaire la session et le serveur.
3. `TDpccEditorCompletion` prend le mot avant le curseur comme début et le rectangle du caret comme ancre.
4. La session envoie le texte courant de l'éditeur (la première fois `didOpen`, ensuite `didChange` avec la zone
   modifiée), puis `textDocument/completion`.
5. Le serveur détermine le contexte, examine les cas de complétion dans un ordre fixe et livre des entrées, en
   plusieurs parties pour les grandes listes.
6. `TDpccCompletionController` filtre et trie localement ; le popup de `dpcc.UI` ne dessine que les lignes visibles.
7. La poursuite de la saisie filtre localement. Pour les listes tronquées, dpcc renvoie une requête en arrière-plan.
8. L'acceptation écrit le nom, l'entrée `uses` et les autres modifications en une seule étape d'annulation.

Le survol et l'aide aux paramètres passent de la même façon par la session (`textDocument/hover`,
`textDocument/signatureHelp`). L'infobulle n'est pas déclenchée par l'IDE, mais par le mouvement de la souris, via
l'API de l'éditeur de code.

Ctrl+clic et « Find Declaration » n'atteignent dpcc que s'il est le fournisseur Code Insight choisi : l'IDE appelle
`GotoDefinition` du gestionnaire, qui interroge `textDocument/declaration` via `TLspSession.GotoTarget` (sur la
déclaration elle-même ensuite `textDocument/definition`) et attend au plus 1 seconde. Sans cible, il répond True avec
un nom de fichier vide, et l'IDE abandonne alors sans message. Les règles se trouvent dans
`dpcc.Core.Editor.Navigation`.

## Robustesse

- **Fusible de sécurité** (`dpcc.Core.Diagnostics.Guard`) : chaque point d'entrée depuis l'IDE passe par
  `TDpccGuard.Run`. Les exceptions ne quittent jamais dpcc en direction de l'IDE. Trois erreurs d'une fonction en
  cinq minutes désactivent uniquement cette fonction jusqu'au redémarrage de l'IDE.
- **File d'attente vers le thread principal** (`dpcc.Core.Diagnostics.MainThread`) : chaque entrée appartient à un
  propriétaire propre ; au déchargement, les entrées en attente sont abandonnées, afin que rien ne s'exécute dans du
  code déchargé.
- **Plantages du serveur** (`dpcc.IDE.CodeInsight.Manager.Crashes`) : redémarrage ; après deux plantages identiques
  en dix minutes, plus de redémarrage automatique.
- **Journal** : rotatif, anonymisé, avec verrou entre plusieurs instances de l'IDE.

## Textes et langue

Les textes se trouvent dans des tables `cTexts: array[TDpccLanguage, …]`, avec l'allemand et l'anglais côte à côte,
et dans `dpcc.UI` dans des unités propres à chaque fonctionnalité (`dpcc.UI.Strings`, `dpcc.UI.Completion.Strings`,
`dpcc.UI.Settings.Strings` …). La couche IDE définit la langue au chargement d'après la langue de l'IDE ; elle est
aussi transmise au serveur. Les identificateurs, les signatures, le XMLDoc et les lignes du journal ne sont jamais
traduits.
