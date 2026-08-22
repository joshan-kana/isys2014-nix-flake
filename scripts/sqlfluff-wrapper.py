import re
import subprocess
import sys
import tempfile
from pathlib import Path

DIRECTIVE = re.compile(r"^\s*(?:source|\\\.)\s+.+;?\s*$", re.IGNORECASE)
TOKEN = "__ISYS2014_MYSQL_CLIENT_DIRECTIVE_"
ARGS = [
    "--dialect",
    "mysql",
    "--templater",
    "raw",
    "--exclude-rules",
    "CP02,RF04",
    "--disable-progress-bar",
]


def process(mode: str, filename: str) -> int:
    path = Path(filename)
    if not path.is_file():
        print(f"ERROR: SQL file not found: {path}", file=sys.stderr)
        return 2

    source = path.read_text(encoding="utf-8")
    if TOKEN in source:
        print(f"ERROR: reserved SQL marker appears in {path}", file=sys.stderr)
        return 2

    saved: dict[str, str] = {}
    masked: list[str] = []
    for number, line in enumerate(source.splitlines(keepends=True)):
        if DIRECTIVE.match(line):
            marker = f"{TOKEN}{number}__"
            saved[marker] = line.rstrip("\r\n")
            masked.append(f"-- {marker}\n")
        else:
            masked.append(line)

    with tempfile.TemporaryDirectory() as tmpdir:
        temporary = Path(tmpdir) / path.name
        temporary.write_text("".join(masked), encoding="utf-8")
        result = subprocess.run(
            ["sqlfluff", mode, *ARGS, str(temporary)],
            capture_output=True,
            text=True,
        )
        output = (result.stdout + result.stderr).replace(str(temporary), str(path))
        if output:
            print(output, end="", file=sys.stderr if result.returncode else sys.stdout)
        if result.returncode or mode == "lint":
            return result.returncode

        formatted = temporary.read_text(encoding="utf-8")
        for marker, original in saved.items():
            pattern = rf"(?m)^\s*--\s*{re.escape(marker)}\s*$"
            if len(re.findall(pattern, formatted)) != 1:
                print(f"ERROR: SQLFluff lost or duplicated a directive in {path}", file=sys.stderr)
                return 2
            formatted = re.sub(pattern, lambda _: original, formatted)
        path.write_text(formatted, encoding="utf-8")
    return 0


if len(sys.argv) < 3 or sys.argv[1] not in {"format", "lint"}:
    raise SystemExit("Usage: sqlfluff-wrapper.py {format|lint} FILE.sql [...]")

raise SystemExit(max(process(sys.argv[1], filename) for filename in sys.argv[2:]))
