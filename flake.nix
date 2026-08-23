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
        overrides = import ./overrides.nix { inherit lib pkgs; };

        rootMarkerFile = ".isys2014-practical";

        templateFiles = [
          rootMarkerFile
          ".envrc"
          ".gitignore"
          ".vscode/extensions.json"
          ".vscode/settings.json"
          ".vscode/tasks.json"
          "flake.lock"
          "flake.nix"
        ];

        deletedTemplateFiles = [
          "scripts/dbctl.sh"
        ];

        globalExcludes = [
          ".direnv"
          ".state"
          "unit_materials"
        ];

        runtimeEnv = ''
          root="''${ISYS2014_ROOT:-$PWD}"
          while [[ "$root" != / && ! -f "$root/flake.nix" ]]; do root="$(dirname "$root")"; done
          [[ -f "$root/flake.nix" ]] || { echo "ERROR: could not find flake.nix" >&2; exit 1; }
          id="$(printf '%s' "$root" | cksum)"
          export ISYS2014_ROOT="$root"
          export ISYS2014_RUN_DIR="/tmp/isys2014-''${id%% *}"
          export MYSQL_UNIX_PORT="$ISYS2014_RUN_DIR/mysql.sock"
        '';

        mysqlServices = (import process-compose-flake.lib { inherit pkgs; }).makeProcessCompose {
          name = "mysql-services";
          modules = [
            services-flake.processComposeModules.default
            {
              cli = {
                environment.PC_SOCKET_PATH = "$ISYS2014_RUN_DIR/process-compose.sock";
                options = {
                  no-server = false;
                  use-uds = true;
                };
                preHook = ''
                  ${runtimeEnv}
                  mkdir -p "$ISYS2014_RUN_DIR"
                  cd "$ISYS2014_ROOT"
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
                };
              };
            }
          ];
        };
        mysqlServicesExe = "${mysqlServices}/bin/mysql-services";

        sqlOptions = [
          "--templater=raw"
          "--ignore=parsing"
          "--exclude-rules=CP02,RF04"
        ];
        markdownOptions = [
          "--disable"
          "MD013"
        ];
        baseConfig = final: {
          treefmtConfig = {
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
              global.excludes = map (dir: "${dir}/**") globalExcludes;
              formatter = {
                statix.priority = 1;
                deadnix.priority = 2;
                nixfmt.priority = 3;
                rumdl-format = {
                  options = markdownOptions;
                  priority = 1;
                };
                rumdl-check = {
                  options = markdownOptions;
                  priority = 2;
                };
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

          devShellConfig = {
            packages =
              (with pkgs; [
                mysql84
                nixd
                nixfmt
                zip
              ])
              ++ [
                final.treefmt.config.build.wrapper
                (pkgs.writeShellScriptBin "fmt" ''exec ${pkgs.lib.getExe final.treefmt.config.build.wrapper} "$@"'')
                (pkgs.writeShellScriptBin "chk" ''exec ${pkgs.lib.getExe check} "$@"'')
                db
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
              ${runtimeEnv}

              if ! mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then
                mkdir -p "$ISYS2014_RUN_DIR"
                if ${mysqlServicesExe} project state >/dev/null 2>&1; then
                  ${mysqlServicesExe} process start mysql >/dev/null
                else
                  rm -f "$ISYS2014_RUN_DIR/process-compose.sock"
                  ${mysqlServicesExe} up --detached >/dev/null
                fi
                for _ in {1..60}; do
                  mysql -u root -Nse 'USE dswork' >/dev/null 2>&1 && break
                  sleep 0.5
                done
                mysql -u root -Nse 'USE dswork' >/dev/null 2>&1 || {
                  echo "ERROR: MySQL did not become ready" >&2
                  return 1
                }
              fi
            '';
          };

          treefmt = treefmt-nix.lib.evalModule pkgs final.treefmtConfig;
        };

        config = (lib.makeExtensible baseConfig).extend overrides;
        inherit (config) treefmt;

        check = pkgs.writeShellApplication {
          name = "check";
          runtimeInputs = [ pkgs.pre-commit ];
          text = ''exec pre-commit run nix-flake-check "$@"'';
        };
        db = pkgs.writeShellApplication {
          name = "db";
          runtimeInputs = [ pkgs.mysql84 ];
          text = ''exec mysql -u root dswork "$@"'';
        };
        sync = pkgs.writeShellApplication {
          name = "sync";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.rsync
          ];
          text = ''
            root="$(pwd -P)"

            while [[ "$root" != "/" && ! -f "$root/${rootMarkerFile}" ]]; do
              root="$(dirname "$root")"
            done

            if [[ ! -f "$root/${rootMarkerFile}" ]]; then
              echo "error: could not find template root (${rootMarkerFile})" >&2
              exit 1
            fi

            rsync -rlpc --chmod=u+w \
              --files-from=${pkgs.writeText "template-files" (pkgs.lib.concatStringsSep "\n" templateFiles)} \
              ${self.outPath}/ "$root/"

            ${pkgs.lib.concatMapStringsSep "\n" (path: ''rm -f -- "$root/${path}"'') deletedTemplateFiles}
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell config.devShellConfig;

        formatter = treefmt.config.build.wrapper;
        packages.check = check;
        packages.sync = sync;
        checks = {
          formatting = treefmt.config.build.check self;
          services = mysqlServices;
          inherit sync;
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
