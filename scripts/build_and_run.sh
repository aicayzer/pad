#!/bin/zsh
set -euo pipefail
cd "${0:a:h}/.."
mode="${1:-run}"
case "$mode" in
  run|--build-only) ;;
  *) print -u2 'usage: scripts/build_and_run.sh [--build-only]'; exit 2 ;;
esac
xcodegen generate -q
mkdir -p build/Dev
xcodebuild -project Pad.xcodeproj -scheme Pad -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Dev -showBuildSettings -json > build/Dev/settings.json
app_id=$(python3 -c 'import json; print(next(x["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"] for x in json.load(open("build/Dev/settings.json")) if x["target"] == "Pad"))')
app_path=$(python3 -c 'import json; s=next(x["buildSettings"] for x in json.load(open("build/Dev/settings.json")) if x["target"] == "Pad"); print(s["TARGET_BUILD_DIR"]+"/"+s["FULL_PRODUCT_NAME"])')
if [[ -n "$(/usr/bin/lsappinfo find bundleID="$app_id")" ]]; then
  print -u2 'The development app is running. Check whether it is in use, then quit it before rebuilding.'
  exit 1
fi
signing=()
if [[ ! -f Config/Local.xcconfig ]]; then
  signing=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi
xcodebuild -project Pad.xcodeproj -scheme Pad -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/Dev "${signing[@]}" build
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")" == "$app_id" ]]
print "Built: $app_path"
[[ "$mode" == --build-only ]] && exit 0
open -n "$app_path"
