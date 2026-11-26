[Deutsch](../de/troubleshooting.md) | [English](../en/troubleshooting.md) | Français

# Dépannage

[Vue d'ensemble](index.md) › Dépannage

## Le plugin ne se charge pas

Cas typique : au démarrage ou lors de l'installation, l'IDE signale qu'un paquet ne peut pas être chargé.

La cause est presque toujours le PATH. `dpcc.Plugin370.bpl` a besoin de sept autres BPL, et Windows ne les cherche
que via le PATH.

1. Fermer l'IDE.
2. Appeler `powershell -NoProfile -File Tools\IdePath.ps1` et lire la sortie. La sortie est toujours en allemand ;
   la dernière ligne est le résultat. « … » représente le dossier des BPL, 37.0 est la version BDS de Delphi 13
   (paramètre `-BdsVersion` ; pour Delphi 12 `-BdsVersion 23.0`, le message nomme alors le groupe dpcc_d12 et le
   dossier `Output\Win32\D12\…`) :
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
| L'interrupteur principal est désactivé. | **Tools › Options › Third Party › dpcc**, activer « Code Insight by dpcc » (Code Insight de dpcc). |
| Le fusible de sécurité a désactivé la complétion. | La fenêtre Messages le signale (voir plus bas). Redémarrer l'IDE. |
| La liste de dpcc est restée vide, et Ctrl+Espace a été pressé une seconde fois au même endroit. | Comportement attendu, voir [Utilisation](usage.md#liste-de-lide-quand-dpcc-ne-trouve-rien). Après une saisie ou à un autre endroit, Ctrl+Espace interroge de nouveau dpcc. |

## Aucune liste ne s'ouvre après le point

Le plus souvent, « Code completion » (complétion de code) est désactivé dans les options Code Insight de l'IDE (valeur
de registre `Auto Code Completions` = `False`). Alors ni la liste de l'IDE ni celle de dpcc ne s'ouvre après « . ».
Deuxième cause possible : « Auto invoke » (appel automatique) est désactivé (`Auto Invoke` = `False`) ; l'IDE
n'appelle alors pas d'elle-même la complétion après « . ».

- Mode dpcc : dpcc règle lui-même les deux valeurs sur `True` au démarrage de Delphi ; prend effet au prochain
  démarrage.
- Mode IDE (DelphiLSP choisi) : dpcc ne fait que signaler l'écart, dans le journal (« IDE-Einstellungen: 1 Abweichung:
  Auto Code Completions ») et sur la page dpcc dans la section **IDE**. Activer « Code completion » et « Auto invoke »
  dans les options Code Insight de l'IDE.

Emplacements et valeurs attendues pour Delphi 12 et 13 : [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).

## La liste après « . » est différente de celle obtenue avec Ctrl+Espace

