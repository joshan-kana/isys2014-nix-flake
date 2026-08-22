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

        globalExcludes = [
          ".direnv/**"
          ".state/**"
          "unit_materials/**"
        ];

        runtimeEnv = ''
          root="''${ISYS2014_ROOT:-$PWD}"
          while [[ "$root" != / && ! -f "$root/flake.nix" ]]; do root="$(dirname "$root")"; done
          [[ -f "$root/flake.nix" ]] || { echo "ERROR: could not find flake.nix" >&2; exit 1; }
          id="$(printf '%s' "$root" | cksum)"
          export ISYS2014_ROOT="$root"
          export ISYS2014_RUN_DIR="/tmp/isys2014-''${id%% *}"
          export MYSQL_UNIX_PORT="$ISYS2014_RUN_DIR/mysql.sock"
          export MYSQL_HISTFILE="$root/.state/mysql_history"
        '';

        dbServices = (import process-compose-flake.lib { inherit pkgs; }).makeProcessCompose {
          name = "db-services";
          modules = [
            services-flake.processComposeModules.default
            {
              cli = {
                options = {
                  no-server = false;
                  use-uds = true;
                };
                preHook = ''
                  ${runtimeEnv}
                  mkdir -p "$ISYS2014_RUN_DIR"
                  cd "$ISYS2014_ROOT"
                  export PC_SOCKET_PATH="$ISYS2014_RUN_DIR/process-compose.sock"
                '';
              };
              services.mysql.mysql = {
                enable = true;
                package = pkgs.mysql84;
                dataDir = ''"$ISYS2014_ROOT"/.state/mysql'';
                socketDir = ''"$ISYS2014_RUN_DIR"'';
                initialDatabases = [ { name = "dswork"; } ];
                settings.mysqld = {
                  "skip-networking" = true;
                  "skip-log-bin" = true;
                  mysqlx = "OFF";
                  "innodb-buffer-pool-size" = "64M";
                };
              };
            }
          ];
        };

        ensureDb = ''
          if ! mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then
            if db-services process list >/dev/null 2>&1; then
              db-services process start mysql >/dev/null 2>&1 || true
              db-services process start mysql-configure >/dev/null 2>&1 || true
            else
              db-services up --detached >/dev/null
            fi
            timeout 30 db-services project is-ready --wait >/dev/null
          fi
        '';
        mkDbCommand =
          name: text:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              dbServices
              pkgs.coreutils
              pkgs.mysql84
            ];
            text = ''
              ${runtimeEnv}
              ${text}
            '';
          };
        dbCommands = {
          db = mkDbCommand "db" ''
            ${ensureDb}
            exec mysql -u root dswork "$@"
          '';
          "db-start" = mkDbCommand "db-start" ensureDb;
          "db-run" = mkDbCommand "db-run" ''
            (( $# >= 1 && $# <= 2 )) || { echo "Usage: db-run FILE.sql [DATABASE]" >&2; exit 2; }
            [[ -f "$1" ]] || { printf 'ERROR: SQL file not found: %s\n' "$1" >&2; exit 1; }
            file="$(realpath "$1")"
            database="''${2:-dswork}"
            ${ensureDb}
            exec mysql -u root "$database" < "$file"
          '';
          "db-reset" = mkDbCommand "db-reset" ''
            db-services down >/dev/null 2>&1 || true
            rm -rf -- "$ISYS2014_ROOT/.state/mysql" "$ISYS2014_RUN_DIR"
            ${ensureDb}
            echo "MySQL reset: database dswork is ready."
          '';
        }
        //
          lib.mapAttrs
            (name: args: pkgs.writeShellScriptBin name ''exec ${lib.getExe dbServices} ${args} "$@"'')
            {
              "db-stop" = "down";
              "db-status" = "process list";
              "db-log" = "process logs mysql --follow";
            };

        sqlOptions = [
          "--templater=raw"
          "--ignore=parsing"
          "--exclude-rules=CP02,RF04"
        ];
        treefmt = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            deadnix.enable = true;
            nixfmt.enable = true;
            rumdl-check.enable = true;
            rumdl-format.enable = true;
            shellcheck.enable = true;
            sqlfluff = {
              enable = true;
              dialect = "mysql";
            };
            sqlfluff-lint.enable = true;
            statix.enable = true;
            typos.enable = true;
          };
          settings = {
            global.excludes = globalExcludes;
            formatter = {
              statix.priority = 1;
              deadnix.priority = 2;
              nixfmt.priority = 3;
              rumdl-format.priority = 1;
              rumdl-check.priority = 2;
              typos = {
                includes = [ "*.md" ];
                priority = 3;
              };
              shellcheck.options = [
                "-s"
                "bash"
              ];
              sqlfluff = {
                options = sqlOptions;
                priority = 1;
              };
              sqlfluff-lint = {
                options = sqlOptions;
                priority = 2;
              };
            };
          };
        };

        preCommit = pre-commit-hooks.lib.${system}.run {
          src = self;
          hooks.nix-flake-check = {
            enable = true;
            name = "nix flake check";
            entry = "nix flake check";
            language = "system";
            pass_filenames = false;
          };
        };
        fmt = pkgs.writeShellScriptBin "fmt" ''exec ${lib.getExe treefmt.config.build.wrapper} "$@"'';
        chk = pkgs.writeShellScriptBin "chk" ''exec ${pkgs.nix}/bin/nix flake check "$@"'';
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            (with pkgs; [
              less
              mysql84
              nixd
              nixfmt
              zip
            ])
            ++ [
              treefmt.config.build.wrapper
              dbServices
              fmt
              chk
            ]
            ++ lib.attrValues dbCommands;

          shellHook = ''
            ${preCommit.shellHook}
            ${runtimeEnv}
            echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
          '';
        };

        formatter = treefmt.config.build.wrapper;
        packages = dbCommands // {
          "db-services" = dbServices;
        };
        checks = {
          formatting = treefmt.config.build.check self;
          services = dbServices;
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
