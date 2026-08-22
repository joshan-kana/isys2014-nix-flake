{ pkgs }:
let
  runner = pkgs.writeShellApplication {
    name = "isys2014-sql";
    runtimeInputs = [
      pkgs.python3
      pkgs.sqlfluff
    ];
    text = ''exec python3 ${./sqlfluff-wrapper.py} "$@"'';
  };

  mkCommand = name: mode:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [ runner ];
      text = ''
        if (( $# == 0 )); then
          echo "Usage: ${name} FILE.sql [...]" >&2
          exit 2
        fi
        exec isys2014-sql ${mode} "$@"
      '';
    };

  sqlfmt = mkCommand "sqlfmt" "format";
  sqllint = mkCommand "sqllint" "lint";

  check = pkgs.runCommand "isys2014-sql-check" {
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
      date DATE
    );
    source stadium.txt;
    SQL

    sqlfmt assessment.sql
    sqllint assessment.sql
    grep -Fqx 'source stadium.txt;' assessment.sql
    grep -Fq 'Conference' assessment.sql
    touch "$out"
  '';
in
{
  inherit
    check
    runner
    sqlfmt
    sqllint
    ;
}
