# ThinkPad X1 Carbon Gen 14 — Arch Linux + Hyprland

Fixes for the hardware that does not work out of the box on this laptop, with
the reasoning for each one. Written while making this machine my daily driver.

**Tested on:** ThinkPad X1 Carbon Gen 14, machine type 21V7, Core Ultra 5 335
(Panther Lake), BIOS 1.14, Arch Linux, kernel 7.2.3, Hyprland 0.56, `xe` driver.
Other CPU SKUs and panels in this generation are likely close but untested.

## Quick start

```sh
# 1. Packages. The lists are commented; strip the comments to pass them on.
sudo pacman -S --needed $(sed 's/#.*//' packages.pacman)
yay -S --needed --removemake --cleanafter --sudoloop \
    --answerdiff None --answerclean None --answeredit None $(sed 's/#.*//' packages.aur)

# 2. The fixes.
./install.sh --list        # what each component installs, and where
./install.sh --dry-run     # print the commands, change nothing
./install.sh               # touchpad, lid, fingerprint, camera

# 3. Type-C. A DKMS package: built, not copied.
(cd typec-ucsi && makepkg -si)
```

`install.sh` installs no packages, thus step 1 is not optional. The camera
component skips itself if its packages are absent.

## What is broken, and what fixes it

| Symptom | Cause | Fix |
|---|---|---|
| Type-C dead for the whole session — no charging, no display — on about half of boots | `typec_ucsi` PPM init fails and the driver does not retry | `typec-ucsi/` |
| Camera invisible; no `/dev/video*` that works | IPU7 + imx471 need a sensor module, libcamera config and tuning. Interim, until kernel 7.3 | `camera/` |
| Pointer drifts a few tenths of a mm when a finger lifts | the panel reports fuzz 0, thus libinput has no hysteresis | `touchpad/61-touchpad-fuzz.hwdb` |
| …still drifts a little | the panel reports a position change at pressure 0, before it reports the touch as up | `touchpad/local-overrides.quirks` |
| Pointer accelerates unlike any other OS | libinput's default profile | `touchpad/input-host.lua` |
| Fingerprint reader dead after resume | fprintd holds a stale device handle | `fingerprint/25-fprintd-stabilize` |
| Password refused after two fingerprint unlocks | hyprlock races PAM against fprintd; the loser is recorded as a failure | `fingerprint/faillock.conf` |
| No fingerprint for `sudo` or polkit | not wired by default | `fingerprint/fingerprint-pam`, `fingerprint/pam.d-polkit-1` |
| External display never appears after a suspend or an unplug | a compositor bug leaves the CRTC enabled, which pins the Type-C port | `display/` — no fix, a recovery |

## Not specific to this model

`fingerprint/` and `lid/` work on any ThinkPad with a fingerprint reader and a
lid. Only `touchpad/`, `typec-ucsi/`, `camera/` and `display/` are tied to this
model's panel, PD controller and camera.

## The touchpad numbers do not transfer

`input-host.lua` holds an acceleration curve and a scroll curve; the hwdb file
holds a fuzz value; the quirks file holds a pressure range. Each was measured on
this panel with `evtest` and then tuned by feel. A different panel reports
different deltas at a different resolution, thus the same numbers give a
different result. **Take the method, measure your own numbers.** Each file
records how its values were found.

## Upstream bugs

Each fix here exists because of a bug somewhere else. They are named in the
files, with what breaks without the workaround and how to tell the bug is fixed:

- `hyprwm/hyprlock#531`, `#577` — fingerprint not re-armed after a suspend
- `hyprwm/hyprlock#258` — fingerprint unlock counts as a failed password
- `hyprwm/aquamarine#386` — the CRTC of a removed connector is never disabled
- kernel `typec_ucsi` — no retry when PPM init fails. My patch, acked, not yet merged:
  https://lore.kernel.org/linux-usb/20260824173536.2395830-1-jacob@riff.dk/

## Licence

MIT, except `typec-ucsi/`, which is GPL-2.0 because it is derived from the Linux
kernel. See `NOTICE` for attribution.
