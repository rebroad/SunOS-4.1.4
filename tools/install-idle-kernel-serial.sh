#!/bin/bash
set -euo pipefail

# Install the freshly built test kernel into a running, throwaway SunOS VM.
# Raw mode avoids both uuencoded expansion and the canonical tty input queue.

kernel=${SUNOS_IDLE_KERNEL:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE/vmunix_small}
serial_fifo=${SUNOS_SERIAL_INPUT_FIFO:-/home/rebroad/SunOS/sunos-serial-input}
console_log=${SUNOS_CONSOLE_LOG:-/home/rebroad/SunOS/sunos-console.log}
remote_kernel=/home/rebroad/vmunix_idle
block_size=4096
kernel_size=$(stat -c '%s' "$kernel")
full_blocks=$((kernel_size / block_size))
remainder=$((kernel_size % block_size))

if [[ ! -x "$kernel" ]]; then
    printf 'kernel not found: %s\n' "$kernel" >&2
    exit 2
fi
if [[ ! -p "$serial_fifo" ]]; then
    printf 'serial FIFO not found: %s\n' "$serial_fifo" >&2
    printf 'Start run_Solaris112.sh with --nographic --throwaway --autologin first.\n' >&2
    exit 2
fi
if [[ ! -f "$console_log" ]]; then
    printf 'console log not found: %s\n' "$console_log" >&2
    exit 2
fi

# Last-login output is not the shell prompt. Wait for the prompt itself so
# startup commands cannot consume the first part of the binary transfer.
printf 'waiting for the logged-in SunOS shell prompt...\n'
until tail -c 1024 "$console_log" 2>/dev/null |
    grep -aEq '(^|[[:space:]])%([[:space:]]|$)'; do
    sleep 2
done

exec 9>"$serial_fifo"
printf 'stty raw -echo; dd of=%s bs=%s count=%s\r' \
    "$remote_kernel" "$block_size" "$full_blocks" >&9
sleep 2
dd if="$kernel" of=/proc/self/fd/9 bs="$block_size" count="$full_blocks" status=none

if ((remainder)); then
    # The first dd exits after its exact block count; give the shell time to
    # parse the next command before sending the final partial block.
    sleep 2
    printf 'dd of=%s bs=%s count=1\r' "$remote_kernel" "$remainder" >&9
    sleep 1
    dd if="$kernel" of=/proc/self/fd/9 bs=1 skip=$((full_blocks * block_size)) \
        count="$remainder" status=none
fi

sleep 2
printf 'stty -raw echo; chmod 755 %s; sum %s; ls -l %s\r' \
    "$remote_kernel" "$remote_kernel" "$remote_kernel" >&9
exec 9>&-

printf 'serial raw kernel transfer complete; verify %s before booting it\n' "$remote_kernel"
