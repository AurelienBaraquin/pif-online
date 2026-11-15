# Index de la documentation

Chaque surface du projet — tout ce qu'il faut savoir pour le construire, le lancer, le tester, le
publier, l'exploiter ou l'utiliser — a un document, listé ici. Un document est mis à jour dans le
même changement que ce qu'il couvre. Ce que chaque type de document doit contenir est décrit par
le skill `project-sync` (`doc-surfaces.md`).

La colonne **Covers** liste, entre backticks, les chemins qu'un document décrit. Le contrôle
(`scripts/check-docs.mjs`) s'en sert : un dossier de premier niveau, un pipeline de CI ou un
contrat d'API qu'aucun document ne couvre est une erreur, et un document dont les chemins changent
souvent sans lui est signalé comme peut-être périmé.

| Document | Ce qu'il répond | Covers | Mettre à jour quand |
|---|---|---|---|
| [brief.md](brief.md) | Quoi construire et pourquoi : objectif, périmètre, priorités, critères de réussite | l'intention du projet | le périmètre, les priorités ou les critères changent |
| [architecture.md](architecture.md) | Comment le code est organisé et comment ses parties s'emboîtent | `client/998_Multiplayer/` `server/` `tools/` | un module, dossier, flux ou convention est ajouté, déplacé ou retiré |
| [PROTOCOL.md](../protocol/PROTOCOL.md) | Les messages entre client et serveur, leurs champs et leurs erreurs | `protocol/` `server/internal/protocol/` | un message, champ, code d'erreur ou la version du protocole change |
| [testing.md](testing.md) | Les tests, ce qu'ils couvrent et comment les lancer ; la sandbox à deux jeux | `tools/engine-test/` `tools/sandbox/` | un test, une catégorie, une variable ou la sandbox change |
| [release.md](release.md) | CI, Release, installeurs, déploiement du serveur | `.github/workflows/release.yml` `tools/release/` `deploy/` `client/installer/` `client/supported-game.json` | un workflow, un fichier de Release, un installeur ou le déploiement change |
| [configuration.md](configuration.md) | Fichiers lus et écrits chez le joueur, constantes partagées, options du serveur | `client/998_Multiplayer/core/001_config.rb` `server/cmd/pif-server/` | un fichier, une option ou une constante partagée change |
| [technologies.md](technologies.md) | Le moteur du jeu, Go, WSL, GitHub : usage et pièges | `server/go.mod` | une technologie est ajoutée, remplacée ou un piège découvert |
| [README.md](../README.md) | Guide des joueurs et des hébergeurs (français) | l'usage du jeu et du serveur | un comportement visible par le joueur ou l'hébergeur change |
| [CLAUDE.md](../CLAUDE.md) | Règles de travail des agents | `.claude/` `.githooks/` | une règle de travail ou un hook change |
| [adr/](adr/) | Pourquoi les choix structurants ont été faits | décisions | une décision structurante est prise ou annulée |
| [decisions-log.md](../.assistant/decisions-log.md) | Les choix plus petits et leurs raisons | `.assistant/` | un choix plus petit est fait |
| [lessons.md](../.assistant/lessons.md) | Les erreurs déjà faites et ce qui les empêche | leçons | une revue, la CI ou le propriétaire attrape une erreur |
| [README.md](README.md) | Cet index et l'outillage de documentation | `scripts/check-docs.mjs` `.github/workflows/docs-check.yml` | le contrôle de doc ou son workflow change |
