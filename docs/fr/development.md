[Deutsch](../de/development.md) | [English](../en/development.md) | Français

# Développement

[Vue d'ensemble](index.md) › Développement

## Prérequis

- Delphi 13 / RAD Studio 37.0, plateforme Win32.
- DUnitX pour les tests ; il fait partie de RAD Studio.

## Compilation

`dpcc_d13.groupproj` contient neuf projets :

1. `Packages\dpcc.Text\dpcc.Text.dproj`
2. `Packages\dpcc.WinBase\dpcc.WinBase.dproj`
3. `Packages\dpcc.Common\dpcc.Common.dproj`
4. `Packages\dpcc.Windows\dpcc.Windows.dproj`
5. `Packages\dpcc.Server\dpcc.Server.dproj` (sources dans `Application\Source\Shell`)
6. `Packages\dpcc.Core\dpcc.Core.dproj`
7. `Packages\dpcc.UI\dpcc.UI.dproj`
8. `Packages\dpcc.IDE.Base\dpcc.IDE.Base.dproj`
9. `Tests\dpcc.Completion.Tests.dproj`

Ouvrir le groupe dans l'IDE, choisir Win32 et Debug, et compiler tous les projets. Les dépendances du groupe fixent
l'ordre.

| Sortie | Dossier |
|---|---|
| BPL | `Output\Win32\Debug\Bpl` |
| DCP | `Output\Win32\Debug\Dcp` |
| DCU | `Output\Win32\Debug\Dcu\<projet>` |
| Programme de test | `Output\Win32\Debug\Bin` |

**Ligne de commande :** le compilateur en ligne de commande (`dcc32`, MSBuild) est bloqué dans les éditions Community
et Starter de Delphi. Avec ces éditions, compiler le groupe dans l'IDE.

Si dpcc est installé dans la même IDE, l'IDE décharge le plugin pendant la compilation. Après la compilation,
redémarrer l'IDE.

Les sorties de compilation n'ont pas leur place dans le dépôt (`.gitignore` : `Output/`, `*.dcu`, `*.bpl`, `*.exe`
…).

## Tests

`Tests\dpcc.Completion.Tests.dproj` est un programme console DUnitX. Après la compilation :

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

| Option | Signification |
|---|---|
| `--exclude:Benchmark` | omet les mesures de la catégorie `Benchmark` |
| `--exitbehavior:Continue` | n'attend pas Entrée à la fin |

- Code de sortie 0 si tous les tests réussissent. Une fuite de mémoire compte comme un échec.
- Sortie sur la console et en XML NUnit.
- Les tests écrivent le journal du fusible de sécurité dans `%TEMP%\dpccCompletionTests\Logs`, pas dans le
  `dpcc.log` de la version installée. Les tests provoquent volontairement des erreurs.
- Avec le symbole `TESTINSIGHT`, le programme s'exécute sous TestInsight au lieu de la console.

| Dossier | Contenu |
|---|---|
| `Tests\Common\Lsp` | côté serveur : complétion, survol, aide aux paramètres |
| `Tests\IDE` | côté plugin sans ToolsAPI : déroulement de la liste, classement, favoris, mode ensemble, espaces réservés, réglages, textes |
| `Tests\Application\Shell` | enveloppe du serveur |
| `Tests\Common` | mémoire : auto-mesure, noms des `.dcp`, cache partagé, bibliothèques de types Office et WinRT, libération après l'arrêt du serveur, documents, tables de noms et de références, signatures dans le cache, format de cache 34, catalogue, chargement à la demande et éviction, statistiques d'utilisation, recherche dans les unités non chargées, unités protégées, réutilisation des tables de références, chargement simultané, ajout au cache |
| `Tests\Memory` | programme de mesure de la mémoire (catégorie `Benchmark`) |
| `Tests\Support` | utilitaires : source de données fixe, surveillance des fuites |

