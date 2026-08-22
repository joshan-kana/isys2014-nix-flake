{ config, pkgs, ... }:

{
  packages = with pkgs; [
    less
    nixd
    statix
    zip
  ];

  services.mysql = {
    enable = true;
    package = pkgs.mysql84;

    initialDatabases = [
      { name = "dswork"; }
    ];

    settings.mysqld = {
      "skip-networking" = true;
      "skip-log-bin" = true;
      mysqlx = "OFF";
      "innodb-buffer-pool-size" = "64M";
    };
  };

  env.MYSQL_HISTFILE = "${config.env.DEVENV_STATE}/mysql_history";

  scripts = {
    db-start.exec = ''
      if ! mysqladmin -u root ping --silent >/dev/null 2>&1; then
        devenv up --mode all -d mysql >/dev/null
      fi
    '';

    db.exec = ''
      db-start
      exec mysql -u root dswork "$@"
    '';

    db-run.exec = ''
      if (( $# < 1 || $# > 2 )); then
        echo "Usage: db-run FILE.sql [DATABASE]" >&2
        exit 2
      fi

      file="$1"
      database="${2:-dswork}"

      if [[ ! -f "$file" ]]; then
        printf 'ERROR: SQL file not found: %s\n' "$file" >&2
        exit 1
      fi

      db-start
      mysql -u root "$database" < "$file"
    '';

    db-reset.exec = ''
      devenv down >/dev/null 2>&1 || true
      rm -rf -- "$MYSQL_HOME"
      db-start
      echo "MySQL reset: database dswork is ready."
    '';
  };

  enterShell = ''
    echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
  '';
}
