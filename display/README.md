# External display dead after a suspend or an unplug

No files here. The fix is upstream; this is the recovery and the evidence.

## Symptom

The external display on USB-C does not appear. `/sys/class/drm/card0-DP-1/status`
reads `disconnected` while the monitor is connected and powered. It starts after
a suspend or after an unplug, and it does not recover on its own.

## Recovery

```sh
sudo sh -c 'chvt 2; sleep 3; chvt 1'
```

A VT switch makes fbdev commit every CRTC, thus the connector-less pipe is
disabled and the port mode is read again.

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

## Fixed when

Unplug the external display and plug it in again, and it appears with no VT
switch. Watch `hyprwm/aquamarine#386`. A fix has to let a disable commit through
for a connector that is already disconnected.

## Reported

Added to `#386` on 2026-09-07 as a second hardware path: Panther Lake, the `xe`
driver, DP-alt with no dock and no MST, and a different downstream failure from
the original reporter's, who has MST and gets `EINVAL` modesets.

Captured with `drm.debug=0x116` on the kernel command line, which is how the
`Cannot commit a disconnected output` line and the AUX `-ENXIO` were tied to the
same commit.
