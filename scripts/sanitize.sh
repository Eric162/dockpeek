#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Keep instrumentation isolated and remove disposable compiler caches afterward.
trap 'rm -rf .build/address .build/thread' EXIT HUP INT TERM
./scripts/test.sh --scratch-path .build/address --sanitize address
./scripts/test.sh --scratch-path .build/thread --sanitize thread
