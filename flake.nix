{
  description = "ISYS2014 practicals: MySQL 8.4 development environment";

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

        excludes = [
          ".direnv/**"
          ".state/**"
          "unit_materials/**"
        ];
        excludeArgs = lib.concatMapStringsSep " " (
          pattern: "-g ${lib.escapeShellArg "!${pattern}"}"
        ) excludes;

        projectRoot = ''
          root="''${ISYS2014_ROOT:-$PWD}"
          while [[ "$root" != / && ! -f "$root/flake.nix" ]]; do
            root="$(dirname "$root")"
          done
          [[ -f "$root/flake.nix" ]] || { echo "ERROR: could not find flake.nix" >&2; exit 1; }
          cd "$root"
          export MYSQL_UNIX_PORT="$root/.state/run/mysql/mysql.sock"
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
                  ${projectRoot}
                  checksum="$(printf %s "$root" | ${pkgs.coreutils}/bin/cksum)"
                  export PC_SOCKET_PATH="/tmp/isys2014-pc-''${checksum%% *}.sock"
                '';
              };

              services.mysql.mysql = {
                enable = true;
                package = pkgs.mysql84;
                dataDir = ''"$PWD"/.state/mysql'';
                socketDir = ''"$PWD"/.state/run/mysql'';
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

        mkDb = name: text:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              dbServices
              pkgs.coreutils
              pkgs.mysql84
            ];
            text = ''
              ${projectRoot}
              ${text}
            '';
          };

        dbStart = mkDb "db-start" ''
          if mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then exit 0; fi
          mkdir -p .state/run/mysql
          if db-services process list >/dev/null 2>&1; then
            db-services process start mysql >/dev/null 2>&1 || true
            db-services process start mysql-configure >/dev/null 2>&1 || true
          else
            db-services up --keep-project --detached >/dev/null
          fi
          for _ in {1..300}; do
            mysql -u root -Nse 'USE dswork' >/dev/null 2>&1 && exit 0
            sleep 0.1
          done
          echo "ERROR: MySQL did not become ready." >&2
          db-services process list >&2 || true
          db-services process logs mysql --tail 50 >&2 || true
          db-services process logs mysql-configure --tail 50 >&2 || true
          exit 1
        '';
        dbStop = mkDb "db-stop" ''db-services down >/dev/null 2>&1 || true'';
        dbStatus = mkDb "db-status" ''exec db-services process list'';
        dbLog = mkDb "db-log" ''exec db-services process logs mysql --follow'';
        db = mkDb "db" ''
          db-start
          exec mysql -u root dswork "$@"
        '';
        dbReset = mkDb "db-reset" ''
          db-stop
          rm -rf .state/mysql .state/run/mysql
          db-start
          echo "MySQL reset: database dswork is ready."
        '';
        dbRun = pkgs.writeShellApplication {
          name = "db-run";
          runtimeInputs = [
            dbStart
            pkgs.coreutils
            pkgs.mysql84
          ];
          text = ''
            (( $# >= 1 && $# <= 2 )) || { echo "Usage: db-run FILE.sql [DATABASE]" >&2; exit 2; }
            [[ -f "$1" ]] || { printf 'ERROR: SQL file not found: %s\n' "$1" >&2; exit 1; }
            file="$(realpath "$1")"
            database="''${2:-dswork}"
            ${projectRoot}
            db-start
            mysql -u root "$database" < "$file"
          '';
        };

        sqlCompat = pkgs.writeText "isys2014-sql.py" ''
          import re
          import subprocess
          import sys
          import tempfile
          from pathlib import Path

          directive = re.compile(r"^\s*(?:source|\\\.)\s+.+;?\s*$", re.IGNORECASE)
          args = ["--dialect", "mysql", "--templater", "raw", "--exclude-rules", "CP02,RF04", "--disable-progress-bar"]

          def run(mode, path):
              path = Path(path)
              if not path.is_file():
                  print(f"ERROR: SQL file not found: {path}", file=sys.stderr)
                  return 2

              saved, lines = {}, []
              for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(keepends=True)):
                  if directive.match(line):
                      marker = f"__ISYS2014_DIRECTIVE_{i}__"
                      saved[marker] = line.rstrip("\r\n")
                      lines.append(f"-- {marker}\n")
                  else:
                      lines.append(line)

              with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as f:
                  f.writelines(lines)
                  temp = Path(f.name)
              try:
                  result = subprocess.run(["sqlfluff", mode, *args, str(temp)], capture_output=True, text=True)
                  output = (result.stdout + result.stderr).replace(str(temp), str(path))
                  if output:
                      print(output, end="", file=sys.stderr if result.returncode else sys.stdout)
                  if result.returncode or mode == "lint":
                      return result.returncode
                  formatted = temp.read_text(encoding="utf-8")
                  for marker, original in saved.items():
                      formatted = re.sub(rf"(?m)^\s*--\s*{marker}\s*$", original, formatted)
                  path.write_text(formatted, encoding="utf-8")
                  return 0
              finally:
                  temp.unlink(missing_ok=True)

          if len(sys.argv) < 3 or sys.argv[1] not in {"format", "lint"}:
              raise SystemExit("Usage: isys2014-sql {format|lint} FILE.sql [...]")
          raise SystemExit(max(run(sys.argv[1], path) for path in sys.argv[2:]))
        '';

        mkSql = name: mode:
          pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [
              pkgs.python3
              pkgs.sqlfluff
            ];
            text = ''
              (( $# )) || { echo "Usage: ${name} FILE.sql [...]" >&2; exit 2; }
              exec python3 ${sqlCompat} ${mode} "$@"
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
            global.excludes = excludes;
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
              shellcheck.options = [ "-s" "bash" ];
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

            mapfile -t markdown < <(rg --files -g '*.md' ${excludeArgs})
            (( ''${#markdown[@]} == 0 )) || { rumdl check "''${markdown[@]}"; typos "''${markdown[@]}"; }

            mapfile -t sql < <(rg --files -g '*.sql' ${excludeArgs})
            (( ''${#sql[@]} == 0 )) || sqllint "''${sql[@]}"
          '';
        };

        runCheck = package:
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
          CREATE TABLE Conference (confID CHAR(4), name VARCHAR(50), date DATE);
          source stadium.txt;
          SQL
          sqlfmt assessment.sql
          sqllint assessment.sql
          grep -Fqx 'source stadium.txt;' assessment.sql
          grep -Fq Conference assessment.sql
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

        mkAlias = alias: command:
          pkgs.writeShellScriptBin alias ''exec ${command} "$@"'';
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
            treefmt.config.build.wrapper
            lint
            sqlfmt
            sqllint
            dbServices
            dbStart
            dbStop
            dbStatus
            dbLog
            db
            dbRun
            dbReset
            (mkAlias "fmt" (lib.getExe treefmt.config.build.wrapper))
            (mkAlias "lt" (lib.getExe lint))
            (mkAlias "chk" "nix flake check")
          ];

          shellHook = ''
            ${preCommit.shellHook}
            export ISYS2014_ROOT="$PWD"
            export MYSQL_UNIX_PORT="$PWD/.state/run/mysql/mysql.sock"
            export MYSQL_HISTFILE="$PWD/.state/mysql_history"
            echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
          '';
        };

        formatter = treefmt.config.build.wrapper;

        packages = {
          inherit lint sqlfmt sqllint db dbRun dbReset;
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
