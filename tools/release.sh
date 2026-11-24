#!/bin/sh
# tools/release.sh <version> <git-ref-of-previous-release>
# Regenerates the changelog page, runs the offline tests and builds
# dist/ForeverMemories-v<version>.zip with the files the game needs.
# Output goes to $OUT (default: ./dist).
set -e
VERSION="$1"
OUT="${OUT:-dist}"
lua5.1 tools/changelog.lua >/dev/null
lua5.1 tests/run.lua | tail -1
BUILD="$(mktemp -d)"
mkdir -p "$BUILD/ForeverMemories"
cp -r ForeverMemories.toc Bindings.xml README.md Core Capture Modules UI Locales "$BUILD/ForeverMemories/"
mkdir -p "$OUT"
rm -rf "$OUT/ForeverMemories" "$OUT/ForeverMemories-v$VERSION.zip"
(cd "$BUILD" && zip -qr "ForeverMemories-v$VERSION.zip" ForeverMemories)
cp -r "$BUILD/ForeverMemories" "$BUILD/ForeverMemories-v$VERSION.zip" "$OUT/"
rm -rf "$BUILD"
echo "$OUT/ForeverMemories-v$VERSION.zip"
