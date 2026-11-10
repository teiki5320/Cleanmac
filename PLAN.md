# Cleanmac — plan de construction

Cocher chaque case quand l'étape est faite et testée sur le Mac.
Ajouter en bas, dans « Décisions », tout choix important pris en cours de route.

## Phase 0 — Fondations
- [x] Projet Xcode : appli SwiftUI macOS 15+, cibles `Cleanmac`, `CleanmacCore`, `CleanmacHelper`, tests
- [x] `.gitignore` Xcode, signature locale (équipe perso)
- [ ] Écran d'accueil au premier lancement : explication + bouton qui ouvre
      Réglages système › Confidentialité › Accès complet au disque, et détection de l'autorisation
      → codé et compilé, détection testée ; reste à le valider à l'écran
- [ ] Installation de l'outil d'aide privilégié (`SMAppService`) + XPC avec commandes autorisées
      → codé, paquet et signatures vérifiés ; reste à l'installer, l'autoriser dans
        Réglages système › Général › Ouverture et extensions, puis « Tester la connexion »
- [x] Moteur de règles : chargement de `Rules/*.json`, catégories, niveaux de risque
- [x] Moteur de scan : parcours asynchrone, calcul des tailles réelles (espace alloué), annulation
- [x] Moteur de nettoyage : Corbeille par défaut, journal, exclusions
      (testé avec un faux suppresseur ; pas encore branché à l'interface)

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
- Projet Xcode écrit à la main avec des dossiers synchronisés (format Xcode 16+) :
  ajouter un fichier dans un dossier suffit, pas besoin de toucher au projet. Aucun outil externe.
- Identifiants : `com.teiki.cleanmac` (appli), `com.teiki.cleanmac.helper` (outil d'aide et service XPC),
  `com.teiki.cleanmac.core` (moteur). Signature manuelle « Apple Development », équipe K597U7X3FZ,
  runtime renforcé.
- `CleanmacCore` est un framework embarqué dans l'appli. Le protocole XPC et la liste des commandes
  sont dans `Shared/`, compilé à la fois dans l'appli et dans l'outil d'aide (l'outil reste autonome).
- XPC : l'outil d'aide n'accepte que l'appli signée par l'équipe (`setCodeSigningRequirement`), et l'appli
  ne parle qu'à l'outil signé par l'équipe. Commandes : liste fermée `HelperCommand`, programmes et
  arguments fixes, sans shell, aucun paramètre venant de l'appli.
- Format des règles : documenté en tête de `CleanmacCore/RuleEngine/Rule.swift`. Les fichiers sont dans
  `CleanmacCore/Rules/*.json`. Motifs refusés : relatifs, `..`, `**`, premier composant joker (`~/*`).
- Taille réelle = blocs alloués (`st_blocks × 512`), liens symboliques jamais suivis, liens physiques
  comptés une fois. Les clones APFS sont comptés pour chaque copie (comme le Finder).
- Protections d'office en plus de CLAUDE.md : `~/Library/Mobile Documents` (iCloud Drive : y supprimer
  supprimerait dans iCloud), `~/Library/Photos`, `/System`, `/bin`, `/sbin`, `/usr`, `/private/etc`,
  `/Library/Keychains`, toute photothèque (`*.photoslibrary`), le dossier personnel et ses parents.
  Un élément est refusé s'il est dans un emplacement protégé, s'il en contient un, ou s'il contient
  ou est contenu dans un dossier `.git`.
- Avant chaque suppression, le nettoyeur revérifie tout : règle connue, chemin conforme à la règle,
  protections (y compris recherche d'un `.git` à l'intérieur), existence.
- Ne jamais utiliser `standardizingPath` / `resolvingSymlinksInPath` sur les chemins : ces fonctions
  retirent `/private` et désalignent les chemins. On ne retire que les « / » finaux.
- Journal et exclusions en JSON dans `~/Library/Application Support/Cleanmac/`.
- Phase 0 : l'écran principal est un écran de contrôle provisoire (scan en lecture seule, aucun bouton
  de nettoyage tant que l'écran de vérification de la Phase 1 n'existe pas).
- Version 0.1.0 (build 1) : première livraison testable.
