# Cleanmac — plan de construction

Cocher chaque case quand l'étape est faite et testée sur le Mac.
Ajouter en bas, dans « Décisions », tout choix important pris en cours de route.

## Phase 0 — Fondations
- [x] Projet Xcode : appli SwiftUI macOS 15+, cibles `Cleanmac`, `CleanmacCore`, `CleanmacHelper`, tests
- [x] `.gitignore` Xcode, signature locale (équipe perso)
- [x] Écran d'accueil au premier lancement : explication + bouton qui ouvre
      Réglages système › Confidentialité › Accès complet au disque, et détection de l'autorisation
      → codé, détection testée ; refait en style verre (0.7.0), rendu hors écran vérifié
- [x] Installation de l'outil d'aide privilégié (`SMAppService`) + XPC avec commandes autorisées
      → codé, paquet et signatures vérifiés ; reste à l'installer, l'autoriser dans
        Réglages système › Général › Ouverture et extensions, puis « Tester la connexion »
        (Réglages › Accès). Fait le 13 novembre 2026 : installé, autorisé, « répond (version 2) ».
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
- [x] Fichier de thème : couleurs, dégradés par module, typographie, espacements
      → `Cleanmac/Theme/Theme.swift` (0.3.0), étendu aux 12 modules (0.7.0), couleurs des jauges comprises (0.8.0)
- [x] Fenêtre principale : barre latérale translucide + zone de contenu
      → `MainWindowView.swift` ; trois sections (Nettoyage, Espace et applis, Entretien), défilante (0.7.0)
- [x] Composants : gros bouton de scan animé, anneau de progression, cartes de résultat,
      liste détaillée avec cases à cocher, écran « terminé » avec espace libéré
      → 0.7.0 : écran de vérification et écran « terminé » (coche animée, espace traité) au style verre,
        communs à tous les modules (`GlassScreens.swift`) ; cases à cocher de 44 pt partout

## Phase 2 — Modules de nettoyage
- [x] **Analyse complète** : parcourt toutes les règles, résume, nettoie après validation
      → 0.3.1, et inclut Mail et Corbeilles depuis 0.7.0
- [x] **Fichiers système inutiles** : caches utilisateur, logs, fichiers temporaires,
      caches d'applis connues, rapports de plantage (`Rules/systeme.json`)
- [x] **Développeur** : Xcode (DerivedData, Archives, iOS DeviceSupport, simulateurs via `xcrun simctl`),
      Gradle, `.pub-cache` / Flutter, npm / pnpm / yarn, Homebrew (`brew cleanup`), CocoaPods, pip ;
      modèles Ollama et ComfyUI affichés mais jamais cochés par défaut
      → fait en avance (0.2.0), avec en plus : copies des appareils (CoreDevice), SDK Android,
        caches et machine virtuelle de Claude. Homebrew : cache des téléchargements au lieu de `brew cleanup`.
        0.7.0 : simulateurs « indisponibles » (source `unavailableSimulators`, `xcrun simctl delete <udid>`).
- [x] **Mail** : pièces jointes téléchargées de Mail et caches de Thunderbird
      → 0.7.0 : `Rules/mail.json` ; pièces jointes « à vérifier », cache Thunderbird « sûr »
- [x] **Corbeilles** : Corbeille système, corbeilles des volumes externes, corbeille de Photos
      → 0.7.0 : `Rules/corbeilles.json` (règles `inTrash`) ; Photos : bouton qui ouvre Photos (photothèque protégée)
- [x] **iCloud Drive** : repérer les fichiers téléchargés en local et les libérer (`brctl evict`)
      sans les supprimer d'iCloud
      → 0.7.0 : `ICloudScanner` + `ICloudEvictionService` (`evictUbiquitousItem`, `brctl evict` en secours)

## Phase 3 — Espace disque
- [x] **Carte du disque** : vue en anneaux ou en blocs, navigation par dossier, taille en direct
      → 0.4.0 : anneaux sur trois niveaux, clic pour descendre, centre pour remonter, fil d'Ariane,
        liste du contenu, onglet des plus gros fichiers (> 50 Mo, « ancien » si non modifié depuis un an),
        « Afficher dans le Finder ». Dossier personnel ou tout le Mac. Reste à valider à l'écran.
- [x] **Gros et anciens fichiers** : filtres taille / date / type, aperçu Quick Look
      → 0.5.0 : onglet « Gros fichiers » de la carte, filtres taille / ancienneté / type, aperçu Coup d'œil.
        Reste à valider à l'écran.
- [x] **Doublons** : comparaison par taille puis empreinte, choix de l'exemplaire à garder
      → 0.5.0 : recherche faite (taille, puis SHA-256 du début, puis complet), suggestion de l'exemplaire
        à garder, copies APFS repérées, aperçu et Finder.
      → 0.6.0 : choix de l'exemplaire gardé, copies à cocher, écran de vérification, mise à la Corbeille
        via la règle `doublons.copies` avec revérification octet par octet. Reste à valider à l'écran.
- [x] **Instantanés APFS locaux** et espace « purgeable » : affichage et purge (via l'outil d'aide)
      → 0.7.0 : module « Espace purgeable » ; la purge exige l'outil d'aide installé et autorisé

