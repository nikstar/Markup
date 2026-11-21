#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
output="${1:-$(mktemp -d -t markup-frames)}"
mkdir -p "$output"
output="$(cd "$output" && pwd)"
scratch="$(mktemp -d -t markup-recorder)"
trap 'rm -rf "$scratch"' EXIT
cd "$project_root"
xcodebuild -project Markup.xcodeproj -scheme Markup -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build/QuickMarkup build > "$output/build.log"
ditto build/QuickMarkup/Build/Products/Release/Markup.app/Contents/Resources "$scratch"
xcrun swiftc -O -target "$(uname -m)-apple-macos27.0" Core/*.swift Vendor/*.swift Editor/*.swift App/MarkupWindow.swift App/ImageDrop.swift Scripts/record-editor.swift -o "$scratch/record"
for scenario in zoom text controls colors shelf-light shelf-dark; do
  "$scratch/record" "$output/$scenario.mp4" "$scenario"
done
