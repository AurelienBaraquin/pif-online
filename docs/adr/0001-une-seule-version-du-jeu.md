# ADR-0001 — Une seule version du jeu supportée, fixée par la Release

- **Status**: Accepted
- **Date**: 2026-11-13
- **Deciders**: le propriétaire du projet
- **Supersedes**: none

## Context

Enregistré rétroactivement le 2026-11-15, à partir de la session de travail du 2026-11-13.

Les duels simulent le même combat sur deux jeux : deux versions différentes du code ou des données
divergent. Le dépôt public du jeu a une branche `main` en avance sur la branche `releases`, que
le launcher officiel installe (1.3.2 au 2026-11-13). Les tests tournaient alors sur `main`.

## Options considered

1. **Suivre `main`** — dernières nouveautés ; mais aucun joueur ne l'a, et la cible bouge.
2. **Supporter plusieurs versions** — plus de joueurs ; mais chaque version multiplie les tests
   et les cas de désynchronisation.
3. **Une seule version, la plus récente du launcher, fixée par la Release** — ce que les joueurs
   ont réellement ; une cible stable.

## Decision

Option 3, choisie par le propriétaire : `client/supported-game.json` fixe titre, version et commit
(1.3.2, `0434bbfd`). L'installeur refuse une autre version, les tests aussi. Le serveur refuse les
duels entre deux empreintes de jeu différentes (`core/006_game_build.rb`, raison `game_version`).
Gérer des versions plus récentes viendra plus tard.

## Consequences

- Positive : un seul jeu à tester ; les désynchronisations dues aux versions sont exclues.
- Négative : à chaque mise à jour du launcher, il faut une nouvelle Release pour que les joueurs
  mis à jour puissent réinstaller.
- Suite : passer à une nouvelle version = changer `supported-game.json`, relancer toute la suite
  de tests (`deep` comprise) sur cette version, puis publier.
