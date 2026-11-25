#!/bin/sh
# tools/release.sh <version>
# Regenerates the changelog page, runs the offline tests and builds
# dist/ForeverMemories-v<version>.zip with the files the game needs.
# Output goes to $OUT (default: ./dist).
# The finished release is also kept in $RELEASES (default: ./releases):
# the zip and ForeverMemories-v<version>.changelog.md, the CHANGELOG.en.md
# entry without "### Development", ready for the CurseForge upload form.
set -e
VERSION="$1"
OUT="${OUT:-dist}"
RELEASES="${RELEASES:-releases}"
lua5.1 tools/changelog.lua >/dev/null
lua5.1 tests/smoke.lua | tail -1
lua5.1 tests/run.lua | tail -1
BUILD="$(mktemp -d)"
mkdir -p "$BUILD/ForeverMemories"
cp -r ForeverMemories.toc Bindings.xml README.md README.en.md Core Capture Modules UI Locales Media "$BUILD/ForeverMemories/"
mkdir -p "$OUT"
rm -rf "$OUT/ForeverMemories" "$OUT/ForeverMemories-v$VERSION.zip"
(cd "$BUILD" && zip -qr "ForeverMemories-v$VERSION.zip" ForeverMemories)
cp -r "$BUILD/ForeverMemories" "$BUILD/ForeverMemories-v$VERSION.zip" "$OUT/"
rm -rf "$BUILD"
mkdir -p "$RELEASES"
cp "$OUT/ForeverMemories-v$VERSION.zip" "$RELEASES/"
awk -v v="## [$VERSION]" '
    index($0, v) == 1 { on = 1; print "### " substr($0, 4); next }
    on && /^## \[/ { exit }
    on && /^### / { skip = ($0 == "### Development"); if (!skip) print "#" $0; next }
    on && !skip { print }
' CHANGELOG.en.md > "$RELEASES/ForeverMemories-v$VERSION.changelog.md"
echo "$RELEASES/ForeverMemories-v$VERSION.zip"
