# Scan Tickets

Application iPhone et Android : photographiez vos tickets, l'app lit le montant, la date et le commerçant, puis remplit votre note de frais Excel.

- `ios/` : app iPhone (SwiftUI)
- `android/` : app Android (Kotlin, Jetpack Compose)
- `.github/workflows/build.yml` : fabrication automatique des deux apps à chaque modification
- `sidestore/source.json` : source SideStore, mise à jour automatiquement

## Comment fonctionnent les mises à jour

1. Une modification du code arrive sur GitHub (branche `main`).
2. GitHub Actions compile l'app iPhone (`ScanTickets.ipa`) sur un Mac, et l'app Android (`ScanTickets.apk`).
3. Une nouvelle **version** est publiée (onglet *Releases*) avec les deux fichiers.
4. La source SideStore est mise à jour : l'iPhone propose la mise à jour dans SideStore. Côté Android, Obtainium la propose aussi.

Chaque version est numérotée automatiquement : 1.0.1, 1.0.2, etc.

## Mise en place (une seule fois)

### 1. Secrets pour l'app Android

L'APK doit toujours être signé avec la même clé, sinon Android refuse les mises à jour.
Dans le dépôt GitHub, va dans **Settings › Secrets and variables › Actions › New repository secret** et crée ces deux secrets :

| Nom | Valeur |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | le contenu du fichier `keystore_base64.txt` |
| `ANDROID_KEYSTORE_PASSWORD` | le contenu du fichier `password.txt` |

Ces deux fichiers sont fournis à part. **Ne les mets jamais dans le dépôt**, et garde-les en lieu sûr.

### 2. Lancer la première fabrication

Onglet **Actions › Construire et publier › Run workflow**. Compte environ 10 minutes.

### 3. iPhone : ajouter la source dans SideStore

1. Dans SideStore, ouvre l'onglet **Sources** et touche **+**.
2. Colle l'adresse suivante :
   `https://raw.githubusercontent.com/Lycraz/scan-tickets/main/sidestore/source.json`
3. Scan Tickets apparaît dans la source. Les mises à jour arrivent ensuite dans **My Apps**.

### 4. Android : Obtainium

1. Installe **Obtainium**. C'est une app gratuite, disponible sur obtainium.imranr.dev.
2. Touche **Ajouter une app** et colle `https://github.com/Lycraz/scan-tickets`.
3. Obtainium installe l'APK, puis prévient à chaque nouvelle version.

## Modèle de note de frais

Le modèle Excel de l'entreprise n'est **pas** inclus dans le dépôt. Chaque utilisateur l'importe une fois dans l'app : **Réglages › Note de frais › Modèle Excel**.