Attendu après l'activation de dpcc et jusqu'au redémarrage de Delphi : la liste qui s'ouvre d'elle-même après « . »
vient encore du fournisseur précédent (DelphiLSP). Après le redémarrage, dpcc est le fournisseur. Voir
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
- L'index semble périmé : **Rebuild index** (reconstruire l'index) sur la page **dpcc** (section **Index**).
- Si dpcc ne trouve rien à un endroit, un second Ctrl+Espace y ouvre la liste de l'IDE (voir
  [Utilisation](usage.md#liste-de-lide-quand-dpcc-ne-trouve-rien)).

## Aucune proposition pour DUnitX

DUnitX, DUnit et FireDAC ne sont livrés avec l'installation qu'en `.dcu`. Sans code source, dpcc connaît leurs types
par les paquets que l'IDE a chargés, et leurs membres seulement lorsqu'un projet cite l'unité dans ses `uses`. Les
constantes et les routines hors des types manquent alors.

- Si le code source est disponible (par exemple un clone de DUnitX), indiquer son dossier dans la page **dpcc** sous
  « Additional source folders » (dossiers source supplémentaires). « + Unit » propose ensuite par exemple
  `TestFixtureAttribute` et `Assert`. Voir [Index et cache](index-cache.md#dossiers-source-supplémentaires).
- Une référence comme `$(DUnitX)` dans un chemin de recherche n'agit que si la variable figure dans les variables
  d'environnement de l'IDE ou du système. Sinon, `dpcc.log` cite le chemin (« … mit unaufgelöstem Verweis übergangen »,
  ignoré avec une référence non résolue).

## Ctrl+clic ne saute pas

Ctrl+clic et « Find Declaration » (Alt+↑) vont au fournisseur Code Insight choisi dans les options de l'IDE. dpcc ne
saute que s'il y est choisi (voir [Utilisation](usage.md#quand-dpcc-est-choisi-comme-fournisseur)).

| Cause | Remède |
|---|---|
| La cible se trouve dans une unité sans source (connue seulement par un package). Message « unit X is only available as a package ». | Attendu : pas de saut. Si la source existe, ajouter son dossier sous « Additional source folders » (dossiers source supplémentaires). |
| dpcc ne trouve pas l'unité ou ne peut pas résoudre le nom sans ambiguïté (surcharge ambiguë, `with` avec un type inconnu). Message « unit X not found » ou « "Name" could not be resolved ». | Attendu. Vérifier les chemins de recherche ; voir [La liste est vide ou incomplète](#la-liste-est-vide-ou-incomplète). |
| L'index est encore en construction (« No jump: the index is still being built. Please click again in a moment. », pour les autres raisons l'ajout « The index is still being built. » ; dpcc ne saute alors pas plus tard), dpcc démarre encore ou la réponse a pris plus de 10 secondes (« no answer from dpcc within 10 s »). Après 250 ms, dpcc saute lui-même, mais seulement jusque-là et tant que le curseur reste dans le même identificateur. | Attendre et réessayer. |
| Aucun message dans la fenêtre des messages. | `dpcc.log` consigne chaque saut sans cible sur une ligne `Gehe zu Definition: <issue> nach <n> ms, <fichier> <ligne>:<colonne> (Maus\|Cursor)` (lignes du journal non traduites), y compris les réponses tardives écartées (« Cursor bewegt », « andere Datei aktiv », « neuerer Sprungwunsch », « zu spät »). |
| Ctrl+clic sur une utilisation saute vers la déclaration, mais Ctrl+clic sur la déclaration ne saute pas vers l'implémentation. | Activer « Log the flow (log file) », refaire le saut et envoyer la chaîne (voir [Journal du déroulement](#journal-du-déroulement)) : elle montre le verdict de `OnTarget` et si `definition` a été demandée. |
| Une aide aux paramètres de dpcc avec plusieurs surcharges est ouverte. | Depuis cette version, Ctrl+Alt+↑/↓ y change de surcharge ; Alt+↑ va à l'IDE. |
| L'infobulle de dpcc recouvre le mot. | Maintenir Ctrl enfoncée : la souris et le clic traversent alors l'infobulle jusqu'à l'éditeur. |

### Saut vers un autre package

Si un package en requiert un autre (`requires`), dpcc cherche sa source `<Nom>.dpk` et ajoute les unités de son
`contains` à l'index du projet. Il cherche dans les dossiers de tous les projets signalés du groupe (y compris ceux en
cours de chargement), dans le dossier du projet, dans les chemins de recherche, dans les
[dossiers source supplémentaires](index-cache.md#dossiers-source-supplémentaires) et dans les dossiers voisins du
dossier du projet (`Packages\<Nom>\<Nom>.dpk`, un niveau). L'autre package n'a pas besoin d'être un projet du groupe.
Si un projet package rejoint le groupe plus tard, les packages existants se rechargent. S'il n'existe que le package
compilé (`.dcp`, BPL), il n'y a pas de cible ; si la source est ailleurs, ajouter son dossier sous « Additional source
folders ».

Si dpcc ne trouve pas de cible, le serveur en indique la raison (`dpcc/noTarget`) avant la réponse vide : `noDocument`
(fichier inconnu du serveur), `noIdentifier` (pas d'identificateur à cet endroit), `unresolved` (nom non résolu),
`unitNotFound` (unité de `uses` introuvable), `noSource` (unité disponible seulement comme package sans source),
`inactiveBranch` (branche `$IFDEF` inactive), `other` ; ainsi que si l'index est encore en construction. Le journal de
diagnostic du serveur donne la même raison dans la ligne de la requête (`empty:unitNotFound` …, le nom seulement sous
forme de code `name=h…`), précédée d'une ligne `declaration start` ou `definition start`.

## Deux infobulles apparaissent

- L'IDE ne lit ses réglages qu'au prochain démarrage. dpcc désactive Help Insight, l'infobulle Symbol Insight et,
  pendant le débogage, l'évaluation d'expressions dans l'infobulle dès qu'il est le fournisseur Code Insight.
  Redémarrer Delphi.
- En plus, dpcc masque à l'exécution la fenêtre Help Insight de l'IDE (par exemple « TQRCustomBand Type ») dès
  qu'elle apparaît : toujours avec l'infobulle propre activée, sinon tant que la liste de dpcc est ouverte. Aucun
  redémarrage n'est nécessaire pour cela, y compris sous Delphi 12, où la valeur de registre seule n'agit pas de façon
  fiable. dpcc désactivé, la fenêtre de l'IDE reste. Le journal contient « Help Insight der IDE: Fenster
  THelpInsightWindow verborgen … » au premier masquage et « Help Insight in der Registry (…) » avec les valeurs lues
  au démarrage.
- La page dpcc affiche l'état dans la section **IDE** (« Check now », vérifier maintenant).
- Qui veut garder l'infobulle de l'IDE désactive « Own tooltip when hovering identifiers » (infobulle propre au
  survol des identificateurs) ou « Show values while debugging » (afficher les valeurs pendant le débogage).

## Help Insight manque après la désinstallation

dpcc ne rend le fournisseur et les réglages de l'IDE que tant qu'il est chargé. S'il a été retiré sans désactiver
auparavant l'interrupteur principal et redémarrer Delphi, choisir DelphiLSP dans les options Code Insight de l'IDE et
réactiver Help Insight, l'infobulle Symbol Insight et l'évaluation d'expressions dans l'infobulle. Les valeurs de
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
| « dpcc: dpcc switched the IDE's Code Insight provider to dpcc; takes effect after restarting Delphi. » (dpcc a basculé le fournisseur Code Insight de l'IDE sur dpcc ; prend effet après le redémarrage de Delphi) | Après interrupteur principal activé et OK, une fois par session. Jusqu'au redémarrage, l'IDE appelle le fournisseur précédent. Voir [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide). |
| « dpcc: dpcc switched the IDE's Code Insight provider back to …; takes effect after restarting Delphi … » (dpcc a rétabli le fournisseur Code Insight de l'IDE sur … ; prend effet après le redémarrage de Delphi) | Après interrupteur principal désactivé et OK, une fois par session. |
| « dpcc: The Code Insight provider is no longer dpcc …; dpcc is off … » (le fournisseur Code Insight n'est plus dpcc … ; dpcc est désactivé …) | Au démarrage : dpcc s'était inscrit comme fournisseur, mais l'IDE a démarré avec un autre (modifié dans les options de l'IDE ou réécrit par l'IDE). Pour activer dpcc, réactiver l'interrupteur principal. |
| « dpcc is selected as the Code Insight provider for Delphi in the IDE options … » (dpcc est choisi comme fournisseur Code Insight pour Delphi dans les options de l'IDE …) | Une fois par session si dpcc est le fournisseur choisi : Ctrl+clic passe par dpcc, Error Insight et les autres services de DelphiLSP manquent. Voir [Utilisation](usage.md#quand-dpcc-est-choisi-comme-fournisseur). |

## Le serveur a planté

- Si le serveur s'arrête de façon inattendue, dpcc le redémarre et renvoie les fichiers ouverts.
- S'il s'arrête deux fois avec la même cause en moins de 10 minutes, dpcc ne le redémarre plus de lui-même, afin que
  l'erreur ne se répète pas en boucle. La fenêtre Messages le signale (« Server crashed repeatedly », le serveur a
  planté à plusieurs reprises), et dpcc demande « Restart server? » (redémarrer le serveur ?). Avec **Yes** (oui), il
  redémarre et le comptage repart de zéro. Avec **No** (non), il reste arrêté jusqu'au redémarrage de l'IDE.
- La cause figure dans le journal.

## L'IDE plante avec un dépassement de pile dans clr.dll

Symptôme : l'IDE se termine sur un dépassement de pile (stack overflow) ; le vidage mémoire montre `clr.dll` et un
thread d'arrière-plan de l'IDE (par exemple Error Insight) qui appelle du code .NET. Dans un cas examiné, la cause était
le réglage de la virgule flottante : l'exception « Invalid » n'était pas masquée dans le mot de contrôle x87, et
`System.Default8087CW` de la RTL partagée valait `$137A` au lieu de `$033F` (valeur par défaut de la RTL Delphi, toutes
les exceptions masquées). Le vidage ne dit pas qui l'a modifié (l'IDE, un expert, un package).

