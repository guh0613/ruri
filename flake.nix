{
  description = "Ruri for macOS and its Xcode development environment";

  inputs = {
    # 26.05 still supports Intel macOS; 26.11 has dropped x86_64-darwin.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, devenv, ... }@inputs:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forEachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          # Upstream has not published a license; permit only this binary package.
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "ruri-launcher";
        };
      packageFor = system: (pkgsFor system).callPackage ./nix/package.nix { };
    in
    {
      packages = forEachSystem (system: {
        default = packageFor system;
        ruri-launcher = packageFor system;
      });

      apps = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          ruri = packageFor system;
        in
        {
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "ruri-open" ''
              exec /usr/bin/open -a "${ruri}/Applications/Ruri.app" "$@"
            ''}";
          };
          cli = {
            type = "app";
            program = "${ruri}/bin/ruri";
          };
        }
      );

      devShells = forEachSystem (system: {
        default = devenv.lib.mkShell {
          inherit inputs;
          pkgs = pkgsFor system;
          modules = [ ./devenv.nix ];
        };
      });

      checks = forEachSystem (
        system:
        let
          pkgs = pkgsFor system;
          src = nixpkgs.lib.fileset.toSource {
            root = ./.;
            fileset = nixpkgs.lib.fileset.unions [
              ./Package.swift
              ./Resources
              ./Sources
              ./scripts
            ];
          };
        in
        {
          package = packageFor system;
          scripts = pkgs.runCommand "ruri-script-checks" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            cp -R ${src} source
            chmod -R u+w source
            cd source
            python3 -m unittest discover -s scripts/tests
            python3 scripts/localization.py --check
            touch "$out"
          '';
        }
      );

      formatter = forEachSystem (system: (pkgsFor system).nixfmt-tree);
    };
}
