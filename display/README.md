# External display dead after a suspend or an unplug

Fixed in aquamarine 0.16.0. This file holds the recovery for older versions
and the evidence. No files here.

## Symptom

The external display on USB-C does not appear. `/sys/class/drm/card0-DP-1/status`
reads `disconnected` while the monitor is connected and powered. It starts after
a suspend or after an unplug, and it does not recover on its own.

## Fixed in

`hyprwm/aquamarine` 0.16.0 holds both parts of the fix:

| Part | Commit | What it does |
|---|---|---|
| 1 | `3c3292c1` (PR `#410`, in 0.15.1) | Commits the disable before the connector is marked disconnected |
| 2 | `082179bc` (in 0.16.0) | Clears a stale page-flip when the connector comes back |

On `xe`, 0.15.1 alone is not sufficient. After an s2idle resume, each commit is
rejected with `drm: Cannot commit when a page-flip is awaiting`.

Verified on this machine with aquamarine 0.16.0 and Hyprland 0.57.2: an
unplug, a replug and a suspend each recover with no manual step.

### What a fixed unplug logs

```text
drm: Disabled KMS output DP-1 before disconnect
drm: Cannot commit a disconnected output
drm: DP-1 is not connected, clearing stale crtc 270
```

The second line is harmless: the disable is already committed. The first line
exists only in the fixed code.

NOTE: Two `Cannot commit when a page-flip is awaiting` lines at the first
modeset after login are normal on 0.16.0. The outputs come up after them.

## Recovery on aquamarine 0.15.x and older

Do the three steps in this order:

1. Unplug the display, then plug it in again.
2. `sudo sh -c 'chvt 2; sleep 3; chvt 1'`
3. `hyprctl reload`

A VT switch makes fbdev commit every CRTC, thus the connector-less pipe is
disabled and the port mode is read again.

NOTE: A VT switch alone repairs the kernel and leaves the screen black, because
aquamarine drops the restore.

## Cause

`hyprwm/aquamarine#386`, a 0.15.0 regression. When a connector goes away its
CRTC stays enabled in the kernel: Hyprland sends the disable, aquamarine refuses
it, and the log shows `drm: Cannot commit a disconnected output`. On a Type-C
DP-alt port the enabled CRTC holds the link, thus the port stays in `tbt-alt`,
AUX gives `-ENXIO`, and the connector never reports connected again.

## What does NOT work

Measured, each in the failed state: writing `detect` to the connector's sysfs
`status`, once and polled every 2 s for 60 s; a DPMS off and on cycle; the
compositor's renderer reload; unplugging and plugging in the monitor.

## Do not trust the Type-C sysfs here

`/sys/class/typec/*/displayport/{hpd,configuration,pin_assignment}` read the
same when the link works and when it does not (`hpd=0`, `[USB] sink`). Use
`/sys/class/drm/card0-DP-1/status`.

## Reported

Added to `#386` on 2026-09-07 as a second hardware path: Panther Lake, the `xe`
driver, DP-alt with no dock and no MST, and a different downstream failure from
the original reporter's, who has MST and gets `EINVAL` modesets.

Captured with `drm.debug=0x116` on the kernel command line, which is how the
`Cannot commit a disconnected output` line and the AUX `-ENXIO` were tied to the
same commit.
