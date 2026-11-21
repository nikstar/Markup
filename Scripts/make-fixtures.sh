#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
"$project_root/Scripts/build.sh" > "$project_root/build-fixtures.log" 2>&1
fixture_app="$project_root/build/FixtureGenerator.app"
mkdir -p "$fixture_app/Contents/MacOS"
ditto "$project_root/build/Build/Products/Release/Markup.app/Contents/Resources" "$fixture_app/Contents/Resources"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.nikstar.Markup.FixtureGenerator</string><key>CFBundleExecutable</key><string>FixtureGenerator</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
xcrun swiftc -O -target arm64-apple-macos27.0 "$project_root"/Core/*.swift "$project_root"/Vendor/*.swift "$project_root/Scripts/make-fixtures.swift" -o "$fixture_app/Contents/MacOS/FixtureGenerator"
"$fixture_app/Contents/MacOS/FixtureGenerator" "$project_root/Documentation"
