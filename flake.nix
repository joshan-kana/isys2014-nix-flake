{
  description = "ISYS2014 practicals: isolated MySQL 8.4 and database tools";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      pre-commit-hooks,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        mysql = pkgs.mysql84;

        dbctl = pkgs.writeShellApplication {
          name = "dbctl";
          runtimeInputs = [
            mysql
            pkgs.coreutils
          ];
          text = builtins.readFile ./scripts/dbctl.sh;
        };

        mkDbCommand =
          name: command:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [ dbctl ];
            text = ''exec dbctl ${command} "$@"'';
          };

        dbStart = mkDbCommand "db-start" "start";
        dbStop = mkDbCommand "db-stop" "stop";
        dbStatus = mkDbCommand "db-status" "status";
        dbReset = mkDbCommand "db-reset" "reset";
        dbShell = mkDbCommand "db-shell" "shell";
        dbRun = mkDbCommand "db-run" "run";
        dbLog = mkDbCommand "db-log" "log";

        mkAlias =
          alias: package:
          pkgs.writeShellScriptBin alias ''
            exec ${pkgs.lib.getExe package} "$@"
          '';

        treefmt = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            statix.enable = true;
          };
          settings.global.excludes = [
            ".direnv/**"
            ".mysql/**"
          ];
        };

        lint = pkgs.writeShellApplication {
          name = "lint";
          runtimeInputs = [
            pkgs.shellcheck
            pkgs.statix
          ];
          text = ''
            statix check flake.nix
            shellcheck scripts/*.sh
          '';
        };

        check = pkgs.writeShellApplication {
          name = "check";
          runtimeInputs = [ pkgs.nix ];
          text = ''exec nix flake check "''${1:-${self}}" "$@"'';
        };

        runCheck =
          pkg:
          pkgs.runCommand "isys2014-${pkg.name}-check" { nativeBuildInputs = [ pkg ]; } ''
            cp -R ${self} source
            chmod -R u+w source
            cd source
            ${pkg}/bin/${pkg.name}
            touch "$out"
          '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            mysql
            pkgs.less
            pkgs.nixd
            pkgs.nixfmt
            pkgs.shellcheck
            pkgs.statix
            pkgs.zip
            dbctl
            dbStart
            dbStop
            dbStatus
            dbReset
            dbShell
            dbRun
            dbLog
            (mkAlias "db" dbShell)
            (mkAlias "lt" lint)
            (mkAlias "fmt" treefmt.config.build.wrapper)
            (mkAlias "chk" check)
            treefmt.config.build.wrapper
          ];

          shellHook = ''
            ${(pre-commit-hooks.lib.${system}.run {
              src = self;
              hooks.nix-flake-check = {
                enable = true;
                name = "nix flake check";
                entry = "nix flake check";
                language = "system";
                pass_filenames = false;
              };
            }).shellHook
            }
            eval "$(dbctl env)"
            dbctl start --quiet
            echo "MySQL ready: mysql -u root    database: dswork"
          '';
        };

        formatter = treefmt.config.build.wrapper;

        packages = {
          inherit dbctl lint;
          "db-start" = dbStart;
          "db-stop" = dbStop;
          "db-status" = dbStatus;
          "db-reset" = dbReset;
          "db-shell" = dbShell;
          "db-run" = dbRun;
          "db-log" = dbLog;
          default = dbShell;
        };

        checks = {
          formatting = treefmt.config.build.check self;
          lint = runCheck lint;
          mysql-client = pkgs.runCommand "isys2014-mysql-client-check" { nativeBuildInputs = [ mysql ]; } ''
            mysql --version > "$out"
          '';
        };
      }
    )
    // {
      templates.default = {
        path = ./.;
        description = "ISYS2014 practical: isolated MySQL 8.4 environment";
      };
    };
}
