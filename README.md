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
- `less`, `zip`, nixd, nixfmt, Statix, treefmt, and direnv support
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

Install the recommended VS Code extensions for this repository, including
Remote-SSH when opening the practical through an SSH remote host.

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

## Development commands

```bash
nix fmt
nix flake check --impure
```

`nix fmt` applies nixfmt and Statix fixes through treefmt. `nix flake check` is
read-only and verifies formatting plus the MySQL client package. The same check
runs as the pre-commit hook.
