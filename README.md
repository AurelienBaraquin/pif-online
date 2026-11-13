# PIF Online

Surcouche multijoueur pour [Pokémon Infinite Fusion](https://github.com/infinitefusion/infinitefusion-hoenn-public) : monde partagé et duels entre joueurs. Le jeu lui-même n'est pas fourni ici.

Deux programmes : la surcouche à ajouter au jeu, et un serveur que l'un des joueurs héberge.

## Jouer

PIF Online est fait pour **Pokémon Infinite Fusion 2 (Hoenn) version 1.3.2**, la version du launcher officiel au 3 novembre 2026. Tous les joueurs doivent avoir cette version.

1. Installe ou mets à jour le jeu avec le launcher officiel, puis ferme le jeu.
2. Ouvre PowerShell (touche Windows, tape `PowerShell`, Entrée) et colle :

   ```powershell
   irm https://github.com/AurelienBaraquin/pif-online/releases/latest/download/install.ps1 | iex
   ```

   L'installeur trouve le jeu, vérifie sa version et que le jeu est fermé, télécharge PIF Online, contrôle son intégrité et l'installe. Relance la même commande pour mettre à jour. Si le jeu n'est pas trouvé, il demande son dossier (celui qui contient `InfiniteFusion2.exe`).
3. Lance le jeu, charge ta partie, ouvre le menu Pause, puis **Multiplayer > Add a server**, et tape l'adresse donnée par l'hébergeur.

Le jeu mémorise le serveur et s'y reconnecte au prochain chargement. **Disconnect** te ramène en solo.

Pour défier un joueur, place-toi face à lui et appuie sur la touche d'action.

## Héberger

### Sur un PC, en réseau local

Télécharge `pif-server-windows-amd64.exe` depuis la Release et lance-le. Accepte l'autorisation du pare-feu Windows. La fenêtre affiche les adresses à donner aux joueurs, et doit rester ouverte.

### Sur un VPS Linux, pour jouer à distance

```bash
curl -fsSL https://raw.githubusercontent.com/AurelienBaraquin/pif-online/main/deploy/install-vps.sh | sudo bash
```

Le serveur démarre avec la machine. Les joueurs utilisent l'adresse IP publique du VPS ou son nom de domaine. Si ton hébergeur a son propre pare-feu, ouvre le port TCP 7777. Relance la même commande pour mettre à jour.

Pour héberger chez toi sans VPS, redirige le port TCP 7777 de ta box vers le PC qui lance le serveur.

Le serveur n'a pas de mot de passe et le trafic n'est pas chiffré : ne donne l'adresse qu'à des gens de confiance.

## En cas de problème

Le fichier `multiplayer.log`, à côté de l'exécutable du jeu, détaille les erreurs de connexion.

## Développement

Le protocole est décrit dans [protocol/PROTOCOL.md](protocol/PROTOCOL.md). La version du jeu supportée est fixée dans [client/supported-game.json](client/supported-game.json) : l'installeur et les tests la vérifient. Un tag `v*` construit et publie une Release.

```bash
cd server && go test -race ./...
```

Les tests du client tournent dans le moteur du jeu : voir `tools/engine-test/run.sh`.
