# ISYS2014 practicals development environment

Nix flake for ISYS2014 Database Systems practicals.

## Included

- MySQL 8.4 with isolated per-practical data under `.mysql/`
- A local Unix socket with TCP networking disabled
- An automatically created `dswork` database
- MySQL helpers, `less`, and `zip`
- nixfmt, Statix, ShellCheck, nixd, treefmt, and direnv support

## Start a practical folder

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

Without direnv, enter the environment with `nix develop`.

## Database commands

```bash
mysql -u root              # Open the MySQL client
db-shell                   # Equivalent helper
db-run create_tables.sql   # Run a SQL file against dswork
db-status                  # Show server state
db-stop                    # Stop the server
db-reset                   # Delete this practical's data and start fresh
db-log                     # Follow the MySQL log
```

The server starts when the development shell loads. Its data stays inside the
current practical folder and is ignored by Git. SQL files, command files, and
captured `.out` files are deliberately not ignored, so each practical repository
can track its own work and submission evidence.

## Development commands

```bash
nix fmt
nix run .#lint
nix flake check
```
