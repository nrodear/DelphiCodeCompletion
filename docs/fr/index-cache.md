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
- les chemins de bibliothèque et de recherche de l'installation (RTL, VCL, composants), y compris les bibliothèques
  de types Office et WinRT (voir [plus bas](#bibliothèques-de-types-office-et-winrt)) ;
- les dossiers source supplémentaires (voir [plus bas](#dossiers-source-supplémentaires)).

S'y ajoutent :

- la configuration, la plateforme, les symboles conditionnels, les chemins de recherche et les espaces de noms
  d'unités de la configuration active, y compris les modifications non enregistrées. dpcc remplace les macros comme
  `$(BDS)` dans les chemins de la même façon que l'IDE : d'abord les variables d'environnement des options de l'IDE,
  puis les dossiers de l'installation, enfin toutes les variables d'environnement du processus. Un chemin contenant une
  référence que dpcc ne sait pas résoudre est omis et cité dans `dpcc.log` (« … mit unaufgelöstem Verweis
  übergangen », message en allemand).
- le chemin de bibliothèque et le chemin de navigation (Browsing Path) de l'IDE en cours, y compris avec un profil
  propre (`bds -r`). Win64x n'a pas de chemin de navigation propre dans le registre ; c'est alors celui de Win64 qui
  s'applique.
- les types des paquets chargés dans l'IDE, même sans code source. dpcc les communique au serveur au démarrage de
  chaque session. Parmi les paquets de l'installation, seules comptent les unités sans code source (par exemple DUnitX,
  DUnit, FireDAC) ; ce qui existe en `.pas` sous `$(BDS)\source` ou `$(BDS)\OCX` vient du code source. Le serveur ne
  demande les membres de ces types que pour les unités qu'un projet cite dans ses `uses`. dpcc lit les deux par
  petites étapes d'environ 15 ms pour que l'IDE reste réactif, et envoie en arrière-plan ; avec `Diagnose` = 1, les
  lignes `IDE-Typen` et `IDE-Mitglieder` du journal de diagnostic indiquent le nombre d'étapes et la plus longue.
- les unités de `uses X in 'chemin'` du `.dpr`, même sans entrée dans le `.dproj`. Comme le compilateur, dpcc cherche
  les `uses` d'une unité d'abord dans son propre dossier.
- Un fichier hors du groupe de projets reçoit le projet de son dossier ou d'un dossier parent. S'il y a plusieurs
  `.dproj`, c'est celui qui cite le fichier qui s'applique, sinon le premier dans l'ordre alphabétique. Sans projet, le
  dossier du fichier sert de chemin de recherche ; dpcc charge ses unités à la demande.

L'index contient des déclarations, pas des utilisations. Sa limite de mémoire est fixe (768 Mo).

### Contenu par déclaration

Depuis le format de cache 35, l'index retient davantage pour chaque déclaration :

- Les valeurs des énumérations sans `{$SCOPEDENUMS ON}` figurent dans le catalogue. « + Unit » propose donc aussi
  `fsBold`, `ssShift` ou `rfReplaceAll`. Les valeurs des énumérations anonymes (`set of (a, b)`, `F: (x, y)`) et les
  champs des records anonymes (`F: record … end`) figurent dans l'index avec le nom du type ou du champ comme
  conteneur.
- Le catalogue connaît le nombre de paramètres de type. « + Unit » affiche les types génériques avec des
  marques de réservation (`TList<T>`) et n'insère que le nom. Si un `<` suit le mot, le type générique vient en premier,
  sinon le type du même nom sans paramètres de type (par exemple `TList` de `System.Classes`).
- Une valeur explicite dans une énumération (`A = B + 1`) appartient à sa valeur ; auparavant, `B` comptait comme une
  valeur de plus.
- Dans les unités de la bibliothèque, l'index ne stocke plus les corps de la partie implementation qui répètent une
  déclaration de l'interface. Les indications d'une routine de DLL (`external`, `name`, `index`, `delayed`) et la ligne
  du corps sont stockées avec la déclaration. Les routines qui n'existent que dans la partie implementation restent.
  Les unités du projet ne sont pas concernées.
- Les pointeurs, tableaux, ensembles, `class of`, types procéduraux et intervalles gardent leur type cible
  (`PInteger` → `^Integer`, bornes des tableaux comprises), aussi pour les champs et variables d'un type anonyme. Les
  attributs (`[Weak]`), les sortes `resourcestring`, `threadvar`, `class operator` et `destructor`, le message après
  `message` et les contraintes des paramètres de type figurent également dans l'index.
- Les signatures des routines, méthodes et constructeurs sont stockées jusqu'à 1000 caractères, toutes les autres
  jusqu'à 300 caractères. dpcc lit la longueur complète dans le fichier source au besoin, de même que la déclaration
  d'une branche qui ne s'applique pas (affichage des détails de la liste).
- Compilation conditionnelle : dpcc évalue dans `{$IF}` les constantes de la même unité comme
  `GenericSafeArrays = False`, `Declared()` connaît les types intégrés (`AnsiChar`, `Integer` …) et la bibliothèque
  lit `{$IFOPT}` avec les valeurs par défaut du compilateur. Auparavant, les deux branches s'appliquaient dans ces cas.
  Une déclaration du même nom dans une branche qui ne s'applique pas (`{$IFDEF WIN64} function F(…)` … `{$ELSE}` …)
  apparaît comme non disponible, même si la branche qui s'applique porte le même nom ; `A, B: T` dans une section
  `var` donne les deux noms.
- `.dpk` : `contains` compte comme `uses`, `requires` reste à part.
- L'index ne stocke plus le résumé XMLDoc. Le survol et la liste lisent la documentation dans le fichier source,
  comme auparavant.

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

Limite : les actions qui cherchent un nom dans toutes les unités (par exemple lors de la création de méthodes d'accès ou
pour les noms de champs des modules de données) trouvent les symboles de premier niveau de toutes les unités et chargent
ces unités pour cela. Une telle recherche reprend aussitôt les résultats de chaque unité rechargée ; la limite de 32 Mo
continue de s'appliquer pendant ce temps, y compris pour les autres requêtes. Elle voit ainsi tous les résultats sans
garder en mémoire en même temps toutes les unités d'un nom fréquent (par exemple `Register`). Elles ne trouvent les
membres des classes et des records que dans les unités chargées.

Les déclarations issues de fichiers d'inclusion (`{$I …}`) d'une unité qui ne figure que dans le catalogue sont
trouvées grâce à une table fichier d'inclusion → unité : l'en-tête de chaque unité énumère ses fichiers
d'inclusion, y compris pour les unités qui ne figurent que dans le catalogue (ils sont enregistrés dans le répertoire
du cache). Le survol, l'aide aux paramètres et les détails de la complétion chargent ainsi l'unité qui l'inclut ;
pour les [unités de même nom](#unités-de-même-nom), le fichier qui inclut le fichier d'inclusion. La table ne contient
qu'une entrée par fichier d'inclusion et ne modifie pas le format du cache (toujours le format 35).

Après `raise`, `on E: ` et entre crochets d'attribut, la complétion vérifie les classes des unités qui ne figurent
que dans le catalogue au moyen des ancêtres du catalogue et ne charge pas ces unités pour cela. Les classes des
packages de l'IDE sans code source s'y ajoutent par leur ancêtre, tel que l'IDE l'indique.

#### Préchargement à l'ouverture

Quand un fichier devient actif dans l'éditeur (ouverture, changement d'onglet, saut) et le reste environ 0,4 s, le
plugin le synchronise en arrière-plan avec le serveur et demande son préchargement (`dpcc/prewarm`) ; parcourir
rapidement les onglets ne déclenche rien, et chaque fichier n'est préchargé qu'une fois par état. Le serveur place
alors, dans un thread à faible priorité, l'arbre syntaxique du fichier dans le cache des requêtes et charge les unités
de ses `uses` (plus System) comme le ferait la première requête : depuis le catalogue ou par les chemins de recherche.
Le premier Ctrl+clic, la première infobulle ou la première liste de complétion après l'ouverture n'ont ainsi plus rien
à charger. Une seule tâche tourne à la fois ; un autre fichier l'interrompt avant l'unité suivante. Les unités froides
ne sont chargées que tant que les unités chargées à la demande restent sous les trois quarts de la limite de 32 Mo ;
le préchargement n'épingle rien et n'évince aucune unité utilisée. Pendant la construction de l'index, il attend la
fin de celle-ci. Le journal de diagnostic du serveur indique une ligne par tâche : `prewarm doc#n units … catalog …
parsed … missing … ms … cancelled …`.

#### Statistiques d'utilisation

Pour chaque unité de la bibliothèque, dpcc compte combien de fois des requêtes en ont besoin et combien de fois une
unité du projet l'ajoute à ses `uses`, par exemple par « + Unit ». Les points sont divisés par deux chaque semaine. La
construction suivante charge aussitôt les unités souvent utilisées, et dpcc ne les libère pas. Les statistiques se
trouvent dans `usage.dat` à côté du cache de la bibliothèque (voir [Cache](#cache)). Le serveur les écrit à son arrêt et
au plus toutes les 10 minutes, et seulement si elles ont changé ; deux écritures n'ont jamais lieu en même temps. Si
elles sont perdues, elles repartent de zéro ; l'index ne s'en aperçoit pas.

### Bibliothèques de types Office et WinRT

`$(BDS)\OCX\Servers` (bibliothèques de types d'Excel, Word, Outlook et Access) et `$(BDS)\source\rtl\win\winrt`
font partie de la bibliothèque comme toute autre unité de l'installation : elles figurent dans le cache de la
bibliothèque et dans le catalogue, et « + Unit » propose leurs symboles. Seul leur catalogue reste en mémoire ; dpcc
charge les symboles d'une unité lorsque la complétion, le survol ou l'aide aux paramètres en ont besoin.

- Si une unité hors de l'installation les cite dans ses `uses`, elles restent chargées. Elles n'entrent pas par les
  `uses` d'autres unités de l'installation.
- L'ancien interrupteur « Pre-index Office type libraries and WinRT » (`index.officeAndWinRt`) n'existe plus. Une valeur
  dans `settings.json` est sans effet et ne produit aucun message.
- Le premier démarrage après la mise à jour lit ces unités une fois. Le cache de la bibliothèque grandit d'environ
  41 Mo, le catalogue en mémoire d'environ 7 Mo. dpcc supprime l'ancien cache de bibliothèque
  sans elles après `index.cacheMaxAgeDays` jours sans utilisation.

### Dossiers source supplémentaires

Les unités que l'installation ne livre qu'en `.dcu` (DUnitX, DUnit, FireDAC …) ne sont connues de dpcc, par l'IDE,
qu'avec leurs types (voir [plus haut](#contenu-de-lindex)). Si leur code source se trouve sur le disque, indiquez son
dossier dans la page **dpcc** sous « Additional source folders » (dossiers source supplémentaires,
`index.extraSourceFolders` dans `settings.json`, voir [Réglages](settings.md#index)) :

- plusieurs dossiers séparés par `;`, dans `settings.json` aussi sous forme de liste ;
- les sous-dossiers comptent aussi, sauf `.git`, `__history` et `__recovery` ; au plus 2000 dossiers ; `index.exclude`
  s'applique ;
- `$(Nom)` (variables de l'IDE et de l'environnement) et `%Nom%` (environnement) sont résolus ; un chemin relatif part du
  dossier du projet ;
- leurs unités entrent dans l'index comme la bibliothèque : dans le catalogue (« + Unit »), chargées à la demande, lues
  avec les symboles de la plateforme et de la version, pas ceux du projet. Elles ont leur propre cache (voir
  [Cache](#cache)) ; un autre dossier ne relit donc pas toute la bibliothèque.

Exemple : les sources de DUnitX, `…\DUnitX\Source`. Cela fait 64 unités avec environ 2600 symboles ; la première
construction les lit en moins d'une seconde, leur cache fait 0,3 Mo, le catalogue grandit d'environ 0,1 Mo.

### Unités de même nom

Si une unité existe plusieurs fois, par exemple une copie adaptée d'une unité de la bibliothèque dans le projet ou
`Unit1` dans deux projets du groupe, l'index conserve tous les fichiers. Celui qui s'applique dépend du projet du
fichier dans lequel on travaille, dans l'ordre du compilateur : unités du projet, dossier du projet, chemins de
recherche, bibliothèque, dossiers source supplémentaires. Sans projet, l'ordre est : projet avant chemin de recherche
avant bibliothèque avant dossiers supplémentaires. Les espaces de noms d'unités (`DCC_Namespace`) s'appliquent eux
aussi par projet.

## Quand l'index est créé

- Dans le mode Plugin, le serveur démarre à la première requête, par exemple Ctrl+Espace, ou au passage au mode
  Plugin. Dans le mode Server, `dpcc.LspServer.exe` construit son propre index (voir
  [Serveur LSP](lsp-server.md#stockage)).
- Il construit alors l'index. Cela se fait en arrière-plan ; l'IDE ne l'attend pas.
- Tant que la construction est en cours, la liste affiche « limited (index is being built) » (limitée, index en cours
  de construction) et peut être incomplète.
- La première construction peut prendre quelques minutes sur les grosses installations, car elle lit la
  bibliothèque. Ensuite, l'essentiel vient du cache.

## Modifications

- dpcc vérifie les modifications du groupe de projets au plus toutes les deux secondes, les modifications de la
  configuration et des options au plus une fois par seconde. Il ne compare que les projets, le projet actif, la
  configuration et la plate-forme ; il relit les chemins de recherche, les defines et le chemin de bibliothèque quand
  l'un d'eux change, quand un dialogue de l'IDE (par exemple les options du projet) se ferme, et sinon au moins toutes
  les 15 secondes.
- dpcc signale au serveur les fichiers enregistrés.
- Modifications en dehors de l'IDE : dpcc surveille les dossiers des projets (le répertoire de travail Git, sinon le
  dossier du projet). Les modifications collectées partent vers le serveur avec la requête suivante.
- Les dossiers situés en dehors (chemins de recherche dans d'autres dépôts, composants du chemin de bibliothèque,
  dossiers source supplémentaires, `$(BDS)`) sont vérifiés par le serveur lui-même : pendant le travail dans l'éditeur,
  au plus toutes les 10 secondes, dans un thread à part. Il reprend les unités nouvelles, modifiées et supprimées.
- Une nouvelle unité dans un chemin de recherche, un dossier de bibliothèque ou un dossier source supplémentaire entre
  aussitôt dans l'index, et non seulement lorsqu'une unité la cite.
- Avant de charger à la demande une unité de la bibliothèque, dpcc vérifie l'état de son fichier ; s'il diffère du
  cache, il relit le fichier.
- Un fichier est considéré comme modifié si son horodatage diffère, ou si l'horodatage est identique et la taille
  différente.
- Une modification du seul chemin de navigation (Browsing Path) de l'IDE reconstruit l'index.
- Un fichier illisible ou impossible à analyser (par exemple à cause de son encodage) manque dans l'index ; la
  construction continue. `dpcc.log` le cite avec chemin et erreur (« Datei nicht lesbar, im Index übergangen »), le
  journal de diagnostic le compte (« index project#n unreadable »). Si la mémoire est épuisée, la construction ne lit
  plus de fichiers et garde ce qu'elle a.
- Les fiches ouvertes partent vers le serveur avec leur état courant dans le concepteur, pas depuis le disque.

## Cache

Le cache se trouve sous `%LOCALAPPDATA%\dpcc\Index` :

| Chemin | Contenu |
|---|---|
| `Index\<version-IDE>\<hash>\index-<format>.dpccidx` | cache d'un projet |
| `Index\<version-IDE>\Bibliothek\<hash>\index-<format>.dpccidx` | cache de la bibliothèque, séparé du projet |
| `…\<cache>.lock` | verrou ; seule la première instance écrit le cache, les suivantes ne font que le lire |
| `Index\<version-IDE>\Zusatzordner\<hash>\index-<format>.dpccidx` | cache des dossiers source supplémentaires, par plateforme, version et dossiers |
| `Index\<version de l'IDE>\Bibliothek\<hash>\usage.dat` | statistiques d'utilisation de la bibliothèque (voir [plus haut](#statistiques-dutilisation)) |
| `…\projekt.txt` | fichier de projet auquel appartient le cache |
| `…\benutzt.stamp` | date et heure de la dernière utilisation |

La version du format figure dans le nom du fichier. Ainsi, différentes versions de dpcc ne se gênent pas
mutuellement.

Depuis le format 34, chaque unité se trouve dans un bloc qui lui est propre, avec sa propre somme de contrôle. Un
répertoire à la fin du fichier énumère toutes les unités avec leur catalogue. Au démarrage, dpcc ne lit que le
répertoire et les blocs des unités qu'il charge, par un handle ouvert ; une autre instance peut malgré tout remplacer
le fichier. Un bloc endommagé ne concerne que son unité ; dpcc la relit alors depuis le fichier source. Le format
actuel 35 apporte le contenu décrit sous [Contenu par déclaration](#contenu-par-déclaration). Le répertoire énumère
aussi les fichiers d'inclusion de chaque unité ; au démarrage, la table fichier d'inclusion → unité en est
construite (voir [Bibliothèque à la demande](#bibliothèque-à-la-demande)).

dpcc ne lit plus les caches des formats plus anciens (par exemple `index-34.dpccidx`) : le premier démarrage après la
mise à jour reconstruit l'index une fois. Dès que dpcc a écrit un cache dans le nouveau format, il supprime dans le même
dossier les fichiers `index-<numéro>.dpccidx` des formats plus anciens avec leur fichier `.lock`, sauf si une autre
instance les verrouille (par exemple une version plus ancienne de dpcc dans un second IDE). Les autres fichiers
restent. « Reconstruire l'index » (voir [plus bas](#reconstruire-lindex)) supprime aussitôt tous les caches.

Lors de la première construction sans cache, dpcc écrit le cache de la bibliothèque en cours de route, afin que les
unités nouvellement lues puissent quitter la mémoire. Il ajoute seulement les nouveaux blocs et un nouveau répertoire à
la fin du fichier, et uniquement au fichier qu'il a lui-même écrit en dernier (même horodatage, même taille, même
en-tête) ; sinon, il écrit le fichier entier. Il n'écrit le cache du projet en cours de route que si des unités de la
bibliothèque situées hors de l'installation se sont ajoutées (par exemple des sources de tiers ; elles se trouvent dans
le cache du projet), sinon seulement à la fin de la construction. Chaque ajout laisse le répertoire précédent comme
espace inutilisé dans le fichier ; si cet espace dépasse 4 Mo ou 10 % du fichier à la fin d'une construction, dpcc
réécrit le fichier entier. Si l'ajout est interrompu, l'état précédent reste valable, et celui qui lit le fichier
continue de lire ses blocs inchangés. Pour ces états intermédiaires, les lignes « cacheWrite library » du journal de
diagnostic n'indiquent que les Ko ajoutés.

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

**Tools › Options › Third Party › dpcc › Rebuild index** (reconstruire l'index) :

1. dpcc demande confirmation : « Delete all index caches and rebuild the index? The first build can take a few
   minutes. » (supprimer tous les caches d'index et reconstruire l'index ? La première construction peut prendre
   quelques minutes.)
2. Il arrête une session en cours, supprime tous les caches d'index qui ne sont pas verrouillés et redémarre la
   session. Cela se fait en arrière-plan ; l'IDE reste utilisable. Pendant ce temps, le bouton est grisé et affiche à
   côté « Rebuilding index: stopping the session, deleting caches … » (reconstruction de l'index : arrêt de la
   session, suppression des caches …). On peut fermer les options entre-temps ; à la prochaine ouverture, la page
   affiche l'état actuel.
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
plus d'effet ; le périmètre est fixe. Il en va de même pour `index.officeAndWinRt` : les bibliothèques de types
Office et WinRT figurent toujours dans le catalogue (voir [plus haut](#bibliothèques-de-types-office-et-winrt)).
`index.extraSourceFolders` agit (voir [plus haut](#dossiers-source-supplémentaires)).
