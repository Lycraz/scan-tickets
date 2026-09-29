# Scan Tickets : installer l'app sur ton iPhone

C'est une vraie app iPhone (SwiftUI). Tu l'installes depuis ton Mac avec Xcode, sans passer par l'App Store.

## 1. Installer Xcode (une seule fois)

1. Ouvre l'**App Store** sur le Mac, cherche **Xcode** et installe-le. C'est gratuit, mais le téléchargement est gros (environ 10 Go, compte 30 à 60 min).
2. Lance Xcode une première fois et accepte l'installation des composants supplémentaires.
3. Va dans **Xcode › Réglages › Comptes**, clique sur **+**, choisis **Apple ID** et connecte-toi avec ton compte Apple habituel.

## 2. Préparer l'iPhone (une seule fois)

1. Branche l'iPhone au Mac avec un câble et touche **Se fier à cet ordinateur**.
2. Sur l'iPhone, ouvre **Réglages › Confidentialité et sécurité › Mode développeur** et active-le. L'iPhone redémarre.
   (Si l'option n'apparaît pas, elle s'affichera après l'étape 3.)

## 3. Installer l'app

1. Dézippe le dossier et double-clique sur **ScanTickets.xcodeproj**.
2. Dans la colonne de gauche, clique sur **ScanTickets** (l'icône bleue tout en haut), puis sur la cible **ScanTickets** et sur l'onglet **Signing & Capabilities**.
3. Dans **Team**, choisis ton nom (Personal Team).
   Si Xcode signale que le « Bundle Identifier » est déjà pris, remplace `com.lemercier.scantickets` par autre chose, par exemple `com.fabien.scantickets2`.
4. En haut de la fenêtre, choisis ton **iPhone** comme destination, puis clique sur ▶︎ (ou appuie sur Cmd + R).
5. La première fois, l'iPhone refuse d'ouvrir l'app. Va dans **Réglages › Général › VPN et gestion de l'appareil**, touche ton Apple ID, puis **Faire confiance**. Relance l'app.

Après ça, l'icône **Scan Tickets** reste sur l'écran d'accueil.

> Avec un compte Apple gratuit, l'app doit être réinstallée **tous les 7 jours** : rebranche l'iPhone et clique sur ▶︎. Tes tickets sont conservés.
> Avec le compte Apple Developer (99 €/an), l'app reste installée un an, et tu peux aussi la distribuer via TestFlight.

## 4. Premier réglage dans l'app

- **Réglages › iCloud Drive** : crée un dossier (par ex. « Notes de frais ») et sélectionne-le. Chaque ticket y sera copié automatiquement dans `Photos/AAAA-MM/`, et les Excel dans `Exports/`.
- **Réglages › Lecture des tickets** : colle ta clé API Anthropic (console.anthropic.com) pour avoir la lecture par IA, la plus précise. Sans clé, l'iPhone lit le ticket lui-même : c'est gratuit et ça marche hors ligne.

## Ce que fait l'app

- **Scanner** : le scanner de documents d'Apple recadre le ticket tout seul. Tu peux scanner plusieurs tickets à la suite.
- **Lecture automatique** : commerçant, date, TTC, TVA, HT, moyen de paiement et nature (restaurant, carburant, péage…).
- **Liste par mois** avec les totaux, une recherche, le badge « à vérifier », et un balayage vers la gauche pour supprimer.
- **Export Excel** : un onglet Tickets et un onglet Récap par nature (avec formules), photos jointes si tu le souhaites, partage via « Enregistrer dans Fichiers », Mail, AirDrop…
- **Données** : visibles aussi dans l'app Fichiers, sous *Sur mon iPhone › Scan Tickets*.

## En cas d'erreur de compilation

Copie le message d'erreur affiché par Xcode (en rouge) et envoie-le-moi : je corrige.

## Note de frais (modèle de l'entreprise)

1. **Réglages › Note de frais › Profil** : saisis ton nom, ton entité, ton véhicule, ton immatriculation, ta puissance fiscale (CV) et le type de moteur.
2. **Réglages › Note de frais › Listes** : ajoute tes N° d'affaire, tes lieux, tes partenaires et tes raisons de déplacement.
3. Sur chaque ticket, choisis ces valeurs dans la section « Note de frais ». Le dernier choix est repris automatiquement sur le ticket suivant. Pour un repas, tu peux indiquer les personnes invitées.
4. Pour un trajet avec ta voiture, utilise **Scanner › Ajouter des kilomètres**.
5. Dans **Export › Note de frais**, choisis la semaine, indique le N° de feuille de mission, puis touche « Créer la note de frais ». Tu obtiens ton modèle Excel rempli, avec les justificatifs numérotés comme la colonne « Just » (01_…, 02_…).

Si l'entreprise change sa trame, tu peux importer la nouvelle dans **Réglages › Modèle Excel**, à condition que la disposition des cases reste la même.
