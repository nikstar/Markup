#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
launch=true
if [[ "${1:-}" == --no-launch ]]; then
  launch=false
  shift
fi
"$project_root/Scripts/build.sh" "$@"
app=/Applications/Markup.app
guard_running_app() {
  if pgrep -f '^/Applications/Markup[.]app/Contents/MacOS/Markup( |$)' >/dev/null; then
    echo "Save and quit the running Markup app, then run this installer again." >&2
    exit 1
  fi
}
guard_running_app
stage="$(mktemp -d /Applications/.Markup-install.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
ditto "$project_root/build/Build/Products/Release/Markup.app" "$stage/Markup.app"
codesign --verify --deep --strict "$stage/Markup.app"
guard_running_app
backup=""
if [[ -e "$app" ]]; then
  backups="$HOME/Library/Application Support/Markup/Previous Builds"
  mkdir -p "$backups"
  backup="$(mktemp -d "$backups/$(date +%Y%m%d-%H%M%S).XXXXXX")/Markup.app"
  mv "$app" "$backup"
fi
if ! mv "$stage/Markup.app" "$app"; then
  if [[ -n "$backup" ]]; then mv "$backup" "$app"; fi
  exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
pluginkit -a "$app/Contents/PlugIns/MarkupAction.appex"
if "$launch"; then open "$app"; fi
