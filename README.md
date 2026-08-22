# ISYS2014 practicals development environment

Pure Nix flake for ISYS2014 Database Systems practicals. It uses
services-flake and process-compose-flake to provide an isolated MySQL 8.4
service without impure flake evaluation or a custom database supervisor.

## Included

- MySQL 8.4, pinned by the flake lock
- Pure `nix develop` and `nix flake check`
- Per-practical persistent database state under `.state/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- services-flake MySQL configuration and initialization
- process-compose-flake readiness and process supervision
- Native treefmt-nix SQLFluff formatting and linting for `.sql` files
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
are pinned by `flake.lock`; checkout-dependent paths are resolved only when the
generated commands run.

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
db-start                    # Start MySQL without opening the client
db-run query.sql            # Run a SQL file against dswork
db-run query.sql other_db   # Run a SQL file against another database
db-status                   # Show service state
db-log                      # Follow MySQL logs
db-stop                     # Stop this practical's services
db-reset                    # Delete MySQL state and recreate dswork
```

The database starts lazily on the first `db`, `db-start`, or `db-run`, so simply
entering the development shell does not leave an unused MySQL process running.
Once it is running, the normal client is also available directly:

```bash
mysql -u root dswork
```

Each practical keeps persistent database data under `.state/`, which is ignored
by Git. Runtime sockets for MySQL and process-compose use a short deterministic
per-project directory under `/tmp`; this keeps practicals isolated while avoiding
Unix-socket path-length failures in deeply nested checkout paths. MySQL still has
TCP networking disabled.

services-flake owns MySQL initialization and creates `dswork` only after the
server becomes healthy. process-compose owns process supervision and readiness;
the project commands are only a thin convenience layer over those services.

## SQL support

`.sql` files are formatted and linted directly by SQLFluff through treefmt-nix,
using the MySQL dialect and raw templater.

```bash
sqlfmt query.sql             # Format one or more SQL files
sqllint query.sql            # Read-only lint one or more SQL files
nix run .#sqlfmt -- query.sql
nix run .#sqllint -- query.sql
```

SQLFluff is configured to ignore parser-family errors so MySQL client-only
commands that are outside the SQL grammar do not make the whole project check
fail. SQL formatting and linting remain advisory tooling; use `db-run` or the
interactive `db` client to verify behaviour against MySQL itself.

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

If supplied lecturer code should not be formatted or linted, add its path or glob
to this list once. The same exclusion then applies to both paths.

## Development commands

```bash
nix fmt
nix run .#lint
nix flake check
```

Convenience aliases are also available inside the development shell:

```bash
fmt    # nix fmt
lt     # lint
chk    # nix flake check
```

`nix fmt` is the write/fix path and is deliberately treefmt-first. Treefmt uses
native modules for Statix, Deadnix, nixfmt, rumdl, typos, ShellCheck, SQLFluff
formatting, and SQLFluff linting.

`nix run .#lint` is the independent read-only counterpart and runs Statix,
Deadnix, ShellCheck, rumdl, Markdown typo checks, and SQLFluff linting without
modifying tracked files. `nix flake check` verifies both the treefmt formatting
check and the independent lint check, and builds the generated MySQL service
runner.

The pre-commit hook uses `pre-commit-hooks.nix` directly, like the COMP1002
flake, and runs the full pure `nix flake check`. Commits therefore fail for
formatting drift or lint errors without silently modifying files.
