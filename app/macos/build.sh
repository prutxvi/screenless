#!/bin/zsh
# Build the screenless Mac app. No external dependencies: xcode CLT swiftc only.
# Output: app/macos/Screenless.app (ad-hoc signed, custom vector icon).
#
#   ./build.sh            just build
#   ./build.sh --open     build + launch
#   ./build.sh --install  build + copy to /Applications + launch

set -e
cd "$(dirname "$0")"

APP="Screenless.app"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# 1. compile the app (-swift-version 5 keeps the code out of Swift 6 strictness)
swiftc -swift-version 5 -O \
  -o "$STAGE/Screenless" \
  ScreenlessApp.swift

# 2. app icon: vector -> png set -> icns
swiftc -O -o "$STAGE/icongen" icon_gen.swift
"$STAGE/icongen" "$STAGE/AppIcon.iconset" >/dev/null
mkdir -p "$STAGE/Resources"
iconutil -c icns "$STAGE/AppIcon.iconset" -o "$STAGE/Resources/AppIcon.icns" 2>/dev/null \
  || echo "warn: iconutil failed, building without icon"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$STAGE/Screenless" "$APP/Contents/MacOS/Screenless"
cp "$STAGE/Resources/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true

# 3. Info.plist — regular app (Dock + ⌘-Tab), custom icon
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>screenless</string>
  <key>CFBundleDisplayName</key>     <string>screenless</string>
  <key>CFBundleIdentifier</key>      <string>app.screenless.macos</string>
  <key>CFBundleExecutable</key>      <string>Screenless</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>0.2.0</string>
  <key>CFBundleVersion</key>         <string>2</string>
  <key>LSMinimumSystemVersion</key>  <string>12.0</string>
  <key>LSApplicationCategoryType</key> <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key> <true/>
  <key>NSHumanReadableCopyright</key> <string>MIT — see the repository notice</string>
</dict>
</plist>
EOF

# 4. ad-hoc signature so the local app runs without warnings
codesign --force --deep --sign - "$APP"

echo "Built $APP ($(du -sh "$APP" | cut -f1))."
if [[ $1 == --open ]]; then
  open "$APP"
  echo "Launched."
elif [[ $1 == --install ]]; then
  rm -rf /Applications/$APP
  cp -R "$APP" /Applications/$APP
  open /Applications/$APP
  echo "Installed to /Applications and launched."
fi
