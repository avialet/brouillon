<div align="center">

# Brouillon

**Le bloc-notes qui comprend ce que vous y collez.**

[![Dernière version](https://img.shields.io/github/v/release/avialet/brouillon?color=8B78E6&label=version)](https://github.com/avialet/brouillon/releases/latest)
[![macOS 26](https://img.shields.io/badge/macOS-26%20Tahoe-F0A020)](#installation)
[![Licence MIT](https://img.shields.io/badge/licence-MIT-2E9D6E)](LICENSE)

[**Télécharger le DMG**](https://github.com/avialet/brouillon/releases/latest) · [Site](https://brouillon.vialet.app)

</div>

## Ce que fait Brouillon

<!-- a adapter : trois idees, une phrase chacune -->

- **Première idée.** Une phrase.
- **Deuxième idée.** Une phrase.
- **Rester chez vous.** Tout est stocké sur votre Mac. Aucun compte, aucun serveur, aucune télémétrie.

## Installation

**Prérequis :** un Mac Apple Silicon sous macOS 26 (Tahoe) ou plus récent.

1. Téléchargez `Brouillon-X.Y.Z.dmg` depuis la [dernière version](https://github.com/avialet/brouillon/releases/latest).
2. Ouvrez le DMG et glissez **Brouillon** dans **Applications**, puis double-cliquez.
3. Au premier lancement, macOS indique qu'il n'a pas pu vérifier l'app (elle est signée
   sans certificat Apple Developer). Cliquez **Terminé** (pas « Placer dans la corbeille »),
   ouvrez **Réglages Système › Confidentialité et sécurité**, descendez jusqu'à
   « Brouillon a été bloqué… », cliquez **Ouvrir quand même**, authentifiez-vous, puis **Ouvrir**.
   Cette étape n'a lieu qu'une fois par téléchargement. Dans le Terminal :

   ```bash
   xattr -d com.apple.quarantine /Applications/Brouillon.app
   ```

Pour vérifier le fichier téléchargé, comparez son empreinte avec celle publiée dans la même version :

```bash
shasum -a 256 -c Brouillon-X.Y.Z.dmg.sha256
```

### Mises à jour

Brouillon consulte une fois par jour la dernière version publiée sur GitHub. S'il en
existe une plus récente, un clic la télécharge, **vérifie son empreinte SHA-256**, contrôle
l'application qu'elle contient, la remplace et relance l'app. Si une étape échoue, l'app
installée n'est pas touchée. La recherche automatique se désactive dans **Réglages › Mises à jour**.

Le seul échange réseau de Brouillon est cette lecture de la version publiée. Aucune donnée n'est envoyée.

## Notice

<!-- a adapter -->

- **Raccourci global** (⇧⌘Espace par défaut, modifiable dans les Réglages) : affiche ou masque Brouillon depuis n'importe quelle app.
- Fermer la fenêtre ne quitte pas l'app : le raccourci et l'icône de la barre des menus restent actifs. **⌘Q** quitte vraiment.
- Le lien `brouillon://` ouvre la fenêtre principale.

### Vos données

```text
~/Library/Application Support/Brouillon/brouillon.sqlite
```

Pour sauvegarder, copiez ce dossier. Pour repartir de zéro, quittez l'app et supprimez-le.

## Compiler depuis les sources

Il faut Swift 6.3 ou plus récent (les Command Line Tools suffisent, Xcode n'est pas nécessaire).

```bash
git clone https://github.com/avialet/brouillon.git
cd brouillon
make test      # tests du noyau
make run       # construit et lance l'app
make install   # installe dans /Applications
make release   # fabrique build/Brouillon-X.Y.Z.dmg et son empreinte
```

| Dossier | Contenu |
|---|---|
| `Packages/BrouillonCore` | Noyau sans interface : modèles, base SQLite ([GRDB](https://github.com/groue/GRDB.swift)), logique |
| `Brouillon` | L'application SwiftUI ; `App/Brand.swift` porte son identité |
| `scripts` | Assemblage de l'app, du DMG et de l'icône |
| `docs` | [Publier une version](docs/publier-une-version.md), [tests](docs/tests.md), notes de version |

Le socle commun (mises à jour, thème, raccourci global, panneau flottant) vient de
[VialetKit](https://github.com/avialet/vialetkit). Publier une version ne demande que de
modifier `VERSION` puis de pousser un tag `vX.Y.Z` : la CI construit et publie le DMG, et
les utilisateurs reçoivent la mise à jour dans l'app.

## Confidentialité

Brouillon ne collecte rien. Vos données ne quittent jamais votre Mac. La seule requête
réseau est la lecture de la dernière version publiée sur GitHub, que vous pouvez désactiver.

## Licence

[MIT](LICENSE) © 2026 Aurélien Vialet
