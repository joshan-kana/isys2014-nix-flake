# ISYS2014 practicals

Nix development environment for ISYS2014 Database Systems practical work.

## Setup

Create a practical directory from the template:

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

After that, entering the directory activates the development environment automatically.

If you are not using direnv, enter it manually with:

```bash
nix develop
```

## MySQL

The database is started and managed automatically with the development environment.
Connect directly with:

```bash
mysql -u root dswork
```

Normal MySQL client commands used in the practicals work as expected, including:

```text
mysql> tee Prac02Work.out
mysql> source create_tables.sql;
```

Your database state is kept between development-shell activations for the same practical.

## Formatting and checks

Format supported files with:

```bash
nix fmt
```

Run the full read-only repository checks with:

```bash
nix flake check
```

The development shell also provides the shorter aliases:

```bash
fmt
chk
```

The pre-commit hook runs the same checks before a commit is accepted.
