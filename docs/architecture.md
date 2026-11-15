# Architecture

Comment le code est organisé et comment ses parties s'emboîtent. Le *pourquoi* des choix est dans
[`adr/`](adr/) ; cette page décrit **ce qui existe maintenant**. Tout chemin cité doit exister
(vérifié par `scripts/check-docs.mjs`).

## 1. Organisation

```
client/                 la surcouche Ruby copiée dans Data/Scripts du jeu
  998_Multiplayer/
    core/               session réseau, configuration, journal ; indépendant du moteur
    features/           logique des fonctionnalités (présence, duel) ; indépendante du moteur
    game_hooks/         tout ce qui touche aux classes du jeu ; z_install/ branche le reste
  installer/            install.ps1, l'installeur Windows en une commande
  supported-game.json   la seule version du jeu supportée (titre, version, commit)
server/                 le serveur Go (module github.com/AurelienBaraquin/pif-online/server)
  cmd/pif-server/       l'exécutable : écoute, affiche les adresses à donner aux joueurs
  internal/transport/   lignes JSON sur TCP, file d'envoi bornée par connexion
  internal/session/     sessions, poignée de main, routage des messages vers les features
  internal/protocol/    types des messages, validation, clauses de duel
  internal/room/        index des abonnés de chaque carte
  internal/feature/     presence/ et duel/, une feature par dossier
protocol/PROTOCOL.md    le contrat entre client et serveur (version 6)
deploy/install-vps.sh   installation du serveur sur un Linux avec systemd
tools/
  engine-test/          tests du client dans le vrai moteur, lancés depuis WSL
  release/build.sh      construit tous les fichiers d'une Release
  sandbox/two-games.sh  deux copies jouables du jeu sur un seul PC
scripts/check-docs.mjs  contrôle de la documentation
```

## 2. Client

Le moteur (mkxp-z) charge tous les fichiers de `Data/Scripts`, ceux d'un dossier avant ses
sous-dossiers, dans l'ordre alphabétique : d'où les préfixes numériques, et `z_install/` qui doit
passer en dernier.

- **Couches.** `core/` et `features/` n'appellent jamais le jeu ; `game_hooks/` est le seul code
  qui dépend de ses classes. `game_hooks/001_engine_contract.rb` liste chaque méthode du jeu
  utilisée : si une manque, la surcouche se désactive au démarrage au lieu de planter plus tard.
- **Connexion.** `core/003_connection.rb` possède le socket dans un thread et se reconnecte
  seule ; le thread du jeu n'échange que des lignes via deux files. `core/004_client.rb` fait la
  poignée de main (`hello` avec la version du protocole et l'empreinte du jeu de
  `core/006_game_build.rb`) et distribue les messages aux features abonnées.
- **Features.** Chaque feature s'enregistre avec `Runtime.register_feature` et reçoit le client
  quand une session démarre (`core/005_runtime.rb`). La session démarre au chargement d'une
  partie si un serveur actif est enregistré dans `multiplayer.json`, à côté de l'exécutable.
- **Protection du joueur.** `Guard.run(site)` (`core/002_log.rb`) attrape toute erreur d'un point
  d'accroche, l'écrit dans `multiplayer.log` et désactive ce seul point.
- **Présence.** `features/presence/` publie la position du joueur local et suit les autres ;
  `game_hooks/presence/` les dessine comme des personnages qui ne déclenchent aucun événement.
- **Duels.** `features/duel/` mène le défi jusqu'au combat ; `game_hooks/duel/` affiche les menus
  et lance le combat. Le duel s'enregistre dans `game_hooks/duel/001_duel_party.rb`, car sa source
  d'équipe dépend du jeu ; la fenêtre d'interaction entre joueurs
  (`game_hooks/duel/003_interaction_menu.rb`) est aussi rangée là. Les deux jeux simulent le même combat avec la même graine et les mêmes
  indices de combattants ; le joueur du côté 1 voit une image miroir
  (`game_hooks/duel/009_side_one_display.rb`). Voir [ADR-0002](adr/0002-duels-en-lockstep.md).
