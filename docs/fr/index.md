[Deutsch](../de/index.md) | [English](../en/index.md) | Français

# dpcc – Documentation

dpcc (Delphi Pascal Code Completion) est un plugin pour l'IDE Delphi. Il apporte sa propre complétion de code, une
aide aux paramètres et une infobulle sur les identificateurs. Pour cela, il construit dans le processus de l'IDE son
propre index du projet, des chemins de recherche et de la bibliothèque.

Version 0.1.0, pour Delphi 13 (RAD Studio 37.0), Win32.

L'interface de dpcc n'existe qu'en allemand et en anglais : dpcc affiche ses textes en allemand dans une IDE
allemande, sinon en anglais. Il n'y a pas de version française ; une IDE française affiche dpcc en anglais. Cette
documentation cite donc les textes de l'interface de dpcc en anglais, avec une traduction française entre
parenthèses.

## Pour les utilisateurs

| Page | Contenu |
|---|---|
| [Installation](installation.md) | Prérequis, compilation, installation, PATH de l'IDE, mise à jour, désinstallation |
| [Utilisation](usage.md) | Touches, la liste, ce qu'elle propose, survol, aide aux paramètres, espaces réservés, mode ensemble, favoris |
| [Réglages](settings.md) | Chaque option de la page Tools › Options › Third Party › dpcc, stockage, ce que dpcc modifie dans l'IDE |
| [Index et cache](index-cache.md) | Ce que contient l'index, où se trouve le cache, reconstruction, nettoyage |
| [Dépannage](troubleshooting.md) | Le plugin ne se charge pas, la liste manque, infobulles en double, journaux |

## Pour les développeurs

| Page | Contenu |
|---|---|
| [Architecture](architecture.md) | Paquets, couches, serveur dans le processus de l'IDE, déroulement d'une requête |
| [Développement](development.md) | Compilation dans l'IDE, tests, conventions, contribution |

## En bref : ce que dpcc prend en charge

| Fonction | Déclencheur | Fournie par |
|---|---|---|
| Complétion | Ctrl+Espace | dpcc |
| Aide aux paramètres | Ctrl+Maj+Espace | dpcc |
| Infobulle sur les identificateurs | La souris s'attarde sur un identificateur | dpcc |
| Liste qui s'ouvre d'elle-même après « . » | Saisie de « . » | DelphiLSP (IDE) |

dpcc traite les fichiers portant les extensions `.pas`, `.dpr`, `.dpk` et `.inc`. Dans tous les autres fichiers, et
lorsque l'interrupteur principal est désactivé, c'est l'IDE qui reste responsable.

## Licence

MIT, voir [LICENSE](../../LICENSE).
