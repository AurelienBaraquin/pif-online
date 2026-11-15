# État du projet au 2026-11-15

Photo du projet le jour où sa documentation pour agents a été mise en place. Ce fichier **n'est
pas maintenu** : supprimer un point quand il est réglé ou déplacé dans une issue, et le fichier
quand il est vide.

## Pourquoi

Le propriétaire veut que d'autres agents puissent travailler sur le projet sans le contexte des
sessions précédentes.

## État de santé

| Vérification | Commande | Résultat |
|---|---|---|
| Serveur | `cd server && go vet ./... && go test -race ./...` | passe (2026-11-15) |
| Client, catégorie quick | `tools/engine-test/suite.sh quick <jeu> <test>` | passe : server 1 s, client 9 s, menu 24 s (2026-11-15) |
| Client, world et duel | `tools/engine-test/suite.sh world ... et duel ...` | passent (2026-11-15, avant la v0.3.0) |
| Client, deep | `tools/engine-test/suite.sh deep ...` | `battle` et `codec` passent depuis les derniers changements ; `robust` et `two` passaient le 2026-11-13 et n'ont pas été relancés |
| Documentation | `node scripts/check-docs.mjs` | passe |

## Risques et dette

- L'exclusion de `DownloadedSettings.rb` de l'empreinte n'a pas de test — preuve :
  `tools/engine-test/client_test.rb` ne vérifie que le format.
- L'installeur PowerShell n'a pas de test automatique — preuve : `client/installer/install.ps1`.

## Inconnues

- Pourquoi un joueur sur un second PC n'a pas vu le premier (2026-11-13) ; le
  `multiplayer.log` de ce PC n'a jamais été récupéré.
- Duel réel entre deux PC, et `deploy/install-vps.sh` sur un vrai VPS : jamais essayés.

## Premiers pas suggérés

1. Relancer `suite.sh deep` pour confirmer `robust` et `two` sur la v0.3.0.
2. Quand le second PC est disponible : récupérer son `multiplayer.log`, puis faire un vrai duel
   entre deux PC.
