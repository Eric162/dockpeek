#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
xcrun swift-format format --in-place --recursive Package.swift Sources Tests Experiments
