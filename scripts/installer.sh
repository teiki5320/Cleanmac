#!/bin/bash
# Compile Cleanmac en Release et l'installe dans /Applications.
# L'ancienne version installée va à la Corbeille (jamais de suppression définitive).
# Usage : scripts/installer.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DD=build/Release
APP="$DD/Build/Products/Release/Cleanmac.app"
DEST=/Applications/Cleanmac.app
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "Compilation (Release)…"
mkdir -p "$DD"
if ! xcodebuild -project Cleanmac.xcodeproj -scheme Cleanmac -configuration Release \
        -derivedDataPath "$DD" build > "$DD/compilation.log" 2>&1; then
    grep -E "error:" "$DD/compilation.log" | head -20
    echo "Échec de la compilation : voir $DD/compilation.log"
    exit 1
fi
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "Fermeture de Cleanmac…"
pkill -x Cleanmac 2>/dev/null || true
for _ in $(seq 1 10); do pgrep -x Cleanmac > /dev/null || break; sleep 1; done

if [ -d "$DEST" ]; then
    ANCIENNE="$HOME/.Trash/Cleanmac (ancienne, $(date '+%Y-%m-%d %H.%M.%S')).app"
    echo "Ancienne version mise à la Corbeille."
    mv "$DEST" "$ANCIENNE"
fi
ditto "$APP" "$DEST"

# Une seule Cleanmac connue de macOS : la version de développement n'est plus proposée.
for DEV in build/DerivedData/Build/Products/Debug/Cleanmac.app "$APP"; do
    [ -d "$DEV" ] && "$LSREG" -u "$DEV" > /dev/null 2>&1 || true
done
"$LSREG" -f "$DEST"

open "$DEST"
echo "Cleanmac $VERSION installé dans /Applications."
