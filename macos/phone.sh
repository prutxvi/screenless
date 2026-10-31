#!/bin/zsh
# Mirror and control an Android phone from this Mac.
#   ./phone.sh            USB if plugged in (re-arms Wi-Fi), else reconnects over Wi-Fi
#   ./phone.sh audio      also play the phone's sound on the Mac (Android 11+)
#   PHONE_IP=1.2.3.4 ./phone.sh
#   ./phone.sh -s SERIAL  pick a specific USB phone when several are connected
#
# One text record per device in ~/.config/screenless/devices/<serial>.conf stores the
# model, Android version and remembered Wi-Fi IPs — the same format the Windows
# launcher writes, so the two stay in sync.
# If adb's default port 5037 is taken on your Mac, export ANDROID_ADB_SERVER_PORT=5038 first.

# Run with a pristine zsh option set, so rc-file options can't alter function behaviour
emulate -LR zsh

PORT=5555
CONFIG_DIR="$HOME/.config/screenless"
DEVICE_DIR="$CONFIG_DIR/devices"
IP_FILE="$CONFIG_DIR/last-ip"       # legacy single-IP file, migrated into devices/ on first run
MAX_SAVED_IPS=5
MAX_RETRIES=3
RETRY_DELAY=3

fail() { print -P "%F{red}[screenless] $1%f"; exit 1 }
info() { print -P "%F{cyan}[screenless] $1%f" }

for tool in adb scrcpy; do
  command -v $tool >/dev/null || fail "$tool not found. Install with: brew install scrcpy"
done

get_devices() {
  adb devices -l | tail -n +2 | grep -v '^\s*$'
}

is_usb() { [[ $1 == *usb:* ]] }

get_prop() { adb -s "$1" shell getprop "$2" 2>/dev/null | tr -d '\r\n' }

# ---------------------------------------------------------------------------
# Device bookkeeping: <serial>.conf with serial=/model=/android=/last_seen=/ips=
# ---------------------------------------------------------------------------
record_path() {
  local safe
  safe=$(printf %s "$1" | tr -c '[:alnum:]._-' '_')
  print -r -- "$DEVICE_DIR/$safe.conf"
}

read_field() { grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2- }

save_record() {
  local serial="$1" model="$2" android="$3" new_ip="$4"
  local rec_file
  rec_file=$(record_path "$serial")
  mkdir -p "$DEVICE_DIR"
  local old_model old_android old_ips
  old_model=$(read_field "$rec_file" model)
  old_android=$(read_field "$rec_file" android)
  old_ips=$(read_field "$rec_file" ips)
  [[ -n $model ]] || model=$old_model
  [[ -n $android ]] || android=$old_android

  local ip_list="$old_ips"
  [[ -n $new_ip ]] && ip_list="$new_ip${ip_list:+,$ip_list}"

  # dedupe, keep the newest first, cap the history
  local -A seen
  local out=()
  local keep=$MAX_SAVED_IPS
  local p
  for p in ${(s:,:)ip_list}; do
    [[ -n $p ]] || continue
    [[ -z ${seen[$p]} ]] || continue
    (( keep-- > 0 )) || break
    seen[$p]=1
    out+=$p
  done

  {
    print "serial=$serial"
    print "model=$model"
    print "android=$android"
    print "last_seen=$(date +%Y-%m-%dT%H:%M:%S)"
    (IFS=,; print "ips=${(j:,:)out}")
  } > "$rec_file"
}