## Phase 4 — Applications
- [x] **Désinstallateur** : appli + tous ses fichiers associés (`~/Library`, conteneurs, préférences)
      → 0.7.0 : règles à jetons `applications.appli` (sûr) et `applications.donnees` (à vérifier)
- [x] **Restes** d'applis déjà supprimées → 0.7.0 : règle `applications.restes`
- [x] **Démarrage** : éléments de connexion et agents `launchd`, activer / désactiver
      → 0.7.0 : vos agents (`launchctl enable/disable`) ; ceux du système en lecture seule ; les éléments
        de connexion de macOS (gérés par le système) s'ouvrent dans Réglages système
- [x] **Mises à jour** : liste des applis qui ont une nouvelle version (Sparkle, Homebrew Cask)
      → 0.7.0 : lecture seule (flux Sparkle, `brew outdated --cask --greedy`)

## Phase 5 — Maintenance
- [x] Vider le cache DNS, réindexer Spotlight, reconstruire les services de lancement,
      lancer les scripts de maintenance (via l'outil d'aide)
      → 0.7.0 : module « Maintenance ». Les scripts `periodic` n'existent plus sur ce macOS : retirés.
- [x] Libérer la mémoire vive (purge) et afficher les applis gourmandes

## Phase 6 — Confort
- [x] **Barre des menus** : espace libre, mémoire, alerte quand le disque passe sous un seuil
- [x] **Nettoyage programmé** : chaque mois, analyse sûre + notification avant de nettoyer
- [x] **Historique** : journal des nettoyages et total libéré
- [x] **Réglages** : exclusions, Corbeille ou suppression définitive, seuils, langue
      → fenêtre Réglages (⌘,) ; langue : français uniquement (règle du projet), pas de choix

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
- Doublons : recherche dans le dossier personnel, hors Bibliothèque, dossiers cachés, paquets (applis,
  photothèques…) et dépôts de code. Fichiers de plus de 1 Mo. Les fichiers iCloud non téléchargés
  (« dataless ») sont ignorés : les lire les téléchargerait, et ils ne prennent pas de place.
- Doublons : suggestion de l'exemplaire à garder = hors Téléchargements, puis le plus ancien, puis le chemin
  le plus court. Les copies APFS (drapeau EF_MAY_SHARE_BLOCKS) ne comptent pas dans l'espace « en trop ».
