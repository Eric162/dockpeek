#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcrun swift-format lint --strict --recursive Package.swift Sources Tests Experiments
swift build -Xswiftc -warnings-as-errors
./scripts/test.sh
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/package_app.py").read_text())'
