#!/bin/zsh
# Usage: RURI_VERSION=0.1.0-beta.1 scripts/package-dmg.sh
# Optional public defaults: RURI_MICROSOFT_CLIENT_ID, RURI_BUILD_NUMBER.
set -euo pipefail
cd "${0:A:h:h}"
scripts/build-app.sh release

app="$(pwd)/build/Ruri.app"
version="$(plutil -extract RuriVersion raw -o - "$app/Contents/Info.plist")"
architecture="$(lipo -archs "$app/Contents/MacOS/Ruri")"
case "$architecture" in
  arm64|x86_64) ;;
  *) print -u2 -- "Expected a native arm64 or x86_64 application, got: $architecture"; exit 1 ;;
esac
[[ "$(lipo -archs "$app/Contents/Helpers/ruri-monitor")" == "$architecture" ]]

mkdir -p build/dmg
stage_dir="$(mktemp -d "$(pwd)/build/.ruri-dmg.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
mkdir "$stage_dir/volume"
ditto "$app" "$stage_dir/volume/Ruri.app"
ln -s /Applications "$stage_dir/volume/Applications"
filename="Ruri-$version-macOS-$architecture.dmg"
hdiutil create -volname "Ruri $version" -srcfolder "$stage_dir/volume" \
  -format UDZO -fs HFS+ "$stage_dir/$filename"
hdiutil verify "$stage_dir/$filename"
mv -f "$stage_dir/$filename" "build/dmg/$filename"
(
  cd build/dmg
  shasum -a 256 "$filename" > "$filename.sha256"
)
print -- "Packaged $(pwd)/build/dmg/$filename"
