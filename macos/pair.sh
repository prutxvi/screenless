#!/bin/zsh
# Guided pairing: connect a phone over Wi-Fi **without USB first** (Android 11+).
#   ./pair.sh                          guided flow (discovers the pairing service via mDNS)
#   ./pair.sh IP:PORT CODE             explicit pairing endpoint + 6-digit code
#
# How it works: while the phone shows its "Pair device with pairing code" dialog,
# it advertises _adb-tls-pairing._tcp on the network. The wizard waits for that
# announcement, pairs with your code, then connects to the phone's advertised
# connect service and saves it into the same device record `phone.sh` uses.
#
# Honesty note: you need the phone's screen (or voice control that can reach
# Developer options) to read the 6-digit code. A fully dead screen phone must
# be paired the USB way (docs/MACOS.md) — there is no cold wireless pairing
# without Android authorization, whoever claims otherwise.

# Run with a pristine zsh option set, so rc-file options can't alter behaviour
emulate -LR zsh

CONFIG_DIR="$HOME/.config/screenless"
DEVICE_DIR="$CONFIG_DIR/devices"

fail() { print -P "%F{red}[screenless-pair] $1%f"; exit 1 }
info() { print -P "%F{cyan}[screenless-pair] $1%f" }

command -v adb >/dev/null || fail "adb not found. Install with: brew install scrcpy (bundles adb)"

# ---------------------------------------------------------------------------
# Device bookkeeping — same format as phone.sh (<serial>.conf key=value files)
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

  local -A seen
  local out=()
  local keep=5
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

# ip:port pairs on a given mdns service line type
scan_mdns() {
  local kind="$1" out
  out=$(adb mdns services 2>/dev/null) || return 1
  printf '%s\n' "$out" | grep "_adb-${kind}\." | \
    grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}:[0-9]+' | sort -u
}

# old platform-tools (pre-31) has no adb pair
# (parse the "Version 37.x-" line of adb --version, NOT the "version 1.0.41" protocol line)
ADB_VER=$(adb --version 2>/dev/null | awk '/^Version /{split($2,a,"."); print a[1]; exit}')
[[ ${ADB_VER:-0} -ge 31 ]] || \
  fail "This adb is too old for wireless pairing (needs platform-tools 31+, which brew's scrcpy ships)."

if [[ $# -eq 2 ]]; then
  ENDPOINT=$1
  CODE=$2
else
  print -P "%F{cyan}== Guided wireless pairing (Android 11+) ==%f"
  print
  print "On the phone (its screen must be usable):"
  print "  1. Settings → Developer options → turn ON  Wireless debugging"
  print "  2. Tap PAIR DEVICE WITH PAIRING CODE and leave that screen open"
  print "(The 6-digit code and this dialog's port disappear when it closes, so"
  print " keep it open until pairing succeeds.)"
  print

  info "Searching for the phone's pairing announcement ... (leave the dialog open)"
  ENDPOINT=''
  for i in {1..30}; do
    endpoints=($(scan_mdns pairing))
    if (( ${#endpoints} )); then
      printf '  found:\n'
      for j in {1..${#endpoints}}; do printf '    [%d] %s\n' "$j" "${endpoints[$j]}"; done
      break
    fi
    sleep 2
    (( i % 5 == 0 )) && info "  nothing yet ($((i*2))s) ..."
  done
  if (( ${#endpoints} == 1 )); then
    ENDPOINT=${endpoints[1]}
  elif (( ${#endpoints} > 1 )); then
    print -nP "Choose [1] (or type your own ip:port, empty=first): "
    read -r pick
    if [[ -z $pick ]]; then
      ENDPOINT=${endpoints[1]}
    elif [[ $pick == *:* ]]; then
      ENDPOINT=$pick
    elif [[ $pick =~ '^[0-9]+$' ]]; then
      ENDPOINT=${endpoints[$pick]}
    else
      ENDPOINT=$pick
    fi
  fi

  print -nP "Pairing endpoint ${ENDPOINT:+[$ENDPOINT] }"
  [[ -n $ENDPOINT ]] || print -nP "(type ip:port as shown on the phone): "
  read -r typed
  [[ -z $typed ]] || ENDPOINT=$typed
  [[ $ENDPOINT == *:* ]] || fail "Endpoint must look like IP:PORT, e.g. 192.168.1.42:39089"

    print -nP "6-digit pairing code from the phone: "
  read -r CODE
  [[ $CODE =~ '^[0-9]{6}$' ]] || fail "The code is exactly 6 digits."

fi
if [[ ! $CODE =~ '^[0-9]{6}$' ]]; then fail "The code is exactly 6 digits."; fi

info "Pairing with $ENDPOINT ..."
OUT=$(adb pair "$ENDPOINT" "$CODE" 2>&1)
if [[ $OUT != *uccess* ]]; then
  fail "Pairing failed: $OUT — the code expires fast; reopen the pairing dialog and try again."
fi
info "$OUT."

# The phone now advertises its (different) connect endpoint
info "Finding the phone's connect service ..."
CONNECT_EP=$(scan_mdns tls-connect | head -n1)
if [[ -z $CONNECT_EP ]]; then
  print -nP "No connect service found via mDNS. Type the phone's connect address "
  print -nP "(shown in Developer options → Wireless debugging): "
  read -r CONNECT_EP
fi

adb connect "$CONNECT_EP" | grep -q 'connected to' || \
  fail "Could not connect to $CONNECT_EP. The phone may have closed wireless debugging."

serial=$(adb devices | awk '/\tdevice$/{print $1}' | grep "$CONNECT_EP" | head -n1)
[[ -n $serial ]] || serial=$CONNECT_EP
model=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n')
android=$(adb -s "$serial" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r\n')
save_record "$serial" "$model" "$android" "${CONNECT_EP%%:*}"

info "$model (Android $android) is saved and connected."
info "From now on just run phone.sh — it reconnects on its own."