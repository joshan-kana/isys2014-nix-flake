{
  description = "ISYS2014 practicals: reproducible MySQL 8.4 development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    devenv = {
      url = "github:cachix/devenv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      devenv,
      treefmt-nix,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      treefmtConfig = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
          statix.enable = true;
        };
        settings.global.excludes = [
          ".devenv/**"
          ".direnv/**"
        ];
      };

      treefmtFor = system: treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} treefmtConfig;

      lintFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "lint";
          runtimeInputs = [
            pkgs.shellcheck
            pkgs.statix
          ];
          text = ''
            statix check flake.nix
            statix check devenv.nix
            shellcheck -s bash .envrc
          '';
        };

      runCheck =
        system: pkg:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.runCommand "isys2014-${pkg.name}-check" { nativeBuildInputs = [ pkg ]; } ''
          cp -R ${self} source
          chmod -R u+w source
          cd source
          ${pkg}/bin/${pkg.name}
          touch "$out"
        '';
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          lint = lintFor system;
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              ./devenv.nix
              {
                packages = [ lint ];

                scripts = {
                  lt.exec = ''exec lint "$@"'';
                  fmt.exec = ''exec nix fmt "$@"'';
                  chk.exec = ''exec nix flake check --impure "$@"'';
                };

                treefmt = {
                  enable = true;
                  config = treefmtConfig;
                };

                git-hooks.hooks.nix-flake-check = {
                  enable = true;
                  name = "nix flake check";
                  entry = "nix flake check --impure";
                  language = "system";
                  pass_filenames = false;
                };
              }
            ];
          };
        }
      );

      formatter = forAllSystems (system: (treefmtFor system).config.build.wrapper);

      packages = forAllSystems (system: {
        lint = lintFor system;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmt = treefmtFor system;
          lint = lintFor system;
        in
        {
          formatting = treefmt.config.build.check self;
          lint = runCheck system lint;
          mysql-client =
            pkgs.runCommand "isys2014-mysql-client-check" { nativeBuildInputs = [ pkgs.mysql84 ]; }
              ''
                mysql --version > "$out"
              '';
        }
      );

      templates.default = {
        path = ./.;
        description = "ISYS2014 practical: isolated MySQL 8.4 environment";
      };
    };
}
