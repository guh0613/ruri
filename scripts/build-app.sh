#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
configuration="${1:-release}"
scratch="${RURI_BUILD_DIR:-.build/validation}"
xcrun swift build --scratch-path "$scratch" -c "$configuration" --product Ruri
binary_dir="$(xcrun swift build --scratch-path "$scratch" -c "$configuration" --show-bin-path)"
app="$(pwd)/build/Ruri.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Ruri" "$app/Contents/MacOS/Ruri"
cp Resources/Info.plist "$app/Contents/Info.plist"
for bundle in "$binary_dir/"*.bundle(N); do
  ditto "$bundle" "$app/Contents/Resources/${bundle:t}"
done
xcrun swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign "${RURI_SIGN_IDENTITY:--}" "$app"
print "Built $app"
