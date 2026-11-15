# Technologies

Les briques que le code ne laisse pas deviner, et leurs pièges. Pour quiconque modifie le client
ou le serveur.

## Moteur du jeu : mkxp-z, Ruby 3.1, Pokémon Essentials v19

- **Usage** : le client tourne dans le jeu ; il n'existe pas d'autre Ruby pour le lancer.
- **Code du jeu** : [infinitefusion-hoenn-public](https://github.com/infinitefusion/infinitefusion-hoenn-public),
  branche `releases` du launcher officiel, à la version de `client/supported-game.json`.
- **Chargement** : tous les fichiers de `Data/Scripts` sont exécutés, ceux d'un dossier avant ses
  sous-dossiers, par ordre alphabétique. Tout fichier déposé là est exécuté : ne jamais lancer un
  outil depuis `Data/Scripts` d'une copie du jeu (les hooks de Claude Code y créent
  `.claude-flow/`). La Release n'empaquette que les fichiers suivis par git.
- **F12** réévalue tous les scripts dans le même processus, mais l'objet `Graphics` survit : un
  alias posé dessus doit être protégé contre une double pose (`hook_graphics_update`).

Pièges vérifiés dans le moteur :

| Piège | Conséquence |
|---|---|
| pas de `require "json"` | utiliser `HTTPLite::JSON` ; il lit tous les nombres en `Float` et indente en écrivant |
| `MKXPError` n'hérite pas de `StandardError` | `Guard::RECOVERABLE` l'attrape explicitement |
| pas de `Socket.tcp` | `TCPSocket.new(host, port, connect_timeout:)` fonctionne |
| `PBDebug.logonerr` avale les erreurs de combat | un duel en réseau doit s'interrompre sur toute exception (`DuelRunner::ErrorPassthrough`) |
| `Settings` dans `module Multiplayer` est celui de la surcouche | le `Settings` du jeu s'écrit `::Settings` |
| sans sauvegarde, le jeu demande la langue | les tests y répondent (`tools/engine-test/000_test_support.rb`) |

## Go

- **Usage** : le serveur, sans dépendance hors bibliothèque standard (`server/go.mod`).
- Compilé statiquement (`CGO_ENABLED=0`) pour Windows et Linux par `tools/release/build.sh`.

## Windows depuis WSL

- **Usage** : les tests et la sandbox lancent l'exécutable Windows du jeu depuis WSL (via
  `powershell.exe`) ; le dossier de test doit donc être sous `/mnt/c/`.
- Le serveur de test est compilé dans WSL et le jeu s'y connecte en local.

## GitHub Releases et Actions

- **Usage** : distribution du client et du serveur ; voir [release.md](release.md).
