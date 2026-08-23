# ISYS2014 practicals development environment

Nix flake for ISYS2014 Database Systems practicals.

## Setup

Create a practical directory from the template:

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git'
direnv allow
```

After that, entering the directory activates the development environment automatically.

Without direnv:

```bash
nix develop
```

## MySQL

Connect with:

```bash
mysql -u root dswork
```

MySQL client commands used in the practicals work normally, including:

```text
mysql> tee Prac02Work.out
mysql> source create_tables.sql;
```

Database state is preserved for the practical.

## Formatting and checks

Format supported files with:

```bash
nix fmt
```

or:

```bash
fmt
```

Check staged files with:

```bash
chk
```

Run the full repository checks with:

```bash
nix flake check
```
