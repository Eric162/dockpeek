#!/bin/sh
# Source from scripts after changing to the repository root.
set -eu
SWIFTLINT_VERSION=0.65.1
SWIFTLINT=.tools/swiftlint/swiftlint
if [ ! -x "$SWIFTLINT" ] || [ "$("$SWIFTLINT" version)" != "$SWIFTLINT_VERSION" ]; then
  echo 'Run make bootstrap to install the pinned SwiftLint.' >&2
  exit 1
fi
if [ "$(xcrun swift-format --version)" != '6.3.0' ]; then
  echo 'swift-format 6.3.0 is required. Select Xcode 26.5 or matching Command Line Tools.' >&2
  exit 1
fi
# SourceKitten skips Command Line Tools during automatic discovery, even though
# current CLT releases ship SourceKit. Point it at the selected installation.
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
if [ -f "$developer_dir/usr/lib/sourcekitdInProc.framework/Versions/A/sourcekitdInProc" ]; then
  export XCODE_DEFAULT_TOOLCHAIN_OVERRIDE="$developer_dir"
fi
