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

exec /usr/bin/bwrap \
    --die-with-parent \
    --unshare-all \
    --ro-bind /usr /usr \
    --ro-bind /bin /bin \
    --ro-bind /sbin /sbin \
    --ro-bind /lib /lib \
    --ro-bind /lib64 /lib64 \
    --ro-bind /etc /etc \
    --ro-bind /dev /dev \
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
