# ISYS2014 practicals development environment

Pure Nix flake for ISYS2014 Database Systems practicals. It uses
services-flake and process-compose-flake to provide an isolated MySQL 8.4
service without impure flake evaluation or a custom database supervisor.

## Included

- MySQL 8.4, pinned by the flake lock
- Pure `nix develop`, `nix fmt`, and `nix flake check`
- Per-practical persistent database state under `.state/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- services-flake MySQL initialization and process-compose supervision
- Native treefmt-nix formatting/linting for Nix, Markdown, shell, and SQL
- nixd, nixfmt, direnv, SQLTools/MySQL, and Draw.io support
- A read-only `nix flake check` pre-commit hook

## Start a practical folder

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

Without direnv:

```bash
nix develop
```

No `--impure` or `--no-pure-eval` flag is required. Inputs are pinned by
`flake.lock`; checkout-dependent paths are resolved only when generated commands
run.

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

The database starts lazily on the first `db`, `db-start`, or `db-run`. Entering
the development shell does not start MySQL by itself.

Persistent database data stays under `.state/`. MySQL and process-compose use a
short deterministic per-project runtime directory under `/tmp`, avoiding Unix
socket path-length failures in deeply nested checkouts while keeping practicals
isolated. MySQL TCP networking remains disabled.

services-flake owns MySQL initialization, including creating `dswork` after the
server is healthy. process-compose owns process supervision and readiness. The
project commands are only convenience wrappers around those services.

## Formatting and checks

`nix fmt` is the write/fix path. treefmt-nix natively coordinates:

- Statix, Deadnix, and nixfmt for Nix
- rumdl and typos for Markdown
- ShellCheck for shell files
- SQLFluff formatting and linting with the MySQL dialect

SQLFluff uses the raw templater and ignores parser-family errors so MySQL
client-only commands outside the SQL grammar do not fail the whole project
check. `CP02` and `RF04` are excluded so formatting does not silently change
schema identifier casing or reject otherwise valid MySQL identifiers.

```bash
nix fmt
nix flake check
```

Inside the development shell the same commands are available as:

```bash
fmt    # nix fmt
chk    # nix flake check
```

`nix flake check` is the single read-only verification path. Its treefmt check
runs the same formatter/linter pipeline against a copy of the source and fails if
formatting would change anything or any lint stage reports an error. It also
builds the generated MySQL service runner.

The pre-commit hook uses `pre-commit-hooks.nix` directly and runs `nix flake
check`, so commits are rejected for formatting or lint failures without rewriting
files.

## Formatting exclusions

`flake.nix` contains one `globalExcludes` list used by treefmt. Local state and
lecturer material are excluded by default:

```nix
globalExcludes = [
  ".direnv/**"
  ".state/**"
  "unit_materials/**"
];
```

Add supplied files or globs there if they should not be formatted or linted.

## VS Code and Remote Development

The recommended extensions include nix-ide, direnv, SQLTools with its MySQL
driver, Draw.io for ER diagrams, and Remote-SSH. VS Code tasks provide database
access, formatting through `nix fmt`, and full verification through `nix flake
check`.
