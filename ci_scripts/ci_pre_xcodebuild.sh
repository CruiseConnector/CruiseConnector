#!/bin/sh
set -eu

echo "CruiseConnect Xcode Cloud pre-xcodebuild setup"

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
cd "$REPO_ROOT"

ACTION="${CI_XCODEBUILD_ACTION:-}"
ARCHIVE_PATH="${CI_ARCHIVE_PATH:-}"

if [ "$ACTION" = "archive" ] || [ -n "$ARCHIVE_PATH" ]; then
    GENERATED_XCCONFIG="ios/Flutter/Generated.xcconfig"
    if [ ! -f "$GENERATED_XCCONFIG" ]; then
      echo "Generated.xcconfig missing, skipping archive signing override"
      exit 0
    fi

    if ! grep -q "CruiseConnect archive signing override" "$GENERATED_XCCONFIG"; then
      {
        echo ""
        echo "// CruiseConnect archive signing override for Xcode Cloud TestFlight/App Store exports."
        echo "CODE_SIGN_IDENTITY[sdk=iphoneos*]=Apple Distribution"
      } >> "$GENERATED_XCCONFIG"
    fi
else
  echo "No archive action detected; keeping local/development signing defaults"
fi

echo "Xcode Cloud pre-xcodebuild setup finished"
