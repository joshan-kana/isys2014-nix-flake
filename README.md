# ISYS2014 practicals development environment

Pure Nix flake for ISYS2014 Database Systems practicals. It provides an
isolated MySQL 8.4 service through services-flake and process-compose-flake,
without impure evaluation or a custom database supervisor.

## Included

- MySQL 8.4, pinned by `flake.lock`
- Pure `nix develop`, `nix fmt`, and `nix flake check`
- Per-practical persistent database state under `.state/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- Native treefmt-nix formatting and linting for Nix, Markdown, shell, and SQL
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

## MySQL

In one terminal, start the generated MySQL service:

```bash
mysql-services
```

Leave it running. In another terminal in the same practical environment, use the
normal MySQL client:

```bash
mysql -u root dswork
```

With direnv, the second terminal enters the environment automatically. Otherwise,
run `nix develop` there first.

This matches the practical workflow directly. MySQL client commands such as
`tee` and `source` work normally, for example:

```text
mysql> tee Prac02Work.out
mysql> source create_tables.sql;
```

Stop MySQL by exiting `mysql-services` with `Ctrl-C`.

Persistent database data stays under `.state/`. MySQL uses a short deterministic
per-project runtime directory under `/tmp`, avoiding Unix socket path-length
failures in deeply nested checkouts while keeping practicals isolated. MySQL TCP
networking remains disabled.

services-flake owns MySQL initialization, including creating `dswork` after the
server is healthy. process-compose owns process supervision and readiness.

## Formatting and checks

`nix fmt` is the write/fix path. treefmt-nix natively coordinates:

- Statix, Deadnix, and nixfmt for Nix
- rumdl formatting/linting and typos for Markdown
- ShellCheck for shell files
- SQLFluff formatting and linting with the MySQL dialect

The Markdown policy matches the Hot Wheels repository where relevant: line
length (`MD013`) is disabled, and tabs inside code blocks are allowed. rumdl is
used directly through treefmt-nix for both formatting and linting.

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
runs the same formatter/linter pipeline against the source and fails if
formatting would change anything or a lint stage reports an error. It also builds
the generated MySQL service runner.

The pre-commit hook uses `pre-commit-hooks.nix` directly and runs
`nix flake check`, so commits are rejected for formatting or lint failures
without rewriting files.

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
driver, Draw.io for ER diagrams, and Remote-SSH. VS Code tasks provide formatting
through `nix fmt` and full verification through `nix flake check`.
