# Cleanmac

Appli macOS perso de nettoyage et d'optimisation du Mac (SwiftUI).

- Règles du projet : [CLAUDE.md](CLAUDE.md)
- Plan de construction : [PLAN.md](PLAN.md)

## Organisation

- `Cleanmac/` : l'appli SwiftUI.
- `CleanmacCore/` : moteur de règles, de scan et de nettoyage (framework testable).
  Les règles sont dans `CleanmacCore/Rules/*.json`.
- `CleanmacCoreTests/` : tests unitaires du moteur (Swift Testing).
- `CleanmacHelper/` : outil d'aide privilégié (démon `SMAppService`, XPC).
- `Shared/` : protocole XPC et liste fermée des commandes, communs à l'appli et à l'outil d'aide.
- `Support/` : plist launchd et Info.plist de l'outil d'aide.

## Compiler, tester, lancer

```bash
xcodebuild -project Cleanmac.xcodeproj -scheme Cleanmac -derivedDataPath build/DerivedData build
```

```bash
xcodebuild -project Cleanmac.xcodeproj -scheme Cleanmac -derivedDataPath build/DerivedData test
```

```bash
open build/DerivedData/Build/Products/Debug/Cleanmac.app
```
