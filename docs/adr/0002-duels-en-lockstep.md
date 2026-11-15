# ADR-0002 — Duels simulés sur les deux clients, indices canoniques

- **Status**: Accepted
- **Date**: 2026-11-09
- **Deciders**: le propriétaire du projet, sur la base des mesures du banc d'essai
- **Supersedes**: none

## Context

Enregistré rétroactivement le 2026-11-15, à partir de la session de travail et des mesures du
2026-11-09.

Le moteur de combat du jeu est en Ruby, dans le client. Le serveur est en Go et ne peut pas le
faire tourner. Il faut que les deux joueurs voient le même combat, chacun de son côté de l'écran.

## Options considered

1. **Serveur autoritaire** — réécrire le moteur de combat en Go : énorme, et diverge à chaque
   mise à jour du jeu.
2. **Lockstep, indices miroirs** — chaque client se met en position 0 : mesuré divergent (par
   exemple, Forewarn ne tire au hasard que pour l'indice 0).
3. **Lockstep, `pbOwnedByPlayer?` inversé** pour le joueur B — mesuré divergent aussi.
4. **Lockstep, indices canoniques** — les deux clients simulent avec les mêmes indices (le
   challenger est le côté 0) ; seul l'affichage est inversé pour le côté 1.

## Decision

Option 4 : 0 duel divergent sur 197 au banc d'essai, contre des divergences pour 2 et 3. Les deux
clients partagent une graine ; le serveur ordonne les tours, révèle les choix quand les deux sont
arrivés et compare les empreintes d'état. Le tirage de la Patte de Mankey, qui contourne
`pbRandom`, passe par le générateur du duel (`DuelRandom`).

## Consequences

- Positive : le moteur du jeu reste la seule vérité ; pas de règles de combat dupliquées.
- Négative : tout code qui dessine ou formule le combat doit savoir inverser les côtés
  (`client/998_Multiplayer/game_hooks/duel/009_side_one_display.rb`), et rien dans ce fichier ne
  doit changer ce que la simulation lit. Un aléa hors `pbRandom` désynchronise.
- Suite : les tests `battle` et `two` ([testing.md](../testing.md)) gardent la garantie.
