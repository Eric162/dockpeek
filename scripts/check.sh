#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
git diff --check
git diff --cached --check
for script in scripts/*.sh .githooks/* build.sh; do sh -n "$script"; done
python3 -m unittest discover -s scripts/tests -v
./scripts/lint.sh
swift build
swift build -c release
./scripts/test.sh --enable-code-coverage
mkdir -p .build/reports
cp "$(swift test --show-codecov-path)" .build/reports/coverage.json
python3 scripts/check_coverage.py .build/reports/coverage.json
./scripts/analyze.sh
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/package_app.py").read_text())'
