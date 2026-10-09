#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
version=0.65.1
checksum=c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
if [ ! -x .tools/swiftlint/swiftlint ] || [ "$(.tools/swiftlint/swiftlint version)" != "$version" ]; then
  temporary=$(mktemp -d)
  trap 'rm -rf "$temporary"' EXIT HUP INT TERM
  curl --fail --location --retry 3 "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" -o "$temporary/swiftlint.zip"
  printf '%s  %s\n' "$checksum" "$temporary/swiftlint.zip" | shasum -a 256 -c -
  mkdir -p .tools/swiftlint
  unzip -oq "$temporary/swiftlint.zip" -d .tools/swiftlint
fi
. ./scripts/tools.sh
git config --local core.hooksPath .githooks
printf 'Tools verified. Repository hooks installed.\n'
