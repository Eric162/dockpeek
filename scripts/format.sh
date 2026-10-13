#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. ./scripts/tools.sh
xcrun swift-format format --configuration .swift-format --in-place --recursive Package.swift Sources Tests
