#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    if [[ -d "$xcode/Contents/Developer" ]]; then
      export DEVELOPER_DIR="$xcode/Contents/Developer"
      break
    fi
  done
fi
destination="${1:?Pass the destination RuriGame.app path}"
main_plist="${2:-Resources/Info.plist}"
icon="${3:-}"
destination="${destination:A}"
mkdir -p "${destination:h}"
stage_dir="$(mktemp -d "${destination:h}/.ruri-game-build.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
app="$stage_dir/RuriGame.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp Resources/GameHost-Info.plist "$app/Contents/Info.plist"
python3 - "$main_plist" "$app/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
source, target = map(Path, sys.argv[1:])
main = plistlib.loads(source.read_bytes())
host = plistlib.loads(target.read_bytes())
for key in ('CFBundleVersion', 'CFBundleShortVersionString', 'LSMinimumSystemVersion'):
    host[key] = main[key]
target.write_bytes(plistlib.dumps(host))
PY
sdk="$(xcrun --sdk macosx --show-sdk-path)"
# Both slices permit the same fixed host to load native or Rosetta Java.
compiler=(xcrun clang -isysroot "$sdk" -mmacosx-version-min=14.0 -arch arm64 -arch x86_64
  -fobjc-arc -O2 -Wall -Wextra -Werror)
# dyld installs interposition from launch-time dylibs, not from executables.
"${compiler[@]}" -dynamiclib -framework Foundation Sources/RuriGameHost/WorkingDirectory.m \
  -install_name @rpath/libRuriGameSupport.dylib -o "$app/Contents/Frameworks/libRuriGameSupport.dylib"
"${compiler[@]}" -framework AppKit -framework ImageIO \
  Sources/RuriGameHost/main.m Sources/RuriGameHost/HostProtocol.m Sources/RuriGameHost/GameApplication.m \
  -L"$app/Contents/Frameworks" -lRuriGameSupport -Wl,-rpath,@executable_path/../Frameworks \
  -o "$app/Contents/MacOS/ruri-game"
if [[ -n "$icon" ]]; then cp "$icon" "$app/Contents/Resources/AppIcon.icns"; fi
sign_options=()
if [[ "${RURI_SIGN_IDENTITY:--}" != "-" ]]; then
  # JIT/legacy HotSpot executable memory and vendor/mod native libraries belong
  # to this executable's runtime permissions, not to the launcher or monitor.
  sign_options=(--options runtime --entitlements Resources/GameHost.entitlements)
fi
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "$app/Contents/Frameworks/libRuriGameSupport.dylib"
codesign --force --sign "${RURI_SIGN_IDENTITY:--}" "${sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
if [[ -e "$destination" ]]; then mv "$destination" "$stage_dir/previous.app"; fi
if ! mv "$app" "$destination"; then
  if [[ -e "$stage_dir/previous.app" ]]; then mv "$stage_dir/previous.app" "$destination"; fi
  exit 1
fi
