#!/bin/sh
set -eu

# Build the same SUN4M_IDLE kernel with the historical SunOS tools inside a
# guest.  Keep all generated files and logs under /home; /usr is deliberately
# small on the test disk.
root=${1:-/home/rebroad/sunos414}
config=${2:-/home/rebroad/SUN4M_IDLE.conf}
logroot=${3:-/home/rebroad/sunos414-native-build}
apply_idle_patch=${SUNOS_NATIVE_IDLE_PATCH:-yes}

mkdir -p "$logroot"

if test "$apply_idle_patch" = yes; then
    "$root/tools/apply-qemu-idle-kernel-patch-native.sh" "$root" \
        >"$logroot/patch.log" 2>&1
else
    echo "Skipped QEMU idle kernel patch (SUNOS_NATIVE_IDLE_PATCH=$apply_idle_patch)" \
        >"$logroot/patch.log"
fi

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

if test "$apply_idle_patch" = yes; then
    # Keep the idle instructions and diagnostics enabled in this native build.
    sed 's/^IDENT=/IDENT=-DQEMU_IDLE_POWERDOWN -DQEMU_KERNEL_DIAGNOSTICS /' \
        Makefile >Makefile.native-tmp
    mv Makefile.native-tmp Makefile
fi

# SunOS cc emits #line directives for -E unless -P is supplied; the historical
# host-generator recipes feed that output back to cc, which otherwise rejects
# the directives as source characters.  Keep this compatibility change in the
# native workflow rather than the shared source tree.
sed 's/\${CC} -E /\${CC} -E -P /g' Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# config also hard-codes the generator compile recipe as plain `cc`, bypassing
# HOSTCC.  Rewrite only those generated host-generator recipes.
sed 's/^        cc \${COPTS}/        \${HOSTCC} \${COPTS}/' \
    Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# Some SunOS config versions omit these source Makefile variables from the
# generated kernel Makefile.  Without them, make falls back to a plain host
# cc for the SPARC generator and links it as if it needed main().
cat >>Makefile <<'EOF'
HOSTCC=${CC}
HOSTRUN=./a.out
EOF

make depend >"$logroot/kernel-depend.log" 2>&1
status=$?
if test "$status" -ne 0; then
    echo "Native SunOS dependency generation failed; see $logroot/kernel-depend.log" >&2
    exit 1
fi
make >"$logroot/kernel-build.log" 2>&1
status=$?
if test "$status" -ne 0; then
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
