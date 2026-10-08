{
  lib,
  stdenvNoCC,
  fetchurl,
  undmg,
}:
let
  releases = {
    aarch64-darwin = {
      arch = "arm64";
      hash = "sha256-JU1hrP1xBGwavc8stbaVs2UZyTwmx4uXwalKMGbHK8E=";
    };
    x86_64-darwin = {
      arch = "x86_64";
      hash = "sha256-OXQAyA8REI4AwzbeVSGW3zIe9biUy3t+FBaAsicLTXw=";
    };
  };
  release = releases.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "ruri-launcher";
  version = "0.10.5";

  src = fetchurl {
    url = "https://github.com/guh0613/ruri/releases/download/v${finalAttrs.version}/Ruri-${finalAttrs.version}-macOS-${release.arch}.dmg";
    inherit (release) hash;
  };

  nativeBuildInputs = [ undmg ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # Keep the upstream Mach-O binaries, framework symlinks and signatures intact.
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R Ruri.app "$out/Applications/"
    ln -s "$out/Applications/Ruri.app/Contents/Helpers/ruri-cli" "$out/bin/ruri"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test "$("$out/bin/ruri" --version)" = "${finalAttrs.version}"
    "$out/bin/ruri" --help > /dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Minecraft Java launcher for macOS";
    homepage = "https://github.com/guh0613/ruri";
    # No license is published upstream. Revisit when a license is added.
    license = lib.licenses.unfree;
    platforms = lib.platforms.darwin;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "ruri";
  };
})
