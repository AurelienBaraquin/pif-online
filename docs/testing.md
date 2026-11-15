# Tests

Comment le projet est vérifié, et comment lancer chaque test. Pour toute personne ou tout agent
qui modifie le code.

## Serveur

Tests Go en tables, à côté du code (`server/**/*_test.go`), dont un harnais de duel complet
(`server/internal/feature/duel/harness_test.go`).

```bash
cd server && go vet ./... && go test -race ./...
```

La CI de Release les relance avant de publier ([release.md](release.md)).

## Client, dans le vrai moteur

Il n'y a pas de Ruby dans WSL : le seul Ruby est celui du jeu (mkxp-z, Ruby 3.1). Les tests
copient le jeu dans un dossier de test Windows, y ajoutent la surcouche et un script de test,
lancent le jeu depuis WSL et lisent `test_result.txt` (`PASS` ou `FAIL`).

Prérequis : un clone du jeu à la version de `client/supported-game.json` (sinon le test refuse de
tourner), Go dans WSL, et un dossier de test sous `/mnt/c/...`.

`tools/engine-test/suite.sh` lance une catégorie et affiche la durée de chaque test :

| Catégorie | Tests | Durée mesurée | Quand |
|---|---|---|---|
| `quick` | `server`, `client`, `menu` | < 1 min | à chaque modification |
| `world` | `game`, `presence` | ~1 min | présence, apparence, cartes |
| `duel` | `interaction`, `network`, `rules`, `flip` | ~6 min | tout ce qui touche aux duels |
| `deep` | `battle`, `codec`, `robust`, `two` | ~25 min (estimé) | avant une Release |
| `all` | tout | | |

```bash
tools/engine-test/suite.sh quick <dossier-du-jeu> <dossier-windows-de-test>
```

Un test seul : `tools/engine-test/run.sh <test> <dossier-du-jeu> <dossier-windows-de-test>`. Un
verrou empêche deux tests de tourner en même temps : ils partagent le port du serveur et l'écran.

| Test | Fichier | Ce qu'il vérifie |
|---|---|---|
| `client` | `tools/engine-test/client_test.rb` | cœur du client et présence contre un vrai serveur (scripts empaquetés par `pack_scripts.py`) |
| `menu` | `tools/engine-test/menu_test.rb` | le menu Multiplayer, avec la vraie scène de pause |
| `game` | `tools/engine-test/game_test.rb` | le vrai jeu sur une nouvelle partie, un second client marche à côté |
| `presence` | `tools/engine-test/presence_test.rb` | deux vrais jeux se voient sur la même carte |
| `interaction` | `tools/engine-test/interaction_test.rb` | fenêtre d'interaction et combat, touches simulées |
| `network` | `tools/engine-test/network_duel_test.rb` | duels complets via le vrai serveur, dans un processus |
| `rules` | `tools/engine-test/rules_duel_test.rb` | chaque règle et clause de duel |
| `flip` | `tools/engine-test/display_flip_test.rb` | l'affichage miroir du côté 1 |
| `battle` | `tools/engine-test/battle_determinism_test.rb` | deux simulations du même duel restent identiques |
| `codec` | `tools/engine-test/party_codec_test.rb` | une équipe survit à l'aller-retour réseau, sur tout le Pokédex |
| `robust` | `tools/engine-test/duel_robustness_test.rb` | chaque fin de duel ferme le combat proprement |
| `two` | `tools/engine-test/two_process_duel_test.rb` | duels entre deux processus de jeu, sans désynchronisation |

`tools/engine-test/000_test_support.rb` est chargé avant chaque test : les tests utilisent un
dossier de sauvegarde isolé (`pif-online-test`), ce qui fait demander la langue au jeu ; ce
fichier y répond.

### Variables

| Variable | Rôle |
|---|---|
| `PIF_TEST_SAVES` | dossier avec `red.rxdata` et `blue.rxdata` : `presence` charge ces parties au lieu d'en créer |
| `PIF_TEST_ROLE` | rôle d'un processus dans les tests à deux jeux ; fixé par `run.sh`, pas à la main |

### Quand un test bloque sans résultat

Le jeu affiche souvent une boîte d'erreur native. Lister le texte des fenêtres du processus de
test (EnumWindows depuis PowerShell) plutôt que faire une capture d'écran : jamais de capture de
l'écran entier. Les journaux complets sont dans `<dossier-de-test>.<test>.log`.

## À la main, sans second PC

`tools/sandbox/two-games.sh` prépare deux copies jouables du jeu, chacune avec ses sauvegardes
(`%APPDATA%\pif-online-a` et `-b`), reliées à un serveur local :

```bash
tools/sandbox/two-games.sh setup <dossier-du-jeu> <dossier-windows> [sauvegarde-a] [sauvegarde-b]
tools/sandbox/two-games.sh update <dossier-windows>
tools/sandbox/two-games.sh start <dossier-windows>
tools/sandbox/two-games.sh stop <dossier-windows>
```

`stop` n'arrête que les processus lancés par `start`.

## Non testé

- Le duel entre deux PC réels, et `deploy/install-vps.sh` sur un vrai VPS.
- `client/installer/install.ps1` n'a pas de test automatique ; il a été vérifié à la main sur la
  Release v0.3.0.
