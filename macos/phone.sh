#!/bin/zsh
# Mirror and control an Android phone from this Mac.
#   ./phone.sh            USB if plugged in (re-arms Wi-Fi), else Wi-Fi to the last saved IP
#   ./phone.sh audio      also play the phone's sound on the Mac
#   PHONE_IP=1.2.3.4 ./phone.sh
# If adb's default port 5037 is taken on your Mac, export ANDROID_ADB_SERVER_PORT=5038 first.

PORT=5555
CONFIG_DIR="$HOME/.config/screenless"
IP_FILE="$CONFIG_DIR/last-ip"

fail() { print -P "%F{red}[screenless] $1%f"; exit 1 }
info() { print -P "%F{cyan}[screenless] $1%f" }

for tool in adb scrcpy; do
  command -v $tool >/dev/null || fail "$tool not found. Install with: brew install scrcpy"
done

COMMON=(--video-codec=h264 --max-fps=60 --turn-screen-off)
[[ $1 == audio ]] || COMMON+=(--no-audio)

USB_LINE=$(adb devices -l | grep "usb:" | head -1)
if [[ -n $USB_LINE ]]; then
  SERIAL=${USB_LINE%% *}
  STATE=$(echo $USB_LINE | awk '{print $2}')
  [[ $STATE == unauthorized ]] && fail "Phone not trusted. Tick 'Always allow' on the phone, or install a trusted key (docs/MACOS.md)."
  [[ $STATE == device ]] || fail "Phone state is '$STATE'. Unplug, wait 5 seconds, plug back in."

  IP=$(adb -s $SERIAL shell ip -f inet addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
  if [[ -n $IP ]]; then
    mkdir -p $CONFIG_DIR && echo $IP > $IP_FILE
    info "Phone Wi-Fi IP: $IP (saved)"
  fi

  # Wireless mode turns off on every phone restart; re-arm it while we're plugged in
  adb -s $SERIAL tcpip $PORT >/dev/null
  adb -s $SERIAL wait-for-usb-device
  adb -s $SERIAL shell svc power stayon true
  adb -s $SERIAL shell input keyevent KEYCODE_WAKEUP

  info "Mirroring over USB. Close the window to stop."
  exec scrcpy -s $SERIAL --video-bit-rate=8M --stay-awake $COMMON
fi

IP=${PHONE_IP:-$(cat $IP_FILE 2>/dev/null)}
[[ -n $IP ]] || fail "No USB phone and no saved Wi-Fi IP. Plug the phone in once and run this again."

TARGET="$IP:$PORT"
info "Connecting over Wi-Fi to $TARGET ..."
adb connect $TARGET | grep -q "connected to" ||
  fail "Could not reach $TARGET. If the phone restarted, wireless mode is off: plug in USB once and run this again."

adb -s $TARGET shell svc power stayon true
adb -s $TARGET shell input keyevent KEYCODE_WAKEUP

info "Mirroring over Wi-Fi. Close the window to stop."
# Less data per frame so a weak network drops fewer frames
exec scrcpy -s $TARGET --video-bit-rate=3M --max-size=1024 $COMMON