Les tests lient statiquement les DCU des paquets. Les parties utilisant la ToolsAPI (`dpcc.IDE.Base`) ne peuvent être
vérifiées que dans l'IDE.

### Mesurer la mémoire

`dpcc.Memory.Bench.Tests` démarre le serveur dans son propre processus comme le plugin, ouvre un groupe de projets
avec la bibliothèque de l'installation et écrit chaque seconde les octets privés, le pic, le working set et la plus
grande zone libre de l'espace d'adressage dans un fichier CSV. Points de mesure : démarrage, index prêt, après les
requêtes, après chaque reconstruction (`.dproj` enregistré) et après un redémarrage du serveur. Sans la variable
`DPCC_MEMBENCH_OUT`, le test se termine aussitôt. Sur demande, des complétions sur des unités de la bibliothèque prises
au hasard suivent les requêtes et mesurent le chargement à la demande et l'éviction (`DPCC_MEMBENCH_COLD`), une
frappe dans une unité du projet avec des requêtes simultanées mesure les temps de réponse (`DPCC_MEMBENCH_TYPING`), et
de grandes unités dans les `uses` d'une unité du projet, suivies de complétions sur des unités prises au hasard,
comptent le chargement et l'éviction (`DPCC_MEMBENCH_PINNED`).

| Variable | Signification |
|---|---|
| `DPCC_MEMBENCH_OUT` | fichier CSV ; les points de mesure figurent dans `<fichier>-points.csv` |
| `DPCC_MEMBENCH_GROUP` | `.groupproj` dont les projets forment l'espace de travail |
| `DPCC_MEMBENCH_REQUESTS`, `DPCC_MEMBENCH_REBUILDS`, `DPCC_MEMBENCH_RESTARTS`, `DPCC_MEMBENCH_BETWEEN` | requêtes (2000), reconstructions (5), redémarrages (1), requêtes entre deux reconstructions (100) |
| `DPCC_MEMBENCH_COLD`, `DPCC_MEMBENCH_LIBDIR` | nombre de complétions « Unit. » sur des unités de la bibliothèque prises au hasard (0) et dossier de leurs sources (`source` de Delphi 13) |
| `DPCC_MEMBENCH_TYPING` | tours de frappe (0) : quatre frappes chacun, puis la pause de frappe ; pendant ce temps, un second thread envoie des requêtes. Ligne « [typing] » avec médiane, 95e et 99e centile et maximum des temps de réponse, chacun dans `<fichier>-latency.csv` |
| `DPCC_MEMBENCH_PINNED`, `DPCC_MEMBENCH_PINNEDUNITS`, `DPCC_MEMBENCH_PINNEDCOUNT` | complétions sur des unités prises au hasard (0) après qu'une unité du projet a nommé et chargé de grandes unités dans ses `uses` : noms séparés par des virgules ou les plus gros fichiers de la bibliothèque (80). Ligne « [pinned] » avec chargement et éviction |
| `DPCC_CACHE_ROOT` ou `LOCALAPPDATA`, `APPDATA` | dossiers propres pour que le cache de l'utilisateur reste intact ; pour un démarrage à chaud, y placer une copie du cache de la bibliothèque |

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --run:dpcc.Memory.Bench.Tests --exitbehavior:Continue
```

Chaque point de mesure indique aussi la mémoire allouée par le gestionnaire de mémoire (`alloc_mb`) ; l'écart
avec les octets privés correspond à la perte. Les lignes « [lazy] » et les colonnes `loaded` à `largest_load_ms`
indiquent les unités chargées, épinglées, libérables et présentes seulement dans le catalogue, le catalogue, le
chargement à la demande et l'éviction avec leur durée. Les erreurs du serveur (`ERangeError`, `EIntOverflow`,
`EAccessViolation`) sont écrites par le programme de mesure, avec l'adresse de l'erreur et les adresses de retour,
dans `<fichier>-exceptions.txt` ; on les résout avec le fichier `.map` du programme de test.

Comme `bds.exe`, le programme de test est LARGEADDRESSAWARE (4 Go d'espace d'adressage). Les données de mesure
n'ont pas leur place dans le dépôt.

## Conventions

D'après le code existant :

- **Noms d'unités** : `dpcc.<Paquet>.<Domaine>.<Nom>`, par exemple `dpcc.Core.Completion.Controller`. Les unités du
  serveur s'appellent `Shell.*`.
- **Noms** : champs `F…`, paramètres `A…`, variables locales `m…`. Types du plugin `TDpcc…`, interfaces `IDpcc…` ;
  dans `dpcc.Common`, aussi selon le domaine (`TLsp…`, `TIndex…`).
- **Blocs** : `begin`/`end` même pour les instructions isolées.
- **Commentaires** en allemand. Chaque unité commence par un commentaire sur son objet ; les éléments publics portent
  un XMLDoc (`/// <summary>`).
