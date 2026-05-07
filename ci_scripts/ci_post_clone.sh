#!/bin/sh
set -eu

echo "CruiseConnect Xcode Cloud post-clone setup"

REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(pwd)}"
cd "$REPO_ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"
  if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
    echo "Installing Flutter stable into $FLUTTER_ROOT"
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
  fi
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi

if ! command -v pod >/dev/null 2>&1; then
  GEM_BIN="$(ruby -e 'print Gem.user_dir')/bin"
  export PATH="$GEM_BIN:$PATH"
  echo "Installing CocoaPods for Xcode Cloud"
  gem install --user-install cocoapods --no-document
fi

flutter --version
flutter config --no-analytics
flutter pub get
flutter precache --ios

cd "$REPO_ROOT/ios"
pod install --repo-update

test -f "Pods/Target Support Files/Pods-Runner/Pods-Runner-resources-Release-input-files.xcfilelist"
test -f "Pods/Target Support Files/Pods-Runner/Pods-Runner-resources-Release-output-files.xcfilelist"

echo "Xcode Cloud post-clone setup finished"
