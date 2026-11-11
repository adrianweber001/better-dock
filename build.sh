#!/bin/zsh
# Baut "Better Dock.app" aus dem Swift-Paket.
#   ./build.sh           nur bauen
#   ./build.sh install   bauen, nach /Applications kopieren und starten
#   ./build.sh zip       bauen und dist/Better-Dock.zip erzeugen
#   ./build.sh dmg       bauen und dist/Better-Dock.dmg mit gestaltetem Fenster erzeugen
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.3.0"
APP="Better Dock.app"

# Universal-Binary: läuft auf Apple-Silicon- und Intel-Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/awyre" "$APP/Contents/MacOS/BetterDock"
cp "$BIN/awyre-folder" "$APP/Contents/Helpers/awyre-folder"

# App-Icon aus Assets/AppIcon.png (1024 px) erzeugen.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Better Dock</string>
    <key>CFBundleDisplayName</key><string>Better Dock</string>
    <key>CFBundleIdentifier</key><string>com.awyre.dock</string>
    <key>CFBundleExecutable</key><string>BetterDock</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force -s - "$APP/Contents/Helpers/awyre-folder"
# Feste Signatur-Anforderung: So bleibt die Bedienungshilfen-Berechtigung nach Updates erhalten
# (ohne sie hängt macOS die Berechtigung an den exakten Build).
codesign --force -s - -r='designated => identifier "com.awyre.dock"' "$APP"
echo "Fertig: $(pwd)/$APP"

case "${1:-}" in
install)
    pkill -x BetterDock || true
    sleep 1
    rm -rf "/Applications/$APP"
    cp -R "$APP" /Applications/
    open "/Applications/$APP"
    echo "Installiert und gestartet: /Applications/$APP"
    ;;
zip)
    mkdir -p dist
    rm -f dist/Better-Dock.zip
    ditto -c -k --norsrc --keepParent "$APP" dist/Better-Dock.zip
    echo "Download-Paket: $(pwd)/dist/Better-Dock.zip"
    ;;
dmg)
    # dmgbuild schreibt das Fensterlayout direkt, ohne den Finder fernzusteuern.
    if [[ ! -x .venv/bin/dmgbuild ]]; then
        python3 -m venv .venv
        .venv/bin/pip install --quiet dmgbuild
    fi
    swift Assets/dmg-background.swift >/dev/null
    mkdir -p dist
    rm -f dist/Better-Dock.dmg
    .venv/bin/dmgbuild -s dmg-settings.py -D app="$APP" "Better Dock" dist/Better-Dock.dmg >/dev/null
    echo "Download-Paket: $(pwd)/dist/Better-Dock.dmg"
    ;;
esac
