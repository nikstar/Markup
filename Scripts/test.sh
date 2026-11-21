#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
result_path="$project_root/TestResults/Run-$(date +%Y%m%d-%H%M%S).xcresult"
xcodebuild -project "$project_root/Markup.xcodeproj" -scheme Markup -configuration Debug -derivedDataPath "$project_root/build" -destination 'platform=macOS' -resultBundlePath "$result_path" test "$@"
