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
- les chemins de bibliothèque et de recherche de l'installation (RTL, VCL, composants).

S'y ajoutent :

- la configuration, la plateforme, les symboles conditionnels, les chemins de recherche et les espaces de noms
  d'unités de la configuration active, y compris les modifications non enregistrées. dpcc remplace les macros comme
  `$(BDS)` dans les chemins de la même façon que l'IDE.
- les types des paquets chargés dans l'IDE, même sans code source. dpcc les communique au serveur au démarrage de
  chaque session.

L'index contient des déclarations, pas des utilisations. Sa limite de mémoire est fixe (768 Mo).

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
| `…\projekt.txt` | fichier de projet auquel appartient le cache |
| `…\benutzt.stamp` | date et heure de la dernière utilisation |

La version du format figure dans le nom du fichier. Ainsi, différentes versions de dpcc ne se gênent pas
mutuellement.

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
plus d'effet ; le périmètre est fixe.
