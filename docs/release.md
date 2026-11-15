# Release, CI et déploiement

Comment une version est publiée, ce que fait la CI, et comment le serveur est déployé. Pour qui
publie une version ou héberge un serveur. Les instructions destinées aux joueurs sont dans le
[README](../README.md).

## Versions

- Tags `vMAJEUR.MINEUR.CORRECTIF` annotés (`git tag -a v0.4.0 -m "..."`) : un tag léger est
  refusé ici.
- La version du protocole (`protocol/PROTOCOL.md`) est indépendante de celle des Releases ; tous
  les joueurs d'un serveur doivent avoir la même.
- Le jeu supporté est fixé dans `client/supported-game.json` ([ADR-0001](adr/0001-une-seule-version-du-jeu.md)).

## Pipelines

| Workflow | Déclencheur | Étapes |
|---|---|---|
| `.github/workflows/release.yml` | push d'un tag `v*` | `go test -race`, `tools/release/build.sh dist`, `gh release create` avec tous les fichiers |
| `.github/workflows/docs-check.yml` | chaque push sur `main` et chaque PR | `node scripts/check-docs.mjs` |

La CI n'a pas le jeu : les tests du client ([testing.md](testing.md)) se lancent en local avant
le tag, catégorie `deep` comprise. Seul secret utilisé : le `GITHUB_TOKEN` fourni par GitHub.

## Fichiers d'une Release

`tools/release/build.sh <dossier>` produit, et la CI publie :

| Fichier | Contenu |
|---|---|
| `PIF-Online-Client.zip` | `Data/Scripts/998_Multiplayer`, fichiers suivis par git uniquement |
| `pif-server-windows-amd64.exe`, `pif-server-linux-amd64`, `pif-server-linux-arm64` | le serveur |
| `install.ps1`, `supported-game.json` | l'installeur et la version du jeu qu'il exige |
| `SHA256SUMS` | sommes de contrôle, vérifiées par les deux installeurs |

## Installeur du client

`client/installer/install.ps1`, lancé par `irm .../releases/latest/download/install.ps1 | iex` :
trouve le jeu (config du launcher `%APPDATA%\infinitefusion_common\launcher_config.json`, puis
dossiers courants, sinon demande), vérifie `HOENN_VERSION_NUMBER` contre
`supported-game.json`, vérifie que cette copie du jeu est fermée et que le dossier est
inscriptible, contrôle le SHA256 puis remplace `Data/Scripts/998_Multiplayer`.

| Variable | Rôle |
|---|---|
| `PIF_GAME_DIR` | dossier du jeu, quand il n'est pas trouvé automatiquement |
| `PIF_RELEASE_URL` | autre adresse de téléchargement (autre version, miroir) |

## Serveur

```bash
pif-server -addr :7777    # adresse TCP d'écoute, :7777 par défaut
```

Au démarrage, il affiche la version du protocole et les adresses IPv4 privées à donner aux
joueurs. Sous Windows, une erreur de démarrage attend Entrée avant de fermer la fenêtre.

### Sur un VPS

`deploy/install-vps.sh` (root) télécharge le binaire de la dernière Release pour l'architecture
de la machine, vérifie son SHA256, installe un service systemd `pif-server` (utilisateur
dynamique, durci) et ouvre le port avec ufw s'il est présent. `PIF_PORT` choisit le port (7777 par
défaut). Relancer le script met à jour.

Journaux : `journalctl -u pif-server`. Pas d'état persistant : un redémarrage déconnecte les
joueurs, qui se reconnectent seuls.

### Limites de sécurité

Pas de mot de passe ni de chiffrement : quiconque connaît l'adresse peut se connecter. Le serveur
borne les sessions (256 par défaut), la taille des lignes (16 Kio) et le débit de messages par
client, et valide chaque message.
