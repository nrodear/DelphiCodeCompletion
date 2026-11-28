[Deutsch](../de/usage.md) | [English](../en/usage.md) | Français

# Utilisation

[Vue d'ensemble](index.md) › Utilisation

## Touches dans l'éditeur

| Touche | Effet |
|---|---|
| Ctrl+Espace | ouvrir la complétion de dpcc |
| Ctrl+Maj+Espace | ouvrir l'aide aux paramètres de dpcc |

dpcc attribue ces deux touches au moyen de sa propre liaison de touches (« dpcc Code Completion »). Il ne les prend
que s'il traite le fichier : extension `.pas`, `.dpr`, `.dpk` ou `.inc`, mode Plugin et fonction
non désactivée par le fusible de sécurité (voir [Dépannage](troubleshooting.md)). Sinon, les touches vont à l'IDE.
De même, un second Ctrl+Espace va à l'IDE si la liste de dpcc est restée vide au même endroit, ainsi que tout
Ctrl+Espace tant que la liste de l'IDE est déjà ouverte (voir [plus bas](#liste-de-lide-quand-dpcc-ne-trouve-rien)).

dpcc n'occupe pas d'autres touches de façon permanente. Il ne prend les flèches, Entrée, Tab et Échap que tant
qu'une de ses fenêtres est ouverte et a besoin de la touche.

## Interaction avec DelphiLSP

Delphi 12 et 13 ne transmettent les déclencheurs automatiques (saisie de « . », « ( », « , ») qu'au fournisseur Code
Insight choisi pour Delphi dans les options de l'IDE. La valeur par défaut de l'IDE est DelphiLSP. dpcc et DelphiLSP
ne fonctionnent donc pas côte à côte, mais dans l'un de trois modes de fonctionnement, choisi pour chaque version de
Delphi sous **Tools › Options › Third Party › dpcc** (détails sous [Réglages](settings.md#mode-de-fonctionnement) et
[Ce que dpcc modifie dans l'IDE](settings.md#ce-que-dpcc-modifie-dans-lide)) :

- **Plugin** (par défaut après l'installation) : dpcc est le fournisseur. La liste après « . », l'aide aux paramètres
  sur « ( » et « , », Ctrl+Espace, Ctrl+Maj+Espace et l'infobulle viennent de dpcc. dpcc règle lui-même les options
  de l'IDE dont il a besoin. Ce que dpcc règle figure sur la page dpcc et est masqué dans la boîte de dialogue Code
  Insight de l'IDE ; « Open automatically after the dot » désactive la liste après « . » (voir
  [Code Insight de l'IDE](settings.md#code-insight-de-lide)).
- **Off** : DelphiLSP est le fournisseur, dpcc n'affiche aucune fenêtre. Si DelphiLSP est choisi au démarrage de
  Delphi, Off s'applique, à moins que Server ne soit choisi.
- **Server** : DelphiLSP reste le fournisseur et l'IDE affiche ses propres fenêtres ; les réponses viennent de
  `dpcc.LspServer.exe` au lieu de `DelphiLSP.exe` (voir [Serveur LSP](lsp-server.md#mode-server)). Les fenêtres de
  dpcc n'apparaissent pas, Error Insight reste vide.
- Le passage depuis ou vers Plugin bascule le fournisseur. Cela prend effet après le redémarrage de Delphi ; d'ici là,
  ce qui suit vaut pour l'ancien fournisseur. Entre Off et Server, le changement prend effet à la prochaine ouverture
  d'un groupe de projets.
- La liste qui s'ouvre d'elle-même pendant la saisie d'un nom (seulement si activée, voir
  [Ouverture pendant la saisie](#ouverture-pendant-la-saisie)) vient de dpcc : pour cela, dpcc observe lui-même
  l'éditeur.

Au démarrage, dpcc écrit dans le journal quel fournisseur est choisi (ligne « Code Insight für Delphi-Dateien:
gewählt … », c'est-à-dire Code Insight pour les fichiers Delphi : choisi …).

### Liste de l'IDE quand dpcc ne trouve rien

Si la liste reste vide après Ctrl+Espace, son pied affiche « Press Ctrl+Space again for the IDE list » (Ctrl+Espace
à nouveau pour la liste de l'IDE). Un second Ctrl+Espace au même endroit ouvre alors la liste de l'IDE (DelphiLSP)
au lieu de celle de dpcc. Vide signifie ici : rien trouvé, pas de contexte adapté, une erreur ou le délai d'attente
du serveur.

- Cela ne vaut que si le curseur est toujours au même endroit (fichier, ligne, colonne) et que rien n'a été saisi
  entre-temps. Échap entre-temps n'y change rien ; changer d'onglet, si.
- Tant que la réponse de dpcc se fait attendre, un autre Ctrl+Espace interroge de nouveau dpcc.
- Ensuite, tout recommence : le Ctrl+Espace suivant interroge de nouveau dpcc.
- dpcc ne passe jamais de lui-même à la liste de l'IDE.
- Si la liste de l'IDE est déjà ouverte (par exemple après « . » de DelphiLSP), Ctrl+Espace lui appartient. dpcc
  n'ouvre alors pas de seconde liste à côté.

La liste de l'IDE vient du fournisseur Code Insight choisi pour Delphi dans les options de l'IDE (par défaut
DelphiLSP). Si dpcc lui-même y est choisi, il n'y a pas de liste de l'IDE : l'IDE rappelle dpcc même pour un
Ctrl+Espace que dpcc lui transmet, jamais DelphiLSP. Le message du pied n'apparaît alors pas, et un second
Ctrl+Espace interroge de nouveau dpcc. Pour garder la liste de DelphiLSP comme recours, laissez DelphiLSP choisi
dans les options.

### Quand dpcc est choisi comme fournisseur

Si dpcc est choisi comme fournisseur Code Insight pour Delphi dans les options de l'IDE, l'IDE n'interroge que dpcc
pour Ctrl+clic et « Find Declaration » (rechercher la déclaration, Alt+↑). Avec DelphiLSP (par défaut), l'IDE saute
comme d'habitude via DelphiLSP ; dpcc n'y participe pas.

- Depuis une utilisation, dpcc saute à la déclaration (pour les méthodes, celle de la classe ou de la section
  interface). Si la position est déjà sur la déclaration elle-même, il va à l'implémentation, et de là en retour.
  Pour les surcharges, c'est la variante avec les mêmes types de paramètres qui compte.
- Déclarations sans corps (méthodes abstraites, méthodes d'une interface, `external`) : Ctrl+clic reste sur place,
  aussi pour les surcharges ; il ne saute pas vers une autre variante.
- `inherited;` sans nom saute, comme `inherited Nom`, vers la méthode de même nom de l'ancêtre.
- Cibles : à travers les unités, noms d'unités dans `uses` (début du fichier), noms de fichiers dans `{$I …}` ou
  `{$INCLUDE …}` (début du fichier inclus ; `{$R …}` ne saute pas), variables locales et paramètres,
  types, champs après des expressions comme `Liste[i].X`, déclarations dans des fichiers inclus et dans des branches
  inactives (`{$IFDEF …}`), unités de la bibliothèque que dpcc charge exprès (y compris les bibliothèques de types
  Office et WinRT). Pour des unités de même nom, c'est celle du projet qui compte.
- Pas de cible, pas de saut : unités sans source (connues seulement par les packages), unités que dpcc ne trouve pas,
  surcharges ambiguës et `with` avec un type inconnu. L'IDE ne saute alors pas ; dpcc indique la raison dans la
  fenêtre des messages (groupe dpcc, texte en anglais si l'IDE n'est pas en allemand), par exemple « unit X is only
  available as a package (no source) », « unit X not found » ou « "Name" could not be resolved ». Si un nom ou une
  unité ne manque que parce que l'index est encore en construction, le message est à la place « No jump: the index is
  still being built. Please click again in a moment. » (l'index est encore en construction, cliquer à nouveau dans
  un instant) ; dpcc n'attend alors pas et ne saute pas plus tard. Pour les autres raisons, l'ajout « The index is
  still being built. » apparaît pendant la construction de l'index. Le même message ne s'affiche pas plusieurs
  fois de suite. Chaque saut sans cible figure aussi sur une ligne de `dpcc.log`.
- Pour Ctrl+clic, c'est la position sous la souris qui compte, pour « Find Declaration » le curseur.
- L'IDE attend dpcc au plus 250 ms. Si la réponse arrive plus tard, dpcc saute lui-même, à condition que le même
  fichier soit actif, que le curseur soit toujours dans le même identificateur (celui cliqué ou celui où il se
  trouvait au moment du clic) et que la réponse soit arrivée au plus 10 secondes après le clic.
- Si dpcc démarre encore, il mémorise le saut (« dpcc is still starting » dans la fenêtre des messages) et l'effectue
  dès qu'il est prêt, selon les mêmes règles.

La première fois de chaque session, la fenêtre Messages indique que dpcc est choisi et ce qui manque alors : Error
Insight (marques d'erreur dans l'éditeur) et les autres services de DelphiLSP. Si vous en avez besoin, choisissez le
mode Off (ou de nouveau DelphiLSP dans les options de l'IDE) ; dpcc est alors désactivé à partir du prochain
démarrage. Le mode Server garde les fenêtres de l'IDE, mais Error Insight y reste vide aussi.

## La liste

Ctrl+Espace ouvre la liste au niveau du curseur. Le mot situé avant le curseur sert de début du terme recherché.

Structure d'une ligne :

- à gauche, la nature en toutes lettres, atténuée (`procedure`, `function`, `type`, `property` …) ;
- le nom en gras, les caractères saisis soulignés ;
- ensuite la signature ou, atténué, un détail ;
- à droite, atténués, « + » et le nom de l'unité (par exemple « + System.SysUtils ») si l'unité ne figure pas encore
  dans `uses`, et les avertissements sous forme de texte.

Le pied de la liste indique les touches ou une remarque.

### Ouverture pendant la saisie

Le réglage « Open on typing from characters » (ouvrir lors de la saisie à partir de … caractères,
`completion.autoMinChars`, voir [Réglages](settings.md)) vaut par défaut 0 = désactivé : la saisie n'ouvre
alors jamais la liste, comme avant cette fonction. Si vous la voulez, réglez par exemple 5. Lorsqu'on saisit alors un
nom sans point devant, dpcc ouvre la liste de lui-même dès que le mot situé avant le curseur compte ce nombre de
caractères. Avec moins de caractères, dpcc n'interroge pas du tout le
serveur : la liste de tous les noms de la portée compterait souvent plus de mille entrées pour un début court et
demanderait un temps de calcul sensible.

- Ctrl+Espace ouvre la liste immédiatement comme avant, quel que soit le nombre de caractères.
- Tant que la liste est ouverte (y compris ouverte par Ctrl+Espace avec moins de caractères), chaque caractère
  supplémentaire ne fait que filtrer ; la saisie ne relance pas de requête.
- Après « . » le seuil ne s'applique pas : la liste des membres vient avec le point comme avant, tant que « Open
  automatically after the dot » est activé (par défaut). Interrupteur désactivé, seul Ctrl+Espace ouvre la liste
  après « . » ; cela prend effet après OK sans redémarrage. Les autres
  déclencheurs restent eux aussi inchangés (« [ », « ( » après un nom, « ; » et Entrée après un constructeur
  accepté).
- La saisie n'ouvre rien dans les commentaires (y compris `{$…}`), les chaînes, les nombres et au milieu d'un mot.
  Si le serveur ne trouve rien (par exemple dans un commentaire sur plusieurs lignes), la liste reste fermée sans
  message.
- Dans `uses`, après `raise` et entre les crochets d'attribut, le même seuil s'applique ; comme avec Ctrl+Espace,
  le serveur décide quelle liste vient. Il ne propose toujours les unités qui ne figurent pas encore dans `uses`
  (« + Unit ») qu'à partir de 2 caractères.
- Le délai fixe avant ouverture (150 ms) s'applique ici aussi : qui continue de saisir rapidement n'obtient la
  liste que pendant la pause, avec le mot saisi jusque-là.
- Si le mot saisi est déjà le nom de l'entrée choisie (par exemple `begin`), rien n'est sélectionné : Entrée coupe
  la ligne au lieu d'accepter l'entrée. Une touche fléchée sélectionne l'entrée.
- Après Échap, la liste ne se rouvre plus d'elle-même dans le même mot.
- En mode espaces réservés et tant que la liste de l'IDE est ouverte, la saisie n'ouvre rien.
- 0 désactive l'ouverture pendant la saisie.

### Touches dans la liste ouverte

| Touche | Effet |
|---|---|
| ↑ / ↓ | déplacer la sélection |
| Page préc. / Page suiv. | se déplacer page par page |
| Début / Fin | première / dernière entrée |
| Entrée ou Tab | accepter l'entrée sélectionnée |
| Échap | fermer la liste |
| continuer à taper | filtrer la liste |
| Retour arrière | assouplir le filtre ; si le mot est plus court qu'au moment de la requête, dpcc interroge à nouveau |
| « ( », « ; », « . » | accepter si l'entrée sélectionnée correspond de façon univoque ; le caractère reste en place (caractères de validation, désactivables) |
| Ctrl+D | épingler l'entrée sélectionnée comme favori ou la détacher |
| Espace | uniquement en mode ensemble : cocher ou décocher la valeur |

La liste se ferme aussi lorsque le curseur quitte le mot ou la ligne, que l'éditeur perd le focus, que l'IDE devient
inactive, que l'éditeur défile ou que la vue change.

Après une fermeture avec Échap, un démarrage automatique dans le même mot ne rouvre pas la liste. Ctrl+Espace l'ouvre
et lève ce blocage.

### Filtrage et ordre

Pendant la saisie, dpcc filtre lui-même la liste existante, sans nouvelle requête. Ordre des résultats :

1. nom exact,
2. début avec la même casse,
3. début,
4. débuts de mots (`TSL` trouve `TStringList`),
5. sous-chaîne,
6. sous-séquence.

S'y ajoutent, selon les réglages :

- Les **favoris** passent avant tous les autres s'ils correspondent à la saisie.
- Les **entrées choisies fréquemment et récemment** reçoivent un bonus. Un meilleur résultat reste malgré tout devant.
- **Type attendu** : les entrées qui conviennent sont en haut sous l'en-tête « Matches … » (convient à …), les autres
  en dessous.
- **Membres hérités** : sans début saisi, les membres propres viennent d'abord, puis un groupe
  « Inherited from … » (hérité de …) par ancêtre.
- **Mode de liste** : au choix, dans les listes des membres après « . », les entrées sans correspondance restent
  aussi visibles pendant la saisie. Si aucun résultat n'est alors en haut, rien n'est sélectionné ; Entrée revient à
  l'éditeur, une touche fléchée sélectionne la première entrée.

Si l'on accepte au milieu d'un mot, dpcc remplace le mot entier.

### Largeur et hauteur

- Le nombre de lignes visibles est réglable (5 à 20).
- Le bord droit peut être tiré à la souris. Un double-clic en bas à droite rétablit la largeur automatique.
- Sans largeur tirée, la liste s'élargit avec l'entrée la plus large. Pendant une session, elle ne rétrécit pas, afin
  de ne pas sauter pendant le filtrage.
- Les lignes tronquées affichent le texte complet lorsque la souris s'y attarde 600 ms.

### Remarques dans la liste

| Affichage | Signification |
|---|---|
| « No matches for “…” » (aucun résultat pour « … ») | Rien ne correspond. Seule Échap appartient à la liste ; les flèches et Entrée vont à l'éditeur. |
| « No suggestions here » (aucune suggestion ici) | Il n'y a rien à proposer à cet endroit. |
| Pied « Press Ctrl+Space again for the IDE list » (Ctrl+Espace à nouveau pour la liste de l'IDE) | La liste après Ctrl+Espace est vide ; un second Ctrl+Espace au même endroit ouvre la liste de l'IDE (voir [plus haut](#liste-de-lide-quand-dpcc-ne-trouve-rien)). |
| « limited (index is being built) » (limitée, index en cours de construction) | L'index n'est pas encore prêt ; la liste peut être incomplète. |
| Barre « Results may be incomplete · syntax error in line n » (résultats peut-être incomplets · erreur de syntaxe à la ligne n) | Avant le curseur, la routine ou la classe courante contient une erreur de syntaxe. |
| Barre « Context unclear · syntax error in line n » (contexte incertain · erreur de syntaxe à la ligne n) | comme ci-dessus, et il n'y a pas d'entrées. |

### Aperçu

L'aperçu de l'entrée sélectionnée dans l'éditeur (la partie encore manquante du nom en italique et atténuée
derrière le curseur) n'existe plus ; il était en dernier lieu désactivé de façon fixe (voir
[Réglages](settings.md#valeurs-fixes)).

## Ce que la liste propose

Ce qui apparaît dépend de l'endroit. Le serveur examine les cas dans un ordre fixe ; le premier qui convient répond.

| Endroit | Proposition |
|---|---|
| après `Expression.` | membres du type, y compris hérités ; pour les unités, leurs symboles de la partie interface |
| après `Expression.` avec un type connu | en plus, modèles postfixes (voir plus bas) |
| ailleurs | tous les noms visibles : locaux, classe propre, unité propre, unités de `uses` |
| à partir d'un caractère saisi (jamais après « . ») | en plus les mots-clés selon la position (`begin`, `if`, `procedure` …) ; désactivables avec « Show reserved words in the list » (`completion.keywords`, prend effet après OK sans redémarrage à partir de la liste suivante) |
| à partir de deux caractères saisis | aussi les symboles d'unités qui ne figurent pas encore dans `uses`, avec « + » et le nom de l'unité ; unités du projet avant les bibliothèques |
| dans la section `uses` | unités connues par groupes : « Project » (projet), « RTL/VCL », « Third party » (tiers) ; remarque si une unité figure déjà dans l'autre section ; marque « Circular reference » (référence circulaire) |
| après `inherited ` | méthodes des ancêtres ; la méthode de même nom d'abord, avec des arguments tirés des paramètres propres |
| après `class(`, `is`, `as`, après `:` dans les déclarations | uniquement des types |
| après `<` d'un type générique | arguments de type, filtrés selon les contraintes |
| dans `[…]` avant une déclaration | classes d'attributs, sans le suffixe `Attribute` |
| après `raise ` et `on E: ` | classes d'exception ; après `on E:`, d'abord celles que le bloc try peut lever d'après le XMLDoc |
| comparaison, branche `case`, affectation avec un type énumération | les valeurs de l'énumération d'abord |
| dans un constructeur d'ensemble `[…]` | mode ensemble (voir plus bas) |
| sur une ligne vide d'une classe avec interface | méthodes manquantes de l'interface, à cocher |
| dans une déclaration de classe après `procedure ` ou `function ` | méthodes redéfinissables |
| après `property … read` / `write` | champs et méthodes qui conviennent |
| après `Objet.Evenement := ` | méthodes qui conviennent et « New method … » (nouvelle méthode …) |
| là où un type référence de méthode est attendu | squelette d'une méthode anonyme avec la signature qui convient |
| à la position du nom dans une déclaration | suggestions de noms |
| après `{$`, `{$IFDEF ` etc. | directives de compilation et symboles conditionnels |
| après `{$I ` ou `{$INCLUDE ` | noms des fichiers `.inc` du dossier du fichier (ou du sous-dossier saisi) et des dossiers des fichiers d'inclusion que l'unité inclut déjà |
| dans un commentaire `///` dont les paramètres ne correspondent plus | « Synchronize parameters » (synchroniser les paramètres) |
| dans l'unité d'une fiche | composants de la fiche, dans un groupe à part « Form … » (fiche …) |
| `Sender.` dans un gestionnaire d'événement | membres du type commun des composants auxquels la méthode est affectée dans la fiche |
| dans `FieldByName('…')`, `FindField('…')`, `ParamByName('…')` | noms de champs ou de paramètres de l'ensemble de données |
| nom déclaré dans plusieurs unités | la variante que choisit le compilateur d'abord, avec « active », les autres avec leur unité |

### Expressions avant le point

Après le point, la liste connaît le type non seulement pour les chaînes de noms (`Liste.Items.`), mais aussi après des
expressions :

- index et propriété par défaut : `Liste[i].`, `Items[0].`, `FArray[0].`, aussi avec `array of T`, les tableaux
  statiques et les champs ou variables locales d'un type tableau anonyme
- parenthèses, transtypage et `as` : `(Sender as TButton).`, `TButton(Sender).`
- pointeurs : `P^.`, et `P.` pour un pointeur vers un record
- littéraux : `'abc'.`, `42.` (membres des helpers de `string` et de `Integer`)
- appels : `Foo(1).` avec la surcharge qui convient, appels par des types procéduraux et `reference to`
  (`FOnGet(1).`), routines génériques sans arguments de type (`Max(A, B).`, `T` déduit des arguments)
- types imbriqués comme type d'un membre : `Dict.Values.`, `Liste.GetEnumerator.Current.`

Les variables inline sans type reçoivent le type de leur expression, aussi avec des opérateurs
(`var S := A + IntToStr(1);` est un `string`, `I / 2` un `Extended`, les comparaisons et `not` un `Boolean`), avec les
`class operator` des records, avec `@X` (pointeur vers le type de `X`), `P^`, les constructeurs d'ensemble et les
méthodes anonymes. La variable d'une boucle `for … in` sans type a le type des éléments : l'élément d'un tableau,
`Char` pour un `string`, sinon `GetEnumerator.Current`.

Après un nom de type (`TFoo.`), la liste ne montre que ce qui s'appelle par le type : méthodes de classe,
constructeurs, `class var`, `class property`, constantes, types imbriqués et valeurs d'une énumération. Après
`TFoo.Create.`, `TFoo(X).` et `Self.`, tous les membres apparaissent.

### « + Unit »

Si un identificateur se trouve dans une unité qui ne figure pas encore dans `uses`, la ligne affiche à droite « + »
et le nom de cette unité, par exemple « + System.SysUtils » pour `FreeAndNil`. « + Unit » n'est donc pas un texte
fixe ; dans cette documentation, « Unit » représente le nom. Lors de l'acceptation, dpcc ajoute l'unité dans `uses`
(réglage « Add the unit to uses automatically », ajouter automatiquement l'unité à uses). Le nom et l'entrée `uses`
forment une seule étape d'annulation.

« + Unit » propose aussi les valeurs des énumérations (par exemple `fsBold` de `Vcl.Graphics`). Les types génériques
affichent leurs paramètres de type (`TList<T>`) ; seul le nom est inséré. Si un `<` suit déjà le mot, ils viennent
avant les types du même nom sans paramètres de type, sinon après. Voir
[Index et cache](index-cache.md#contenu-par-déclaration).

### FieldByName et fiches

Pour cela, dpcc lit le fichier de fiche (DFM) de l'unité. Pour les fiches ouvertes, il prend l'état courant dans le
concepteur, même non enregistré ; les modifications dans le concepteur partent vers le serveur après 500 ms. La
conversion en texte et l'envoi se font en arrière-plan ; une fiche inchangée n'est pas convertie du tout.

Sources des noms de champs, dans cet ordre :

1. champs persistants de l'ensemble de données,
2. colonnes de l'instruction SQL de `SQL.Strings` ou de `CommandText` (les alias comptent ; avec `*`, pas de
   colonnes),
3. pour `ParamByName` : les espaces réservés `:nom` de l'instruction et les entrées de la collection Params.

Sans fichier de fiche, ou sans l'ensemble de données dans celui-ci, il n'y a pas de noms. Pour les ensembles de
données d'autres modules de données (`DM.qryOrders`), dpcc cherche la variable globale dans l'index et lit le fichier
de fiche de son unité.

### Modèles postfixes

Après `Expression.`, la liste propose, après les membres, des abréviations qui transforment l'expression. Seul ce qui
convient au type est proposé. Les instructions ne sont proposées que si l'expression commence la ligne.

| Abréviation | Résultat | Type |
|---|---|---|
| `for`, `forin` | `for var Item in Liste do` | énumérable |
| `tryf` | `try … finally Obj.Free; end;` | classe |
| `ifa`, `notnil` | `if Assigned(X) then` | classe, interface, pointeur |
| `nil` | `if not Assigned(X) then` | classe, interface, pointeur |
| `not` | `not B` | Boolean |
| `if` | `if B then` | Boolean |
| `fmt` | `Format(S, [])` | String |
| `free` | `FreeAndNil(Obj);` | classe |
| `try` | `var Foo := TFoo.Create; try … finally Foo.Free; end;` | appel de constructeur |
| `var` | `var Name := X;` | type connu |
| `exit` | `Exit(X);` | dans une fonction |

## Espaces réservés

Certaines entrées insèrent du texte avec des espaces réservés, par exemple les modèles postfixes ou le squelette
d'une méthode anonyme. dpcc gère lui-même les espaces réservés :

| Touche | Effet |
|---|---|
| taper | remplace la valeur par défaut de l'espace réservé courant |
| Tab | espace réservé suivant ; après le dernier, vers la position finale |
| Maj+Tab | espace réservé précédent |
| Entrée | terminer et sauter à la position finale |
| Échap | terminer sur place |

L'espace réservé courant est encadré d'un trait plein, les espaces réservés liés en tirets, les autres en pointillés.
Derrière la ligne figure « Placeholder 1 / 3 · Tab next · Esc done » (espace réservé 1 / 3 · Tab suivant · Échap
terminé). dpcc aligne les espaces réservés liés portant le même numéro. Une modification en dehors ou un changement
de vue met fin au mode.

Si le mode se termine normalement (Échap, Entrée, Tab après le dernier), un Ctrl+Z annule toute l'insertion en une
seule étape.

## Mode ensemble

Dans un constructeur d'ensemble (`Anchors := [akLeft, |`), la liste affiche toutes les valeurs du type d'élément avec
des cases à cocher. Les valeurs qui figurent déjà entre les crochets sont cochées. L'en-tête est par exemple
« TAnchors · set of TAnchorKind » (TAnchors · ensemble de TAnchorKind).

| Touche | Effet |
|---|---|
| Espace | cocher ou décocher la valeur sélectionnée |
| Entrée ou Tab après un appui sur Espace dans cette liste | réécrire tous les crochets : exactement les valeurs cochées dans l'ordre de déclaration, `[]` si aucune n'est cochée ; avec `{$SCOPEDENUMS ON}`, avec le préfixe du type |
| Entrée ou Tab sans appui sur Espace dans cette liste | cocher en plus la valeur sélectionnée et réécrire les crochets comme ci-dessus : les valeurs existantes plus la valeur sélectionnée |
| Échap | abandonner |

Le pied de la liste affiche « Space selects · Enter inserts · Esc discards » (Espace sélectionne · Entrée insère ·
Échap abandonne) et le nombre de valeurs choisies.

La même liste sert pour « Implement interface » (implémenter l'interface) : méthodes manquantes, toutes cochées ;
Entrée insère celles qui sont cochées.

## Favoris

Ctrl+D dans la liste ouverte épingle l'entrée sélectionnée ou la détache. C'est toujours activé (voir
[Réglages](settings.md#valeurs-fixes)).

- Un favori vaut pour une paire type et membre. Le type est la classe déclarante, au niveau de l'unité c'est l'unité.
  Un favori `TDataSet.Open` vaut donc pour tout ensemble de données.
- Au plus 5 favoris par type. Un favori de plus n'en remplace aucun ; le pied de la liste signale « Already 5
  favorites for … » (déjà 5 favoris pour …).
- Les entrées épinglées sont en haut si elles correspondent à la saisie.
- dpcc enregistre immédiatement dans `%APPDATA%\dpcc\favorites.json`.
- Il n'y a plus de liste des favoris sur la page des options ; on détache un favori avec Ctrl+D sur l'entrée.

## Acceptation

Ce qui se passe lors de l'acceptation est en grande partie réglable (section « When accepting », lors de
l'acceptation, voir [Réglages](settings.md#when-accepting)) :

- **Parenthèses** : pour les méthodes, dpcc ajoute les parenthèses. Si l'on tape un « ) » juste devant la parenthèse
  fermante insérée automatiquement, dpcc saute celle-ci au lieu de produire « )) ».
- **Casse** : `showmessage` devient `ShowMessage` (toujours activé).
- **Unité dans uses** : voir « + Unit ».
- **Caractères de validation** : « ( », « ; » et « . » acceptent.

## Aide aux paramètres

Ctrl+Maj+Espace dans un appel affiche les signatures de la routine appelée au niveau de la parenthèse ouvrante.

- Toutes les surcharges sont affichées les unes sous les autres. Dans celle qui est sélectionnée, le paramètre actif
  est en gras et souligné. Les surcharges qui ont trop peu de paramètres sont atténuées.
- La surcharge présélectionnée est la première à laquelle correspondent les arguments saisis jusque-là. Comptent
  les littéraux, les noms et le type d'expressions comme `Liefere(1)`, `Liste[i]` ou `A + 1`.
- Un clic sélectionne une surcharge ; Ctrl+Alt+↑ / Ctrl+Alt+↓ en change. Alt+↑ reste à l'IDE (« Find
  Declaration »), les flèches seules déplacent le curseur.
- Pour les appels imbriqués, une ligne de chemin en haut montre les appels extérieurs, par exemple
  « ShowMessage › Format ».
- En dessous figurent le nom et la description du paramètre actif tirés du XMLDoc (sans `<param>` : « not
  documented », non documenté), les valeurs par défaut (« optional, default … », facultatif, par défaut …) et la
  description de la méthode.
- Si aucune surcharge n'accepte autant d'arguments, on lit « No overload with n parameters. » (aucune surcharge avec
  n paramètres).
- Si la liste de complétion est ouverte ou s'il n'y a pas de place en dessous, l'aide aux paramètres apparaît
  au-dessus de la ligne.
- Échap la ferme. Elle se ferme aussi lorsque le curseur quitte l'appel (y compris par « ) »), en cas de perte du
  focus, de défilement ou de changement d'onglet.
- Si la parenthèse fermante est supprimée et que le curseur se trouve ensuite dans un appel, l'aide réapparaît ; pas
  pour un appel dont l'aide a été fermée avec Échap.

### Appels reconnus

- **Surcharges héritées** : si une méthode de la classe dérivée porte `overload`, les méthodes de même nom des
  ancêtres figurent aussi dans la liste (`TAbgeleitet.Add(const S: string)` et la méthode héritée `Add(A: Integer)`).
  Sans `overload`, la classe dérivée les masque, comme pour le compilateur.
- **Types procéduraux** : les appels via des variables, champs, propriétés et paramètres d'un type procédural
  affichent sa signature, par exemple `FOnChange(Self` (`TNotifyEvent`), `Callback(1` ou `AProc(` avec
  `AProc: TProc<Integer>`. Pour les types génériques, les arguments de type sont substitués
  (`TProc<Integer> = reference to procedure (Arg1: Integer)`).
- **Arguments de type avant la parenthèse** : `Foo<Integer>(` n'affiche que la surcharge générique, avec
  l'argument de type substitué.
- **Propriétés indexées** : `Liste.Items[` et `Liste[` (propriété par défaut) affichent les paramètres d'index,
  avec Ctrl+Maj+Espace ou à la virgule. Si le crochet se trouve dans un appel (`Foo(Liste[`), l'aide reste celle
  de cet appel ; pour un tableau au lieu d'une propriété, rien n'apparaît.

### Espaces réservés de Format

Pour `Format` et les autres routines de formatage, une ligne indique l'espace réservé correspondant à l'argument sous
le curseur, par exemple « Placeholder 2 of 2 expects integer » (l'espace réservé 2 sur 2 attend un entier). Elle
avertit en cas d'arguments en trop, d'espaces réservés invalides et de conflits de type avec des littéraux. L'espace
réservé et l'argument reçoivent dans l'éditeur la même couleur de fond, tant que l'aide aux paramètres est ouverte.
C'est toujours activé et ne disparaît qu'avec l'aide aux paramètres entière (« Parameter hint on “(” and “,” »).

## Survol

Lorsque la souris s'attarde 500 ms sur un identificateur, dpcc affiche une infobulle en dessous. L'IDE n'attend
jamais le serveur pour cela.

Contenu, de haut en bas (les sections vides sont omises) :

| Section | Contenu |
|---|---|
| Valeur dans le débogueur | expression et valeur lorsque le programme est arrêté ; jusqu'à la réponse, « evaluating … » (évaluation en cours …) |
| Ligne d'en-tête | nature et signature, complète même sur plusieurs lignes |
| Origine, emplacement | nature en toutes lettres, bibliothèque, origine ; fichier et ligne |
| Valeur, obsolescence | valeur d'une constante, aussi d'expressions simples ; `deprecated`, `platform`, `experimental` ; branche inactive |
| XMLDoc | résumé, paramètres, valeur de retour, exceptions, remarques, exemple, voir aussi ; `<inheritdoc/>` est résolu ; sans `///`, le commentaire normal (voir ci-dessous) |
| Membres published | pour les classes de composants, propriétés et événements, y compris hérités |
| Héritage | chaîne d'héritage ou type cible d'une référence de classe |

Si l'infobulle est plus haute que la place disponible ou que le nombre de lignes réglé, le XMLDoc défile avec la
molette de la souris.

L'infobulle se ferme 300 ms après que la souris a quitté l'identificateur et l'infobulle, immédiatement avec Échap et
toute autre touche (sauf Maj, Ctrl, Alt seules), en cas de clic de souris, de défilement, de redimensionnement et
lorsque l'IDE devient inactive. Si une liste de complétion, une aide aux paramètres ou un menu est ouvert, aucune
infobulle n'apparaît.

Ctrl+clic à travers l'infobulle : tant que Ctrl est enfoncée, la souris et le clic traversent l'infobulle jusqu'à
l'éditeur en dessous. Si la souris est au-dessus de l'infobulle, Ctrl la ferme. Ainsi, un mot que l'infobulle
recouvre reste accessible par Ctrl+clic.

### Signature, commentaires et valeurs

- **Signature :** si une déclaration s'étend sur plusieurs lignes, la ligne d'en-tête l'affiche en entier
  (paramètres, résultat et directives comme `virtual` ou `stdcall`) sur une seule ligne, sans commentaires. Pour les
  classes, records et interfaces, seule la première ligne est affichée. Les en-têtes très longs sont abrégés après
  1000 caractères par « … ».
- **Type déduit :** pour les variables inline sans type (`var X := TFoo.Create;`, `for var I := 0 to …`),
  dpcc insère le type qui découle de l'expression : `var X: TFoo := TFoo.Create;`. Si le type ne peut pas
  être déterminé avec certitude, la ligne reste telle qu'elle est dans le source.
- **Commentaires comme documentation :** le XMLDoc avec `///` est prioritaire. Sans lui, dpcc affiche le
  bloc de commentaire normal situé juste au-dessus de la déclaration (`//`, `{ }` ou `(* *)`, sans ligne vide entre
  les deux) et le commentaire en fin de la ligne qui porte le nom. Ne comptent pas comme documentation : les
  en-têtes de fichier et de licence (bloc en début de fichier ou contenant des mots comme Copyright, License,
  Lizenz), les blocs placés après une ligne vide, les lignes de séparation comme `//-----`, un nom seul comme
  `{ TFoo }` et le code mis en commentaire (lignes avec `:=`, instructions terminées par `;`, `begin`/`end` …) ;
  un bloc composé majoritairement de code est ignoré entièrement. La ligne d'en-tête n'affiche plus le commentaire
  de fin de ligne.
- **Valeurs :** les constantes affichent aussi la valeur d'expressions simples : entiers avec
  `+ - * div mod and or xor not shl shr`, signes et parenthèses, textes avec `+` et références à d'autres constantes
  de l'unité ou de l'index (`cMax = cBase * 2`). Ce que dpcc ne peut pas calculer avec certitude (virgule flottante,
  fonctions comme `High` ou `Ord`, comparaisons, références circulaires) n'affiche aucune valeur.
- **Branches inactives :** sur une déclaration située dans une branche qui ne s'applique pas à la
  configuration actuelle (`{$IFDEF …}`), le survol affiche son en-tête et son commentaire, lus dans le fichier, avec
  la mention « Inactive » (inactif) et la condition.

dpcc n'enregistre pas les commentaires dans l'index ; le survol les lit au besoin dans le seul fichier de la
déclaration.

### Valeurs pendant le débogage

Si le programme est arrêté et que le réglage « Show values while debugging » (afficher les valeurs pendant le
débogage) est activé, dpcc évalue l'expression sous la souris au moyen du débogueur de l'IDE. L'évaluation
n'appelle rien dans le programme. La valeur figure tout en haut.

### Help Insight

Tant que l'infobulle de dpcc est activée, dpcc désactive Help Insight de l'IDE, afin que deux infobulles
n'apparaissent pas. Détails dans [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).

## Langue

Les textes de dpcc sont en allemand si l'IDE est en allemand, sinon en anglais. Il n'y a pas de textes en français :
une IDE française affiche les textes anglais. Les identificateurs, les signatures et le XMLDoc ne sont jamais
traduits.
