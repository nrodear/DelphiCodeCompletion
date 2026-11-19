[Deutsch](../de/installation.md) | [English](../en/installation.md) | Français

# Installation

[Vue d'ensemble](index.md) › Installation

## Prérequis

- Delphi 13 / RAD Studio 37.0. Pour Delphi 12 / RAD Studio 23.0, voir
  [Compiler pour Delphi 12](#compiler-pour-delphi-12).
- Plateforme Win32. L'IDE est un processus 32 bits, le plugin est donc un paquet Win32.
- Le code source de dpcc. Il n'existe pas de BPL prêtes à l'emploi ; dpcc se compile à partir du groupe de projets.

## Compilation

1. Ouvrir `dpcc_d13.groupproj` dans l'IDE.
2. Plateforme Win32, configuration Debug.
3. Compiler tous les projets du groupe. L'ordre découle des dépendances du groupe.

La sortie se trouve sous `Output\Win32\Debug` :

| Dossier | Contenu |
|---|---|
| `Bpl` | les huit BPL avec le suffixe `370` (version de paquet de Delphi 13), dont le plugin `dpcc.IDE.Base370.bpl` |
| `Dcp` | les fichiers DCP des paquets |
| `Dcu` | les DCU, un sous-dossier par projet |
| `Bin` | le programme de test `dpcc.Completion.Tests.exe` |

Le compilateur en ligne de commande (`dcc32`, MSBuild) est bloqué dans les éditions Community et Starter ; avec ces
éditions, compiler dans l'IDE. Pour en savoir plus, voir [Développement](development.md).

### Compiler pour Delphi 12

Pour Delphi 12 (RAD Studio 23.0), il existe le groupe `dpcc_d12.groupproj` avec les mêmes huit paquets, sans le
programme de test : les tests ne s'exécutent que sous Delphi 13.

1. Ouvrir `dpcc_d12.groupproj` dans l'IDE de Delphi 12.
2. Plateforme Win32, configuration **D12** pour les huit projets (**Project › Configuration Manager**).
3. Compiler tous les projets du groupe.

La configuration D12 hérite de tous les réglages de Debug et compile dans un dossier à part (`Output\Win32\D12`).
Ainsi, les fichiers des deux versions ne s'écrasent pas. Ne jamais compiler Delphi 12 avec la configuration
Debug : il écrirait sinon dans les dossiers de Delphi 13 (recompiler alors `dpcc_d13.groupproj` sous
Delphi 13). Pour en savoir plus, voir [Développement](development.md).

| | Delphi 13 | Delphi 12 |
|---|---|---|
| Groupe | `dpcc_d13.groupproj` | `dpcc_d12.groupproj` |
| Configuration | Debug | D12 |
| Sortie | `Output\Win32\Debug` | `Output\Win32\D12` |
| Plugin | `dpcc.IDE.Base370.bpl` | `dpcc.IDE.Base290.bpl` |
| Autres BPL | `dpcc.Text370.bpl` … `dpcc.UI370.bpl` | `dpcc.Text290.bpl` … `dpcc.UI290.bpl` |
| PATH de l'IDE | `…\Output\Win32\Debug\Bpl` | `…\Output\Win32\D12\Bpl` |
| Registre de l'IDE | `HKCU\Software\Embarcadero\BDS\37.0` | `HKCU\Software\Embarcadero\BDS\23.0` |
| `Tools\IdePath.ps1` | sans `-BdsVersion` | `-BdsVersion 23.0` |
| Tests | oui | non |

Installer et définir le PATH comme ci-dessous, seulement avec les noms et dossiers de la colonne Delphi 12 : dans
l'IDE de Delphi 12, ajouter `Output\Win32\D12\Bpl\dpcc.IDE.Base290.bpl` (l'IDE l'inscrit sous
`HKCU\Software\Embarcadero\BDS\23.0\Known Packages`) et placer `…\Output\Win32\D12\Bpl` dans le PATH de
l'IDE de Delphi 12.

## Installer

1. Dans l'IDE, ouvrir **Component › Install Packages…**.
2. Choisir **Add…** et ouvrir `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl`.
3. L'IDE affiche le paquet avec la description « dpcc (Code Insight-Manager) ».

Seul `dpcc.IDE.Base370.bpl` est installé. Il a besoin à l'exécution de sept autres BPL (sous Delphi 12 avec le
suffixe `290` au lieu de `370`) :

