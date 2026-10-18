#!/bin/zsh
# Rebuild the compiled icons that Nix builds copy, since actool exists only in
# Xcode. Run after changing Resources/AppIcon.icon or Resources/GameHostIcon.icon.
set -euo pipefail
cd "${0:A:h:h:h}"
source scripts/lib/build.sh
select_xcode
minimum="$(plutil -extract LSMinimumSystemVersion raw Resources/Info.plist)"
# The partial Info.plist only names the icon, which both Info.plist files already do.
stage_dir="$(mktemp -d)"
trap 'rm -rf "$stage_dir"' EXIT
for icon in AppIcon GameHostIcon; do
  destination="nix/icons/$icon"
  rm -rf "$destination"
  mkdir -p "$destination"
  xcrun actool "Resources/$icon.icon" --compile "$destination" \
    --platform macosx --target-device mac --minimum-deployment-target "$minimum" \
    --app-icon "$icon" --output-format human-readable-text \
    --output-partial-info-plist "$stage_dir/$icon.plist" > /dev/null
  # actool reports some failures as warnings and still exits successfully.
  [[ -f "$destination/Assets.car" && -f "$destination/$icon.icns" ]] || { print -u2 "actool did not compile $icon"; exit 1; }
done
