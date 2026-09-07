# Revert jr-install.sh. Each touched path is removed or restored to stock.
# Not removed: v4l2-relayd, v4l2loopback-dkms and linux-headers from layer 0.
set -euo pipefail
[ "$EUID" -ne 0 ] || { echo "Run as regular user; sudo is used where needed."; exit 1; }

echo "== Remove DKMS package (modules auto-removed from all kernels + tuning yaml) =="
sudo pacman -Rns --noconfirm imx471-dkms-git 2>/dev/null || echo "(imx471-dkms-git not installed)"

echo "== Remove libcamera/PipeWire packages (kept if something else needs them) =="
sudo pacman -Rns --noconfirm gst-plugin-libcamera pipewire-libcamera libcamera-tools libcamera 2>/dev/null \
  || echo "(libcamera packages kept — dependency of another package)"

echo "== Remove pacman NoUpgrade entry for the tuning yaml =="
sudo sed -i '\|^NoUpgrade = usr/share/libcamera/ipa/simple/imx471.yaml$|d' /etc/pacman.conf

echo "== Restore udev / WirePlumber / relayd stock behavior =="
sudo rm -f /etc/udev/rules.d/71-ipu7-hide-isys.rules
sudo rm -f /etc/wireplumber/wireplumber.conf.d/wireplumber-enable-libcamera.conf
if [ -f /etc/v4l2-relayd.d/ipu7.conf.stock ]; then
  sudo mv /etc/v4l2-relayd.d/ipu7.conf.stock /etc/v4l2-relayd.d/ipu7.conf
fi
sudo rm -f /etc/systemd/system/v4l2-relayd@.service.d/98-sync.conf \
           /etc/systemd/system/v4l2-relayd@.service.d/99-dmabuf.conf
sudo rmdir /etc/systemd/system/v4l2-relayd@.service.d 2>/dev/null || true
sudo rm -f /etc/systemd/system/v4l2-relayd@ipu7.service.d/97-libcamera-pipelines.conf
sudo rmdir /etc/systemd/system/v4l2-relayd@ipu7.service.d 2>/dev/null || true
sudo systemctl disable --now v4l2-relayd.service 2>/dev/null || true
sudo rm -f /etc/modprobe.d/v4l2loopback-ipu7.conf
sudo systemctl daemon-reload

echo
echo ">>> Reverted. REBOOT to unload the modules and return to the stock stack."
echo ">>> Verify: 'dkms status' shows no imx471; 'modinfo imx471' fails."
