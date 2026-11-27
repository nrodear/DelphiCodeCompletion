[Deutsch](README.md) | [English](README.en.md) | Français

# dpcc – Delphi Pascal Code Completion

Version 0.1.0

dpcc est un plugin (paquet de conception) pour l'IDE Delphi. Il apporte sa propre complétion de code, qui construit
dans le processus de l'IDE son propre index du projet, des chemins de recherche et de la bibliothèque.

Documentation détaillée : [docs/fr/index.md](docs/fr/index.md).

## Fonctions

- **Complétion avec Ctrl+Espace** : liste sobre des identificateurs correspondants (nature, nom, signature).
  Si un identificateur se trouve dans une unité qui ne figure pas encore dans la section `uses`, la liste affiche
  « + » et le nom de l'unité (par exemple « + System.SysUtils ») et ajoute l'unité lors de l'acceptation.
- **Aide aux paramètres avec Ctrl+Maj+Espace** : signatures de la routine appelée, le paramètre courant est mis en
  évidence.
- **Survol** : infobulle sur un identificateur avec la déclaration, l'emplacement et le commentaire XMLDoc ; pendant
  le débogage, en plus la valeur de la variable.
- **Complétion FieldByName** : noms de champs dans `FieldByName('…')` et composants des fiches (DFM) du projet.

dpcc fonctionne, pour chaque version de Delphi, dans l'un de trois modes (**Tools › Options › Third Party › dpcc**).
Dans le mode Plugin (par défaut, fournisseur dpcc), la liste après « . » et l'aide aux paramètres à « ( » et « , »
viennent aussi de dpcc. Dans le mode Off, Delphi travaille avec DelphiLSP sans dpcc. Dans le mode Server, l'IDE
affiche ses propres fenêtres, les réponses viennent de `dpcc.LspServer.exe` au lieu de `DelphiLSP.exe`. Le passage
depuis ou vers Plugin change de fournisseur ; cela prend effet après le redémarrage de Delphi. Détails :
[Utilisation](docs/fr/usage.md#interaction-avec-delphilsp),
[Réglages](docs/fr/settings.md#mode-de-fonctionnement) et [Serveur LSP](docs/fr/lsp-server.md#mode-server).

## Prérequis

- Delphi 13 / RAD Studio 37.0 ; pour Delphi 12 / RAD Studio 23.0, il existe un groupe de projets distinct sans
  tests (voir [Compiler pour Delphi 12](docs/fr/installation.md#compiler-pour-delphi-12))
- Plateforme Win32 (l'IDE est un processus 32 bits)

## Compilation

Ouvrir le groupe de projets `dpcc_d13.groupproj` dans l'IDE et compiler tous les projets (Win32, Debug). La sortie
se trouve sous `Output\Win32\Debug` (les BPL dans `Bpl`, le programme de test et le serveur LSP autonome `dpcc.LspServer.exe` dans `Bin`, voir [Serveur LSP](docs/fr/lsp-server.md) ; l'EXE 64 bits est produite dans une étape à part sous `Output\Win64\Debug\Bin`). Pour Delphi 12, c'est
`dpcc_d12.groupproj`, avec la configuration D12 (jamais Debug) et la sortie sous `Output\Win32\D12`. Pour en savoir plus :
[Développement](docs/fr/development.md).

## Installation

1. Dans l'IDE, ajouter via **Component › Install Packages…** le fichier
   `Output\Win32\Debug\Bpl\dpcc.Plugin370.bpl`.
2. `dpcc.Plugin370.bpl` a besoin à l'exécution des sept BPL `dpcc.Text370`, `dpcc.WinBase370`,
   `dpcc.Common370`, `dpcc.Windows370`, `dpcc.Server370`, `dpcc.Core370` et `dpcc.UI370`. Windows les recherche
   via le PATH. Le dossier `Output\Win32\Debug\Bpl` doit donc figurer dans le PATH de l'IDE.
3. Sous Delphi 12, les fichiers s'appellent `…290.bpl` (plugin `dpcc.Plugin290.bpl`), le dossier est
   `Output\Win32\D12\Bpl`.

### Définir le PATH de l'IDE

L'entrée doit aller dans le remplacement de PATH de l'IDE (**Tools › Options › IDE › Environment Variables ›
User overrides**), pas dans le PATH de Windows. Exemple, si le dépôt se trouve sous `D:\src\DelphiCodeCompletion` :

```
D:\src\DelphiCodeCompletion\Output\Win32\Debug\Bpl;$(PATH)
```

Ou par script, depuis le dossier du dépôt et avec l'IDE fermée :

```powershell
powershell -NoProfile -File Tools\IdePath.ps1                 # afficher l'état
powershell -NoProfile -File Tools\IdePath.ps1 -Action Add     # ajouter le dossier des BPL
powershell -NoProfile -File Tools\IdePath.ps1 -Action Remove  # retirer l'entrée
```

L'entrée prend effet au prochain démarrage de l'IDE. Toutes les étapes, la vérification et la désinstallation :
[Installation](docs/fr/installation.md).

### Programme d'installation

À partir des BPL compilées des deux groupes, `Tools\Build-Setup.ps1` crée avec Inno Setup 6 le programme
d'installation `installer\Output\dpccSetup-<version>.exe`. Il installe dpcc pour l'utilisateur courant dans Delphi 12
et/ou 13, sans droits d'administrateur, et définit lui-même les Known Packages et le PATH de l'IDE. Le composant « LSP server » ajoute
`dpcc.LspServer.exe` pour le mode Server ; un ZIP contenant l'EXE est créé à côté. Voir
[Installer avec le programme d'installation](docs/fr/installation.md#installer-avec-le-programme-dinstallation).

Les options se trouvent sous **Tools › Options › Third Party › dpcc** : [Réglages](docs/fr/settings.md).
En cas de problème : [Dépannage](docs/fr/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

Voir [Développement](docs/fr/development.md#tests). Les tests n'existent que pour Delphi 13.

## Licence

MIT, voir [LICENSE](LICENSE).
