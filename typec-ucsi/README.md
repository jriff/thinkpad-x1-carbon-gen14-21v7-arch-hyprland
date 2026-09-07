# Type-C dead for the session on about half of boots

No charging, no external display, no Type-C events at all — for the whole
session, until a reboot. Seen on BIOS 1.12 and 1.14, thus a firmware update is
not the fix.

## Do you have it?

```sh
journalctl -b -k | grep -i ucsi
```

A failing boot shows the init giving up, as `-ENODEV` (`GET_CAPABILITY`
completes but reports zero connectors) or `-EINVAL` (a standard command is
rejected, logged as `possible UCSI driver bug`). A healthy boot says nothing
interesting. Watch across several boots: here it was roughly half.

```sh
ls /sys/class/typec/          # empty on a failed boot, ports on a good one
```

## Cause

The PPM — the firmware behind the Type-C ports — is not ready to answer
commands correctly for a short window during boot. `ucsi_init_work()` requeues
only on `-EPROBE_DEFER`, thus a single bad answer in that window leaves UCSI
dead for the session. It is not a timeout: raising the sync command completion
wait does not change the rate.

Reloading the driver a few seconds later has succeeded on every attempt
observed, which is what suggests a retry is enough.

## Recovery, without the package

```sh
sudo modprobe -r ucsi_acpi && sudo modprobe ucsi_acpi
```

**CAUTION: only in the failed state.** Unloading the module while UCSI is
healthy froze this machine, repeatably. Check `/sys/class/typec/` is empty
first.

## The fix

`rfc-retry.patch` retries `-ENODEV` and `-EINVAL` the same way the driver
already retries the role switch wait, logs the retries at debug level, keeps the
loud report for exhausted retries, and notes when init only succeeded after
retrying. Across 8 consecutive boots with it, 5 hit the failure and all 5
recovered on the first retry; 0 of 8 ended with UCSI unusable, where about 5 of
8 would have without it.

Sent to linux-usb in August 2026 and acked, not yet merged:
https://lore.kernel.org/linux-usb/20260824173536.2395830-1-jacob@riff.dk/

Until it lands, this directory builds the stock `typec_ucsi` module with the
patch applied and installs it through DKMS, so it is rebuilt for every kernel:

```sh
makepkg -si
```

The build fetches the driver sources for the target kernel from kernel.org, thus
it needs the network. It adapts the patch to older kernels that still name the
workqueue `system_long_wq`.

## Verify

```sh
dkms status -m riffos-ucsi-retry     # installed, for each kernel
modinfo -n typec_ucsi                # a path under updates/, not kernel/
journalctl -b -k | grep -i ucsi      # after a boot that hit the race:
                                     # "PPM init succeeded after N attempts"
```

## Retiring it

When a kernel carries the retry logic, the DKMS `PRE_BUILD` step detects it and
**fails on purpose**, with `RETIRE THIS PACKAGE`. A build failure is the success
signal — it fails rather than skipping, because a skip would leave DKMS
reporting success with no module.

```sh
sudo pacman -R riffos-ucsi-retry-dkms
```

`updates/` empties and the stock driver, which now has the fix, loads.

## Licence

GPL-2.0. This directory is derived from the Linux kernel.
