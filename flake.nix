{
  description = "ISYS2014 practicals: pure, reproducible MySQL 8.4 development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
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
    inputs@{
      self,
      flake-parts,
      process-compose-flake,
      services-flake,
      treefmt-nix,
      pre-commit-hooks,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      imports = [ process-compose-flake.flakeModule ];

      flake.templates.default = {
        path = ./.;
        description = "ISYS2014 practical: isolated MySQL 8.4 environment";
      };

      perSystem =
        {
          config,
          pkgs,
          system,
          lib,
          ...
        }:
        let
          globalExcludes = [
            ".direnv/**"
            ".state/**"
            "unit_materials/**"
          ];
          rgExcludeArgs = lib.concatMapStringsSep " " (
            pattern: "-g ${lib.escapeShellArg "!${pattern}"}"
          ) globalExcludes;

          stateDir = ".state";
          mysqlDataDir = "${stateDir}/mysql";
          mysqlSocketDir = "${stateDir}/run/mysql";
          mysqlSocket = "${mysqlSocketDir}/mysql.sock";

          projectRoot = ''
            root="$PWD"
            while [[ "$root" != "/" && ! -f "$root/flake.nix" ]]; do
              root="$(dirname "$root")"
            done
            if [[ ! -f "$root/flake.nix" ]]; then
              echo "ERROR: could not find flake.nix from $PWD" >&2
              exit 1
            fi
          '';
          enterProjectRoot = projectRoot + ''
            cd "$root"
          '';

          sqlTool = pkgs.writeShellApplication {
            name = "isys2014-sql";
            runtimeInputs = [
              pkgs.python3
              pkgs.sqlfluff
            ];
            text = ''
              exec python3 - "$@" <<'PY'
              import os
              import re
              import subprocess
              import sys
              import tempfile
              from pathlib import Path

              if len(sys.argv) < 3 or sys.argv[1] not in {"format", "lint"}:
                  print("Usage: isys2014-sql {format|lint} FILE.sql [...]", file=sys.stderr)
                  raise SystemExit(2)

              mode = sys.argv[1]
              directive = re.compile(r"^\s*(?:source|\\\.)\s+.+;?\s*$", re.IGNORECASE)
              status = 0

              for path_arg in sys.argv[2:]:
                  path = Path(path_arg)
                  if not path.is_file():
                      print(f"ERROR: SQL file not found: {path}", file=sys.stderr)
                      status = 2
                      continue

                  original_lines = path.read_text().splitlines(keepends=True)
                  directives = {}
                  prepared_lines = []

                  for index, line in enumerate(original_lines):
                      if directive.match(line):
                          marker = f"__ISYS2014_MYSQL_CLIENT_DIRECTIVE_{index}__"
                          newline = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
                          directives[marker] = line
                          prepared_lines.append(f"-- {marker}{newline}")
                      else:
                          prepared_lines.append(line)

                  fd, temporary_name = tempfile.mkstemp(suffix=".sql")
                  os.close(fd)
                  temporary = Path(temporary_name)

                  try:
                      temporary.write_text("".join(prepared_lines))
                      result = subprocess.run(
                          [
                              "sqlfluff",
                              mode,
                              "--dialect",
                              "mysql",
                              "--templater",
                              "raw",
                              "--exclude-rules",
                              "CP02,RF04",
                              "--disable-progress-bar",
                              str(temporary),
                          ],
                          capture_output=True,
                          text=True,
                      )

                      output = (result.stdout + result.stderr).replace(str(temporary), str(path))
                      if output:
                          print(output, end="", file=sys.stderr if result.returncode else sys.stdout)

                      if result.returncode:
                          status = result.returncode
                          continue

                      if mode == "format":
                          restored = []
                          seen = set()
                          for line in temporary.read_text().splitlines(keepends=True):
                              matches = [marker for marker in directives if marker in line]
                              if len(matches) > 1:
                                  print(f"ERROR: SQL formatter marker collision in {path}", file=sys.stderr)
                                  status = 1
                                  restored = []
                                  break
                              if matches:
                                  marker = matches[0]
                                  if marker in seen:
                                      print(f"ERROR: SQL formatter duplicated a client directive in {path}", file=sys.stderr)
                                      status = 1
                                      restored = []
                                      break
                                  restored.append(directives[marker])
                                  seen.add(marker)
                              else:
                                  restored.append(line)

                          if restored:
                              missing = set(directives) - seen
                              if missing:
                                  print(f"ERROR: SQL formatter dropped a client directive in {path}", file=sys.stderr)
                                  status = 1
                              else:
                                  path.write_text("".join(restored))
                  finally:
                      temporary.unlink(missing_ok=True)

              raise SystemExit(status)
              PY
            '';
          };

          sqlfmt = pkgs.writeShellApplication {
            name = "sqlfmt";
            runtimeInputs = [ sqlTool ];
            text = ''
              if (( $# == 0 )); then
                echo "Usage: sqlfmt FILE.sql [...]" >&2
                exit 2
              fi
              exec isys2014-sql format "$@"
            '';
          };

          sqllint = pkgs.writeShellApplication {
            name = "sqllint";
            runtimeInputs = [ sqlTool ];
            text = ''
              if (( $# == 0 )); then
                echo "Usage: sqllint FILE.sql [...]" >&2
                exit 2
              fi
              exec isys2014-sql lint "$@"
            '';
          };

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
                sqlfluff = {
                  command = lib.getExe sqlfmt;
                  includes = [ "*.sql" ];
                  priority = 1;
                };
                sqlfluff-lint = {
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
              mapfile -t nix_files < <(rg --files -g '*.nix' ${rgExcludeArgs})
              for file in "''${nix_files[@]}"; do
                statix check "$file"
              done
              if (( ''${#nix_files[@]} )); then
                deadnix --fail "''${nix_files[@]}"
              fi

              mapfile -t markdown_files < <(rg --files -g '*.md' ${rgExcludeArgs})
              if (( ''${#markdown_files[@]} )); then
                rumdl check "''${markdown_files[@]}"
                typos "''${markdown_files[@]}"
              fi

              mapfile -t sql_files < <(rg --files -g '*.sql' ${rgExcludeArgs})
              if (( ''${#sql_files[@]} )); then
                sqllint "''${sql_files[@]}"
              fi

              shellcheck -s bash .envrc
            '';
          };

          runCheck = pkg:
            pkgs.runCommand "isys2014-${pkg.name}-check" { nativeBuildInputs = [ pkg ]; } ''
              cp -R ${self} source
              chmod -R u+w source
              cd source
              ${pkg}/bin/${pkg.name}
              touch "$out"
            '';

          serviceRunner = config.process-compose."db-services".outputs.package;

          dbServices = pkgs.writeShellApplication {
            name = "db-services";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              ${enterProjectRoot}
              checksum="$(${pkgs.coreutils}/bin/cksum <<< "$root")"
              checksum="''${checksum%% *}"
              port="$((20000 + checksum % 30000))"
              exec ${serviceRunner}/bin/db-services --address 127.0.0.1 --port "$port" "$@"
            '';
          };

          dbStart = pkgs.writeShellApplication {
            name = "db-start";
            runtimeInputs = [
              dbServices
              pkgs.coreutils
              pkgs.mysql84
            ];
            text = ''
              ${enterProjectRoot}
              mkdir -p ${lib.escapeShellArg mysqlSocketDir}

              if mysql --socket=${lib.escapeShellArg mysqlSocket} -u root -Nse 'USE dswork' >/dev/null 2>&1; then
                exit 0
              fi

              if db-services process list >/dev/null 2>&1; then
                db-services process start mysql >/dev/null 2>&1 || true
                db-services process start mysql-configure >/dev/null 2>&1 || true
              else
                db-services up --detached >/dev/null
              fi

              for _ in {1..300}; do
                if mysql --socket=${lib.escapeShellArg mysqlSocket} -u root -Nse 'USE dswork' >/dev/null 2>&1; then
                  exit 0
                fi
                sleep 0.1
              done

              echo "ERROR: MySQL did not become ready." >&2
              db-services process logs mysql --tail 50 >&2 || true
              exit 1
            '';
          };

          dbStop = pkgs.writeShellApplication {
            name = "db-stop";
            runtimeInputs = [ dbServices ];
            text = ''
              ${enterProjectRoot}
              db-services down >/dev/null 2>&1 || true
            '';
          };

          dbStatus = pkgs.writeShellApplication {
            name = "db-status";
            runtimeInputs = [ dbServices ];
            text = ''
              ${enterProjectRoot}
              exec db-services process list
            '';
          };

          dbLog = pkgs.writeShellApplication {
            name = "db-log";
            runtimeInputs = [ dbServices ];
            text = ''
              ${enterProjectRoot}
              exec db-services process logs mysql --follow
            '';
          };

          db = pkgs.writeShellApplication {
            name = "db";
            runtimeInputs = [
              dbStart
              pkgs.coreutils
              pkgs.mysql84
            ];
            text = ''
              ${enterProjectRoot}
              db-start
              exec mysql --socket="$root/${mysqlSocket}" -u root dswork "$@"
            '';
          };

          dbRun = pkgs.writeShellApplication {
            name = "db-run";
            runtimeInputs = [
              dbStart
              pkgs.coreutils
              pkgs.mysql84
            ];
            text = ''
              if (( $# < 1 || $# > 2 )); then
                echo "Usage: db-run FILE.sql [DATABASE]" >&2
                exit 2
              fi
              file="$1"
              database="''${2:-dswork}"
              if [[ ! -f "$file" ]]; then
                printf 'ERROR: SQL file not found: %s\n' "$file" >&2
                exit 1
              fi
              file="$(realpath "$file")"
              ${enterProjectRoot}
              db-start
              mysql --socket="$root/${mysqlSocket}" -u root "$database" < "$file"
            '';
          };

          dbReset = pkgs.writeShellApplication {
            name = "db-reset";
            runtimeInputs = [
              dbStart
              dbStop
              pkgs.coreutils
            ];
            text = ''
              ${enterProjectRoot}
              db-stop
              rm -rf -- ${lib.escapeShellArg mysqlDataDir} ${lib.escapeShellArg mysqlSocketDir}
              db-start
              echo "MySQL reset: database dswork is ready."
            '';
          };

          check = pkgs.writeShellApplication {
            name = "check";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${enterProjectRoot}
              exec nix flake check "$@"
            '';
          };

          mkAlias = alias: package:
            pkgs.writeShellScriptBin alias ''
              exec ${lib.getExe package} "$@"
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
        in
        {
          process-compose."db-services" = {
            imports = [ services-flake.processComposeModules.default ];
            cli.options.keep-project = true;

            services.mysql.mysql = {
              enable = true;
              package = pkgs.mysql84;
              dataDir = mysqlDataDir;
              socketDir = mysqlSocketDir;
              initialDatabases = [ { name = "dswork"; } ];

              settings.mysqld = {
                "skip-networking" = true;
                "skip-log-bin" = true;
                mysqlx = "OFF";
                "innodb-buffer-pool-size" = "64M";
              };
            };
          };

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
              dbServices
              lint
              sqlfmt
              sqllint
              dbStart
              dbStop
              dbStatus
              dbLog
              db
              dbRun
              dbReset
              (mkAlias "lt" lint)
              (mkAlias "fmt" treefmt.config.build.wrapper)
              (mkAlias "chk" check)
            ];

            shellHook = preCommit.shellHook + ''
              ${projectRoot}
              export MYSQL_UNIX_PORT="$root/${mysqlSocket}"
              export MYSQL_HISTFILE="$root/${stateDir}/mysql_history"
              echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
            '';
          };

          formatter = treefmt.config.build.wrapper;

          packages = {
            inherit
              lint
              sqlfmt
              sqllint
              db
              ;
            "db-services" = lib.mkForce dbServices;
            "db-start" = dbStart;
            "db-stop" = dbStop;
            "db-status" = dbStatus;
            "db-log" = dbLog;
            "db-run" = dbRun;
            "db-reset" = dbReset;
            default = lint;
          };

          checks = {
            formatting = treefmt.config.build.check self;
            lint = runCheck lint;
            mysql-client =
              pkgs.runCommand "isys2014-mysql-client-check" { nativeBuildInputs = [ pkgs.mysql84 ]; }
                ''
                  mysql --version > "$out"
                '';
            services = pkgs.runCommand "isys2014-services-check" { } ''
              test -x ${serviceRunner}/bin/db-services
              test -x ${dbServices}/bin/db-services
              touch "$out"
            '';
            sql =
              pkgs.runCommand "isys2014-sql-check"
                {
                  nativeBuildInputs = [
                    sqlfmt
                    sqllint
                  ];
                }
                ''
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
                  grep -Fq 'CREATE TABLE Conference' assessment.sql
                  grep -Fq 'confID' assessment.sql
                  grep -Fq 'source stadium.txt;' assessment.sql
                  touch "$out"
                '';
          };
        };
    };
}
