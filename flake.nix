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
      lib = nixpkgs.lib;
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = lib.genAttrs systems;

      # Single source of truth for files/directories owned by the environment or
      # supplied by the lecturer. Add exceptional supplied files here as needed.
      globalExcludes = [
        ".devenv/**"
        ".direnv/**"
        "unit_materials/**"
      ];
      rgExcludeArgs = lib.concatMapStringsSep " " (pattern: "-g ${lib.escapeShellArg "!${pattern}"}") globalExcludes;

      sqlToolFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
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

      sqlfmtFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sqlTool = sqlToolFor system;
        in
        pkgs.writeShellApplication {
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

      sqllintFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sqlTool = sqlToolFor system;
        in
        pkgs.writeShellApplication {
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

      treefmtConfigFor =
        system:
        let
          sqlfmt = sqlfmtFor system;
        in
        {
          projectRootFile = "flake.nix";
          programs = {
            deadnix.enable = true;
            nixfmt.enable = true;
            rumdl-format.enable = true;
            statix.enable = true;
          };
          settings = {
            global.excludes = globalExcludes;
            formatter = {
              statix.priority = 1;
              deadnix.priority = 2;
              nixfmt.priority = 3;
              sqlfluff = {
                command = lib.getExe sqlfmt;
                includes = [ "*.sql" ];
              };
            };
          };
        };

      treefmtFor =
        system:
        treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} (treefmtConfigFor system);

      lintFor =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          sqllint = sqllintFor system;
        in
        pkgs.writeShellApplication {
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
          sqlfmt = sqlfmtFor system;
          sqllint = sqllintFor system;
        in
        {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [
              ./devenv.nix
              {
                packages = [
                  lint
                  sqlfmt
                  sqllint
                ];

                scripts = {
                  lt.exec = ''exec lint "$@"'';
                  fmt.exec = ''exec nix fmt "$@"'';
                  chk.exec = ''exec nix flake check --impure "$@"'';
                };

                treefmt = {
                  enable = true;
                  config = treefmtConfigFor system;
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

      packages = forAllSystems (
        system:
        let
          lint = lintFor system;
          sqlfmt = sqlfmtFor system;
          sqllint = sqllintFor system;
        in
        {
          inherit lint sqlfmt sqllint;
          default = lint;
        }
      );

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          treefmt = treefmtFor system;
          lint = lintFor system;
          sqlfmt = sqlfmtFor system;
          sqllint = sqllintFor system;
        in
        {
          formatting = treefmt.config.build.check self;
          lint = runCheck system lint;
          mysql-client =
            pkgs.runCommand "isys2014-mysql-client-check" { nativeBuildInputs = [ pkgs.mysql84 ]; }
              ''
                mysql --version > "$out"
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
                SELECT 1;
                source stadium.txt;
                SQL
                sqlfmt assessment.sql
                sqllint assessment.sql
                grep -Fq 'source stadium.txt;' assessment.sql
                touch "$out"
              '';
        }
      );

      templates.default = {
        path = ./.;
        description = "ISYS2014 practical: isolated MySQL 8.4 environment";
      };
    };
}
