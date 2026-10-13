#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
git diff --check
git diff --cached --check
for script in scripts/*.sh .githooks/* build.sh; do sh -n "$script"; done
python3 -m unittest discover -s scripts/tests -v
./scripts/lint.sh
swift build --disable-index-store
swift build --disable-index-store -c release
./scripts/test.sh --enable-code-coverage
mkdir -p .build/reports
cp "$(swift test --show-codecov-path)" .build/reports/coverage.json
python3 scripts/check_coverage.py .build/reports/coverage.json
./scripts/analyze.sh
python3 -c 'import ast, pathlib; [ast.parse(p.read_text(), filename=str(p)) for p in pathlib.Path("scripts").rglob("*.py")]'
