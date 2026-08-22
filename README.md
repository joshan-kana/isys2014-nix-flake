# ISYS2014 practicals development environment

Pure Nix flake for ISYS2014 Database Systems practicals. It uses
services-flake and process-compose-flake to provide an isolated MySQL 8.4
service without requiring impure flake evaluation or a custom database
supervisor.

## Included

- MySQL 8.4, pinned by the flake lock
- Pure `nix develop` and `nix flake check`
- Per-practical persistent database state under `.state/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- services-flake MySQL configuration and initialization
- process-compose-flake readiness and process supervision
- MySQL-aware SQLFluff formatting and linting for practical `.sql` files
- nixfmt, Statix, Deadnix, ShellCheck, rumdl, typos, treefmt, nixd, and direnv
- SQLTools/MySQL and Draw.io VS Code recommendations
- A read-only `nix flake check` pre-commit hook

## Start a practical folder

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

Without direnv, enter the environment with:

```bash
nix develop
```

No `--impure` or `--no-pure-eval` flag is required. Package and service inputs
are pinned by `flake.lock`, while project-local runtime paths are resolved only
when the generated commands run.

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

Each practical keeps its own persistent state under `.state/`, which is ignored
by Git. MySQL and process-compose use project-local Unix sockets under
`.state/run/`, so separate practical folders remain isolated without fixed TCP
ports or hard-coded absolute paths.

services-flake owns MySQL initialization and creates `dswork` only after the
server becomes healthy. This removes the first-start readiness workaround that
was needed by the previous devenv flake integration.

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

`nix fmt` also formats and lints tracked `.sql` files, while
`nix run .#lint` provides the read-only SQL lint path. MySQL client-only
`SOURCE file` and `\. file` directives are preserved unchanged while SQLFluff
processes the surrounding SQL.

Formatting and linting do not replace actually running the SQL. Use `db-run` or
the interactive `db` client to verify schema, data, constraints, procedures,
triggers, and other behaviour against MySQL itself.

## Formatting and linting exclusions

`flake.nix` contains one `globalExcludes` list used by both treefmt and the
read-only lint runner. Local state and lecturer material are excluded by default:

```nix
globalExcludes = [
  ".direnv/**"
  ".state/**"
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
nix flake check
```

Convenience aliases are also available inside the development shell:

```bash
fmt    # nix fmt\ nlt     # lint
chk    # nix flake check
```

`nix fmt` is the write/fix path and is deliberately treefmt-first. Treefmt
coordinates Statix fixes, Deadnix, nixfmt, rumdl formatting and lint/fixes,
Markdown typo fixes, ShellCheck, MySQL-aware SQL formatting, and SQLFluff
linting. The SQL stages use a small compatibility wrapper because assessment
command files contain MySQL client `SOURCE`/`\.` directives that SQLFluff itself
does not parse.

`nix run .#lint` is the read-only counterpart and runs Statix, Deadnix,
ShellCheck, rumdl, Markdown typo checks, and SQLFluff linting without modifying
tracked files. `nix flake check` verifies the treefmt formatting check, the
read-only lint check, MySQL tooling, the generated service runner, and the SQL
tooling checks.

The pre-commit hook uses `pre-commit-hooks.nix` directly, like the COMP1002
flake, and runs the full pure `nix flake check`. Commits therefore fail for
formatting drift or lint errors without silently modifying files.
