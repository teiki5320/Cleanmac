# Cleanmac — règles du projet

Appli macOS perso de nettoyage et d'optimisation du Mac, dans l'esprit de CleanMyMac :
même niveau de finition et de profondeur, mais un design original.

Le plan de construction est dans `PLAN.md`. Le relire au début de chaque session,
cocher les cases au fur et à mesure et noter les décisions prises.

## Contexte
- Usage perso, sur un Mac mini M4 (disque interne de 256 Go, souvent plein).
- Pas de distribution sur le Mac App Store : appli non sandboxée, compilée en local.
- Pas d'anti-malware : hors périmètre.
- L'utilisateur pilote souvent depuis un iPad (RealVNC) : textes lisibles, boutons larges.

## Langue
- Interface, commentaires utiles, messages de commit : en français.

## Git
- Travailler uniquement sur `main`. Pas de branche, pas de pull request, sauf demande explicite.
- Un commit par étape cohérente, message clair en français.

## Technique
- Swift 6, SwiftUI, cible macOS 15 minimum. Apple Silicon.
- Pas de dépendance externe sauf vraie nécessité (le dire avant d'en ajouter une).
- Architecture :
  - `Cleanmac` : l'appli SwiftUI.
  - `CleanmacHelper` : outil d'aide privilégié (démon lancé via `SMAppService`),
    pour les seules opérations qui demandent les droits administrateur.
    Communication par XPC, avec une liste fermée de commandes autorisées.
  - `CleanmacCore` : moteur de scan et règles, testable sans interface.
- Scans asynchrones (Swift Concurrency), annulables, avec progression. Jamais bloquer l'interface.
- Tests unitaires pour le moteur de règles et le calcul des tailles.

## Sécurité des suppressions (règle n°1)
- Par défaut, **tout passe par la Corbeille** (`FileManager.trashItem`). Suppression
  définitive seulement pour des caches régénérables, et uniquement si l'utilisateur
  l'a activée dans les réglages.
- Ne jamais utiliser `rm -rf` ni supprimer un chemin construit sans vérification.
- Chaque élément supprimable vient d'une **règle** déclarée dans la base de règles
  (`Rules/*.json`) : chemin, catégorie, niveau de risque (sûr / à vérifier), explication.
  Rien n'est supprimé hors règle.
- Seuls les éléments « sûrs » sont cochés par défaut. Les autres sont affichés, décochés.
- Toujours un écran de vérification avant de nettoyer, avec la taille totale.
- Liste d'exclusions modifiable par l'utilisateur. Protégés d'office :
  `~/Pictures`, `~/Library/Messages`, `~/Documents`, `~/Desktop`, la photothèque,
  les clés et trousseaux, tout dossier de code contenant un `.git`.
- Journal de chaque nettoyage (date, éléments, taille) consultable dans l'appli.

## Design
- Inspiré de l'esprit CleanMyMac (fenêtre sombre et translucide, dégradés par module,
  gros bouton de scan animé, résultats en cartes, animations fluides), mais
  **original** : ne pas reprendre leur logo, leurs icônes, leurs illustrations,
  leurs noms de modules ni leurs couleurs exactes.
- Icônes : SF Symbols. Matériaux : `.ultraThinMaterial` / vibrancy.
- Chaque module a sa couleur et son dégradé, définis dans un seul fichier de thème.
- Animations soignées mais courtes ; respecter « Réduire les animations ».
- Mode sombre en priorité, mode clair correct.

## Versions
- Incrémenter le numéro de version de l'appli (`CFBundleShortVersionString`)
  à chaque livraison testable.