dpcc ne modifie jamais ce réglage. Il se contente de le lire et écrit ces lignes dans `dpcc.log` (les lignes du journal
sont toujours en allemand) :

| Ligne | Signification |
|---|---|
| `Gleitkomma beim Start: Vorgabe $033F (alle maskiert); Hauptthread $033F (alle maskiert); MXCSR Vorgabe $1F80, Hauptthread $1F80` | État à l'inscription de dpcc : valeur par défaut du processus (« Vorgabe ») et mot de contrôle du thread principal (« Hauptthread ») avec les exceptions non masquées (« nicht maskiert: … », ou « alle maskiert » = toutes masquées), plus le réglage SSE (MXCSR) en hexadécimal seulement. |
| `Gleitkomma geändert nach 95 s (Meldung 1 von höchstens 20): Vorgabe $033F (alle maskiert) → $137A (nicht maskiert: Invalid, ZeroDivide); Hauptthread unverändert $033F (alle maskiert)` | Le réglage a changé après l'inscription de dpcc (secondes depuis celle-ci) ; ancienne → nouvelle valeur, séparément pour la valeur par défaut et le thread principal. « Masken gleich » signifie que seules la précision ou l'arrondi diffèrent. |

La vérification suit le rythme du surveillant du thread principal (environ toutes les 50 ms, deux lectures). Une ligne
n'est écrite qu'en cas de changement, au plus 20 par session ; la dernière se termine par « weitere Änderungen werden
nicht mehr gemeldet » (les changements suivants ne sont plus signalés). Si le
[journal du déroulement](#journal-du-déroulement) est activé, la ligne de changement y figure aussi.

Si l'une de ces lignes indique « nicht maskiert: Invalid » :

1. Comparer l'heure de la ligne de changement avec ce qui se passait à ce moment (package chargé, projet ouvert, tests
   lancés).
