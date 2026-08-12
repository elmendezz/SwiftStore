#!/bin/bash

VERSION_FILE="version.sync"

# Inicializar si no existe
if [ ! -f "$VERSION_FILE" ]; then
    echo "3.1.5" > "$VERSION_FILE"
fi

CURRENT_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

# Generar número aleatorio (1-100) para baja probabilidad de subir MAJOR/MINOR
RAND=$((RANDOM % 100 + 1))

if [ "$RAND" -le 5 ]; then
    # 5% de probabilidad: Incrementa Major
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
elif [ "$RAND" -le 20 ]; then
    # 15% de probabilidad: Incrementa Minor
    MINOR=$((MINOR + 1))
    PATCH=0
else
    # 80% de probabilidad: Incrementa Patch
    PATCH=$((PATCH + 1))
fi

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
echo "$NEW_VERSION" > "$VERSION_FILE"
echo "Versión actualizada a: $NEW_VERSION"

# Actualizar en Info.plist si existe
if [ -f "Info.plist" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" Info.plist 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_VERSION" Info.plist 2>/dev/null || true
fi

# Hacer commit y push del version.sync si estamos en git
if git rev-parse --git-dir > /dev/null 2>&1; then
    git add "$VERSION_FILE" Info.plist 2>/dev/null || git add "$VERSION_FILE"
    git commit -m "chore: bump version to $NEW_VERSION [skip ci]" || true
    git push origin $(git rev-parse --abbrev-ref HEAD) || true
fi

# Proceso de Build
mkdir -p Payload/SwiftStore.app

swiftc $(find . -name "*.swift") -parse-as-library \
       -sdk $(xcrun --sdk iphoneos --show-sdk-path) \
       -target arm64-apple-ios15.0 \
       -o Payload/SwiftStore.app/SwiftStore

if [ -f "Info.plist" ]; then
    cp Info.plist Payload/SwiftStore.app/Info.plist
fi

# Compilar y copiar los assets (ícono y otros)
if [ -d "Assets/AppIcon.appiconset" ]; then
    xcrun actool Assets/AppIcon.appiconset \
           --compile Payload/SwiftStore.app \
           --platform iphoneos \
           --minimum-deployment-target 15.0 \
           --app-icon AppIcon \
           --output-partial-info-plist /tmp/actool-partial.plist
fi

zip -r SwiftStore.ipa Payload
rm -rf Payload
