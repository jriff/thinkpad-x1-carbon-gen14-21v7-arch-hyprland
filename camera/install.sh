# Install the X1 Carbon Gen 14 camera stack. Layers, per ocewers' README:
# 1 kernel modules, 2 libcamera/PipeWire, 3 v4l2-relayd, 4 tuning.
# Layers 1 and 4 come from AUR imx471-dkms-git; DKMS rebuilds on kernel updates.
# Layers 2 and 3 are /etc overrides. No package-owned file is modified.
# Revert: jr-revert.sh
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$EUID" -ne 0 ] || { echo "Run as regular user (yay refuses root); sudo is used where needed."; exit 1; }

# Layer 0: prerequisites. linux-headers, because imx471-dkms-git declares only
# dkms and DKMS cannot compile without headers. v4l2-relayd, because layers 2
# and 3 configure it. It is AUR and pulls in v4l2loopback-dkms.
echo "== Layer 0: prerequisites (headers for DKMS, the relayd this script configures) =="
sudo pacman -S --needed --noconfirm linux-headers dkms
yay -S --needed --noconfirm --removemake --cleanafter --sudoloop \
  --answerdiff None --answerclean None --answeredit None v4l2-relayd

# The kernel's IPU7 support is mainline since 7.1. The imx471 sensor driver is
# not, thus this package is still required. Re-check on new kernels.
echo "== Layer 1+4: imx471-dkms-git (imx471 sensor module, tuning yaml) =="
yay -S --needed imx471-dkms-git

echo "== Layer 2: libcamera/PipeWire packages =="
sudo pacman -S --needed --noconfirm libcamera libcamera-tools pipewire-libcamera gst-plugin-libcamera

echo "== Layer 2: unblock ISYS nodes + enable WirePlumber libcamera monitor =="
sudo touch /etc/udev/rules.d/71-ipu7-hide-isys.rules
sudo mkdir -p /etc/wireplumber/wireplumber.conf.d
sudo cp "$REPO/configs/wireplumber-enable-libcamera.conf" /etc/wireplumber/wireplumber.conf.d/

echo "== Layer 3: relayd fed from libcamera instead of icamerasrc =="
sudo cp -n /etc/v4l2-relayd.d/ipu7.conf /etc/v4l2-relayd.d/ipu7.conf.stock 2>/dev/null || true
sudo cp "$REPO/configs/ipu7.conf" /etc/v4l2-relayd.d/ipu7.conf
sudo mkdir -p /etc/systemd/system/v4l2-relayd@.service.d
sudo cp "$REPO/configs/98-sync.conf" "$REPO/configs/99-dmabuf.conf" /etc/systemd/system/v4l2-relayd@.service.d/
# Limit libcamera to the internal sensor, thus a USB webcam is never selected.
sudo install -Dm644 "$REPO/configs/97-libcamera-pipelines.conf" \
  /etc/systemd/system/v4l2-relayd@ipu7.service.d/97-libcamera-pipelines.conf
sudo systemctl daemon-reload

# Two pieces Omarchy's intel-ipu7-camera package provided: the loopback module
# options, and activation of v4l2-relayd.service, which nothing else enables.
echo "== Layer 3: loopback options + relayd activation =="
sudo install -Dm644 "$REPO/configs/v4l2loopback.conf" /etc/modprobe.d/v4l2loopback-ipu7.conf
sudo systemctl enable v4l2-relayd.service
# If v4l2loopback is already loaded without the label, reload it. modprobe -r
# fails if something holds the device.
if ! grep -qsx "Hardware ISP Camera" /sys/devices/virtual/video4linux/*/name; then
  sudo systemctl stop v4l2-relayd.service
  sudo modprobe -r v4l2loopback
  sudo modprobe v4l2loopback
fi
sudo systemctl restart v4l2-relayd.service

echo "== Layer 4: ocewers tuning (this SKU) over the package's X9-derived yaml =="
# The packaged yaml renders pink on this unit; ocewers' calibration is for this
# SKU. NoUpgrade keeps package upgrades from restoring it (pacman writes a .pacnew).
sudo cp "$REPO/tuning/imx471.yaml" /usr/share/libcamera/ipa/simple/imx471.yaml
grep -q '^NoUpgrade = usr/share/libcamera/ipa/simple/imx471.yaml' /etc/pacman.conf \
  || sudo sed -i '/^\[options\]/a NoUpgrade = usr/share/libcamera/ipa/simple/imx471.yaml' /etc/pacman.conf

echo
echo ">>> All layers installed. The relay is up now; REBOOT to prove the boot path, then verify bottom-up:"
echo ">>>   systemctl is-active v4l2-relayd@ipu7        # active"
echo ">>>   cat /sys/devices/virtual/video4linux/video50/name   # Hardware ISP Camera"
echo ">>>   journalctl -k -b | grep -E 'Found supported sensor|imx471'"
echo ">>>   cam --list"
echo ">>>   v4l2-ctl -d /dev/video50 --stream-mmap --stream-count=90"
echo ">>> (Do NOT test with gst-launch v4l2src — known-bad loopback client.)"