2. Désactiver à titre d'essai les autres experts et packages de conception (par exemple TestInsight), redémarrer l'IDE
   et relire la ligne de démarrage. Si tout reste à `$033F (alle maskiert)`, le changement vient de l'un de ceux qui
   ont été désactivés.
3. Transmettre les lignes avec le vidage mémoire à l'éditeur de cet expert ou à Embarcadero.

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

### Journal du déroulement

Pour un dépannage précis, dpcc écrit le déroulement de chaque action dans un journal à part (autrefois « journal
de diagnostic ») : pour Ctrl+clic ou « Find Declaration », la complétion, le survol et l'aide aux
paramètres, une ligne par étape, de l'appel de l'IDE jusqu'au résultat. Toutes les lignes d'une action portent le même
identifiant (`#12 Sprung: …`, `#13 Vervollständigung: …` ; les lignes du journal sont en allemand) ; la dernière
ligne d'une chaîne dit où et pourquoi elle s'arrête. Comme avant, le journal contient aussi les autres appels de l'IDE
à son gestionnaire Code Insight.

Pour l'activer :

1. **Tools › Options › Third Party › dpcc**, section **IDE** : cocher « Log the flow (log file) »
   (journaliser le déroulement) et confirmer avec OK. L'effet est immédiat, sans redémarrage. La fenêtre Messages
   (groupe dpcc) nomme le fichier (« dpcc: The flow is logged to … »), l'infobulle de la case aussi.
2. Ou à la main comme avant : sous `HKCU\Software\dpcc\IdePlugin`, créer la valeur DWORD `Diagnose` = 1 et
   redémarrer l'IDE. C'est la même valeur ; la page l'affiche cochée.

| | |
|---|---|
| Emplacement | à côté de la BPL du plugin : `dpcc.IDE.Expert290.log` (Delphi 12) ou `dpcc.IDE.Expert370.log` (Delphi 13), par exemple `Output\Win32\Debug\Bpl\dpcc.IDE.Expert370.log` |
| Fichiers plus anciens | `dpcc.IDE.Expert370.1.log` à `….4.log` ; au plus 5 fichiers de 1 Mo chacun |
| Contenu | une ligne par étape avec l'heure : point d'entrée de l'IDE, chaque sortie anticipée avec sa raison, réponses du serveur, résultat rendu à l'IDE. Fichiers seulement par leur nom, positions en ligne:colonne |
| Jamais contenu | dossiers et nom d'utilisateur (remplacés), code source sauf le seul mot à la position |

Exemple : Ctrl+clic sur le nom d'une méthode dans la classe (ligne 12), saut vers l'implémentation (ligne 40) :

```
10:15:02.114 #7 Sprung: Eintritt IOTACodeInsightManager.GotoDefinition(Index -1), Datei Haupt.pas
10:15:02.115 #7 Sprung: Stelle der IDE keine (nur Index), Strg True, Cursor 12:15 (Editorspalte 15), Maus über Bezeichner 12:16, gefragt 12:16 (Maus)
10:15:02.115 #7 Sprung: Stelle Haupt.pas 12:16 (Maus), Wort „Rechne“
10:15:02.118 #7 Sprung: declaration: Haupt.pas 12:15 nach 3 ms
10:15:02.118 #7 Sprung: OnTarget ja (Datei gleich; Zeile ja, 12 | 12; Stelle im Wort ja, Spalte 16, Ziel ab 15)
10:15:02.121 #7 Sprung: definition: Haupt.pas 40:20
10:15:02.121 #7 Sprung: Antwort der Sitzung nach 6 ms: Haupt.pas 40:20
10:15:02.121 #7 Sprung: Ergebnis an die IDE: True, Haupt.pas Zeile 40; gleich der Ausgangsstelle: nein
```

