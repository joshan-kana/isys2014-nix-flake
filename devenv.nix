{ config, pkgs, ... }:

{
  packages = with pkgs; [
    deadnix
    less
    nixd
    nixfmt
    rumdl
    shellcheck
    sqlfluff
    statix
    typos
    zip
  ];

  process.manager.implementation = "process-compose";

  services.mysql = {
    enable = true;
    package = pkgs.mysql84;

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
      if mysql -u root -Nse 'USE dswork' >/dev/null 2>&1; then
        exit 0
      fi

      if process-compose process list >/dev/null 2>&1; then
        process-compose process start mysql >/dev/null 2>&1 || true
      else
        process-compose up --detached mysql >/dev/null
      fi

      for _ in {1..300}; do
        if mysqladmin -u root ping --silent >/dev/null 2>&1; then
          mysql -u root --execute='CREATE DATABASE IF NOT EXISTS dswork;'
          exit 0
        fi
        sleep 0.1
      done

      echo "ERROR: MySQL did not become ready." >&2
      process-compose process logs mysql --tail 50 >&2 || true
      exit 1
    '';

    db-stop.exec = ''
      process-compose down >/dev/null 2>&1 || true
    '';

    db-status.exec = ''
      exec process-compose process list
    '';

    db-log.exec = ''
      exec process-compose process logs mysql --follow
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
      database="''${2:-dswork}"

      if [[ ! -f "$file" ]]; then
        printf 'ERROR: SQL file not found: %s\n' "$file" >&2
        exit 1
      fi

      db-start
      mysql -u root "$database" < "$file"
    '';

    db-reset.exec = ''
      db-stop
      rm -rf -- "$MYSQL_HOME"
      db-start
      echo "MySQL reset: database dswork is ready."
    '';
  };

  enterShell = ''
    echo "ISYS2014 ready. Run 'db' to start MySQL and open dswork."
  '';
}
