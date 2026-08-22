{
  pkgs,
  process-compose-flake,
  services-flake,
}:
let
  socket = ".state/run/mysql/mysql.sock";

  enterRoot = ''
    root="''${ISYS2014_ROOT:-$PWD}"
    while [[ "$root" != "/" && ! -f "$root/flake.nix" ]]; do
      root="$(dirname "$root")"
    done
    if [[ ! -f "$root/flake.nix" ]]; then
      echo "ERROR: could not find flake.nix from $PWD" >&2
      exit 1
    fi
    cd "$root"
    export MYSQL_UNIX_PORT="$root/${socket}"
    export MYSQL_HISTFILE="$root/.state/mysql_history"
  '';

  dbServices = (import process-compose-flake.lib { inherit pkgs; }).makeProcessCompose {
    name = "db-services";
    modules = [
      services-flake.processComposeModules.default
      {
        cli = {
          options = {
            keep-project = true;
            no-server = false;
            use-uds = true;
          };
          preHook = ''
            ${enterRoot}
            checksum="$(printf '%s' "$root" | ${pkgs.coreutils}/bin/cksum)"
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

  mkCommand = name: runtimeInputs: text:
    pkgs.writeShellApplication {
      inherit name runtimeInputs text;
    };

  dbStart = mkCommand "db-start" [
    dbServices
    pkgs.coreutils
    pkgs.mysql84
  ] ''
    ${enterRoot}
    if mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then
      exit 0
    fi

    mkdir -p .state/run/mysql
    if db-services process list >/dev/null 2>&1; then
      db-services process start mysql >/dev/null 2>&1 || true
      db-services process start mysql-configure >/dev/null 2>&1 || true
    else
      db-services up --detached >/dev/null
    fi

    for _ in {1..300}; do
      if mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then
        exit 0
      fi
      sleep 0.1
    done

    echo "ERROR: MySQL did not become ready." >&2
    db-services process logs mysql --tail 50 >&2 || true
    exit 1
  '';

  dbStop = mkCommand "db-stop" [
    dbServices
    pkgs.coreutils
  ] ''
    ${enterRoot}
    db-services down >/dev/null 2>&1 || true
  '';

  dbStatus = mkCommand "db-status" [
    dbServices
    pkgs.coreutils
  ] ''
    ${enterRoot}
    exec db-services process list
  '';

  dbLog = mkCommand "db-log" [
    dbServices
    pkgs.coreutils
  ] ''
    ${enterRoot}
    exec db-services process logs mysql --follow
  '';

  db = mkCommand "db" [
    dbStart
    pkgs.coreutils
    pkgs.mysql84
  ] ''
    ${enterRoot}
    db-start
    exec mysql -u root dswork "$@"
  '';

  dbRun = mkCommand "db-run" [
    dbStart
    pkgs.coreutils
    pkgs.mysql84
  ] ''
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
    ${enterRoot}
    db-start
    mysql -u root "$database" < "$file"
  '';

  dbReset = mkCommand "db-reset" [
    dbStart
    dbStop
    pkgs.coreutils
  ] ''
    ${enterRoot}
    db-stop
    rm -rf -- .state/mysql .state/run/mysql
    db-start
    echo "MySQL reset: database dswork is ready."
  '';
in
{
  inherit
    db
    dbLog
    dbReset
    dbRun
    dbServices
    dbStart
    dbStatus
    dbStop
    ;

  services = dbServices;

  packages = [
    dbServices
    dbStart
    dbStop
    dbStatus
    dbLog
    db
    dbRun
    dbReset
  ];

  shellHook = ''
    export ISYS2014_ROOT="$PWD"
    export MYSQL_UNIX_PORT="$ISYS2014_ROOT/${socket}"
    export MYSQL_HISTFILE="$ISYS2014_ROOT/.state/mysql_history"
  '';
}
