{
  description = "ISYS2014 practicals: pure MySQL 8.4 development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
    services-flake.url = "github:juspay/services-flake";

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
      process-compose-flake,
      services-flake,
      treefmt-nix,
      pre-commit-hooks,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (pkgs) lib;

        # One exclusion list for both formatting and read-only linting.
        globalExcludes = [
          ".direnv/**"
          ".state/**"
          "unit_materials/**"
        ];

        sql = import ./nix/sql.nix { inherit pkgs; };
        db = import ./nix/mysql.nix {
          inherit pkgs process-compose-flake services-flake;
        };
        tooling = import ./nix/tooling.nix {
          inherit
            pkgs
            self
            treefmt-nix
            pre-commit-hooks
            globalExcludes
            ;
          inherit (sql) sqlfmt sqllint;
        };

        mkAlias =
          alias: package:
          pkgs.writeShellScriptBin alias ''
            exec ${lib.getExe package} "$@"
          '';
      in
      {
        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.deadnix
            pkgs.less
            pkgs.mysql84
            pkgs.nixd
            pkgs.nixfmt
            pkgs.rumdl
            pkgs.shellcheck
            pkgs.sqlfluff
            pkgs.statix
            pkgs.typos
            pkgs.zip
            tooling.treefmt.config.build.wrapper
            tooling.lint
            tooling.check
            sql.sqlfmt
            sql.sqllint
          ]
          ++ db.packages
          ++ [
            (mkAlias "fmt" tooling.treefmt.config.build.wrapper)
            (mkAlias "lt" tooling.lint)
            (mkAlias "chk" tooling.check)
          ];

          shellHook = ''
            ${tooling.preCommit.shellHook}
            ${db.shellHook}
            echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
          '';
        };

        formatter = tooling.treefmt.config.build.wrapper;

        packages = {
          inherit (sql) sqlfmt sqllint;
          inherit (tooling) lint check;
          inherit (db)
            db
            dbStart
            dbStop
            dbStatus
            dbLog
            dbRun
            dbReset
            dbServices
            ;
          default = tooling.lint;
        };

        checks = {
          formatting = tooling.treefmt.config.build.check self;
          lint = tooling.runCheck tooling.lint;
          sql = sql.check;
          inherit (db) services;
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