- Version 0.5.0 (build 6).
- Doublons : mise à la Corbeille validée par l'utilisateur, « avec garde-fous ». Règle `doublons.copies`
  (Rules/doublons.json) d'un nouveau genre, à contrôle `duplicateCopy` : ses chemins sont des dossiers
  (sans joker) et elle couvre les fichiers qu'ils contiennent, à toute profondeur. Dossiers autorisés :
  Téléchargements, Vidéos, Musique, Public (hors bibliothèques Musique et TV). Toujours « à vérifier »
  (rien coché d'office), jamais régénérable : Corbeille uniquement, même si la suppression définitive
  est activée. Le scanner ignore les règles à contrôle.
- Doublons, garde-fous au moment du nettoyage : l'exemplaire gardé est nommé dans la demande, doit
  exister, ne pas être supprimé dans le même nettoyage, être un autre fichier (pas un lien physique),
  et les deux fichiers ordinaires, présents sur ce Mac (pas « dataless »), doivent être identiques octet
  par octet. Protections inchangées : Bureau, Documents, Images, dossiers git restent intouchables
  (ces copies se suppriment depuis le Finder).
- Version 0.6.0 (build 7).
- Version 0.7.0 (build 8) : tous les modules du plan.
- Corbeilles : vider une Corbeille est forcément définitif. Règles `inTrash` (`~/.Trash/*`,
  `/Volumes/*/.Trashes/{uid}/*`) : méthode « définitive » sans dépendre du réglage (exception assumée à
  la règle n°1, puisque les éléments sont déjà dans la Corbeille), toujours « à vérifier » (rien coché
  d'office), écran de vérification avec avertissement. Le nettoyeur revérifie que l'élément est
  directement dans une vraie Corbeille (aucun lien symbolique). Corbeille de Photos : la photothèque
  reste protégée, Cleanmac ouvre seulement Photos.
- Applications : règles à jetons (`{bundleID}`, `{appName}`), contrôles `appFiles` et `appLeftover`.
  L'identité de l'appli est validée (pas de joker, de « / », de « .. ») avant de remplacer les jetons.
  Désinstallation refusée si l'appli est ouverte ou si c'est Cleanmac. Restes refusés si une appli
  installée porte l'identifiant ; par prudence, Apple, les outils (Swift, Python…) et tout éditeur dont
  une appli est installée sont écartés. Tout va à la Corbeille.
- iCloud Drive : libérer n'est pas supprimer (le fichier reste dans iCloud) : pas de règle, mais même
  rigueur (dans `~/Library/Mobile Documents`, aucun lien, entièrement envoyé) et chaque libération est
  journalisée (méthode `evicted`).
- Démarrage : seuls vos agents (`~/Library/LaunchAgents`) se modifient, de façon réversible
  (`launchctl disable/enable`), jamais supprimés. Mises à jour : lecture seule.
- Outil d'aide version 2 : commande `runMaintenanceScripts` retirée (`/usr/sbin/periodic` absent).
- Confort : réglages `barreDesMenus`, `alerteEspace`, `seuilAlerteGo` (15 Go), `nettoyageProgramme`.
  L'analyse programmée ne parcourt que les règles « sûres » et ne supprime jamais rien : elle notifie.
- Tailles affichées toujours en unités françaises (« Go », « ko »).
- Audit (0.8.0), trois relectures indépendantes (sécurité, justesse, interface), corrections :
  - Désinstallation tout ou rien : le paquet .app passe en premier ; s'il reste en place, ses fichiers
    sont gardés. Applis appartenant au système (root : installeurs, App Store) refusées d'ici : Finder.
    Le paquet doit porter l'identifiant de l'appli nommée (relu dans son Info.plist).
  - Aucun lien symbolique dans les dossiers parents d'un élément (scan et nettoyage) : sinon les
    protections, qui portent sur le chemin écrit, pourraient être contournées.
  - Un chemin qui contient un chemin déjà pris par une règle n'est plus proposé (plus de double compte).
  - ByHost : seulement `{bundleID}.<UUID matériel>.plist` (pas les variantes Canary, Beta…) ;
    conteneurs partagés (`Group Containers`) retirés de la désinstallation.
  - Règles de Corbeille obligatoirement « à vérifier » ; journaux non régénérables ; `~/.ssh` et
    `~/.gnupg` protégés ; doublons refusés dans un paquet (projets Logic, iMovie…).
  - iCloud : jamais un dossier entier ; plus de secours `brctl evict`.
  - Journal : fichier illisible mis de côté, écritures sérialisées, un échec d'écriture ne fait plus
    passer un nettoyage réussi pour un échec. Exclusions illisibles : nettoyage bloqué.
  - Réglage « suppression définitive » figé pendant l'écran de vérification.
  - Outils lancés (`ToolRunner`) annulables et bornés dans le temps ; outil d'aide : délai de 10 min.
  - Outil d'aide : refuse une appli débogable (`get-task-allow`) ; l'appli est signée sans ce droit
    (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`).
  - Mises à jour : versions bêta et incompatibles ignorées. Restes : applis ouvertes et éléments de
    démarrage écartés.
  - Interface : erreurs d'analyse affichées, bandeau si l'Accès complet au disque manque, place
    « libérée » (définitif, iCloud) distincte de « mise à la Corbeille », chemins visibles sans survol,
    listes complètes, étiquettes en 14 pt, textes de 13 pt au moins, boutons de 44 pt, libellés VoiceOver.
- Noms propres à Cleanmac : « Vider les Corbeilles », « Entretien » (section « Soin du Mac »).
- La fenêtre principale reste toujours sombre (style verre) ; Réglages et barre des menus suivent le
  mode clair ou sombre du système.
- Un projet git mis à la Corbeille reste protégé : Cleanmac ne vide pas cet élément (le Finder le peut).
- Version 0.8.0 (build 9).
- Couleurs (13 novembre 2026) : « Analyse complète » passe en magenta-rose (0xD0237A), à la demande
  de l'utilisateur, dans l'esprit CleanMyMac mais avec des teintes propres ; « Applications » passe en
  émeraude pour ne pas se confondre. Logo : sphère de verre magenta, assortie à l'écran principal
  (`Cleanmac/Assets.xcassets/AppIcon`, source dans `Design/logo-source.swift`). La barre des menus garde
  le symbole « étincelles », repris du logo.
- Doublons : la jauge avance selon les octets lus, y compris pendant la lecture complète des gros fichiers.
- Version 0.8.1 (build 10).
- Améliorations (0.9.0) :
  - Nouvelles règles « Fichiers système » : caches des applis du Mac App Store (conteneurs, hors applis
    Apple dont les caches servent à l'analyse des photos) en « sûr » ; sauvegardes d'iPhone et d'iPad
    (nom de l'appareil et date affichés), installeurs de macOS et disque virtuel de Docker en « à vérifier ».
  - Historique : « Remettre en place » un élément mis à la Corbeille, s'il y est encore, si son
    emplacement d'origine est libre et son dossier parent présent (rien n'est écrasé ni recréé).
    Journalisé avec la méthode `restored` (déduit du total mis à la Corbeille).
  - Résultats : « Toujours ignorer » (main levée) ajoute l'élément aux exclusions et le retire de la liste.
- Version 0.9.0 (build 11).
- Installation (13 novembre 2026) : `scripts/installer.sh` compile en Release, vérifie la signature,
  ferme Cleanmac, met l'ancienne version de /Applications à la Corbeille (jamais `rm`), copie la nouvelle
  avec `ditto`, retire la version de développement de LaunchServices et ouvre /Applications/Cleanmac.app.
  C'est désormais la façon de livrer une version testable. L'outil d'aide reste autorisé : macOS a
  rattaché son autorisation à /Applications/Cleanmac.app.
