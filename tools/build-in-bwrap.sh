#!/bin/bash
set -euo pipefail

# Run host-side SunOS builds with the source read-only and the external build
# tree writable.  The wrapper itself is intentionally small: callers supply
# the build command after `--`, so the command remains visible and auditable.

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
build_root=${SUNOS_BUILD_ROOT:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build}
if [[ ! -d "$build_root" ]]; then
    printf 'build tree does not exist: %s\n' "$build_root" >&2
    exit 2
fi

if [[ ${1:-} == -- ]]; then
    shift
fi
if (($# == 0)); then
    set -- /bin/bash
fi

# qemu-sparc32plus needs the 32-bit SPARC loader, while the Debian cross
# package keeps it under the sparc64 sysroot.  This link is generated build
# state, not source content, and is recreated whenever the build tree is
# synchronized.
mkdir -p "$build_root/sparc32root"
if [[ ! -e "$build_root/sparc32root/lib" ]]; then
    ln -s /usr/sparc64-linux-gnu/lib32 "$build_root/sparc32root/lib"
fi

exec /usr/bin/bwrap \
    --die-with-parent \
    --unshare-all \
    --ro-bind /usr /usr \
    --ro-bind /bin /bin \
    --ro-bind /sbin /sbin \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /etc /etc \
    --dev /dev \
    --proc /proc \
    --ro-bind /sys /sys \
    --ro-bind "$source_root" /src \
    --bind "$build_root" /build \
    --tmpfs /tmp \
    --setenv HOME /tmp \
    --setenv SOURCE_ROOT /src \
    --setenv BUILD_ROOT /build \
    --chdir /build \
    -- "$@"
