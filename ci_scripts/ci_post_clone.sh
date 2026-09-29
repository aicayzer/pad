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
team="${APPLE_DEVELOPMENT_TEAM:?Set APPLE_DEVELOPMENT_TEAM in the workflow environment}"
[[ "$team" =~ '^[A-Z0-9]{10}$' ]] || {
  print -u2 'APPLE_DEVELOPMENT_TEAM must be a valid development team identifier.'
  exit 1
}
# Project settings override xcconfig values, so update the generated project counter.
xcrun agvtool new-version -all "$build_number"
# Cloud manages signing; its build sequence is the single distribution counter.
cat > Config/Cloud.xcconfig <<SETTINGS
CODE_SIGNING_ALLOWED = YES
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = $team
PAD_DISTRIBUTION_SIGNING_STYLE = Automatic
PAD_DISTRIBUTION_PROFILE =
SETTINGS

# Build the bundled offline editor on the ephemeral Cloud worker.
export HOMEBREW_NO_AUTO_UPDATE=1
command -v node >/dev/null || brew install node
command -v pnpm >/dev/null || brew install pnpm
