#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
configuration="${1:-release}"
export RURI_BUILD_DIR="${RURI_BUILD_DIR:-.build/validation}"
mkdir -p build
stage_dir="$(mktemp -d "$(pwd)/build/.ruri-build.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/Ruri.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
mkdir -p "$app/Contents/Helpers"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/ThirdPartyNotices.txt "$app/Contents/Resources/ThirdPartyNotices.txt"
python3 scripts/configure-app.py "$app/Contents/Info.plist"
scripts/swift-build.sh -c "$configuration" --product Ruri
scripts/swift-build.sh -c "$configuration" --product ruri-monitor
binary_dir="$(scripts/swift-build.sh -c "$configuration" --show-bin-path)"
cp "$binary_dir/Ruri" "$app/Contents/MacOS/Ruri"
cp "$binary_dir/ruri-monitor" "$app/Contents/Helpers/ruri-monitor"
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "$app/Contents/Helpers/ruri-monitor"
for bundle in "$binary_dir/"*.bundle(N); do
  ditto "$bundle" "$app/Contents/Resources/${bundle:t}"
done
xcrun swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
python3 scripts/check-localization-bundle.py "$app"
destination="$(pwd)/build/Ruri.app"
if [[ -e "$destination" ]]; then
  mv "$destination" "$stage_dir/previous.app"
fi
if ! mv "$app" "$destination"; then
  if [[ -e "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$destination"; fi
  exit 1
fi
print "Built $destination"
