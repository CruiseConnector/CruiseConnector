#!/bin/sh
set -eu

echo "CruiseConnect Xcode Cloud post-xcodebuild signing check"

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ] || [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  echo "No Xcode Cloud archive action detected; skipping archive signing check"
  exit 0
fi

ARCHIVE_PATH="${CI_ARCHIVE_PATH:-}"
if [ -z "$ARCHIVE_PATH" ] || [ ! -d "$ARCHIVE_PATH" ]; then
  echo "Archive path missing; skipping archive signing check"
  exit 0
fi

APP_PATH="$ARCHIVE_PATH/Products/Applications/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Runner.app missing inside archive; skipping archive signing check"
  exit 0
fi

signature_authority() {
  /usr/bin/codesign -dv --verbose=4 "$1" 2>&1 | sed -n 's/^Authority=//p' | head -n 1
}

runner_authority="$(signature_authority "$APP_PATH" || true)"
echo "Runner.app signing authority: ${runner_authority:-unknown}"

if printf '%s' "$runner_authority" | grep -q '^Apple Distribution'; then
  echo "Archive already uses Apple Distribution signing"
  exit 0
fi

distribution_identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.* \"\\(Apple Distribution[^\"]*\\)\".*/\\1/p' | head -n 1)"
if [ -z "$distribution_identity" ]; then
  echo "No Apple Distribution identity available in keychain"
  exit 1
fi

echo "Re-signing archive with Apple Distribution identity"

if [ -d "$APP_PATH/Frameworks" ]; then
  find "$APP_PATH/Frameworks" -maxdepth 1 -type d -name "*.framework" -print | while IFS= read -r framework; do
    /usr/bin/codesign --force --sign "$distribution_identity" "$framework"
  done
fi

/usr/bin/codesign --force --sign "$distribution_identity" --preserve-metadata=entitlements "$APP_PATH"

runner_authority="$(signature_authority "$APP_PATH" || true)"
echo "Runner.app signing authority after re-sign: ${runner_authority:-unknown}"

if ! printf '%s' "$runner_authority" | grep -q '^Apple Distribution'; then
  echo "Archive is still not distribution-signed after re-sign"
  exit 1
fi

echo "Xcode Cloud archive signing check finished"
