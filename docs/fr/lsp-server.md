[Deutsch](../de/lsp-server.md) | [English](../en/lsp-server.md) | Français

# Serveur LSP (dpcc.LspServer.exe)

[Vue d’ensemble](index.md) › Serveur LSP

`dpcc.LspServer.exe` est dpcc sous forme de serveur de langage autonome. Il parle le Language Server Protocol sur
stdin/stdout et peut remplacer `DelphiLSP.exe` dans l’IDE Delphi. À l’intérieur tourne le même serveur que dans le
plugin (index, complétion, survol, aide aux paramètres, cibles de saut) ; s’y ajoutent la vue structure et le format
attendu par l’IDE.

Le plugin garde son serveur intégré. L’EXE est un second chemin, séparé, vers le même résultat.

## Ce qu’il fait

| Requête | Résultat |
|---|---|
| `textDocument/completion`, `completionItem/resolve` | liste avec genre, nom et signature comme DelphiLSP |
| `textDocument/hover` | déclaration et documentation en texte brut |
| `textDocument/signatureHelp` | signatures avec le paramètre courant |
| `textDocument/definition`, `declaration`, `typeDefinition` | saut vers implémentation, déclaration, type |
| `textDocument/documentSymbol` | vue structure : sections, types avec champs, propriétés et méthodes, routines |
| `didOpen`, `didChange` (texte entier ou plages), `didClose` | documents en mémoire |
| `workspace/didChangeConfiguration` | données de projet de l’IDE, voir plus bas |

Ce qu’il ne sait pas faire reçoit l’erreur -32601 (méthode introuvable), par exemple `textDocument/implementation` et
`textDocument/references`. Il n’y a pas de diagnostics de code (Error Insight reste vide) ni de transmission à
DelphiLSP.

## Appel

```
dpcc.LspServer.exe [--cache-root <dossier>] [--log-level debug|info|warning|error] [--no-log] [--version] [--help]
```

Les autres paramètres sont ignorés. Le serveur répond tout de suite à `initialize` et charge projet et index en
arrière-plan ; tant que l’index n’est pas prêt, les réponses sont vides ou incomplètes au lieu de l’attendre. Il se
termine après `exit` (notification ou requête avec id), à la fin de l’entrée ou quand le processus indiqué par
`processId` dans `initialize` se termine. Le dossier de travail ne joue aucun rôle.

L’EXE existe en Win32 et Win64 ; les deux servent Delphi 12 et Delphi 13. Elle ne dépend d’aucune BPL.

## Stockage

| Ordre | Emplacement |
|---|---|
| 1 | `--cache-root <dossier>` |
| 2 | variable d’environnement `DPCC_LSPSERVER_CACHE_ROOT` |
| 3 | `%LOCALAPPDATA%\dpcc.LspServer` |

On y trouve, comme pour le plugin, `Index\<version de Delphi>\…` (caches), `projektauswahl.json` et
`Logs\Diagnose` (journal de diagnostic anonyme), ainsi que le journal de l’EXE dans
`Logs\LspServer\lsp-<date>-<processus>.log` (un fichier par processus, supprimé après 14 jours). Le dossier du
plugin (`%LOCALAPPDATA%\dpcc`) n’est pas touché ; une variable `DPCC_CACHE_ROOT` ne vaut pas pour l’EXE. Les réglages
sont lus comme dans le plugin depuis `%APPDATA%\dpcc\settings.json` et `dpcc.json`, mais jamais écrits.

Le serveur écrit les caches dans un fichier intermédiaire puis le renomme ; un arrêt brutal (l’IDE termine le
processus après `shutdown` sans `exit`) ne laisse donc jamais de cache à moitié écrit.

## Données de projet de l’IDE

L’IDE annonce le projet actif par `workspace/didChangeConfiguration`. Le serveur en lit :

| Champ | Usage |
|---|---|
| `project` | fichier principal (.dpr/.dpk) ; le .dproj voisin devient espace de travail si les fichiers ouverts ne le donnent pas déjà |
| `dllname` | version de Delphi (`dcc32290.dll` → 23.0, `dcc32370.dll` → 37.0) et plateforme (`dcc32` Win32, `dcc64` Win64) |
| `dccOptions` | `-D` symboles, `-NS` espaces de noms, `-U` chemins : dans les dossiers d’installation ou Studio comme bibliothèque, sinon comme chemin de recherche du projet |
| `browsingPaths` | chemin de navigation de l’IDE (sources de la bibliothèque) |
| `CommonAppData` | profil de l’IDE (`bds -r`) dont le serveur lit variables et chemins |

Sans ces données (autres clients), le serveur déduit les projets des fichiers ouverts : le .dproj dans le dossier du
fichier ou au-dessus.

## Clients

Si le client se présente comme `RAD Studio` dans `initialize`, le serveur répond au format de l’IDE (texte entier à
chaque modification, complétion avec `kibitzkind` et `DCC_Flags`, aide aux paramètres avec `documentation`, survol
en texte brut) et n’envoie aucune notification propre. Tout autre client reçoit du LSP standard.

## Voir aussi

- [Architecture](architecture.md) : serveur, index et parcours d’une requête
- [Index et cache](index-cache.md)