- **Menu.** `game_hooks/menu/` ajoute l'entrée Multiplayer du menu Pause : ajouter, rejoindre,
  retirer un serveur, se déconnecter.

## 3. Serveur

Un seul goroutine (le hub, `internal/session/hub.go`) exécute toute la logique de jeu : les
features n'ont besoin d'aucun verrou. Chaque connexion a un goroutine de lecture qui publie des
événements vers le hub, et un écrivain qui ne bloque jamais le hub ; un client trop lent est
déconnecté. Une feature implémente `session.Feature` (ses handlers par type de message) et,
au besoin, `session.Ticker`. `cmd/pif-server/main.go` les assemble : `presence.New()` et
`duel.New(...)`.

Le serveur arbitre les duels sans les simuler : il ordonne le déroulement, révèle les choix d'un
tour quand les deux sont arrivés, compare les empreintes d'état envoyées par les clients et
tranche les abandons et les délais.

## 4. Conventions en place

- **Ajouter un élément tient en une entrée** : un format de duel (`Duel::FORMATS` et
  `formatSideSizes`), une clause (`DuelClauses::ALL` et `duelClauses`), une option du menu
  d'interaction (`InteractionMenu.options`), une feature (un appel à `register_feature` côté
  client, un argument de `NewHub` côté serveur).
- **Constantes jumelles** : `PROTOCOL_VERSION` (`core/001_config.rb`) et `protocol.Version` doivent
  rester égales ; le protocole est décrit dans `protocol/PROTOCOL.md`, mis à jour dans le même
  changement.
- **Données reçues = non fiables** : le serveur valide chaque message
  (`internal/protocol/`), le client revalide ce qui vient d'un autre joueur
  (`game_hooks/battle/001_party_codec.rb`, `DuelLook`).
- **Immutabilité côté client** : la configuration (`ServerBook`) renvoie un nouvel objet à chaque
  changement.
- Dans `module Multiplayer`, `Settings` désigne le module de la surcouche : le `Settings` du jeu
  s'écrit `::Settings`.
- Commentaires en anglais, qui expliquent le *pourquoi* ; tests Go en tables, à côté du code.

## 5. Ajouter une fonctionnalité réseau

1. **Protocole** : décrire les messages dans `protocol/PROTOCOL.md`. Le serveur déconnecte un
   client qui envoie un type inconnu (`dispatch`, `server/internal/session/hub.go`) : un nouveau
   message client vers serveur casse la compatibilité, donc incrémenter la version des deux côtés.
2. **Serveur** : types et validation dans `server/internal/protocol/`, la feature dans
   `server/internal/feature/<nom>/` (implémente `session.Feature`), branchée dans
   `server/cmd/pif-server/main.go`. Deux features qui gèrent le même type font paniquer `NewHub`.
3. **Client** : la logique dans `features/<nom>/`, sans appel au jeu : le test `client` empaquette
   `core/` et `features/` seuls (`tools/engine-test/run.sh`). L'affichage et l'enregistrement
   (`Runtime.register_feature`) dans `game_hooks/<nom>/`, chaque point d'accroche dans `Guard.run`,
   et chaque méthode du jeu utilisée ajoutée à `game_hooks/001_engine_contract.rb`.
4. **Tests et docs** : tests Go en tables, un test moteur dans `tools/engine-test/` rangé dans une
   catégorie de `suite.sh`, puis [testing.md](testing.md), cette page et un ADR si le choix est
   structurant. Tout ce qui modifie la sauvegarde du joueur demande une attention particulière
   (priorité 1 du [brief](brief.md)).

## 6. Décisions

Voir [`adr/`](adr/) et [`decisions-log.md`](../.assistant/decisions-log.md).
