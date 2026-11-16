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

La liste qui s'ouvre d'elle-même après un « . » continue de venir de DelphiLSP. dpcc prend en charge Ctrl+Espace et
Ctrl+Maj+Espace dans les fichiers qu'il traite. Détails : [Utilisation](docs/fr/usage.md).

## Prérequis

- Delphi 13 / RAD Studio 37.0
- Plateforme Win32 (l'IDE est un processus 32 bits)

## Compilation

Ouvrir le groupe de projets `dpcc_d13.groupproj` dans l'IDE et compiler tous les projets (Win32, Debug). La sortie
se trouve sous `Output\Win32\Debug` (les BPL dans `Bpl`, le programme de test dans `Bin`). Pour en savoir plus :
[Développement](docs/fr/development.md).

## Installation

1. Dans l'IDE, ajouter via **Component › Install Packages…** le fichier
   `Output\Win32\Debug\Bpl\dpcc.IDE.Base370.bpl`.
2. `dpcc.IDE.Base370.bpl` a besoin à l'exécution des sept BPL `dpcc.Text`, `dpcc.WinBase`, `dpcc.Common`,
   `dpcc.Windows`, `dpcc.Server`, `dpcc.Core` et `dpcc.UI`. Windows les recherche via le PATH. Le dossier
   `Output\Win32\Debug\Bpl` doit donc figurer dans le PATH de l'IDE.

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

Les options se trouvent sous **Tools › Options › Third Party › dpcc** : [Réglages](docs/fr/settings.md).
En cas de problème : [Dépannage](docs/fr/troubleshooting.md).

## Tests

```
Output\Win32\Debug\Bin\dpcc.Completion.Tests.exe --exclude:Benchmark --exitbehavior:Continue
```

Voir [Développement](docs/fr/development.md#tests).

## Licence

MIT, voir [LICENSE](LICENSE).