- **Couches** : voir [Architecture](architecture.md#règles-des-couches). Pas de VCL ni de ToolsAPI dans
  `dpcc.Core`, pas de ToolsAPI dans `dpcc.UI`.
- **Points d'entrée depuis l'IDE** : chaque appel venant de l'IDE (timer, notificateur, dessin, touches) passe par
  `TDpccGuard.Run`. Le thread principal n'attend jamais le serveur ; les résultats reviennent via `TDpccMainThread`.
- **Textes** : chaque texte destiné à l'utilisateur figure en allemand et en anglais dans une table
  `cTexts: array[TDpccLanguage, …]`. Dans `dpcc.UI`, chaque fonctionnalité a sa propre unité Strings. Un test vérifie
  toutes les tables : aucun texte vide, mêmes espaces réservés dans les deux langues.
- **Fins de ligne** : CRLF pour `.pas`, `.dpr`, `.dpk`, `.inc`, `.dfm`, `.dproj`, `.groupproj`, `.ps1`
  (`.gitattributes`).

### Ajouter une option

Sur le modèle des options existantes :

1. Champ, valeur par défaut, limites et lecture/écriture dans le record approprié, par exemple
   `dpcc.Core.Settings.Plugin.Completion` (`Defaults`, `Normalize`, `Exchange`), et la propriété dans
   `TDpccPluginSettings` (`dpcc.Core.Settings.Plugin`).
2. Entrée dans le catalogue `dpcc.Core.Settings.PluginSchemaData` avec `x-key`, `x-area` et `x-page`. Le fichier est
   tenu à jour à la main.
3. Visibilité : `dpcc.Core.Settings.CompletionView` affiche entièrement les pages (`x-page`) « Vervollständigung »
   (Completion), « Einfügen » (Insertion) et « Hints ». Des autres pages, il n'affiche que certaines clés :
   l'interrupteur principal `completion.enabled` (zone « General », `cPluginKeys`) et toutes les clés `hints.*`. La
   page ajoute elle-même le bouton « Rebuild index » (reconstruire l'index) dans la zone « General ». Une nouvelle
   option d'une autre page doit figurer dans `cPluginKeys`.
4. Contrôle dans la partie correspondante de la page, par exemple `dpcc.UI.Settings.Page.Completion`, avec
   `BindCheck('<nom-registre>', …)`.
5. Libellé en allemand et en anglais dans `dpcc.UI.Settings.Strings`.
6. Test.

## Contribuer

Le dépôt se trouve à l'adresse <https://github.com/nrodear/DelphiCodeCompletion>. Signaler les erreurs et les
suggestions par une issue, proposer les modifications par une pull request.

Avant une pull request :

- tout le groupe se compile sans erreur ;
- les tests passent au vert (`--exclude:Benchmark`) ;
- les nouveaux textes destinés à l'utilisateur existent en allemand et en anglais ;
- la documentation sous `docs` est adaptée si l'utilisation ou les options changent.

Licence : MIT, voir [LICENSE](../../LICENSE).
