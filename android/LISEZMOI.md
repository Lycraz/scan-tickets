# Scan Tickets pour Android : créer l'APK et l'installer

C'est la même app que sur iPhone : scan des tickets, lecture automatique, kilomètres, listes, note de frais remplie à partir du modèle de l'entreprise, et export Excel.
Sur Android, l'app s'installe avec un simple fichier **.apk**. Il n'y a ni limite de 7 jours ni compte payant.

## 1. Installer Android Studio (une seule fois, sur ton Mac)

1. Télécharge **Android Studio** sur https://developer.android.com/studio. C'est gratuit.
2. Lance-le et suis l'assistant en gardant les options « Standard ». Il télécharge les outils Android (quelques Go).

## 2. Créer l'APK

1. Dans Android Studio, fais **File › Open**, puis choisis le dossier **ScanTickets-Android/ScanTickets**.
2. Attends la fin de la synchronisation Gradle (barre de progression en bas, plusieurs minutes la première fois).
   - Si Android Studio propose de mettre à jour Gradle ou le plugin Android, tu peux accepter.
3. Fais **Build › Build App Bundle(s) / APK(s) › Build APK(s)**.
4. Quand c'est terminé, clique sur **locate** dans la notification. Le fichier est `app/build/outputs/apk/debug/app-debug.apk`.
   Tu peux le renommer en `ScanTickets.apk`.

> Pour tester sur ton ordinateur, tu peux aussi créer un téléphone virtuel dans **Device Manager**, puis cliquer sur ▶︎.
> Le scanner de documents a besoin d'un vrai téléphone avec les services Google.

## 3. Installer l'app sur le téléphone Android

1. Envoie `ScanTickets.apk` à la personne, par WhatsApp, e-mail, Google Drive ou câble USB.
2. Sur le téléphone, elle ouvre le fichier. Android demande d'autoriser l'installation depuis cette source (WhatsApp, Fichiers…) : elle touche **Paramètres**, active **Autoriser**, puis revient en arrière.
3. Elle touche **Installer**. Si Play Protect affiche un avertissement, elle touche **Plus de détails › Installer quand même**. C'est normal pour une app qui ne vient pas du Play Store.

Pour les mises à jour, tu refais un APK et elle l'installe par-dessus. Ses tickets sont conservés.

## 4. Premiers réglages dans l'app

- **Réglages › Note de frais › Profil** : nom, entité, véhicule, immatriculation, CV et moteur.
- **Réglages › Note de frais › Listes** : N° d'affaire, lieux, partenaires et raisons de déplacement.
- **Réglages › Lecture des tickets** : colle une clé API Anthropic pour la lecture par IA. Sans clé, la lecture se fait sur le téléphone, gratuitement.
- **Réglages › Dossier de sauvegarde** : choisis un dossier du téléphone. Chaque photo de ticket et chaque export y sont copiés.

## Différences avec l'iPhone

- Il n'y a pas d'iCloud sur Android. Les exports passent par le menu de partage (Drive, Gmail, Fichiers…) ou par le dossier de sauvegarde choisi.
- Le scanner et la lecture hors ligne utilisent les outils de Google (ML Kit), gratuits. Le premier lancement peut télécharger un petit module.

## En cas d'erreur

Si Android Studio affiche une erreur en rouge pendant la synchronisation ou la création de l'APK, copie le message et envoie-le-moi : je corrige.
