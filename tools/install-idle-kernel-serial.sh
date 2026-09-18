#!/bin/bash
set -euo pipefail

# Install the freshly built test kernel into a running, throwaway SunOS VM.
# The serial line is deliberately paced: SunOS's tty input queue cannot safely
# absorb a complete uuencoded kernel at host speed.

source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
kernel=${SUNOS_IDLE_KERNEL:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE/vmunix_small}
serial_fifo=${SUNOS_SERIAL_INPUT_FIFO:-/home/rebroad/SunOS/sunos-serial-input}
remote_kernel=/home/rebroad/vmunix_idle
line_delay=${SUNOS_SERIAL_LINE_DELAY:-0.01}

if [[ ! -x "$kernel" ]]; then
    printf 'kernel not found: %s\n' "$kernel" >&2
    exit 2
fi
if [[ ! -p "$serial_fifo" ]]; then
    printf 'serial FIFO not found: %s\n' "$serial_fifo" >&2
    printf 'Start run_Solaris112.sh with --nographic --throwaway --autologin first.\n' >&2
    exit 2
fi
if ! [[ "$line_delay" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    printf 'invalid serial line delay: %s\n' "$line_delay" >&2
    exit 2
fi

# uuencode is present in the host BusyBox used by this build environment.
# The quoted heredoc prevents the SunOS shell from interpreting encoded data.
exec 9>"$serial_fifo"
printf 'rm -f %s; uudecode <<'"'EOF'"'\r' "$remote_kernel" >&9
busybox uuencode "$kernel" "$remote_kernel" |
while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\r' "$line" >&9
    sleep "$line_delay"
done
printf 'EOF\r' >&9
printf 'sum %s; ls -l %s\r' "$remote_kernel" "$remote_kernel" >&9
exec 9>&-

printf 'serial kernel transfer complete; verify %s before booting it\n' "$remote_kernel"
