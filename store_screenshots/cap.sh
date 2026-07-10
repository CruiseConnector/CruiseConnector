#!/bin/zsh
# cap.sh NAME  -> weckt das Gerät, prüft Sperre, macht Screenshot -> raw/android/NAME.png
ADB=~/Library/Android/sdk/platform-tools/adb
NAME="${1:-shot}"
DIR="$(cd "$(dirname "$0")" && pwd)/raw/android"
mkdir -p "$DIR"
$ADB shell input keyevent 224 >/dev/null 2>&1   # WAKEUP
LOCK=$($ADB shell dumpsys window 2>/dev/null | grep -c "isKeyguardShowing=true")
if [ "$LOCK" -gt 0 ]; then
  echo "GESPERRT — bitte Samsung entsperren. Kein Screenshot gemacht."
  exit 1
fi
sleep 1
$ADB shell screencap -p /sdcard/_c.png >/dev/null 2>&1
$ADB pull /sdcard/_c.png "$DIR/$NAME.png" >/dev/null 2>&1
SZ=$(ls -la "$DIR/$NAME.png" 2>/dev/null | awk '{print $5}')
FOCUS=$($ADB shell dumpsys window 2>/dev/null | grep -iE "mCurrentFocus" | head -1 | sed 's/.*Window{//' | sed 's/}.*//')
echo "OK -> $DIR/$NAME.png ($SZ bytes) | Fokus: $FOCUS"
