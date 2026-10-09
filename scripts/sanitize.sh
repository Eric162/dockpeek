#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Keep instrumentation separate from ordinary builds and coverage.
./scripts/test.sh --scratch-path .build/address --sanitize address
./scripts/test.sh --scratch-path .build/thread --sanitize thread
