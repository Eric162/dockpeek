#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
developer_dir=${DEVELOPER_DIR:-$(xcode-select -p)}
frameworks="$developer_dir/Library/Developer/Frameworks"
if [ -d "$frameworks/Testing.framework" ]; then
  # Command Line Tools ship Testing outside the normal SDK framework search path.
  swift test --disable-index-store "$@" --disable-xctest -Xswiftc -warnings-as-errors \
    -Xswiftc -F -Xswiftc "$frameworks" \
    -Xswiftc -load-plugin-library \
    -Xswiftc "$developer_dir/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib" \
    -Xlinker -F -Xlinker "$frameworks" \
    -Xlinker -framework -Xlinker Testing \
    -Xlinker -rpath -Xlinker "$frameworks" \
    -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
else
  swift test --disable-index-store "$@" --disable-xctest -Xswiftc -warnings-as-errors
fi
