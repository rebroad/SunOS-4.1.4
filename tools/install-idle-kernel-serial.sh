#!/bin/bash
set -euo pipefail

# Install the freshly built test kernel into a running, throwaway SunOS VM.
# Raw mode avoids both uuencoded expansion and the canonical tty input queue.

kernel=${SUNOS_IDLE_KERNEL:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE/vmunix_small}
serial_fifo=${SUNOS_SERIAL_INPUT_FIFO:-/home/rebroad/SunOS/sunos-serial-input}
remote_kernel=/home/rebroad/vmunix_idle

if [[ ! -x "$kernel" ]]; then
    printf 'kernel not found: %s\n' "$kernel" >&2
    exit 2
fi
if [[ ! -p "$serial_fifo" ]]; then
    printf 'serial FIFO not found: %s\n' "$serial_fifo" >&2
    printf 'Start run_Solaris112.sh with --nographic --throwaway --autologin first.\n' >&2
    exit 2
fi

exec 9>"$serial_fifo"
# SunOS cat drains raw input continuously. The short pause lets the shell
# apply raw mode before the host writes the binary stream.
printf 'stty raw -echo; cat > %s\r' "$remote_kernel" >&9
sleep 2
dd if="$kernel" of=/proc/self/fd/9 bs=65536 status=none
printf '\004' >&9
sleep 2
printf 'stty -raw echo; chmod 755 %s; sum %s; ls -l %s\r' \
    "$remote_kernel" "$remote_kernel" "$remote_kernel" >&9
exec 9>&-

printf 'serial raw kernel transfer complete; verify %s before booting it\n' "$remote_kernel"
