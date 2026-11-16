[Deutsch](../de/index-cache.md) | [English](../en/index-cache.md) | Français

# Index et cache

[Vue d'ensemble](index.md) › Index et cache

La complétion, le survol, l'aide aux paramètres et l'affichage « + » avec le nom d'une unité manquante (par exemple
« + System.SysUtils ») lisent dans un index de symboles. C'est le serveur de dpcc qui le construit, dans le processus
de l'IDE. Il est indépendant de l'index de DelphiLSP.

## Contenu de l'index

Le périmètre est fixe :

- tous les projets du groupe de projets ouvert, le projet actif en premier ;
- toutes les unités des chemins de recherche des projets ;
- les chemins de bibliothèque et de recherche de l'installation (RTL, VCL, composants), sans les bibliothèques de types
  Office et WinRT (voir [plus bas](#bibliothèques-de-types-office-et-winrt)).

S'y ajoutent :

- la configuration, la plateforme, les symboles conditionnels, les chemins de recherche et les espaces de noms
  d'unités de la configuration active, y compris les modifications non enregistrées. dpcc remplace les macros comme
  `$(BDS)` dans les chemins de la même façon que l'IDE.
- les types des paquets chargés dans l'IDE, même sans code source. dpcc les communique au serveur au démarrage de
  chaque session.

L'index contient des déclarations, pas des utilisations. Sa limite de mémoire est fixe (768 Mo).

### Bibliothèque à la demande

De la bibliothèque, l'index ne garde en mémoire qu'une partie avec tous ses symboles. Sont toujours chargées
(épinglées) :

- les unités des projets et de leurs chemins de recherche ;
- les unités que les projets atteignent par les `uses` (interface et implementation des unités du projet, puis de
  proche en proche par les `uses` de l'interface) ;
- les unités qu'une unité du projet nomme dans ses `uses`, y compris celles que l'on vient de taper dans un fichier
  ouvert ;
- les unités de la bibliothèque souvent utilisées (voir [Statistiques d'utilisation](#statistiques-dutilisation)).

De toutes les autres unités, l'index connaît un catalogue : nom, fichier, `uses`, les premiers types et tous les
symboles qu'une autre unité peut importer. Grâce à lui, « + Unit », les symboles homonymes d'autres unités, la
complétion dans la section `uses` et la recherche de class helpers couvrent toujours toutes les unités. dpcc ne lit les
symboles complets d'une telle unité, depuis son bloc dans le cache, que lorsque la complétion, le survol, l'aide aux
paramètres ou l'accès à la définition en ont besoin. Cela prend en général moins de 5 ms, jusqu'à environ 150 ms pour
les très grandes unités.

Si les unités ainsi chargées occupent ensemble, selon l'estimation, plus de 32 Mo, dpcc libère la moins souvent utilisée, à égalité celle
qui n'a pas servi depuis le plus longtemps. Il libère toujours l'unité entière ; son entrée de catalogue reste. La
limite est fixe et n'est pas un réglage. Les unités nommées dans les `uses` d'une unité du projet et les unités souvent
utilisées ne comptent pas ; elles sont épinglées (voir plus haut).

Limite : les actions qui cherchent un nom dans toutes les unités (par exemple lors de la création de méthodes d'accès
ou pour les noms de champs des modules de données) trouvent les symboles de premier niveau de toutes les unités et
chargent ces unités pour cela. Tant qu'une telle recherche charge des unités, dpcc n'en libère aucune, afin qu'elle
voie tous les résultats ; ensuite, la limite s'applique de nouveau. Elles ne trouvent les membres des classes et des
records que dans les unités chargées.

#### Statistiques d'utilisation

Pour chaque unité de la bibliothèque, dpcc compte combien de fois des requêtes en ont besoin et combien de fois une
unité du projet l'ajoute à ses `uses`, par exemple par « + Unit ». Les points sont divisés par deux chaque semaine. La
construction suivante charge aussitôt les unités souvent utilisées, et dpcc ne les libère pas. Les statistiques se
trouvent dans `usage.dat` à côté du cache de la bibliothèque (voir [Cache](#cache)). Le serveur les écrit à son arrêt
et au plus toutes les 10 minutes. Si elles sont perdues, elles repartent de zéro ; l'index ne s'en aperçoit pas.

### Bibliothèques de types Office et WinRT

dpcc ne lit pas à l'avance `$(BDS)\OCX\Servers` (bibliothèques de types d'Excel, Word, Outlook et Access, plus
MSHTML) ni `$(BDS)\source\rtl\win\winrt`. Ensemble, elles représentent un bon 40 % des symboles de la bibliothèque
et environ 140 Mo dans l'index, et elles servent rarement.

- Les unités restent accessibles par les `uses` : si une unité hors de l'installation les inclut, la construction les lit
  aussitôt. Si seule une unité de l'installation les inclut, dpcc les charge lorsque la complétion, le survol ou l'aide
  aux paramètres en ont besoin.
- « + Unit » ne propose pas leurs symboles.
- L'interrupteur « Pre-index Office type libraries and WinRT » (pré-indexer les bibliothèques de types Office et
  WinRT) de la page **General** (`index.officeAndWinRt` dans `settings.json`) les réintègre. Voir
  [Réglages](settings.md#general).
- Chaque position a son propre cache de bibliothèque. Au premier basculement, dpcc relit une fois la bibliothèque ;
  ensuite, elle vient du cache correspondant. À la désactivation, le serveur retire aussitôt les unités de l'index.

## Quand l'index est créé

- Le serveur démarre à la première requête, par exemple Ctrl+Espace, ou à l'activation de l'interrupteur principal.
- Il construit alors l'index. Cela se fait en arrière-plan ; l'IDE ne l'attend pas.
- Tant que la construction est en cours, la liste affiche « limited (index is being built) » (limitée, index en cours
  de construction) et peut être incomplète.
- La première construction peut prendre quelques minutes sur les grosses installations, car elle lit la
  bibliothèque. Ensuite, l'essentiel vient du cache.

## Modifications

- dpcc vérifie les modifications du groupe de projets au plus toutes les deux secondes, les modifications de la
  configuration et des options au plus une fois par seconde.
- dpcc signale au serveur les fichiers enregistrés.
- Modifications en dehors de l'IDE : dpcc surveille les dossiers des projets (le répertoire de travail Git, sinon le
  dossier du projet). Les modifications collectées partent vers le serveur avec la requête suivante.
- Les fiches ouvertes partent vers le serveur avec leur état courant dans le concepteur, pas depuis le disque.

## Cache

Le cache se trouve sous `%LOCALAPPDATA%\dpcc\Index` :

| Chemin | Contenu |
|---|---|
| `Index\<version-IDE>\<hash>\index-<format>.dpccidx` | cache d'un projet |
| `Index\<version-IDE>\Bibliothek\<hash>\index-<format>.dpccidx` | cache de la bibliothèque, séparé du projet |
| `…\<cache>.lock` | verrou ; seule la première instance écrit le cache, les suivantes ne font que le lire |
| `Index\<version de l'IDE>\Bibliothek\<hash>\usage.dat` | statistiques d'utilisation de la bibliothèque (voir [plus haut](#statistiques-dutilisation)) |
| `…\projekt.txt` | fichier de projet auquel appartient le cache |
| `…\benutzt.stamp` | date et heure de la dernière utilisation |

La version du format figure dans le nom du fichier. Ainsi, différentes versions de dpcc ne se gênent pas
mutuellement.

Depuis le format 34, chaque unité se trouve dans un bloc qui lui est propre, avec sa propre somme de contrôle. Un
répertoire à la fin du fichier énumère toutes les unités avec leur catalogue. Au démarrage, dpcc ne lit que le
répertoire et les blocs des unités qu'il charge, par un handle ouvert ; une autre instance peut malgré tout remplacer
le fichier. Un bloc endommagé ne concerne que son unité ; dpcc la relit alors depuis le fichier source. dpcc ne lit plus
les caches des formats plus anciens (par exemple `index-33.dpccidx`) : le premier démarrage après la mise à jour
reconstruit l'index une fois. L'ancien fichier reste jusqu'à ce que le nettoyage par taille le supprime ;
« Reconstruire l'index » (voir [plus bas](#reconstruire-lindex)) le supprime aussitôt.

Lors de la première construction sans cache, dpcc écrit le cache de la bibliothèque en cours de route, afin que les
unités nouvellement lues puissent quitter la mémoire. Il ajoute seulement les nouveaux blocs et un nouveau répertoire à
la fin du fichier ; il n'écrit le cache du projet et le fichier entier qu'à la fin de la construction. Si l'ajout est
interrompu, l'état précédent reste valable. Pour ces états intermédiaires, les lignes « cacheWrite library » du
journal de diagnostic n'indiquent que les Ko ajoutés.

La variable d'environnement `DPCC_CACHE_ROOT` déplace tout le dossier `%LOCALAPPDATA%\dpcc` du serveur (caches et
journal de diagnostic), par exemple pour des tests avec une copie du cache. Sans elle, c'est `LOCALAPPDATA` de
l'environnement du processus qui s'applique.

Si l'index contient déjà chaque unité du cache de la bibliothèque ou des chemins de recherche dans le même état, une
nouvelle construction ne relit pas le cache (par exemple après l'enregistrement d'un `.dproj`). Le journal de
diagnostic le signale par « index project#n cache skipped library ».

### Nettoyage

Le serveur nettoie lui-même le dossier du cache :

| Règle | Par défaut | Clé dans `settings.json` |
|---|---|---|
| Supprimer les caches des projets supprimés | activé | `index.removeOrphans` (`true`/`false`) |
| Supprimer les caches inutilisés depuis ce nombre de jours | 14 | `index.cacheMaxAgeDays` (0 à 3650 ; 0 = désactivé) |
| Taille maximale du dossier du cache en Mo, les plus anciens d'abord | 1024 | `index.cacheMaxMb` (0 = sans limite) |

Si l'origine d'un cache se trouve sur un lecteur actuellement absent (USB, réseau), le cache est conservé.

## Reconstruire l'index

**Tools › Options › Third Party › dpcc › General › Rebuild index** (reconstruire l'index) :

1. dpcc demande confirmation : « Delete all index caches and rebuild the index? The first build can take a few
   minutes. » (supprimer tous les caches d'index et reconstruire l'index ? La première construction peut prendre
   quelques minutes.)
2. Il arrête une session en cours, supprime tous les caches d'index qui ne sont pas verrouillés et redémarre la
   session.
3. La page signale le résultat :
   - « n index caches deleted; the index is being rebuilt. » (n caches d'index supprimés ; l'index est en cours de
     reconstruction) – la session tournait et a redémarré ;
   - « n index caches deleted; the index is rebuilt the next time code completion starts. » (n caches d'index
     supprimés ; l'index sera reconstruit au prochain démarrage de la complétion de code) – aucune session ne
     tournait ; le bouton ne démarre pas de serveur ;
   - « Index cache could not be deleted: … » (le cache d'index n'a pas pu être supprimé : …) – erreur.

On peut aussi supprimer le cache à la main : fermer l'IDE et supprimer `%LOCALAPPDATA%\dpcc\Index`.

## Exclure des unités de l'index

Dans `dpcc.json` dans le dossier du projet, `index.exclude` exclut des fichiers. Les motifs s'appliquent au chemin
complet : `*` sans séparateur, `**` à travers les dossiers, `?` un caractère, sans distinction entre majuscules et
minuscules.

```json
{
  "index": {
    "exclude": ["**/Demos/**", "**/Generated/*.pas"]
  }
}
```

## Fichiers de réglages du serveur

| Fichier | Emplacement | S'applique à |
|---|---|---|
| `settings.json` | `%APPDATA%\dpcc` | tous les projets (personnel, propre à la machine) |
| `dpcc.json` | dossier du projet | ce projet (pour l'équipe, à placer dans le dépôt) |

Chaque clé a exactement un emplacement. Une clé au mauvais endroit est sans effet. Dans `dpcc.json`, le serveur
ignore les identifiants d'accès et les chemins absolus. Il surveille lui-même les deux fichiers ; les modifications
agissent sans redémarrage.

Le serveur lit encore les clés d'index `index.projectGroup`, `index.searchPaths`, `index.libraryPaths`,
`index.usages` et `memoryBudgetMb`, afin que les fichiers plus anciens se chargent sans avertissement. Elles n'ont
plus d'effet ; le périmètre est fixe. Seule `index.officeAndWinRt` agit (voir
[plus haut](#bibliothèques-de-types-office-et-winrt)).