| BPL | Rôle |
|---|---|
| `dpcc.Text370.bpl` | utilitaires de texte, RTL uniquement |
| `dpcc.WinBase370.bpl` | RTL et API Windows |
| `dpcc.Common370.bpl` | analyseur, index, parties LSP, sans Windows ni VCL |
| `dpcc.Windows370.bpl` | parties spécifiques à Windows, sans VCL |
| `dpcc.Server370.bpl` | le serveur de complétion, s'exécute dans le processus de l'IDE |
| `dpcc.Core370.bpl` | logique du plugin, sans VCL ni ToolsAPI |
| `dpcc.UI370.bpl` | interface VCL du plugin |

L'IDE charge ces BPL en même temps. Mais Windows ne les cherche pas dans le dossier de la BPL du plugin ; il les
cherche via le PATH. Le dossier `Output\Win32\Debug\Bpl` doit donc figurer dans le PATH de l'IDE.

## Définir le PATH de l'IDE

L'entrée doit aller dans le remplacement de PATH de l'IDE, pas dans le PATH de Windows. L'IDE enregistre ce
remplacement dans le registre sous `HKCU\Software\Embarcadero\BDS\37.0\Environment Variables`, valeur `PATH`.

Exemple, si le dépôt se trouve sous `D:\src\DelphiCodeCompletion` :

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

### À la main dans l'IDE

1. Ouvrir **Tools › Options › IDE › Environment Variables**.
2. Sous **User overrides**, cliquer sur **New…** ou modifier une entrée `PATH` existante.
3. Variable `PATH`. Valeur : le dossier des BPL en tête, puis `;$(PATH)`. Une valeur existante est conservée ; le
   dossier des BPL est seulement placé devant.
4. Fermer avec OK et redémarrer l'IDE.

### Par script

