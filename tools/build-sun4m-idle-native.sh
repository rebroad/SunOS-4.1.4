#!/bin/sh
set -eu

# Build the same SUN4M_IDLE kernel with the historical SunOS tools inside a
# guest.  Keep all generated files and logs under /home; /usr is deliberately
# small on the test disk.
root=${1:-/home/rebroad/sunos414}
config=${2:-/home/rebroad/SUN4M_IDLE.conf}
logroot=${3:-/home/rebroad/sunos414-native-build}

mkdir -p "$logroot"

"$root/tools/apply-qemu-idle-kernel-patch-native.sh" "$root" \
    >"$logroot/patch.log" 2>&1

cp "$config" "$root/sys/sun4m/conf/SUN4M_IDLE"
cd "$root/sys/sun4m/conf"
/etc/config -n SUN4M_IDLE >"$logroot/config.log" 2>&1

cd "$root/sys/boot/lib/sun4m"
make clean >"$logroot/prom-clean.log" 2>&1 || true
make >"$logroot/prom-build.log" 2>&1

cd "$root/sys/sun4m/SUN4M_IDLE"
make clean >"$logroot/kernel-clean.log" 2>&1 || true

# The throwaway SS-5 disk has no floppy, tape, or removable SCSI devices.
sed 's/fd_asm\.o //g; s/sr_conf\.o //g; s/st_conf\.o //g; s/st\.o //g' \
    Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# Keep the idle instructions and diagnostics enabled in this native build.
sed 's/^IDENT=/IDENT=-DQEMU_IDLE_POWERDOWN -DQEMU_KERNEL_DIAGNOSTICS /' \
    Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# SunOS cc emits #line directives for -E unless -P is supplied; the historical
# host-generator recipes feed that output back to cc, which otherwise rejects
# the directives as source characters.  Keep this compatibility change in the
# native workflow rather than the shared source tree.
sed 's/\${CC} -E /\${CC} -E -P /g' Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

if ! make depend >"$logroot/kernel-depend.log" 2>&1; then
    echo "Native SunOS dependency generation failed; see $logroot/kernel-depend.log" >&2
    exit 1
fi
if ! make >"$logroot/kernel-build.log" 2>&1; then
    echo "Native SunOS kernel build failed; see $logroot/kernel-build.log" >&2
    exit 1
fi
test -s vmunix_small || {
    echo "Native SunOS kernel build produced no vmunix_small" >&2
    exit 1
}

echo "Native SunOS build succeeded"
ls -l vmunix_small
echo "Logs: $logroot"
