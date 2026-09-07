# Camera

No working `/dev/video*` out of the box. The IPU7 ISP has been in the mainline
kernel since 7.1, but the `imx471` sensor behind it has not, and the userspace
above it needs configuring before anything can open the camera.

**This is an interim layer.** When `modinfo imx471` succeeds on a stock kernel,
delete all of it.

## Layers

Following [ocewers' work in `basecamp/omarchy#6000`](https://github.com/basecamp/omarchy/issues/6000),
which is where the configuration below comes from:

| | |
|---|---|
| 1 · kernel | the `imx471` sensor module — AUR `imx471-dkms-git`, rebuilt per kernel |
| 2 · libcamera / PipeWire | unblock the ISYS nodes, enable WirePlumber's libcamera monitor |
| 3 · v4l2-relayd | feed a `v4l2loopback` node from libcamera, so ordinary apps see a camera |
| 4 · tuning | the sensor tuning file, also from `imx471-dkms-git` |

Layers 1 and 4 are packages. Layers 2 and 3 are the files in `configs/`, all
installed as `/etc` overrides — **no package-owned file is modified**.

```sh
./install.sh      # needs the packages from ../packages.{pacman,aur} first
./revert.sh       # undo
```

`install.sh` deliberately installs no packages, thus there is one package list
and not two.

## Verify

The sensor module loads at boot, thus **test after a reboot**, not straight
after installing.

```sh
cam --list                                            # the sensor, via libcamera
systemctl is-active v4l2-relayd@ipu7                  # active
cat /sys/devices/virtual/video4linux/video50/name     # Hardware ISP Camera
v4l2-ctl -d /dev/video50 --stream-mmap --stream-count=90
```

The last one is the end-to-end test: 90 frames off the loopback node.

**Do not test with `gst-launch v4l2src`.** It is a known-bad loopback client —
it fails against a working camera and sends you looking for a fault that is not
there. Browsers and conferencing apps are fine.

## Traps

- **The IR sensor enumerates first.** Both internal sensors are on libcamera's
  `simple` pipeline, thus an unpinned `libcamerasrc` takes the IR one and you get
  a monochrome image or none. `ipu7.conf` pins the RGB sensor by name (LNK0);
  `97-libcamera-pipelines.conf` keeps USB webcams out but does **not** replace
  that pin.
- **The loopback needs its options.** Without `configs/v4l2loopback.conf` the
  module loads as "Dummy video device" on a random node, relayd cannot find its
  `CARD_LABEL`, and Chromium ignores a loopback that lacks `exclusive_caps=1`.
- **`v4l2-relayd.service` is enabled by nothing.** `install.sh` enables it.

## The IR camera

Not configured here. The `VD55G1` IR sensor works — it has no illuminator on
this machine, thus it is useless indoors, which is why it is not part of this
set. The work is at
[jriff/x1c14-ir-vd55g1](https://github.com/jriff/x1c14-ir-vd55g1).
