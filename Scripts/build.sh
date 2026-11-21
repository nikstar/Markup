#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
xcodebuild -project "$project_root/Markup.xcodeproj" -scheme Markup -configuration Release -derivedDataPath "$project_root/build" build "$@"
