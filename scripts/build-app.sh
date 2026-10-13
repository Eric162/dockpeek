#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
configuration=${1:-release}
case "$configuration" in debug|release) ;; *) echo 'Use debug or release.' >&2; exit 1;; esac
swift build --disable-index-store -c "$configuration" -Xswiftc -warnings-as-errors
bin_path=$(swift build --disable-index-store -c "$configuration" --show-bin-path)
python3 scripts/package_app.py "$bin_path"
identity=${CODE_SIGN_IDENTITY:--}
codesign --force --sign "$identity" 'dist/Dock Peek.app/Contents/Resources/Dock Tile Probe.app'
codesign --force --sign "$identity" 'dist/Dock Peek.app/Contents/Library/LoginItems/DockPeekWorker.app'
codesign --force --sign "$identity" 'dist/Dock Peek.app'
codesign --verify --deep --strict 'dist/Dock Peek.app'
plutil -lint 'dist/Dock Peek.app/Contents/Info.plist'
echo 'Built dist/Dock Peek.app'
