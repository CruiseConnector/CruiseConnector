#!/bin/sh
set -eu

echo "CruiseConnect Xcode Cloud pre-xcodebuild setup"

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
cd "$REPO_ROOT"

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
  echo "Not running in Xcode Cloud; keeping local/development signing defaults"
  echo "Xcode Cloud pre-xcodebuild setup finished"
  exit 0
fi

GENERATED_XCCONFIG="ios/Flutter/Generated.xcconfig"
if [ ! -f "$GENERATED_XCCONFIG" ]; then
  echo "Generated.xcconfig missing, skipping Xcode Cloud signing override"
  exit 0
fi

if ! grep -q "CruiseConnect Xcode Cloud signing override" "$GENERATED_XCCONFIG"; then
  {
    echo ""
    echo "// CruiseConnect Xcode Cloud signing override for TestFlight/App Store exports."
    echo "CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution"
  } >> "$GENERATED_XCCONFIG"
fi

echo "Xcode Cloud pre-xcodebuild setup finished"
