#!/bin/bash
# Build using the signed-in Xcode account. Publish only the ZIP that Gatekeeper assessed.
set -euo pipefail
cd "$(dirname "$0")/.."
repo=nikstar/Markup
team=6RX8GEVB43
notes=""
if [[ $# -ne 0 ]]; then
  if [[ $# -ne 2 || "$1" != --publish || ! -s "$2" ]]; then
    echo "Usage: Scripts/release.sh [--publish path/to/release-notes.md]" >&2
    exit 2
  fi
  notes="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
fi
revision="$(git rev-parse HEAD)"
out="$PWD/build/releases/$revision"
mkdir -p "$out"
shlock -f "$out/release.lock" -p $$ || { echo "This revision is already being released." >&2; exit 1; }
work="$(mktemp -d "$out/work.XXXXXX")"
trap 'rm -rf "$work"; rm -f "$out/release.lock"' EXIT

archive="$out/Markup.xcarchive"
if [[ ! -d "$archive" ]]; then
  # Build exactly the revision that will be tagged, even when other edits are in progress.
  mkdir "$work/source"
  git archive "$revision" | tar -x -C "$work/source"
  xcodebuild -project "$work/source/Markup.xcodeproj" -scheme Markup -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$work/DerivedData" \
    -clonedSourcePackagesDirPath "$out/SourcePackages" -onlyUsePackageVersionsFromResolvedFile \
    -archivePath "$work/Markup.xcarchive" -allowProvisioningUpdates ARCHS=arm64 \
    DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic 'CODE_SIGN_IDENTITY=Apple Development' archive
  mv "$work/Markup.xcarchive" "$archive"
fi

if [[ ! -e "$out/submitted" ]]; then
  options="$work/export.plist"
  plutil -create xml1 "$options"
  plutil -insert method -string developer-id "$options"
  plutil -insert destination -string upload "$options"
  plutil -insert signingStyle -string automatic "$options"
  plutil -insert teamID -string "$team" "$options"
  plutil -insert manageAppVersionAndBuildNumber -bool NO "$options"
  xcodebuild -exportArchive -archivePath "$archive" -exportPath "$work/upload" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates
  touch "$out/submitted"
fi

app="$out/export/Markup.app"
if [[ ! -d "$app" ]]; then
  # Retry this step on the same archive if Apple is still processing.
  xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$work/export"
  mv "$work/export" "$out/export"
fi
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
build="$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")"
name="Markup-$version-macOS.zip"
zip="$out/$name"
if [[ ! -f "$zip" ]]; then
  zip="$work/$name"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
fi
ditto -x -k "$zip" "$work/unpacked"
download="$work/unpacked/Markup.app"
codesign --verify --deep --strict "$download"
for bundle in "$download" "$download/Contents/PlugIns/MarkupAction.appex"; do
  signature="$(codesign -dvvv "$bundle" 2>&1)"
  grep -Fqx "TeamIdentifier=$team" <<<"$signature"
  grep -q '^Authority=Developer ID Application:' <<<"$signature"
  grep -Eq 'flags=.*\(.*runtime.*\)' <<<"$signature"
done
xcrun stapler validate "$download"
spctl --assess --type execute --verbose=2 "$download"
if [[ "$zip" == "$work/$name" ]]; then mv "$zip" "$out/$name"; fi
(cd "$out" && shasum -a 256 "$name") > "$work/$name.sha256"
mv "$work/$name.sha256" "$out/"
# Publish the signed feed beside the ZIP so the latest release switches both together.
sparkle="$out/SourcePackages/artifacts/sparkle/Sparkle/bin"
account=dev.nikstar.Markup
publicKey="$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")"
[[ "$("$sparkle/generate_keys" --account "$account" -p)" == "$publicKey" ]] || {
  echo "The Sparkle public key in Markup must match the $account Keychain account." >&2; exit 1;
}
feed="$work/feed"
mkdir "$feed"
ln "$out/$name" "$feed/$name"
releaseNotes="${notes:-Documentation/Releases/$version.md}"
cp "$releaseNotes" "$feed/${name%.zip}.md"
releaseURL="https://github.com/$repo/releases"
"$sparkle/generate_appcast" --account "$account" --maximum-deltas 0 --embed-release-notes \
  --link "$releaseURL/tag/v$version" --full-release-notes-url "$releaseURL" \
  --download-url-prefix "$releaseURL/download/v$version/" "$feed"
"$sparkle/sign_update" --account "$account" --verify "$feed/appcast.xml"
signature="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$feed/appcast.xml")"
[[ -n "$signature" ]]
"$sparkle/sign_update" --account "$account" --verify "$out/$name" "$signature"
mv "$feed/appcast.xml" "$out/appcast.xml"
echo "Verified $name (build $build) from $revision in $out"

if [[ -n "$notes" ]]; then
  tag="v$version"
  git fetch origin main
  git merge-base --is-ancestor "$revision" FETCH_HEAD || { echo "Push the release commit to main first." >&2; exit 1; }
  # An existing tag must resolve to this exact revision, including on a release retry.
  if git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null; then
    git fetch origin "refs/tags/$tag"
    [[ "$(git rev-parse 'FETCH_HEAD^{commit}')" == "$revision" ]]
  else
    git push origin "$revision:refs/tags/$tag"
  fi
  gh release create "$tag" "$out/$name" "$out/$name.sha256" "$out/appcast.xml" --repo "$repo" --verify-tag \
    --title "Markup $version" --notes-file "$notes" --latest
fi
