# ISYS2014 practicals development environment

Nix flake for ISYS2014 Database Systems practicals. The flake uses devenv's
Nix modules to provide an isolated MySQL 8.4 service without maintaining a
project-specific database supervisor.

## Included

- MySQL 8.4, pinned by the flake lock
- Per-practical persistent database state under `.devenv/`
- Unix-socket-only MySQL with TCP networking disabled
- An automatically created `dswork` database
- `less`, `zip`, nixd, nixfmt, Statix, treefmt, and direnv support
- treefmt-backed pre-commit formatting checks

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

## Database commands

```bash
db                          # Start MySQL if needed and open dswork
db-run create_tables.sql    # Run a SQL file against dswork
db-run file.sql other_db    # Run a SQL file against another database
db-reset                    # Delete this practical's MySQL state and recreate dswork
```

The database starts lazily on the first `db` or `db-run`, so simply entering the
development shell does not leave an unused MySQL process running.

For service management, use devenv directly:

```bash
devenv up --mode all -d mysql    # Start MySQL in the background
devenv processes status          # Show process state
devenv processes logs mysql      # Follow MySQL logs
devenv down                       # Stop the practical's processes
```

Once MySQL is running, the normal client is also available directly:

```bash
mysql -u root dswork
```

Each practical keeps its own persistent service state under `.devenv/`, which is
ignored by Git. SQL files, command files, and captured `.out` files remain
trackable for practical work and submission evidence.

## Development commands

```bash
nix fmt
nix flake check --impure
```

`nix fmt` applies nixfmt and Statix fixes through treefmt. `nix flake check` is
read-only and verifies formatting plus the MySQL client package.
