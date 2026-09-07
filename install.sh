#!/bin/bash
# Install the fixes in this directory.
#
#   ./install.sh                     each component
#   ./install.sh touchpad lid        the named components only
#   ./install.sh --list              what each component installs, and where
#   ./install.sh --dry-run           print the commands; change nothing
#
# The script is idempotent and asks no questions, thus a configuration manager
# can call it. It uses sudo for /etc and /usr, and no sudo for $HOME.
#
# NOT here: typec-ucsi. That component is a DKMS package, thus it is built, not
# copied: `cd typec-ucsi && makepkg -si`. See typec-ucsi/ and README.md.
# NOT here by default: camera. Run camera/install.sh; it needs the network.
set -uo pipefail
# Keep the path before the cd: $0 is relative to the OLD cwd.
SELF="$(readlink -f "$0")"
cd "$(dirname "$0")"

DRY=0
# ORDER MATTERS: lid before fingerprint. pam.d-polkit-1 gates on
# /usr/local/bin/hw-laptop-closed, thus that binary must exist first.
COMPONENTS=(touchpad lid fingerprint camera)

say() { printf '+ %s\n' "$*"; }
run() { say "$*"; [ "$DRY" = 1 ] && return 0; "$@" || { echo "install.sh: FAILED: $*" >&2; exit 1; }; }

list() {
  cat <<'LIST'
touchpad     this Goodix 27C6:0F95 panel only
  local-overrides.quirks  -> /etc/libinput/local-overrides.quirks
  61-touchpad-fuzz.hwdb   -> /etc/udev/hwdb.d/61-touchpad-fuzz.hwdb   (+ systemd-hwdb update)
  input-host.lua          -> ~/.config/hypr/input-host.lua            (symlink; Hyprland only)

fingerprint  any ThinkPad with a fingerprint reader, not only this model
  25-fprintd-stabilize    -> /usr/lib/systemd/system-sleep/25-fprintd-stabilize
  faillock.conf           -> /etc/security/faillock.conf
  fingerprint-pam  -> /usr/local/bin/fingerprint-pam
  pam.d-polkit-1          -> /etc/pam.d/polkit-1

lid          any ThinkPad
  hw-laptop-closed -> /usr/local/bin/hw-laptop-closed

camera       this model. Runs camera/install.sh, which writes /etc overrides for
             libcamera, v4l2-relayd and the loopback, then restarts the relay.
             Skipped when the packages are absent.

typec-ucsi   this model. Built, not copied: cd typec-ucsi && makepkg -si
packages     packages.pacman and packages.aur list what the above needs
LIST
}

touchpad() {
  run sudo install -Dm644 touchpad/local-overrides.quirks /etc/libinput/local-overrides.quirks
  run sudo install -Dm644 touchpad/61-touchpad-fuzz.hwdb  /etc/udev/hwdb.d/61-touchpad-fuzz.hwdb
  run sudo systemd-hwdb update
  # systemd-hwdb update writes the database. It does NOT re-read a device that
  # is already present, thus the fuzz is not live until the device is re-added.
  # CAUTION: Trigger THIS device only. A trigger over /sys/class/input/event*
  # removes and re-adds the keyboard too.
  local ev
  ev=$(grep -lE "GXTP.*Touchpad" /sys/class/input/event*/device/name 2>/dev/null | head -1)
  if [ -n "$ev" ]; then
    ev=${ev%/device/name}
    run sudo udevadm trigger --action=remove "$ev"
    sleep 1
    run sudo udevadm trigger --action=add "$ev"
  else
    say "note: no GXTP5420 touchpad found; the fuzz applies at the next boot"
  fi
  # CAUTION: local-overrides.quirks needs more than a trigger. libinput parses
  # the quirks files ONCE, when the compositor makes its libinput context, thus
  # the pressure range is live only after a new session.
  say "note: log out and in for local-overrides.quirks to take effect"
  # A link, not a copy: the file is then tuned in the repository and is live at
  # once. CAUTION: Hyprland only. input.lua must load it; see README.md.
  if [ -d "$HOME/.config/hypr" ]; then
    run ln -sfn "$PWD/touchpad/input-host.lua" "$HOME/.config/hypr/input-host.lua"
  else
    say "skip ~/.config/hypr/input-host.lua: no ~/.config/hypr"
  fi
}

fingerprint() {
  run sudo install -Dm755 fingerprint/25-fprintd-stabilize   /usr/lib/systemd/system-sleep/25-fprintd-stabilize
  run sudo install -Dm644 fingerprint/faillock.conf          /etc/security/faillock.conf
  run sudo install -Dm755 fingerprint/fingerprint-pam /usr/local/bin/fingerprint-pam
  run sudo install -Dm644 fingerprint/pam.d-polkit-1         /etc/pam.d/polkit-1
}

lid() { run sudo install -Dm755 lid/hw-laptop-closed /usr/local/bin/hw-laptop-closed; }

# A skip, not a failure: someone who wants only the touchpad fix should not have
# ./install.sh stop because a camera package is absent.
camera() {
  if [ ! -d /etc/v4l2-relayd.d ]; then
    say "skip camera: v4l2-relayd is not installed (see packages.aur)"
    return 0
  fi
  run ./camera/install.sh
}

want=()
for a in "$@"; do
  case "$a" in
    --list) list; exit 0 ;;
    --dry-run) DRY=1 ;;
    -h|--help) sed -n '2,14p' "$SELF"; exit 0 ;;
    -*) echo "install.sh: unknown option $a" >&2; exit 2 ;;
    *) want+=("$a") ;;
  esac
done
[ ${#want[@]} -eq 0 ] && want=("${COMPONENTS[@]}")

for c in "${want[@]}"; do
  case " ${COMPONENTS[*]} " in
    *" $c "*) say "--- $c"; "$c" ;;
    *) echo "install.sh: no such component: $c (try --list)" >&2; exit 2 ;;
  esac
done
echo "install.sh: done"
