#!/bin/bash
set -euo pipefail

# Recreate and build the QEMU/SunOS idle-test kernel in the external build
# tree.  Source files stay in this checkout; generated files stay in .build.
source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${SUNOS_BUILD_ROOT:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build}

cpto --no-lngit "$source_root" "$build_root" || true

exec "$source_root/tools/build-in-bwrap.sh" -- /bin/bash -lc '
set -euo pipefail
/src/tools/build-config-host.sh >/build/config-host.log 2>&1
/src/tools/generate-sun4m-config.sh SUN4M_IDLE GENERIC_SMALL \
    --without=HSFS --without=NFSCLIENT --without=NFSSERVER \
    >/build/config-generate.log 2>&1
sed -i -E \
    "/^(device-driver|pseudo-device) (bwtwo|cgthree|cgsix|cgtwelve|gt|tcx|audioamd|dbri|audiocs|win256|dtop4|ms|kb|fd)( |$)/d" \
    /build/sys/sun4m/conf/SUN4M_IDLE
cd /build/sys/sun4m/conf
/build/usr.etc/config/config -n SUN4M_IDLE >/build/config-run.log 2>&1

# The kernel makefile links the standalone PROM library but does not build it.
cd /build/sys/boot/lib/sun4m
if ! make -j1 libprom.a \
    CC="sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -m32 -mno-v8plus -mcpu=v8 -fno-pie -Dsparc -Dsun -Uunix -Wno-endif-labels -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type" \
    AS=/src/tools/sparc-as-wrapper.sh \
    AR=sparc-linux-gnu-ar LD=sparc-linux-gnu-ld \
    >/build/promlib-build.log 2>&1; then
    echo "PROM library build failed; relevant diagnostics:"
    rg -n "error:|fatal error:|make:" /build/promlib-build.log | tail -40 || true
    echo "Last PROM library output:"
    tail -40 /build/promlib-build.log
    exit 1
fi

cd /build/sys/sun4m/SUN4M_IDLE

# The historical configuration always lists these NFS lock-manager objects,
# even when both NFS options are disabled.
sed -i "s/klm_kprot.o klm_lockmgr.o //" Makefile

# The VM has one SCSI hard disk and no floppy, optical, or tape device.
sed -i -E "s/(fd_asm|sr|st_conf|st)\\.(o|L) //g" Makefile

if ! make -j1 all \
    CC="sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -m32 -mno-v8plus -mcpu=v8 -fno-pie -Dsparc -Dsun -Uunix -Wno-endif-labels -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type" \
    HOSTCC="sparc64-linux-gnu-gcc -std=gnu89 -fno-builtin -m32 -mno-v8plus -mcpu=v8 -fno-pie -Dsparc -Dsun -Uunix -Wno-endif-labels -Wno-implicit-int -Wno-implicit-function-declaration -Wno-return-type" \
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

echo "SunOS kernel build succeeded:"
ls -lh /build/sys/sun4m/SUN4M_IDLE/vmunix
echo "Full build log: /build/kernel-build.log"
'
