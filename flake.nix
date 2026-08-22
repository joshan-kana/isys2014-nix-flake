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

        # Single source of truth for generated/lecturer-provided files.
        globalExcludes = [
          ".direnv/**"
          ".state/**"
          "unit_materials/**"
        ];
        excludeArgs = lib.concatMapStringsSep " " (
          pattern: "-g ${lib.escapeShellArg "!${pattern}"}"
        ) globalExcludes;

        # Runtime-only path discovery keeps evaluation pure and sockets short.
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

        # Thin command UI only; services-flake/process-compose own supervision.
        dbctl = pkgs.writeShellApplication {
          name = "dbctl";
          runtimeInputs = [
            dbServices
            pkgs.coreutils
            pkgs.mysql84
          ];
          text = ''
            ${runtimeEnv}

            start() {
              mysql -u root -Nse 'USE dswork' >/dev/null 2>&1 && return
              mkdir -p "$ISYS2014_RUN_DIR"

              if db-services process list >/dev/null 2>&1; then
                db-services process start mysql >/dev/null 2>&1 || true
                db-services process start mysql-configure >/dev/null 2>&1 || true
              else
                db-services up --detached >/dev/null
              fi

              timeout 30 db-services project is-ready --wait >/dev/null 2>&1 &&
                mysql -u root -Nse 'USE dswork' >/dev/null 2>&1 && return

              echo "ERROR: MySQL did not become ready." >&2
              db-services process list >&2 || true
              db-services process logs mysql --tail 50 >&2 || true
              db-services process logs mysql-configure --tail 50 >&2 || true
              return 1
            }

            command="''${1:-shell}"
            (( $# == 0 )) || shift
            case "$command" in
              start) start ;;
              stop) db-services down >/dev/null 2>&1 || true ;;
              status) exec db-services process list ;;
              log) exec db-services process logs mysql --follow ;;
              shell) start; exec mysql -u root dswork "$@" ;;
              run)
                (( $# >= 1 && $# <= 2 )) || { echo "Usage: db-run FILE.sql [DATABASE]" >&2; exit 2; }
                [[ -f "$1" ]] || { printf 'ERROR: SQL file not found: %s\n' "$1" >&2; exit 1; }
                file="$(realpath "$1")"; database="''${2:-dswork}"
                start
                mysql -u root "$database" < "$file"
                ;;
              reset)
                db-services down >/dev/null 2>&1 || true
                rm -rf -- "$ISYS2014_ROOT/.state/mysql" "$ISYS2014_RUN_DIR"
                start
                echo "MySQL reset: database dswork is ready."
                ;;
              *) echo "Usage: dbctl {start|stop|status|log|shell|run|reset}" >&2; exit 2 ;;
            esac
          '';
        };
        dbPackages = lib.mapAttrs (
          name: command:
          pkgs.writeShellScriptBin name ''exec ${lib.getExe dbctl} ${command} "$@"''
        ) {
          db = "shell";
          "db-start" = "start";
          "db-stop" = "stop";
          "db-status" = "status";
          "db-log" = "log";
          "db-run" = "run";
          "db-reset" = "reset";
        };

        sqlRunner = pkgs.writeShellApplication {
          name = "isys2014-sql";
          runtimeInputs = [
            pkgs.python3
            pkgs.sqlfluff
          ];
          text = ''exec python3 ${./scripts/sqlfluff-wrapper.py} "$@"'';
        };
        mkSql =
          name: mode:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [ sqlRunner ];
            text = ''
              (( $# )) || { echo "Usage: ${name} FILE.sql [...]" >&2; exit 2; }
              exec isys2014-sql ${mode} "$@"
            '';
          };
        sqlfmt = mkSql "sqlfmt" "format";
        sqllint = mkSql "sqllint" "lint";

        treefmt = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            deadnix.enable = true;
            nixfmt.enable = true;
            rumdl-check.enable = true;
            rumdl-format.enable = true;
            shellcheck.enable = true;
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
              sql-format = {
                command = lib.getExe sqlfmt;
                includes = [ "*.sql" ];
                priority = 1;
              };
              sql-lint = {
                command = lib.getExe sqllint;
                includes = [ "*.sql" ];
                priority = 2;
              };
            };
          };
        };

        lint = pkgs.writeShellApplication {
          name = "lint";
          runtimeInputs = [
            pkgs.deadnix
            pkgs.python3
            pkgs.ripgrep
            pkgs.rumdl
            pkgs.shellcheck
            pkgs.statix
            pkgs.typos
            sqllint
          ];
          text = ''
            statix check flake.nix
            deadnix --fail flake.nix
            shellcheck -s bash .envrc
            python3 -m py_compile scripts/sqlfluff-wrapper.py

            mapfile -t markdown < <(rg --files -g '*.md' ${excludeArgs})
            (( ''${#markdown[@]} == 0 )) || { rumdl check "''${markdown[@]}"; typos "''${markdown[@]}"; }

            mapfile -t sql < <(rg --files -g '*.sql' ${excludeArgs})
            (( ''${#sql[@]} == 0 )) || sqllint "''${sql[@]}"
          '';
        };
        check = pkgs.writeShellApplication {
          name = "check";
          runtimeInputs = [ pkgs.nix ];
          text = ''exec nix flake check "$@"'';
        };
        runCheck =
          package:
          pkgs.runCommand "isys2014-${package.name}-check" { nativeBuildInputs = [ package ]; } ''
            cp -R ${self} source
            chmod -R u+w source
            cd source
            ${lib.getExe package}
            touch "$out"
          '';
        sqlCheck = pkgs.runCommand "isys2014-sql-check" {
          nativeBuildInputs = [
            pkgs.gnugrep
            sqlfmt
            sqllint
          ];
        } ''
          cat > assessment.sql <<'SQL'
          CREATE TABLE Conference (
            confID CHAR(4),
            name VARCHAR(50),
            date DATE,
            count INT
          );
          source stadium.txt;
          SQL
          sqlfmt assessment.sql
          sqllint assessment.sql
          grep -Fqx 'source stadium.txt;' assessment.sql
          grep -Fq Conference assessment.sql
          grep -Fq confID assessment.sql
          touch "$out"
        '';

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
        mkAlias =
          alias: package:
          pkgs.writeShellScriptBin alias ''exec ${lib.getExe package} "$@"'';
      in
      {
        devShells.default = pkgs.mkShell {
          packages =
            (with pkgs; [
              deadnix
              less
              mysql84
              nixd
              nixfmt
              rumdl
              shellcheck
              sqlfluff
              statix
              typos
              zip
            ])
            ++ [
              treefmt.config.build.wrapper
              lint
              check
              sqlfmt
              sqllint
              dbServices
              dbctl
              (mkAlias "fmt" treefmt.config.build.wrapper)
              (mkAlias "lt" lint)
              (mkAlias "chk" check)
            ]
            ++ lib.attrValues dbPackages;

          shellHook = ''
            ${preCommit.shellHook}
            ${runtimeEnv}
            echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
          '';
        };

        formatter = treefmt.config.build.wrapper;
        packages = dbPackages // {
          inherit
            check
            dbctl
            lint
            sqlfmt
            sqllint
            ;
          "db-services" = dbServices;
          default = lint;
        };
        checks = {
          formatting = treefmt.config.build.check self;
          lint = runCheck lint;
          sql = sqlCheck;
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
