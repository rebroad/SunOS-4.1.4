#!/bin/bash
set -euo pipefail

# Recreate and build the QEMU/SunOS idle-test kernel in the external build
# tree.  Source files stay in this checkout; generated files stay in .build.
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${SUNOS_BUILD_ROOT:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build}

if git -C "$build_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # The external tree is disposable build state.  Clear tracked workflow
    # patches and generated files before synchronizing the authoritative
    # source tree, so an earlier interrupted build cannot poison this one.
    git -C "$build_root" restore --worktree --staged -- .
    git -C "$build_root" clean -fdx >/dev/null
fi
cpto --no-lngit --update-existing "$source_root" "$build_root"

exec "$source_root/tools/build-in-bwrap.sh" -- /bin/bash -lc '
set -euo pipefail
/src/tools/apply-qemu-idle-kernel-patch.sh /build
/src/tools/apply-qemu-idle-kernel-patch.sh /build \
    /src/tools/patches/host-compiler-compat.patch
/src/tools/build-config-host.sh >/build/config-host.log 2>&1
/src/tools/generate-sun4m-config.sh SUN4M_IDLE GENERIC_SMALL \
    --without=HSFS \
    >/build/config-generate.log 2>&1
sed -i -E \
    "/^(device-driver|pseudo-device) (bwtwo|cgthree|cgsix|cgtwelve|gt|tcx|audioamd|dbri|audiocs|win256|dtop4|ms|kb|fd)( |$)/d" \
    /build/sys/sun4m/conf/SUN4M_IDLE
sed -i -E \
    "/^(disk|tape) (sr|st)[0-9]+( |$)/d" \
    /build/sys/sun4m/conf/SUN4M_IDLE
cd /build/sys/sun4m/conf
/build/usr.etc/config/config -n SUN4M_IDLE >/build/config-run.log 2>&1

# The kernel makefile links the standalone PROM library but does not build it.
cd /build/sys/boot/lib/sun4m
if ! (
    rm -f *.o ../../../sun4m/libprom.a
    for prom_src in ../promlib/prom_*.c; do
        prom_obj=${prom_src##*/}
        prom_obj=${prom_obj%.c}.o
        sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -m32 -mno-v8plus \
            -mcpu=v8 -fno-pie -fleading-underscore -Dsun -Dsun4m \
            -Dprintf=prom_printf \
            -Dputchar=prom_putchar -DSTANDALONE \
            -I.. -I../.. -I../../../sun4m -I../../../ -I../promlib \
            -c "$prom_src" -o "$prom_obj" || exit 1
    done
    sparc-linux-gnu-ar rcs ../../../sun4m/libprom.a *.o
    sparc-linux-gnu-ranlib ../../../sun4m/libprom.a
) >/build/promlib-build.log 2>&1; then
    echo "PROM library build failed; relevant diagnostics:"
    rg -n "error:|fatal error:|make:" /build/promlib-build.log | tail -40 || true
    echo "Last PROM library output:"
    tail -40 /build/promlib-build.log
    exit 1
fi

cd /build/sys/sun4m/SUN4M_IDLE

# Always rebuild every kernel object after synchronizing the source tree.
# The historical make dependencies do not reliably notice source changes
# copied into the external build tree, which can otherwise produce a
# successful but stale vmunix_small.
make clean >/build/kernel-clean.log 2>&1

# The VM has one SCSI hard disk and no floppy, optical, or tape device.
sed -i -E "s/(fd_asm|sr|st_conf|st)\\.(o|L) //g" Makefile

# The Sun linker accepted -p here; GNU ld rejects it.  -N retains the required
# OMAGIC/non-page-aligned link mode for this kernel.
sed -i "s/ -p / /" Makefile
sed -i "s/-T F0004000/-Ttext 0xF0004000/" Makefile
sed -i "/@symorder /d" Makefile

if ! make -j1 all \
    CC="sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -fcommon -m32 -mno-v8plus -mcpu=v8 -fno-pie -fleading-underscore -Dsparc -Dsun -Uunix ${SUNOS_IDLE_DEFINE:--DQEMU_IDLE_POWERDOWN} -DQEMU_KERNEL_DIAGNOSTICS -Wno-endif-labels -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type ${SUNOS_EXTRA_CFLAGS:-}" \
    HOSTCC="sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -fcommon -m32 -mno-v8plus -mcpu=v8 -fno-pie -Dsparc -Dsun -Uunix -Wno-endif-labels -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type" \
    HOSTRUN="QEMU_LD_PREFIX=/build/sparc32root qemu-sparc32plus ./a.out" \
    AS=/src/tools/sparc-as-wrapper.sh \
    LD=sparc-linux-gnu-ld AR=sparc-linux-gnu-ar \
    >/build/kernel-build.log 2>&1; then
    echo "SunOS kernel build failed; relevant diagnostics:"
    rg -n "error:|fatal error:|make:" /build/kernel-build.log | tail -40 || true
    echo "Last build output:"
    tail -40 /build/kernel-build.log
    exit 1
fi

python3 /src/tools/elf-to-sparc-aout.py \
    /build/sys/sun4m/SUN4M_IDLE/vmunix_small \
    /build/sys/sun4m/SUN4M_IDLE/vmunix_small.aout
chmod 755 /build/sys/sun4m/SUN4M_IDLE/vmunix_small.aout

echo "SunOS kernel build succeeded:"
ls -lh /build/sys/sun4m/SUN4M_IDLE/vmunix_small
ls -lh /build/sys/sun4m/SUN4M_IDLE/vmunix_small.aout
echo "Full build log: /build/kernel-build.log"
'
