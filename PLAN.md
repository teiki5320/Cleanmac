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

## En avance sur le plan (0.2.0)
- [x] Cases à cocher, écran de vérification (total, Corbeille / définitif), nettoyage, résultat,
      journal et réglage « suppression définitive des caches régénérables » — dans l'écran provisoire,
      à reprendre au design de la Phase 1. Testé par les tests unitaires ; reste à valider à l'écran.

## Phase 1 — Design
- [x] Maquette validée par l'utilisateur : style « verre » (maquette n°10 de la toile
      « Cleanmac — pistes de design »), pour tous les modules
- [ ] Fichier de thème : couleurs, dégradés par module, typographie, espacements
      → codé (`Cleanmac/Theme/Theme.swift`, 0.3.0) ; reste à compiler et valider à l'écran
- [ ] Fenêtre principale : barre latérale translucide + zone de contenu
      → codé (`Cleanmac/Views/Glass/MainWindowView.swift`) ; reste à valider à l'écran
- [ ] Composants : gros bouton de scan animé, anneau de progression, cartes de résultat,
      liste détaillée avec cases à cocher, écran « terminé » avec espace libéré
      → bouton rond, anneau, objets en verre animés et fond animé codés ; les résultats
        reprennent la liste à cases à cocher dans un panneau en verre. Restent : écran de
        vérification et écran « terminé » au style verre (aujourd'hui une feuille simple)

## Phase 2 — Modules de nettoyage
- [ ] **Analyse complète** : parcourt toutes les règles, résume, nettoie après validation
- [ ] **Fichiers système inutiles** : caches utilisateur, logs, fichiers temporaires,
      caches d'applis connues, rapports de plantage
- [x] **Développeur** : Xcode (DerivedData, Archives, iOS DeviceSupport, simulateurs via `xcrun simctl`),
      Gradle, `.pub-cache` / Flutter, npm / pnpm / yarn, Homebrew (`brew cleanup`), CocoaPods, pip ;
      modèles Ollama et ComfyUI affichés mais jamais cochés par défaut
      → fait en avance (0.2.0), avec en plus : copies des appareils (CoreDevice), SDK Android,
        caches et machine virtuelle de Claude. Homebrew : cache des téléchargements au lieu de `brew cleanup`.
        Reste : simulateurs « indisponibles » (`xcrun simctl delete unavailable`, aucun sur ce Mac).
- [ ] **Mail** : pièces jointes téléchargées de Mail et caches de Thunderbird
- [ ] **Corbeilles** : Corbeille système, corbeilles des volumes externes, corbeille de Photos
- [ ] **iCloud Drive** : repérer les fichiers téléchargés en local et les libérer (`brctl evict`)
      sans les supprimer d'iCloud

## Phase 3 — Espace disque
- [x] **Carte du disque** : vue en anneaux ou en blocs, navigation par dossier, taille en direct
      → 0.4.0 : anneaux sur trois niveaux, clic pour descendre, centre pour remonter, fil d'Ariane,
        liste du contenu, onglet des plus gros fichiers (> 50 Mo, « ancien » si non modifié depuis un an),
        « Afficher dans le Finder ». Dossier personnel ou tout le Mac. Reste à valider à l'écran.
- [ ] **Gros et anciens fichiers** : filtres taille / date / type, aperçu Quick Look
      → première version dans la carte du disque (liste triée par taille) ; filtres et Quick Look à faire
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
- Module Développeur avancé avant la Phase 1 à la demande de l'utilisateur (le disque est plein,
  c'est là que se trouve la place). Scan réel : 44 Go repérés, dont 0,7 Go « sûr » coché d'office.
- Règles à source (`"source"` dans le JSON) pour les éléments gérés par un outil du système
  (systèmes de simulateurs via `xcrun simctl runtime`). Ils ne peuvent pas aller à la Corbeille :
  la règle doit être régénérable et ils ne sont supprimables que si la suppression définitive est
  activée. L'élément est revérifié dans la liste de l'outil juste avant sa suppression.
- Les règles Développeur passent avant les caches génériques (fichiers chargés par ordre alphabétique,
  le premier qui revendique un chemin le garde) : `~/Library/Caches/pip` est classé dans « Python ».
- Caches et machine virtuelle de Claude : « à vérifier », car Claude est souvent ouvert pendant l'analyse.
- Version 0.2.0 (build 2).
- Phase 1, style « verre » : fond en dégradé animé propre à chaque module sur toute la fenêtre,
  barre latérale translucide, gros objet en verre animé (sphère, bloc, poubelle, anneaux du disque),
  titre + trois fonctions à droite, bouton rond flottant en bas (Analyser / Arrêter / Relancer).
  Couleurs et objets définis dans `Theme.swift` ; aucun élément repris de CleanMyMac.
- Animations continues pilotées par `AnimationClock` (TimelineView) : tout est figé si
  « Réduire les animations » est activé.
- Le scan peut être limité à des catégories (`startScan(categories:)`) : « Analyse complète » parcourt
  toutes les règles, « Fichiers système » et « Développeur » seulement les leurs. Les modules pas encore
  construits sont visibles avec la mention « bientôt » et un bouton désactivé.
- L'ancien écran de contrôle (accès au disque, outil d'aide, règles, réglages, journal) reste accessible
  par « Réglages et journal » en bas de la barre latérale (⌘,).
- Version 0.3.0 (build 3).
- Le premier module s'appelle « Analyse complète » (et non plus « Analyse en un clic ») : il parcourt
  toutes les règles, y compris les éléments « à vérifier », ce que l'ancien nom ne disait pas.
- Version 0.3.1 (build 4).
- Carte du disque en **lecture seule** : aucune suppression depuis la carte (règle n°1 : rien hors règle).
  Elle sert à comprendre où part la place ; on agit via les modules de nettoyage ou le Finder.
- Carte : « Tout le Mac » lit le volume de données `/System/Volumes/Data` (le système est scellé, et
  /Users, /Applications… y renvoient : on évite de compter deux fois). Pas de traversée des autres volumes.
- Carte : lecture POSIX (`readdir` + `fstatat`, liens jamais suivis, liens physiques comptés une fois),
  deux premiers niveaux de dossiers lus en parallèle (8 lectures au plus) : dossier personnel en ~6 s,
  tout le Mac (1,7 million de fichiers) en ~25 s. Petits éléments regroupés par dossier (40 gardés au plus).
- Version 0.4.0 (build 5).
