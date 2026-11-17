[Deutsch](../de/troubleshooting.md) | [English](../en/troubleshooting.md) | Français

# Dépannage

[Vue d'ensemble](index.md) › Dépannage

## Le plugin ne se charge pas

Cas typique : au démarrage ou lors de l'installation, l'IDE signale qu'un paquet ne peut pas être chargé.

La cause est presque toujours le PATH. `dpcc.IDE.Base370.bpl` a besoin de sept autres BPL, et Windows ne les cherche
que via le PATH.

1. Fermer l'IDE.
2. Appeler `powershell -NoProfile -File Tools\IdePath.ps1` et lire la sortie. La sortie est toujours en allemand ;
   la dernière ligne est le résultat. « … » représente le dossier des BPL, 37.0 est la version BDS de Delphi 13
   (paramètre `-BdsVersion`) :
   - « FEHLT: BPL-Ordner oder BPLs fehlen (…) - erst die Gruppe dpcc_d13 bauen. » (MANQUANT : dossier des BPL ou
     BPL manquants (…) - compiler d'abord le groupe dpcc_d13 ; code de sortie 2) : le groupe n'est pas entièrement
     compilé. La liste au-dessus signale la BPL manquante par « [fehlt] » (manquant). Compiler tous les projets.
   - « FEHLT: … steht nicht in der PATH-Ueberschreibung der IDE 37.0. Abhilfe: -Action Add » (MANQUANT : … ne
     figure pas dans le remplacement de PATH de l'IDE 37.0. Solution : -Action Add ; code de sortie 1) : appeler
     `-Action Add`.
   - « OK: … steht in der PATH-Ueberschreibung der IDE 37.0, alle BPLs vorhanden. » (OK : … figure dans le
     remplacement de PATH de l'IDE 37.0, toutes les BPL sont présentes ; code de sortie 0) : le PATH et les BPL
     sont en ordre.
   - Si la sortie contient plus haut « Hinweis  : n Delphi-Instanz(en) laufen - Aenderungen wirken erst nach einem
     Neustart. » (remarque : n instance(s) de Delphi en cours d'exécution - les modifications ne prennent effet
     qu'après un redémarrage), une IDE tourne encore. La fermer.
3. Redémarrer l'IDE.

Autres causes :

- Le chemin figure dans le PATH de Windows au lieu du remplacement de PATH de l'IDE. Voir
  [Installation](installation.md#définir-le-path-de-lide).
- Une BPL est plus ancienne que les autres, par exemple après une compilation interrompue. `Tools\IdePath.ps1`
  affiche la date de chaque BPL. Recompiler tout le groupe.
- La compilation n'a pas été faite pour Win32. L'IDE ne charge que des paquets Win32.

## dpcc est-il chargé ?

- L'écran de démarrage et la boîte À propos mentionnent « dpcc 0.1.0 ».
- **Tools › Options › Third Party** affiche le nœud **dpcc**.
- Le journal contient « dpcc angemeldet (Code Completion) » (dpcc enregistré).

## Ctrl+Espace affiche la liste de l'IDE au lieu de celle de dpcc

dpcc transmet la touche à l'IDE lorsqu'il ne traite pas le fichier :

| Cause | Solution |
|---|---|
| Le fichier ne se termine pas par `.pas`, `.dpr`, `.dpk` ou `.inc`. | Comportement attendu. |
| L'interrupteur principal est désactivé. | **Tools › Options › Third Party › dpcc › General**, activer « Code Insight by dpcc » (Code Insight de dpcc). |
| Le fusible de sécurité a désactivé la complétion. | La fenêtre Messages le signale (voir plus bas). Redémarrer l'IDE. |
| La liste de dpcc est restée vide, et Ctrl+Espace a été pressé une seconde fois au même endroit. | Comportement attendu, voir [Utilisation](usage.md#liste-de-lide-quand-dpcc-ne-trouve-rien). Après une saisie ou à un autre endroit, Ctrl+Espace interroge de nouveau dpcc. |

## La liste après « . » est différente de celle obtenue avec Ctrl+Espace

C'est le comportement attendu. La liste qui s'ouvre d'elle-même après « . » vient de DelphiLSP. Voir
[Utilisation](usage.md#interaction-avec-delphilsp).

## La liste est vide ou incomplète

- « limited (index is being built) » (limitée, index en cours de construction) : l'index n'est pas encore prêt.
  Attendre.
- Barre d'avertissement « syntax error in line n » (erreur de syntaxe à la ligne n) : il y a une erreur de syntaxe
  avant le curseur. Un clic sur l'indication de ligne soulignée ferme la liste et place le curseur sur l'erreur.
- Une unité manque : si elle ne se trouve dans aucun projet, aucun chemin de recherche et aucun chemin de
  bibliothèque, dpcc ne la connaît pas. Voir [Index et cache](index-cache.md#contenu-de-lindex).
- Une unité manque alors que son fichier se trouve dans le chemin de recherche : chercher « Datei nicht lesbar »
  (fichier illisible) dans `dpcc.log`. L'index ignore un fichier qu'il ne peut ni lire ni analyser.
- L'index semble périmé : **Rebuild index** (reconstruire l'index) sur la page **General**.
- Si dpcc ne trouve rien à un endroit, un second Ctrl+Espace y ouvre la liste de l'IDE (voir
  [Utilisation](usage.md#liste-de-lide-quand-dpcc-ne-trouve-rien)).

## Aucune proposition pour DUnitX

DUnitX, DUnit et FireDAC ne sont livrés avec l'installation qu'en `.dcu`. Sans code source, dpcc connaît leurs types
par les paquets que l'IDE a chargés, et leurs membres seulement lorsqu'un projet cite l'unité dans ses `uses`. Les
constantes et les routines hors des types manquent alors.

- Si le code source est disponible (par exemple un clone de DUnitX), indiquer son dossier dans la page **General** sous
  « Additional source folders » (dossiers source supplémentaires). « + Unit » propose ensuite par exemple
  `TestFixtureAttribute` et `Assert`. Voir [Index et cache](index-cache.md#dossiers-source-supplémentaires).
- Une référence comme `$(DUnitX)` dans un chemin de recherche n'agit que si la variable figure dans les variables
  d'environnement de l'IDE ou du système. Sinon, `dpcc.log` cite le chemin (« … mit unaufgelöstem Verweis übergangen »,
  ignoré avec une référence non résolue).

## Deux infobulles apparaissent

- Help Insight de l'IDE : dpcc le désactive, mais l'IDE ne lit ce réglage qu'au prochain démarrage. Redémarrer
  l'IDE.
- Pendant le débogage, l'infobulle de valeur de l'IDE : dpcc ne la désactive que lorsque la page dpcc est fermée
  avec **OK**. Ouvrir la page une fois, OK, redémarrer l'IDE.
- Qui veut garder l'infobulle de l'IDE désactive « Own tooltip when hovering identifiers » (infobulle propre au
  survol des identificateurs) ou « Values in the hover while debugging » (valeurs dans le survol pendant le
  débogage).

## Help Insight manque après la désinstallation

dpcc ne rend Help Insight et l'infobulle de valeur que tant qu'il est chargé. S'il a été retiré sans désactiver
auparavant l'interrupteur principal, réactiver les deux dans les options Code Insight de l'IDE. Les valeurs de
registre figurent sous [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).

## Messages dans la fenêtre Messages

dpcc écrit les avertissements dans la fenêtre Messages de l'IDE et dans le journal. Il n'affiche de lui-même une
boîte de dialogue que dans un seul cas : le serveur a planté deux fois avec la même cause en moins de 10 minutes, et
dpcc ne le redémarre plus de lui-même (voir [Le serveur a planté](#le-serveur-a-planté)).

| Message | Signification |
|---|---|
| « dpcc: Server crashed repeatedly – The server ended twice with … within 10 minutes. dpcc no longer restarts it on its own … » (dpcc : le serveur a planté à plusieurs reprises – le serveur s'est arrêté deux fois avec … en moins de 10 minutes. dpcc ne le redémarre plus de lui-même …) | Le serveur reste arrêté jusqu'à ce qu'on le redémarre à la main. La question « Restart server? » (redémarrer le serveur ?) apparaît à cet effet. |
| « dpcc: … switched off after 3 errors in 5 minutes (last: …) until the IDE is restarted. » (dpcc : … désactivé après 3 erreurs en 5 minutes (dernière : …) jusqu'au redémarrage de l'IDE) | Le fusible de sécurité a désactivé une fonction. Elle reste désactivée jusqu'au redémarrage de l'IDE. Les erreurs de dpcc n'atteignent jamais l'IDE. |
| « dpcc: source "…" switched off after 3 errors in 5 minutes … » (dpcc : source « … » désactivée après 3 erreurs en 5 minutes …) | Seule cette source de données est désactivée ; les autres continuent de tourner. |
| « dpcc shows the tooltip itself and switched off the IDE's Help Insight … » (dpcc affiche lui-même l'infobulle et a désactivé Help Insight de l'IDE …) | voir « Deux infobulles apparaissent » |

## Le serveur a planté

- Si le serveur s'arrête de façon inattendue, dpcc le redémarre et renvoie les fichiers ouverts.
- S'il s'arrête deux fois avec la même cause en moins de 10 minutes, dpcc ne le redémarre plus de lui-même, afin que
  l'erreur ne se répète pas en boucle. La fenêtre Messages le signale (« Server crashed repeatedly », le serveur a
  planté à plusieurs reprises), et dpcc demande « Restart server? » (redémarrer le serveur ?). Avec **Yes** (oui), il
  redémarre et le comptage repart de zéro. Avec **No** (non), il reste arrêté jusqu'au redémarrage de l'IDE.
- La cause figure dans le journal.

## Journaux

### dpcc.log

| | |
|---|---|
| Emplacement | `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` |
| Fichiers plus anciens | `dpcc.1.log` à `dpcc.4.log` ; au plus 5 fichiers de 1 Mo chacun |
| Contenu | démarrage et déchargement, fournisseur Code Insight choisi, langue, erreurs avec version, fonction, classe d'erreur, message et pile d'appels |
| Jamais inclus | code source de l'éditeur |

Les noms et les chemins sont rendus méconnaissables dans le journal. dpcc n'écrit les noms en clair que si la valeur
DWORD `LogNames` = 1 figure sous `HKCU\Software\dpcc\IdePlugin`. Le journal n'est alors plus anonyme ; le vérifier
avant de le transmettre.

Plusieurs instances de l'IDE partagent le dossier ; un verrou les empêche de se gêner mutuellement.

### Journal de diagnostic

Pour un dépannage précis, dpcc journalise les appels de l'IDE à son gestionnaire Code Insight :

1. Sous `HKCU\Software\dpcc\IdePlugin`, créer la valeur DWORD `Diagnose` = 1.
2. Redémarrer l'IDE.
3. Le journal se trouve à côté de la BPL du plugin : `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log`.

Les chemins et le nom d'utilisateur y sont remplacés. Pour désactiver, supprimer la valeur ou la mettre à 0.

### Journal de diagnostic du serveur

Le serveur écrit un journal anonyme de ses requêtes et de ses constructions d'index dans
`%LOCALAPPDATA%\dpcc\Logs\Diagnose\diag-<date>-<processus>.log`, un fichier par jour et par processus, conservé
7 jours (`diagnostics.log`, `diagnostics.logDays` dans `settings.json`).

Il indique la mémoire du processus de l'IDE dans des lignes « mem » : au début et à la fin de chaque construction de
l'index et au moins toutes les 10 minutes, dès qu'une requête se termine. Exemple :

```
14:02:10.521 mem indexDone private 104 MB peak 127 MB ws 118 MB free 2003 MB index 56 MB units 2027 lib 1481 docs 0 trees 0 0 MB dcp 4 27 kb loaded 703 pinned 701 evictable 2 1 MB cold 1324 catalog 13 MB loads 15 evicted 0 loadms 0.2 max 3.6
```

| Champ | Signification |
|---|---|
| `indexStart`, `indexDone`, `periodic` | occasion : début ou fin d'une construction, ligne régulière |
| `private` | octets privés de tout le processus de l'IDE (mémoire privée engagée) |
| `peak` | valeur la plus haute de `private` depuis le démarrage de l'IDE |
| `ws` | working set (mémoire en RAM ; baisse lors de la pagination, `private` non) |
| `free` | plus grande zone libre contiguë de l'espace d'adressage ; si elle devient petite, « Out of memory » menace malgré la RAM libre |
| `index` | mémoire estimée de l'index de symboles : unités chargées et catalogue |
| `units`, `lib` | unités dans l'index, dont celles de la bibliothèque |
| `docs` | documents ouverts auprès du serveur |
| `trees` | arbres syntaxiques et leur mémoire estimée |
| `dcp` | paquets compilés (`.dcp`) mémorisés et leurs noms en Ko |
| `loaded`, `pinned`, `evictable` | unités avec tous leurs symboles en mémoire ; dont épinglées (jamais libérées) et libérables, avec leur mémoire (limite 32 Mo). Voir [Bibliothèque à la demande](index-cache.md#bibliothèque-à-la-demande) |
| `cold` | unités présentes seulement dans le catalogue |
| `catalog` | mémoire estimée du catalogue de toutes les unités |
| `loads`, `evicted` | unités chargées à la demande et libérées depuis le démarrage du serveur |
| `loadms`, `max` | durée du chargement à la demande en ms : médiane des derniers chargements et maximum |

« run start … mem n MB » et les lignes « index … mem n MB » indiquent eux aussi les octets privés du processus.

## L'IDE consomme beaucoup de mémoire

- Les lignes « mem » du journal de diagnostic du serveur montrent la part de l'index (voir plus haut).
- De la bibliothèque, l'index ne garde en permanence en mémoire que les unités que les projets atteignent ou utilisent
  souvent ; il charge les autres à la demande et les libère ensuite. Voir
  [Index et cache](index-cache.md#bibliothèque-à-la-demande).
- Les bibliothèques de types Office et WinRT ne restent en mémoire qu'avec leur catalogue ; dpcc charge leurs symboles à
  la demande. Voir [Index et cache](index-cache.md#bibliothèques-de-types-office-et-winrt).
- Seuls les 16 fichiers utilisés le plus récemment gardent leur arbre syntaxique dans le serveur ; pour les plus
  anciens, il le reconstruit au prochain accès. Quand l'IDE ferme un fichier, dpcc le libère dans le serveur.
- Un fichier hors du groupe de projets reçoit son propre espace de travail. Celui-ci disparaît quand le dernier de ses
  fichiers est fermé.
- Quand le serveur s'arrête (interrupteur principal désactivé, redémarrage), dpcc libère tout l'index. Si des requêtes
  sont encore en cours et ne se terminent pas à temps, la libération suit dès qu'elles sont terminées.

## Réglages par défaut

- Une option : clic droit, « Reset to default » (rétablir la valeur par défaut).
- Une zone : clic droit, « Reset the whole page to default » (rétablir toute la page par défaut).
- Tout : voir [Réglages](settings.md#stockage).
