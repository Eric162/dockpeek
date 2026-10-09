#!/usr/bin/env python3
"""Enforce Conventional Commits on local messages or a CI revision range."""
import argparse
import re
import subprocess
from pathlib import Path

PATTERN = re.compile(
    r"(?:feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)"
    r"(?:\([a-z0-9][a-z0-9._/-]*\))?!?: [^\s].*"
)


def validate(message):
    subject = message.splitlines()[0] if message.splitlines() else ""
    return bool(PATTERN.fullmatch(subject)) and len(subject) <= 72 and subject == subject.rstrip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--message-file", type=Path)
    group.add_argument("--range")
    args = parser.parse_args()
    messages = ([args.message_file.read_text()] if args.message_file else
                subprocess.check_output(["git", "log", "--format=%s", args.range], text=True).splitlines())
    invalid = [message.splitlines()[0] if message.splitlines() else "<empty>"
               for message in messages if not validate(message)]
    if invalid:
        parser.exit(1, "Use a Conventional Commit subject of at most 72 characters, e.g. fix: preserve badge dismissal\n" + "\n".join(invalid) + "\n")


if __name__ == "__main__":
    main()
