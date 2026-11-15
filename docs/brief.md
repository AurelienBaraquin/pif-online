# Brief

Ce que le projet doit être : l'intention du propriétaire, et la source de vérité sur *quoi*
construire. `CLAUDE.md` dit comment travailler, [architecture.md](architecture.md) comment c'est
construit, ce fichier dit pour quoi.

Changer le périmètre, les priorités ou les critères de réussite est une décision : mettre à jour
ce fichier et l'enregistrer avec le skill `adr-new`. Jamais en silence.

## Objectif

Jouer à Pokémon Infinite Fusion à plusieurs : voir les autres joueurs se déplacer dans le même
monde et les affronter en duel, sans modifier le jeu de base ni sa partie solo.

## Utilisateurs

- **Joueurs** : installent la surcouche avec une seule commande, puis choisissent le serveur
  depuis le menu Pause du jeu. Aucun fichier à éditer à la main.
- **Hébergeurs** : lancent le serveur sur leur PC (réseau local) ou sur un VPS (Internet).

## Périmètre

Dans le périmètre :

- Monde partagé : les joueurs connectés se voient sur la même carte, avec leur apparence.
- Duels entre joueurs : simples et doubles, règles et clauses choisies par le challenger.
- Installation automatique qui trouve le jeu et vérifie sa version, et serveur facile à héberger.
- Une seule version du jeu supportée à la fois : Infinite Fusion 2 (Hoenn) 1.3.2
  ([ADR-0001](adr/0001-une-seule-version-du-jeu.md)).

Plus tard, pas encore commencé : discussion entre joueurs, échanges de Pokémon, versions du jeu
plus récentes.

## Priorités

1. Ne jamais casser la partie solo du joueur : une erreur de la surcouche coûte une
   fonctionnalité, jamais la session.
2. Duels sans désynchronisation entre les deux jeux.
3. Code propre, maintenable et extensible : ajouter une fonctionnalité, un format ou une clause
   tient en une entrée.
4. Simplicité d'installation et d'hébergement.

## Critères de réussite

- Deux joueurs sur deux PC se voient et finissent un duel sans désynchronisation.
- Un joueur installe et rejoint un serveur sans aide, en suivant le `README.md`.

## Contraintes

- Le moteur du jeu (mkxp-z, Ruby 3.1, Pokémon Essentials v19) est la seule cible du client ; il
  tourne sous Windows.
- Dépôt public : aucune donnée personnelle ni sauvegarde de joueur dans le dépôt.

## Questions ouvertes

- Ordre des prochaines fonctionnalités (discussion, échanges, nouvelles versions du jeu) — le
  propriétaire.
