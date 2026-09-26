#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/lib/build.sh
if [[ "${RURI_SIGNING_ACTIVE:-}" != 1 ]]; then
  exec python3 scripts/release/signing.py run -- /bin/zsh scripts/build-app.sh "$@"
fi
select_xcode
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
python3 scripts/lib/app.py bundle "$app"
scripts/swift-build.sh -c "$configuration"
binary_dir="$(scripts/swift-build.sh -c "$configuration" --show-bin-path)"
cp "$binary_dir/Ruri" "$app/Contents/MacOS/Ruri"
cp "$binary_dir/ruri-cli" "$app/Contents/Helpers/ruri-cli"
cp "$binary_dir/ruri-monitor" "$app/Contents/Helpers/ruri-monitor"
sign_keychain=()
if [[ -n "${RURI_SIGN_KEYCHAIN:-}" ]]; then sign_keychain=(--keychain "$RURI_SIGN_KEYCHAIN"); fi
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "${sign_keychain[@]}" "$app/Contents/Helpers/ruri-monitor"
# The CLI acts as the same launcher principal. Its signing identifier preserves
# the designated requirement of existing GUI-created Keychain entries; it is a
# standalone helper, not another app bundle registered with Launch Services.
codesign --force --identifier dev.ruri.launcher --sign "${RURI_SIGN_IDENTITY:--}" "${sign_keychain[@]}" "$app/Contents/Helpers/ruri-cli"
# Ruri is not sandboxed, so Sparkle installs in-process and its XPC services,
# which only sandboxed hosts use, are left out. Sign nested code inside-out.
sparkle="$app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/Frameworks"
ditto "$binary_dir/Sparkle.framework" "$sparkle"
rm -rf "$sparkle/XPCServices" "$sparkle/Versions/B/XPCServices"
for component in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle"; do
  codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "${sign_keychain[@]}" "$component"
done
for bundle in "$binary_dir/"*.bundle(N); do
  ditto "$bundle" "$app/Contents/Resources/${bundle:t}"
done
compile_app_icon "$app" Resources/AppIcon.icon AppIcon "$stage_dir/icon-info.plist"
build_game_host "$app/Contents/Helpers/RuriGame.app" "$app/Contents/Info.plist"
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "${sign_keychain[@]}" "$app"
codesign --verify --deep --strict "$app"
python3 scripts/release/signing.py verify "$app"
python3 scripts/localization.py --bundle "$app"
python3 scripts/validate-cli.py "$app"
destination="$(pwd)/build/Ruri.app"
if [[ -e "$destination" ]]; then
  mv "$destination" "$stage_dir/previous.app"
fi
if ! mv "$app" "$destination"; then
  if [[ -e "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$destination"; fi
  exit 1
fi
print "Built $destination"