`Tools\IdePath.ps1` vérifie et définit la même entrée. L'appeler depuis le dossier du dépôt. Fermer l'IDE
auparavant ; les modifications ne prennent effet qu'au prochain démarrage de l'IDE.

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # afficher l'état
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # ajouter le dossier des BPL
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # retirer l'entrée
```

| Action | Effet |
|---|---|
| `Status` (par défaut) | Affiche la valeur de PATH, le dossier des BPL, chaque BPL attendue avec sa date, les paquets dpcc installés (Known Packages) et les instances de l'IDE en cours d'exécution. Ne modifie rien. |
| `Check` | Comme `Status`, mais seulement la ligne de résultat. Pour les scripts. |
| `Add` | Ajoute le dossier des BPL : avant `$(PATH)` si la valeur contient `$(PATH)`, sinon à la fin ; sans valeur, sous la forme `<dossier>;$(PATH)`. Sauvegarde la valeur précédente sous `HKCU\Software\dpcc\IdePlugin`, valeur `PathOverrideBackup`. |
| `Remove` | Retire le dossier des BPL de la valeur de PATH. Les autres parties de la valeur restent. La sauvegarde n'est pas restaurée. |

| Paramètre | Valeur par défaut | Signification |
|---|---|---|
| `-Action` | `Status` | `Status`, `Check`, `Add` ou `Remove` |
| `-BdsVersion` | `37.0` | version de l'IDE dans le registre ; `23.0` pour Delphi 12 |
| `-BplDir` | `Output\Win32\Debug\Bpl` dans le dépôt, avec `-BdsVersion 23.0` `Output\Win32\D12\Bpl` | autre dossier des BPL |

Code de sortie de `Status` et `Check` :

| Code | Signification |
|---|---|
| 0 | entrée présente, toutes les BPL sont là |
| 1 | entrée manquante ; solution : `-Action Add` |
| 2 | dossier des BPL ou BPL manquants ; compiler d'abord le groupe |

## Vérifier que dpcc est chargé

- L'écran de démarrage et la boîte À propos de l'IDE mentionnent « dpcc 0.1.0 » (texte seul, sans image).
- Sous **Tools › Options › Third Party** figure le nœud **dpcc**.
- Le journal `%LOCALAPPDATA%\dpcc\Logs\dpcc.log` contient la ligne « dpcc angemeldet (Code Completion) » (dpcc
  enregistré).
- Dans un fichier `.pas`, Ctrl+Espace ouvre la liste de dpcc. Elle affiche sur chaque ligne la nature en toutes
  lettres, le nom en gras et la signature.

## Au premier démarrage

- dpcc démarre le serveur à la première requête, par exemple avec Ctrl+Espace. Le serveur construit ensuite l'index.
  La première construction peut prendre quelques minutes sur les grosses installations, car elle lit aussi la
  bibliothèque. Ensuite, l'essentiel vient du cache. Voir [Index et cache](index-cache.md).
- Si DelphiLSP est choisi comme fournisseur Code Insight au démarrage de Delphi (par défaut), dpcc se désactive.
  Pour l'activer, activer l'interrupteur principal sous **Tools › Options › Third Party › dpcc** et fermer avec
  **OK** : dpcc bascule alors le fournisseur de l'IDE sur dpcc et règle les options de l'IDE dont il a besoin (Help
  Insight, infobulles, délai). Cela prend effet après le redémarrage de Delphi ; la fenêtre Messages le signale.
  Voir [Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).

## Mise à jour

1. Récupérer la nouvelle version.
2. Recompiler le groupe (voir plus haut).
3. Redémarrer l'IDE.

Si l'on compile le groupe dans l'IDE où dpcc est installé, l'IDE décharge le plugin pendant la compilation. dpcc se
désenregistre pour cela étape par étape. Redémarrer l'IDE ensuite est la méthode sûre.

Les versions plus anciennes compilaient les sept paquets d'exécution sans suffixe (`dpcc.Text.bpl` … `dpcc.UI.bpl`).
Après la première recompilation, ces fichiers restent dans le dossier des BPL ; le plugin ne les charge plus, on peut
les supprimer.

## Désinstallation

1. Pour que dpcc rende le fournisseur et les réglages de l'IDE : sous **Tools › Options › Third Party › dpcc**,
   désactiver l'interrupteur principal « Code Insight by dpcc » (Code Insight de dpcc), fermer avec **OK** et
   redémarrer Delphi une fois. dpcc rétablit alors le fournisseur (par défaut DelphiLSP) et annule ses réglages.
2. Ouvrir **Component › Install Packages…**, choisir « dpcc (Code Insight-Manager) » puis **Remove**.
3. Fermer l'IDE.
4. Retirer l'entrée du PATH : `powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove` ou à la main sous
   **Tools › Options › IDE › Environment Variables**.

Ce qui reste ensuite et peut être supprimé à la main :

| Emplacement | Contenu |
|---|---|
| `HKCU\Software\dpcc\IdePlugin` | réglages, marqueurs pour les réglages de l'IDE, `PathOverrideBackup` |
| `%APPDATA%\dpcc` | `settings.json`, `usage.json` (historique), `favorites.json` (favoris), issu de versions antérieures `settings-history.json` |
| `%LOCALAPPDATA%\dpcc` | `Logs` (journal), `Index` (caches d'index) |
| dossier des BPL | `dpcc.IDE.Expert370.log`, si le journal de diagnostic était activé |

Si l'on a sauté l'étape 1, dpcc peut rester inscrit comme fournisseur, et Help Insight, les infobulles et
l'infobulle de valeur de l'IDE peuvent rester désactivés. Il faut alors choisir DelphiLSP dans les options Code
Insight de l'IDE et réactiver ces réglages. Les emplacements dans le registre figurent sous
[Réglages](settings.md#ce-que-dpcc-modifie-dans-lide).
