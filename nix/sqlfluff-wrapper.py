import re
import subprocess
import sys
import tempfile
from pathlib import Path

DIRECTIVE = re.compile(r"^\s*(?:source|\\\.)\s+.+;?\s*$", re.IGNORECASE)
SQLFLUFF_ARGS = [
    "--dialect",
    "mysql",
    "--templater",
    "raw",
    "--exclude-rules",
    "CP02,RF04",
    "--disable-progress-bar",
]


def process(mode: str, path: Path) -> int:
    if not path.is_file():
        print(f"ERROR: SQL file not found: {path}", file=sys.stderr)
        return 2

    directives: dict[str, str] = {}
    prepared: list[str] = []

    for index, line in enumerate(path.read_text(encoding="utf-8").splitlines(keepends=True)):
        if DIRECTIVE.match(line):
            marker = f"__ISYS2014_MYSQL_CLIENT_DIRECTIVE_{index}__"
            directives[marker] = line
            newline = "\n" if line.endswith("\n") else ""
            prepared.append(f"-- {marker}{newline}")
        else:
            prepared.append(line)

    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as handle:
        handle.writelines(prepared)
        temporary = Path(handle.name)

    try:
        result = subprocess.run(
            ["sqlfluff", mode, *SQLFLUFF_ARGS, str(temporary)],
            capture_output=True,
            text=True,
            check=False,
        )
        output = (result.stdout + result.stderr).replace(str(temporary), str(path))
        if output:
            print(output, end="", file=sys.stderr if result.returncode else sys.stdout)

        if result.returncode or mode == "lint":
            return result.returncode

        formatted = temporary.read_text(encoding="utf-8")
        for marker, original in directives.items():
            pattern = re.compile(rf"(?m)^[ \t]*--[ \t]*{re.escape(marker)}[ \t]*$")
            formatted, count = pattern.subn(original.rstrip("\r\n"), formatted)
            if count != 1:
                print(f"ERROR: SQL formatter lost a client directive in {path}", file=sys.stderr)
                return 1

        path.write_text(formatted, encoding="utf-8")
        return 0
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in {"format", "lint"}:
        print("Usage: isys2014-sql {format|lint} FILE.sql [...]", file=sys.stderr)
        return 2

    mode = sys.argv[1]
    status = 0
    for argument in sys.argv[2:]:
        status = process(mode, Path(argument)) or status
    return status


if __name__ == "__main__":
    raise SystemExit(main())
