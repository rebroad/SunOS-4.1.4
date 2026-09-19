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

# The generated makefile's historical `syssrc` prerequisite can regenerate
# sources from the old SCCS material.  The checkout/archive is authoritative;
# skip that regeneration so native compilation uses exactly this source.
sed 's/ syssrc / /' Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# SunOS cc emits #line directives for -E, and its -P option is not the GCC
# equivalent of suppressing those directives.  Strip only those preprocessor
# lines between the generated source and the historical host-generator cc.
sed 's|> ./a.out.c$|> ./a.out.c; sed "/^#/d" ./a.out.c > ./a.out.native-tmp; mv ./a.out.native-tmp ./a.out.c|' \
    Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

# config also hard-codes the generator compile recipe as plain `cc`, bypassing
# the SPARC flags.  Rewrite only the exact generated host-generator token;
# literal flags avoid old make's unreliable late variable expansion here.
sed 's/cc \${COPTS}/cc -sparc -Usun4 -Dsun4m \${COPTS}/g' \
    Makefile >Makefile.native-tmp
mv Makefile.native-tmp Makefile

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
