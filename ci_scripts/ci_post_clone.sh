#!/bin/zsh
set -euo pipefail
cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
# The committed project lets Cloud discover the scheme without installing XcodeGen.
if [[ -n "${CI_TAG:-}" ]]; then
  scripts/validate-release.sh "$CI_TAG"
fi
build_number="${CI_BUILD_NUMBER:?Xcode Cloud must supply CI_BUILD_NUMBER}"
[[ "$build_number" =~ '^[1-9][0-9]*$' ]] || {
  print -u2 'CI_BUILD_NUMBER must be a positive integer.'
  exit 1
}
# Project settings override xcconfig values, so update the generated project counter.
xcrun agvtool new-version -all "$build_number"
# Cloud manages signing; its build sequence is the single distribution counter.
cat > Config/Cloud.xcconfig <<SETTINGS
CODE_SIGNING_ALLOWED = YES
CODE_SIGN_STYLE = Automatic
SETTINGS
