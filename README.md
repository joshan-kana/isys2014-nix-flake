# ISYS2014 practicals development environment

Nix flake for ISYS2014 Database Systems practicals.

## Setup

Create a practical directory from the template:

```bash
nix flake init -t 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git' --refresh
direnv allow
```

Optionally: set up a git repository

```bash
git init
git add .
git commit -m "initialised"
```

After that, entering the directory activates the development environment automatically.

## Update

Update an existing practical from the latest template.

Practicals created before the marker and per-practical config were added
need both files created once from the practical root:

```bash
touch .isys2014-practical
printf '_: _final: _prev:\n{ }\n' > overrides.nix
git add overrides.nix
```

Then update with:

```bash
nix run 'git+ssh://git@github.com/joshan-kana/isys2014-nix-flake.git#sync' --refresh
direnv allow
```

Without direnv:

```bash
nix develop -c $SHELL
```

## Per-practical configuration

New practicals include `overrides.nix`. It is deliberately not updated by
`sync`, so each practical can keep its own environment overrides. Older
practicals create the no-op overlay once using the command in **Update** above.

`overrides.nix` is a normal Nix overlay: `prev` is the shared template
configuration and `final` is the configuration after overrides. For example:

```nix
{ lib, pkgs }:
_final: prev: {
  treefmtConfig = lib.recursiveUpdate prev.treefmtConfig {
    settings.global.excludes =
      prev.treefmtConfig.settings.global.excludes ++ [ "generated/**" ];
  };

  devShellConfig = prev.devShellConfig // {
    packages = prev.devShellConfig.packages ++ [ pkgs.jq ];
  };
}
```

## MySQL

Connect with:

```bash
mysql -u root dswork
```

Once the development environment is active, the shorter `db` command opens the
same MySQL shell:

```bash
db
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
