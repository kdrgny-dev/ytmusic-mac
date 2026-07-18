#!/bin/bash
# Wrapper around `swift test` that picks Xcode's toolchain so XCTest is
# available. macOS Command Line Tools alone don't ship XCTest, so plain
# `swift test` fails with "no such module 'XCTest'".
set -euo pipefail
cd "$(dirname "$0")"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcrun swift test "$@"

# The player bridge is JS living inside a Swift string, so XCTest can't reach
# it. These run its extracted source against a fake DOM under node.
for t in Tests/js/*.test.js; do
    echo "=== $t"
    node "$t"
done
