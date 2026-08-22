# ISYS2014 practicals development environment

Nix flake for ISYS2014 Database Systems practicals. The flake uses devenv's
Nix modules to provide an isolated MySQL 8.4 service without maintaining a
project-specific database supervisor.

## Included

- MySQL 8.4, pinned by the flake lock
- Per-practical persistent database state under `.devenv/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- devenv-managed service configuration, readiness, and process supervision
- MySQL-aware SQLFluff formatting and linting for assessment/practical `.sql`
  files
- nixfmt, Statix, Deadnix, ShellCheck, rumdl, typos, treefmt, nixd, and direnv
- SQLTools/MySQL and Draw.io VS Code recommendations for SQL and ER modelling
- A read-only `nix flake check` pre-commit hook

## Start a practical folder

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

Without direnv, enter the environment with:

```bash
nix develop --no-pure-eval
```

The impure evaluation flag lets devenv discover the practical's project root;
packages and inputs are still pinned by `flake.lock`.

## VS Code and Remote Development

Install the recommended VS Code extensions for this repository. They include
SQLTools with its MySQL driver, Draw.io for ER diagrams, and Remote-SSH when
opening the practical through an SSH remote host.

If you also want your normal local extensions available in the remote window,
run `Remote: Install Local Extensions in 'SSH: <host>'`, choose **Select All**,
and choose **Install**.

## Database commands

```bash
db                          # Start MySQL if needed and open dswork
db-run create_tables.sql    # Run a SQL file against dswork
db-run file.sql other_db    # Run a SQL file against another database
db-status                   # Show service state
db-log                      # Follow MySQL logs
db-stop                     # Stop this practical's services
db-reset                    # Delete MySQL state and recreate dswork
```

The database starts lazily on the first `db` or `db-run`, so simply entering the
development shell does not leave an unused MySQL process running. `db-start` is
also available when the database should be started without opening a client.

Once MySQL is running, the normal client is available directly:

```bash
mysql -u root dswork
```

Each practical keeps its own persistent service state under `.devenv/`, which is
ignored by Git. devenv's flake integration supervises the service with
process-compose and keeps its runtime socket separate from the persistent state.
SQL files, command files, and captured `.out` files remain trackable for
practical work and submission evidence.

## SQL support

`.sql` files are first-class source files. SQLFluff runs in the MySQL dialect and
raw templater mode so both formatting and linting understand the SQL used in the
unit.

```bash
sqlfmt assessment.sql       # Format one or more SQL files
sqllint assessment.sql      # Read-only lint for one or more SQL files
nix run .#sqlfmt -- file.sql
nix run .#sqllint -- file.sql
```

`nix fmt` also formats tracked `.sql` files and `nix run .#lint` lints them.
MySQL client-only `SOURCE file` and `\. file` directives are preserved unchanged
while SQLFluff processes the surrounding SQL. This supports command files such as
the practical-test submissions without weakening normal SQL parsing and linting.

Formatting/linting does not replace actually running the SQL. Use `db-run` or the
interactive `db` client to verify schema, data, constraints, procedures, triggers,
and other behaviour against MySQL itself.

## Formatting and linting exclusions

`flake.nix` contains one `globalExcludes` list used by both treefmt and the
read-only lint runner. Environment state and lecturer material are excluded by
default:

```nix
globalExcludes = [
  ".devenv/**"
  ".direnv/**"
  "unit_materials/**"
];
```

If supplied lecturer code does not pass the project checks, add its path or glob
to this list once, for example `"provided_query.sql"` or `"provided/**"`. The
same exclusion then applies to formatting and linting.

## Development commands

```bash
nix fmt
nix run .#lint
nix flake check --impure
```

Convenience aliases are also available inside the development shell:

```bash
fmt    # nix fmt
lt     # lint
chk    # nix flake check --impure
```

`nix fmt` is the write/fix path: treefmt coordinates Statix, Deadnix, nixfmt,
rumdl, and MySQL-aware SQL formatting. `nix run .#lint` is read-only and runs
Statix, Deadnix, ShellCheck, rumdl, typo checks for Markdown, and SQLFluff linting.
`nix flake check --impure` verifies formatting, linting, the MySQL client package,
and SQL tooling including preservation of MySQL `SOURCE` directives. The same
full check runs as the pre-commit hook.
