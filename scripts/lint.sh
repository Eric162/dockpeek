#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/tools.sh
xcrun swift-format lint --configuration .swift-format --strict --recursive Package.swift Sources Tests
"$SWIFTLINT" lint --strict --no-cache --config .swiftlint.yml
