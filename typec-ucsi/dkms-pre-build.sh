# DKMS PRE_BUILD for riffos-ucsi-retry.
#   dkms-pre-build.sh <kernelver>
# Fetches the ucsi driver sources for <kernelver> from kernel.org, applies the
# retry patch, and copies the module Makefile in place. DKMS then runs `make`.
# This runs in the DKMS build directory, a copy of /usr/src/riffos-ucsi-retry-<version>/.
# CAUTION: <kernelver> is the kernel being built for, not the running one.
# Do not use `uname -r`.
set -euo pipefail

KVER="${1:?usage: dkms-pre-build.sh <kernelver>}"
KBASE=${KVER%%-*}

# kernel.org tags: 7.2.0 -> v7.2, 7.2.2 -> v7.2.2.
TAG="v${KBASE%.0}"

BASE="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/usb/typec/ucsi"

echo "riffos-ucsi-retry: fetching ucsi sources for $TAG (kernel $KVER)"

# Each file the module links. module.Makefile builds the full typec_ucsi module.
for f in ucsi.c ucsi.h debugfs.c trace.c trace.h psy.c displayport.c thunderbolt.c; do
    curl -sf --max-time 60 -o "$f" "$BASE/$f?h=$TAG" || {
        echo "riffos-ucsi-retry: FETCH FAILED for $f at $TAG" >&2
        echo "riffos-ucsi-retry: no network, or kernel.org has no such tag." >&2
        echo "riffos-ucsi-retry: the module will be ABSENT for $KVER, which means" >&2
        echo "riffos-ucsi-retry: the stock driver — Type-C dies on ~half of boots." >&2
        echo "riffos-ucsi-retry: re-run with:  sudo dkms autoinstall -k $KVER" >&2
        exit 1
    }
done

# If this kernel already has the retry logic, this package is obsolete. Fail,
# do not skip: a skip leaves DKMS reporting success with no module. With
# updates/ empty, the stock driver, which has the fix, loads.
if grep -q 'PPM init succeeded after\|ret == -ENODEV || ret == -EINVAL' ucsi.c; then
    echo "riffos-ucsi-retry: kernel $KBASE ALREADY HAS THE RETRY FIX UPSTREAM." >&2
    echo "riffos-ucsi-retry: RETIRE THIS PACKAGE — it is no longer needed:" >&2
    echo "riffos-ucsi-retry:   sudo pacman -R riffos-ucsi-retry-dkms" >&2
    echo "riffos-ucsi-retry:   then delete hardware/x1c-gen14/typec-ucsi/, its setup.sh block," >&2
    echo "riffos-ucsi-retry:   and WORKAROUNDS.md #9" >&2
    echo "riffos-ucsi-retry: the stock driver now carries the fix, so nothing is lost." >&2
    exit 1
fi

# Older kernels name the workqueue system_long_wq. Adapt the patch to this kernel.
cp rfc-retry.patch retry.patch
if grep -q 'system_long_wq' ucsi.c; then
    echo "riffos-ucsi-retry: kernel uses system_long_wq; adapting patch"
    sed -i 's/system_dfl_long_wq/system_long_wq/g' retry.patch
fi

echo "riffos-ucsi-retry: applying retry patch"
patch -p5 --fuzz=3 < retry.patch

cp module.Makefile Makefile
echo "riffos-ucsi-retry: sources ready for $KVER"
