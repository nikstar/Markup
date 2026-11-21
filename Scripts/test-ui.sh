#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_path="$project_root/TestResults/UI-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project "$project_root/Markup.xcodeproj" -scheme MarkupUI -configuration Debug -derivedDataPath "$project_root/build/UITesting" -destination 'platform=macOS' MARKUP_APP_ID=dev.nikstar.Markup.UITesting -resultBundlePath "$result_path" test "$@"
