{ pkgs, ... }:
{
  stdenv = pkgs.stdenvNoCC;
  apple.sdk = null;

  # Swift, SourceKit-LSP, Apple SDKs, actool and codesign come from Xcode 27.
  # The build scripts select that toolchain with xcrun; mixing in Nix Swift or
  # a different SDK here would diverge from the existing CI/release builds.
  packages = [
    pkgs.git
    pkgs.python3
    pkgs.nixfmt
    pkgs.zsh
  ];

  scripts = {
    ruri-build = {
      description = "Build Swift products with Xcode";
      exec = ''exec ./scripts/swift-build.sh "$@"'';
    };
    ruri-test = {
      description = "Run Swift tests and build their game-host fixture";
      exec = ''exec ./scripts/swift-build.sh test "$@"'';
    };
    ruri-bundle = {
      description = "Build build/Ruri.app (release by default)";
      exec = ''exec ./scripts/build-app.sh "$@"'';
    };
    ruri-dmg = {
      description = "Build a release app and DMG";
      exec = ''exec ./scripts/package-dmg.sh "$@"'';
    };
    ruri-check = {
      description = "Check build scripts and localization without compiling Swift";
      exec = ''
        set -e
        python3 -m unittest discover -s scripts/tests
        python3 scripts/localization.py --check
      '';
    };
  };

  enterShell = ''
    if [ -z "''${DEVELOPER_DIR:-}" ]; then
      for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$xcode/Contents/Developer" ]; then
          export DEVELOPER_DIR="$xcode/Contents/Developer"
          break
        fi
      done
    fi
    if [ -n "''${DEVELOPER_DIR:-}" ]; then
      export PATH="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
    else
      echo "Install Xcode 27, or set DEVELOPER_DIR to its Contents/Developer directory."
    fi
  '';

  enterTest = "ruri-check";
}
