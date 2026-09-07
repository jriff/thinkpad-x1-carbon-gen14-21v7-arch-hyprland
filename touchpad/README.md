# Touchpad

Three files, three separate problems:

| File | Problem |
|---|---|
| `61-touchpad-fuzz.hwdb` | the pointer moves when a finger lifts — no hysteresis |
| `local-overrides.quirks` | it still moves a little — the panel reports a position at pressure 0 |
| `input-host.lua` | acceleration and scroll feel wrong at every speed |

Every number in them was measured on the Goodix `27C6:0F95` panel in this
machine. **They do not transfer.** A different panel reports different deltas
at a different resolution, thus the same values give a different result. This
file is the method for measuring your own. Each file explains its own values.

## Tools

```sh
sudo pacman -S --needed evtest libinput-tools
```

`evtest` reads the raw device. `libinput-tools` carries the `libinput` command,
which is **not** in the `libinput` package — the library ships without it.

## Find the device

```sh
grep -l Touchpad /sys/class/input/event*/device/name    # /sys/class/input/event9/device/name
sudo evtest /dev/input/event9
```

`/dev/input/event*` is `root:input`, thus this needs `sudo` unless you are in
the `input` group. Match on a name, never on a fixed number: the numbering
changes when devices come and go.

## Read what the panel reports

`evtest` prints an axis table before the events:

```
Event code 53 (ABS_MT_POSITION_X)
  Min 0  Max 3599  Fuzz 0  Flat 0  Resolution 28
```

Two fields matter. **Fuzz** is what libinput sizes its hysteresis from, thus a
fuzz of 0 means every jitter reaches the pointer. **Resolution** is units per
millimetre, which converts a raw number into a distance you can feel.

## 1. Hysteresis — the fuzz value

Press and lift 15 or so times and watch the last position events before
`BTN_TOUCH 0`. Note the largest jump. That is the drift, in device units;
divide by the resolution for millimetres.

Pick a fuzz that covers it and write it into a hwdb file. The format is
`EVDEV_ABS_<hex code>=<min>:<max>:<resolution>:<fuzz>`; the empty fields keep
the kernel values. Set all four axes — `00`/`01` are `ABS_X`/`ABS_Y`, `35`/`36`
are the multitouch pair — and match on the device name and the DMI product
version so the entry cannot follow the file onto another machine.

```sh
sudo install -Dm644 61-touchpad-fuzz.hwdb /etc/udev/hwdb.d/61-touchpad-fuzz.hwdb
sudo systemd-hwdb update
sudo udevadm trigger --action=remove /dev/input/event9
sudo udevadm trigger --action=add    /dev/input/event9
```

`systemd-hwdb update` writes the database and re-reads nothing. Without the
trigger the property appears on the next boot and not before. Trigger **that
one device**: a bare `udevadm trigger` cycles every input device, the keyboard
included.

Verify that the entry matched:

```sh
udevadm info /dev/input/event9 | grep EVDEV_ABS
# E: EVDEV_ABS_00=:::18
```

No output means the match line is wrong — usually the DMI string. Compare it
with `cat /sys/class/dmi/id/product_version`.

Too large a fuzz makes slow, precise movement feel sticky, thus raise it until
the drift stops and no further.

## 2. Pressure range — the remaining drift

If the pointer still shifts a little, watch the pressure on a lift:

```
ABS_MT_PRESSURE   12 -> 9 -> 3 -> 0
ABS_MT_POSITION_X          -> 1943      <- a move at pressure 0
BTN_TOUCH         -> 0
```

libinput still holds the contact at that point, thus that last move reaches the
pointer. `AttrPressureRange=<high>:<low>` releases the contact below `<low>`.

Measure two numbers: the peak pressure of your **lightest deliberate touch**,
and the decay on a lift. Put `high` below the lightest peak, or light touches
are ignored; put `low` inside the decay, so the contact ends before the move at
0. On this panel the lightest peak was 20 and the decay ran 12, 9, 3, 0 — thus
`10:6`.

```sh
sudo install -Dm644 local-overrides.quirks /etc/libinput/local-overrides.quirks
```

**CAUTION: a udev trigger is not enough here.** libinput parses the quirks files
once, when the compositor creates its libinput context. A change needs a new
session — log out and in.

Check for a vendor quirk before writing your own: this panel already has an
entry in `30-vendor-goodix.quirks` setting `AttrInputProp=+INPUT_PROP_PRESSUREPAD`.
A local section with the same `Match*` lines adds to that entry rather than
replacing it. With `libinput-tools` installed:

```sh
libinput quirks list /dev/input/event9
```

## 3. Acceleration and scroll

`accel_profile = "custom <step> <f@0> <f@1step> …"`. Each factor is the
acceleration at a multiple of `step`, thus the curve is a set of points, not a
formula. Keep `f@0` at 0 — anything else moves the pointer under a resting
finger. Flat at the low end buys precision; steep at the top lets a flick cross
the screen.

**Whenever `accel_profile` is custom, set `scroll_points` too.** Otherwise
two-finger scroll inherits the pointer curve, which climbs far higher than
scrolling wants, and a flick throws the page.

Tune by feel, one end at a time, and change one number per round: slow first
(precision), then the top (reach). It takes several sittings.

`input-host.lua` is Hyprland's Lua config format. The same two strings work in
`hyprland.conf` syntax, in a `device {}` block.
