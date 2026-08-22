{
  pkgs,
  self,
  treefmt-nix,
  pre-commit-hooks,
  globalExcludes,
  sqlfmt,
  sqllint,
}:
let
  lib = pkgs.lib;
  excludeArgs = lib.concatMapStringsSep " " (
    pattern: "-g ${lib.escapeShellArg "!${pattern}"}"
  ) globalExcludes;

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
      mapfile -t nix_files < <(rg --files -g '*.nix' ${excludeArgs})
      for file in "''${nix_files[@]}"; do
        statix check "$file"
      done
      if (( ''${#nix_files[@]} )); then
        deadnix --fail "''${nix_files[@]}"
      fi

      mapfile -t markdown_files < <(rg --files -g '*.md' ${excludeArgs})
      if (( ''${#markdown_files[@]} )); then
        rumdl check "''${markdown_files[@]}"
        typos "''${markdown_files[@]}"
      fi

      mapfile -t sql_files < <(rg --files -g '*.sql' ${excludeArgs})
      if (( ''${#sql_files[@]} )); then
        sqllint "''${sql_files[@]}"
      fi

      shellcheck -s bash .envrc
      python3 - <<'PY'
      from pathlib import Path
      path = Path("nix/sqlfluff-wrapper.py")
      compile(path.read_text(encoding="utf-8"), str(path), "exec")
      PY
    '';
  };

  check = pkgs.writeShellApplication {
    name = "check";
    runtimeInputs = [ pkgs.pre-commit ];
    text = ''exec pre-commit run nix-flake-check "$@"'';
  };

  preCommit = pre-commit-hooks.lib.${pkgs.system}.run {
    src = self;
    hooks.nix-flake-check = {
      enable = true;
      name = "nix flake check";
      entry = "nix flake check";
      language = "system";
      pass_filenames = false;
    };
  };

  runCheck = package:
    pkgs.runCommand "isys2014-${package.name}-check" { nativeBuildInputs = [ package ]; } ''
      cp -R ${self} source
      chmod -R u+w source
      cd source
      ${lib.getExe package}
      touch "$out"
    '';
in
{
  inherit
    check
    lint
    preCommit
    runCheck
    treefmt
    ;
}