# Every remembered Wi-Fi IP, newest device first; also imports the old last-ip file once
get_known_ips() {
  local -A seen
  local f line ip val
  for f in "$DEVICE_DIR"/*.conf(.N) "$IP_FILE"(N); do
    while IFS= read -r line; do
      case $line in
        ips=*) val=${line#*=};;
        *) continue;;
      esac
      for ip in ${(s:,:)val}; do
        [[ -n $ip && -z ${seen[$ip]} ]] || continue
        seen[$ip]=1
        print -- "$ip"
      done
    done < "$f"
  done
  if [[ -f $IP_FILE ]]; then
    ip=$(grep -m1 -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$IP_FILE" 2>/dev/null)
    if [[ -n $ip && -z ${seen[$ip]} ]]; then
      print -- "$ip"
      save_record legacy-device '' '' "$ip"
    fi
  fi
}

# Phones advertising wireless-debugging connect services on this network (Android 11+, paired)
find_mdns() {
  local out
  out=$(adb mdns services 2>/dev/null) || return
  printf '%s\n' "$out" | grep -q '_adb-tls-connect\.' || return
  printf '%s\n' "$out" \
    | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+' \
    | sort -u
}

get_model() {
  local m
  m=$(read_field "$(record_path "$1")" model)
  [[ -n $m ]] && { print -- "$m"; return }
  get_prop "$1" ro.product.model
}

# Try each address once; prints nothing, sets REPLY_TARGET to the winner or ''
connect_first() {
  local t out
  REPLY_TARGET=''
  for t in "$@"; do
    # Skip addresses that don't answer within 2 s (adb connect alone can hang for a minute)
    if ! nc -z -G 2 "${t%:*}" "${t##*:}" >/dev/null 2>&1; then
      info "  $t not reachable on this network, skipping"
      continue
    fi
    info "Connecting over Wi-Fi to $t ..."
    out=$(adb connect "$t" 2>&1)
    if [[ $out == *connected\ to* ]]; then
      REPLY_TARGET=$t
      return 0
    fi
    info "  $t did not answer ($out)"
  done
  return 1
}

COMMON=(--video-codec=h264 --max-fps=60 --turn-screen-off)
MODE=video
if [[ $1 == audio ]]; then
  MODE=audio
  shift
fi
# optional -s SERIAL
if [[ $1 == -s ]]; then
  WANT_SERIAL=$2
  shift 2
fi
[[ $MODE == audio ]] || COMMON+=(--no-audio)

USB_LINE=$(get_devices | grep 'usb:' | head -n1)

if [[ -n $USB_LINE ]]; then
  USB_LINES=$(get_devices | grep 'usb:')
  COUNT=$(printf '%s\n' $USB_LINES | wc -l | tr -d ' ')

  if (( COUNT > 1 )); then
    if [[ -n $WANT_SERIAL ]]; then
      USB_LINE=$(printf '%s\n' $USB_LINES | grep "^$WANT_SERIAL " | head -n1)
      [[ -n $USB_LINE ]] || fail "Serial '$WANT_SERIAL' is not among the USB devices connected."
    else
      info 'Multiple USB devices connected:'
      i=0
      choices=()
      printf '%s\n' $USB_LINES | while IFS= read -r line; do
        serial=${line%% *}
        state=$(print -r -- $line | awk '{print $2}')
        print "  [$i] $serial  $state  $(get_model $serial)"
        i=$((i+1))
      done
      print -nP "%F{magenta}[screenless]%f Number to mirror [0-$((COUNT-1))]: "
      read -r pick
      chosen=$(printf '%s\n' $USB_LINES | awk -v n="${pick:-0}" 'NR==n+1 {print; exit}')
      [[ -n $chosen ]] || fail 'Invalid selection.'
      USB_LINE=$chosen
    fi
  fi

  SERIAL=${USB_LINE%% *}
  STATE=$(print -r -- $USB_LINE | awk '{print $2}')
  [[ $STATE == unauthorized ]] && fail "Phone not trusted. Tick 'Always allow' on the phone, or install a trusted key (docs/MACOS.md)."
  [[ $STATE == device ]] || fail "Phone state is '$STATE'. Unplug, wait 5 seconds, plug back in."

  if [[ $MODE == audio ]]; then
    SDK=$(get_prop $SERIAL ro.build.version.sdk)
    if [[ -n $SDK && $SDK -lt 30 ]]; then
      print -P "%F{yellow}[screenless] Phone runs Android SDK $SDK; audio forwarding needs Android 11 (SDK 30). Continuing video-only.%f"
      COMMON+=(--no-audio)
      MODE=video
    fi
  fi

  # Save the phone's current Wi-Fi IP (per-device record, IP history) for cable-free use
  IP=$(adb -s $SERIAL shell ip -f inet addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
  if [[ -n $IP ]]; then
    save_record $SERIAL "$(get_prop $SERIAL ro.product.model)" "$(get_prop $SERIAL ro.build.version.release)" "$IP"
    info "Phone Wi-Fi IP: $IP (saved)"
  else
    save_record $SERIAL "$(get_prop $SERIAL ro.product.model)" "$(get_prop $SERIAL ro.build.version.release)" ''
    info "Could not read the phone's Wi-Fi IP (no Wi-Fi/data connection?). Wireless reconnection later may fail."
  fi

  # Wireless mode turns off on every phone restart; re-arm it while we're plugged in
  # (adbd restarts after tcpip, so wait until the phone is back on USB)
  adb -s $SERIAL tcpip $PORT >/dev/null
  for _ in {1..20}; do
    sleep 0.5
    [[ $(adb -s $SERIAL get-state 2>/dev/null) == device ]] && break
  done
  adb -s $SERIAL shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1

  info 'Mirroring over USB. Close the window to stop.'
  attempt=0
  while true; do
    scrcpy -s $SERIAL --video-bit-rate=8M --stay-awake "${COMMON[@]}"
    code=$?
    [[ $code -eq 0 ]] && exit 0
    attempt=$((attempt + 1))
    (( attempt <= MAX_RETRIES )) || fail "scrcpy kept failing (exit $code)."
    info "Mirror dropped (exit $code). Retrying in ${RETRY_DELAY}s ... [$attempt/$MAX_RETRIES]"
    sleep $RETRY_DELAY
    if ! get_devices | grep -q "^$SERIAL .*device"; then
      info 'Phone no longer visible over USB. Waiting up to 30s for it to come back ...'
      found=0
      for _ in {1..15}; do
        sleep 2
        get_devices | grep -q "^$SERIAL .*device" && { found=1; break; }
      done
      (( found == 1 )) || fail 'Phone did not come back. Check the cable and run Phone again.'
    fi
  done
fi

# No cable: reconnect over Wi-Fi
# A phone adb already holds over Wi-Fi wins (e.g. connected by the app or an earlier run)
targets=()
LIVE=$(get_devices | awk '$2 == "device" && $1 ~ /:[0-9]+$/ {print $1; exit}')
[[ -n $LIVE ]] && targets+=$LIVE
[[ -n $PHONE_IP ]] && targets+=("${PHONE_IP}:$PORT")
for known in $(get_known_ips); do
  targets+=("${known}:$PORT")
done
for m in $(find_mdns); do
  targets+=$m
done

(( ${#targets} )) || fail 'No USB phone, no remembered Wi-Fi IP, and nothing discovered on the network. Plug the phone in once and run this again.'

targets=("${(@u)targets}")
connect_first $targets || fail "Could not reach any address: ${targets[*]}. If the phone restarted, wireless mode is off: plug in USB once and run this again."
TARGET=$REPLY_TARGET
info "Connected to $TARGET."

adb -s $TARGET shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1

info 'Mirroring over Wi-Fi. Close the window to stop.'
# Less data per frame so a weak network drops fewer frames; watchdog reconnects on a drop
attempt=0
final=0
while true; do
  scrcpy -s $TARGET --stay-awake --video-bit-rate=3M --max-size=1024 "${COMMON[@]}"
  code=$?
  [[ $code -eq 0 ]] && break

  attempt=$((attempt + 1))
  if (( attempt > MAX_RETRIES )); then
    info "Wi-Fi reconnect failed after $MAX_RETRIES attempts."
    final=$code
    break
  fi
  info "Mirror dropped (exit $code). Reconnecting ... [$attempt/$MAX_RETRIES]"
  sleep $RETRY_DELAY

  # Drop the stale transport, then retry the last address, then every other remembered one
  adb disconnect "$TARGET" >/dev/null 2>&1
  candidates=($TARGET ${targets:|TARGET})
  reconnected=''
  if connect_first $candidates; then
    TARGET=$REPLY_TARGET
    reconnected=1
  else
    fresh=($(find_mdns))
    if (( ${#fresh} )) && connect_first $fresh; then
      TARGET=$REPLY_TARGET
      reconnected=1
    fi
  fi
  [[ -n $reconnected ]] && attempt=0   # got a fresh session: reset the retry budget
done

adb disconnect "$TARGET" >/dev/null 2>&1
exit $final
