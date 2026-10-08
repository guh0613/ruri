# Ruri

A Minecraft Java launcher for macOS.

## Nix package

On Apple silicon or Intel macOS (macOS 14 or newer):

```sh
nix build
open result/Applications/Ruri.app
nix run .#cli -- --help
```

`nix run` opens the GUI. The default package (`ruri-launcher`) installs the upstream
0.10.5 release DMG, with a separate SHA-256 hash for each architecture. It keeps
the complete signed app, including Sparkle, resources and game/CLI helpers.
`bin/ruri` points to the CLI inside the app so it can find its resources.
The package does not compile the current checkout; local source changes are
built with the development commands below.

The flake uses the Nixpkgs 26.05 Darwin branch to support both architectures.
Nixpkgs 26.11 and newer have dropped Intel macOS support.

Downstream Nix configurations can use
`inputs.ruri.packages.${pkgs.stdenv.hostPlatform.system}.default`. The app is
installed under `Applications/Ruri.app`, as expected by nix-darwin and Home
Manager. Update the version and both hashes in `nix/package.nix` to upgrade the
installed release. The Nix store is read-only; use Nix to upgrade this app
instead of Sparkle's in-app installer.

## Development with devenv

Install **Xcode 27** and complete its first-launch setup. The Command Line Tools
alone do not provide the full app-packaging toolchain. Xcode supplies Swift,
SourceKit-LSP, the macOS SDK, icon compilation and signing tools, matching CI.
Nix supplies the auxiliary tools and commands through `devenv.nix`.

```sh
nix develop --impure
ruri-check
ruri-build --force-resolved-versions
ruri-test --no-parallel --force-resolved-versions
ruri-bundle debug --force-resolved-versions
open build/Ruri.app
```

`ruri-bundle` defaults to a release build; `ruri-dmg` also creates a DMG in
`build/dmg`. These commands reuse the existing scripts, including signing,
localization and packaged-CLI validation. Contributor builds use ad hoc signing
when the pinned signing identity is unavailable.

The shell selects `/Applications/Xcode.app` (or `Xcode-beta.app`) without changing
the system's `xcode-select` setting. Set `DEVELOPER_DIR` before entering the shell
to select another Xcode. Existing overrides such as `RURI_ARCH=x86_64` and
`RURI_BUILD_DIR` still work.

With nix-direnv configured, `direnv allow` enables the same environment in your
existing shell. This project uses devenv's flake integration and one
`flake.lock`; enter through `nix develop --impure` or direnv.

```sh
nix flake check --impure # Package/CLI and Python/localization checks
nix fmt            # Format Nix files
nix flake update   # Update the pinned Nix tools (not the binary app version)
```

The environment is pinned by `flake.lock`, and Swift dependencies by
`Package.resolved`. Xcode is installed separately; its version is not managed by
Nix. Swift builds resolve their dependencies over the network on first use.
