# ADR-0003 — Deux programmes, connexion choisie depuis le jeu, installeur en une commande

- **Status**: Accepted
- **Date**: 2026-11-13
- **Deciders**: le propriétaire du projet
- **Supersedes**: none

## Context

Enregistré rétroactivement le 2026-11-15, à partir de la session de travail du 2026-11-13.

Jusque-là, jouer demandait de copier des fichiers et d'éditer une configuration à la main. Le
propriétaire voulait que tout soit accessible depuis le jeu et que l'installation vérifie tout,
sur une machine où le jeu a été installé par le launcher officiel.

## Options considered

1. **Configuration par fichier** (adresse du serveur dans un fichier à éditer) — simple à coder ;
   source d'erreurs pour les joueurs.
2. **Menu dans le jeu + installeur automatique** — plus de code ; aucun fichier à éditer.

## Decision

Option 2. Deux programmes : la surcouche dans le jeu et un serveur autonome (exécutable Windows
pour le réseau local, script systemd pour un VPS). Le joueur ajoute et rejoint un serveur depuis
Pause > Multiplayer ; le choix est gardé dans `multiplayer.json`. L'installeur
(`client/installer/install.ps1`) trouve le jeu, vérifie version, fermeture, droits d'écriture et
SHA256, puis remplace le dossier de la surcouche. Dépôt public, pour que l'installeur et le
script VPS téléchargent depuis les Releases.

## Consequences

- Positive : installation et mise à jour en une commande, sans édition manuelle.
- Négative : l'installeur est du PowerShell sans test automatique ; Windows seulement côté
  joueur.
- Suite : le menu doit refuser de quitter un serveur pendant un défi (`can_leave?`).
