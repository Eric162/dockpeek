#!/usr/bin/env python3
"""Gate core line coverage; AppKit interaction coverage requires manual testing."""
import json
import sys
from pathlib import Path


def check(report):
    files = [entry for data in report["data"] for entry in data["files"]
             if "/Sources/DockPeekCore/" in entry["filename"]]
    expected = {path.name for path in Path("Sources/DockPeekCore").glob("*.swift")}
    if {Path(entry["filename"]).name for entry in files} != expected or not files:
        raise ValueError("Coverage report must include every DockPeekCore source file")
    count = sum(entry["summary"]["lines"]["count"] for entry in files)
    covered = sum(entry["summary"]["lines"]["covered"] for entry in files)
    percent = 100 * covered / count if count else 0
    print(f"DockPeekCore line coverage: {percent:.2f}% ({covered}/{count})")
    if percent < 100:
        raise ValueError("DockPeekCore line coverage must be 100%")


if __name__ == "__main__":
    try:
        check(json.loads(Path(sys.argv[1]).read_text()))
    except (ValueError, KeyError, IndexError) as error:
        sys.exit(str(error))
