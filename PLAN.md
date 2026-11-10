# Cleanmac — plan de construction

Cocher chaque case quand l'étape est faite et testée sur le Mac.
Ajouter en bas, dans « Décisions », tout choix important pris en cours de route.

## Phase 0 — Fondations
- [ ] Projet Xcode : appli SwiftUI macOS 15+, cibles `Cleanmac`, `CleanmacCore`, `CleanmacHelper`, tests
- [ ] `.gitignore` Xcode, signature locale (équipe perso)
- [ ] Écran d'accueil au premier lancement : explication + bouton qui ouvre
      Réglages système › Confidentialité › Accès complet au disque, et détection de l'autorisation
- [ ] Installation de l'outil d'aide privilégié (`SMAppService`) + XPC avec commandes autorisées
- [ ] Moteur de règles : chargement de `Rules/*.json`, catégories, niveaux de risque
- [ ] Moteur de scan : parcours asynchrone, calcul des tailles réelles (espace alloué), annulation
- [ ] Moteur de nettoyage : Corbeille par défaut, journal, exclusions

## Phase 1 — Design
- [ ] Fichier de thème : couleurs, dégradés par module, typographie, espacements
- [ ] Fenêtre principale : barre latérale translucide + zone de contenu
- [ ] Composants : gros bouton de scan animé, anneau de progression, cartes de résultat,
      liste détaillée avec cases à cocher, écran « terminé » avec espace libéré
- [ ] Maquette validée par l'utilisateur avant d'aller plus loin

## Phase 2 — Modules de nettoyage
- [ ] **Analyse en un clic** : lance les modules sûrs, résume, nettoie après validation
- [ ] **Fichiers système inutiles** : caches utilisateur, logs, fichiers temporaires,
      caches d'applis connues, rapports de plantage
- [ ] **Développeur** : Xcode (DerivedData, Archives, iOS DeviceSupport, simulateurs via `xcrun simctl`),
      Gradle, `.pub-cache` / Flutter, npm / pnpm / yarn, Homebrew (`brew cleanup`), CocoaPods, pip ;
      modèles Ollama et ComfyUI affichés mais jamais cochés par défaut
- [ ] **Mail** : pièces jointes téléchargées de Mail et caches de Thunderbird
- [ ] **Corbeilles** : Corbeille système, corbeilles des volumes externes, corbeille de Photos
- [ ] **iCloud Drive** : repérer les fichiers téléchargés en local et les libérer (`brctl evict`)
      sans les supprimer d'iCloud

## Phase 3 — Espace disque
- [ ] **Carte du disque** : vue en anneaux ou en blocs, navigation par dossier, taille en direct
- [ ] **Gros et anciens fichiers** : filtres taille / date / type, aperçu Quick Look
- [ ] **Doublons** : comparaison par taille puis empreinte, choix de l'exemplaire à garder
- [ ] **Instantanés APFS locaux** et espace « purgeable » : affichage et purge (via l'outil d'aide)

## Phase 4 — Applications
- [ ] **Désinstallateur** : appli + tous ses fichiers associés (`~/Library`, conteneurs, préférences)
- [ ] **Restes** d'applis déjà supprimées
- [ ] **Démarrage** : éléments de connexion et agents `launchd`, activer / désactiver
- [ ] **Mises à jour** : liste des applis qui ont une nouvelle version (Sparkle, Homebrew Cask)

## Phase 5 — Maintenance
- [ ] Vider le cache DNS, réindexer Spotlight, reconstruire les services de lancement,
      lancer les scripts de maintenance (via l'outil d'aide)
- [ ] Libérer la mémoire vive (purge) et afficher les applis gourmandes

## Phase 6 — Confort
- [ ] **Barre des menus** : espace libre, mémoire, alerte quand le disque passe sous un seuil
- [ ] **Nettoyage programmé** : chaque mois, analyse sûre + notification avant de nettoyer
- [ ] **Historique** : journal des nettoyages et total libéré
- [ ] **Réglages** : exclusions, Corbeille ou suppression définitive, seuils, langue

## Décisions
- Usage perso, pas de Mac App Store, pas d'anti-malware.
- Tout passe par la Corbeille par défaut.