Si la déclaration ne saute pas, la chaîne montre l'étape où cela bloque : `OnTarget nein (Datei verschieden …)` avec
« definition nicht gefragt » (l'IDE et le serveur écrivent le fichier différemment), `definition: leer`, ou une
`definition` qui renvoie à la déclaration, et à la fin `gleich der Ausgangsstelle: ja (die IDE bleibt in derselben
Zeile)` (l'IDE reste sur la même ligne). Si le serveur a trouvé une paire déclaration/implémentation figure dans le
[journal de diagnostic du serveur](#journal-de-diagnostic-du-serveur), sur la ligne `declaration` ou `definition` de la
même heure : `pair=found pairChosen=implementation` ou `pair=none:<raison>` avec `pairSame` (emplacements de la
routine) et `pairVariant` (parmi eux, ceux dont les types de paramètres correspondent). Raisons : `noUnit` (unité de
la cible absente de l'index), `noSymbol` (routine introuvable), `single` (un seul emplacement, pas de seconde moitié),
`params` (plusieurs emplacements, mais les types de paramètres ne correspondent pas).

Ce qu'il faut envoyer :

1. Activer « Log the flow (log file) » (OK).
2. Exécuter l'action une fois, par exemple Ctrl+clic sur la déclaration.
3. Envoyer les lignes de cet identifiant du journal du déroulement, avec `dpcc.log` et le journal de diagnostic du
   serveur du même jour. Les relire avant de les transmettre : les noms de fichiers et le mot à la position y
   figurent en clair.
4. Désactiver de nouveau la case.

Pour désactiver : décocher et OK (immédiat), ou supprimer la valeur de registre ou la mettre à 0. La mesure des
appels les plus lents au déchargement et les blocages sans action de dpcc (voir plus bas) ne suivent la case qu'au
prochain démarrage de l'IDE.

### Blocages et actions lentes

Un surveillant vérifie toutes les 50 ms si le thread principal de l'IDE répond. Avec les durées des actions de dpcc,
il écrit ces lignes dans `dpcc.log` (le journal lui-même est en allemand) :

| Ligne | Signification |
|---|---|
| `Hauptthread hängt seit 260 ms in Vervollständigung öffnen` | L'IDE ne répond plus depuis 250 ms ou plus pendant que dpcc exécute cette action. Écrite aussitôt, même si l'IDE ne répond plus jamais. |
| `Hauptthread hing 1300 ms in Vervollständigung öffnen` | L'IDE répond de nouveau ; durée totale du blocage. |
| `Hauptthread: Symbolhinweis: 87 ms` | Une action de dpcc a retenu l'IDE 50 ms ou plus, sans blocage. |
| `Hauptthread wartete 340 ms auf Server textDocument/completion: Zeitlimit` | L'IDE a attendu le serveur 100 ms ou plus ; issue : `Antwort` (réponse), `Zeitlimit` (délai dépassé), `abgebrochen` (annulée) ou `Fehler` (erreur). |
| `Hänger mit dpcc-Aktivität in dieser Sitzung: 3, längster 1300 ms, …` | Résumé au déchargement s'il y a eu des blocages. |

Les lignes sont limitées : au plus une ligne par action et par minute (`dazu n weitere …` compte celles omises), au
plus 5 blocages par minute un par un (`… nicht einzeln protokolliert, zusammen n ms`). Si l'IDE bloque sans action de
dpcc (par exemple pendant la compilation), dpcc n'écrit rien. Les dialogues modaux ne comptent pas comme blocages, pas
plus que le temps où l'IDE était arrêtée dans un débogueur.

Avec `Diagnose` = 1 ou « Log the flow (log file) » au démarrage de l'IDE (voir ci-dessus), les blocages sans
action de dpcc figurent aussi dans le journal du déroulement sous `… ohne dpcc-Aktivität`, et au déchargement il liste
les 10 appels, requêtes au serveur et requêtes de complétion les plus lents.

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

- Une option : la remettre à la main à sa valeur par défaut sur la page **dpcc** ; les valeurs par défaut figurent
  dans [Réglages](settings.md).
- Tout : voir [Réglages](settings.md#stockage).
