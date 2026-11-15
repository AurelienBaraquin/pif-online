# Configuration et fichiers du client

Ce que la surcouche lit et écrit sur la machine du joueur, et comment le serveur se configure.
Pour qui diagnostique une installation ou modifie la configuration.

## Côté joueur

Les deux fichiers sont dans le dossier de travail du jeu, celui de `InfiniteFusion2.exe` quand le
jeu est lancé normalement (chemins relatifs dans le code). Le joueur n'a jamais à les éditer : tout passe par le menu Pause >
Multiplayer.

| Fichier | Rôle | Source |
|---|---|---|
| `multiplayer.json` | serveurs enregistrés et serveur actif | `client/998_Multiplayer/core/001_config.rb` |
| `multiplayer.log` | erreurs de connexion et points d'accroche désactivés | `client/998_Multiplayer/core/002_log.rb` |

Format de `multiplayer.json` :

```json
{"servers": [{"host": "10.0.0.2", "port": 7777}], "active": {"host": "10.0.0.2", "port": 7777}}
```

- `active` vaut `null` après **Disconnect** : la surcouche reste hors ligne et le jeu solo est
  inchangé.
- Fichier absent ou invalide : lu comme une liste vide, l'erreur va dans `multiplayer.log`.
- Écriture atomique (fichier temporaire puis renommage).
- Une adresse saisie est `hôte` ou `hôte:port` ; le port par défaut est 7777.

Les sauvegardes du jeu ne sont pas touchées par la surcouche. Elles sont dans
`%APPDATA%\<dataPathApp de mkxp.json, ou titre de Game.ini>` ; les tests et la sandbox
changent `dataPathApp` pour ne jamais écrire dans celles du joueur.

## Constantes partagées

| Constante | Client | Serveur |
|---|---|---|
| Version du protocole (6) | `PROTOCOL_VERSION`, `core/001_config.rb` | `Version`, `server/internal/protocol/protocol.go` |
| Port par défaut (7777) | `DEFAULT_PORT`, `core/001_config.rb` | option `-addr`, `server/cmd/pif-server/main.go` |
| Jeu supporté | `client/supported-game.json` | — |

## Côté serveur

Une seule option : `-addr` (défaut `:7777`). Les limites (sessions, délais, débit) sont des
constantes de `session.DefaultConfig()` dans `server/internal/session/hub.go`. Les variables
d'environnement des scripts d'installation sont listées dans [release.md](release.md), celles des
tests dans [testing.md](testing.md).
