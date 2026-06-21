#!/bin/bash
# Wrapper around `swift test` that picks Xcode's toolchain so XCTest is
# available. macOS Command Line Tools alone don't ship XCTest, so plain
# `swift test` fails with "no such module 'XCTest'".
set -euo pipefail
cd "$(dirname "$0")"
exec env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcrun swift test "$@"
