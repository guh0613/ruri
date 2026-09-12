#!/bin/zsh
# Build Ruri with the selected Xcode SDK and accurate Mach-O SDK metadata.
# Usage: scripts/swift-build.sh -c debug --product Ruri
# Tests: scripts/swift-build.sh test --filter AuthenticationTests
# DEVELOPER_DIR selects Xcode; RURI_BUILD_DIR optionally selects the build folder.
set -euo pipefail
cd "${0:A:h:h}"
python3 scripts/localization.py --check >&2
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi

swift_command=build
if [[ "${1:-}" == test ]]; then
  swift_command=test
  shift
fi

# This entry point builds this package for macOS. Keep SDK selection consistent
# between compilation and linking instead of allowing conflicting overrides.
for argument in "$@"; do
  case "$argument" in
    --sdk|--sdk=*|--swift-sdk|--swift-sdk=*|--triple|--triple=*|--toolchain|--toolchain=*|--package-path|--package-path=*)
      print -u2 -- "Unsupported override: $argument. Use DEVELOPER_DIR to select the macOS toolchain/SDK."
      exit 2
      ;;
  esac
done

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
sdk_version="$(xcrun --sdk "$sdk_path" --show-sdk-version)"
package="$(xcrun swift package dump-package)"
platform="$(print -r -- "$package" | plutil -extract platforms.0.platformName raw -o - -)"
if [[ "$platform" != macos ]]; then
  print -u2 -- "Expected Package.swift to declare macOS as its first supported platform."
  exit 1
fi
deployment_target="$(print -r -- "$package" | plutil -extract platforms.0.version raw -o - -)"

# Some Swift drivers forward -sdk to clang as --sysroot, losing the SDK version
# at link time. Specify both versions without changing the deployment target.
build_args=(
  --sdk "$sdk_path"
  -Xlinker -platform_version -Xlinker macos
  -Xlinker "$deployment_target" -Xlinker "$sdk_version"
)
if [[ -n "${RURI_BUILD_DIR:-}" ]]; then
  build_args+=(--scratch-path "$RURI_BUILD_DIR")
fi
exec xcrun swift "$swift_command" "${build_args[@]}" "$@"
