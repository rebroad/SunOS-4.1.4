#!/bin/bash
set -euo pipefail

# Copy one host file into a running, throwaway SunOS guest over the existing
# serial shell. This is host-push only: it does not require guest-to-host
# TFTP, FTP data, or SSH access.

source_file=${1:?usage: install-file-serial.sh HOST_FILE [GUEST_FILE]}
guest_file=${2:-/home/rebroad/$(basename "$source_file")}
serial_fifo=${SUNOS_SERIAL_INPUT_FIFO:-/home/rebroad/SunOS/sunos-serial-input}
console_log=${SUNOS_CONSOLE_LOG:-/home/rebroad/SunOS/sunos-console.log}
block_size=${SUNOS_SERIAL_BLOCK_SIZE:-4096}

if [[ ! -f "$source_file" ]]; then
	printf 'source file not found: %s\n' "$source_file" >&2
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

case "$block_size" in
	''|*[!0-9]*) printf 'block size must be a positive integer\n' >&2; exit 2 ;;
esac
if ((block_size == 0)); then
	printf 'block size must be a positive integer\n' >&2
	exit 2
fi

file_size=$(stat -c '%s' "$source_file")
block_count=$(( (file_size + block_size - 1) / block_size ))

printf 'waiting for the logged-in SunOS shell prompt...\n'
until tail -c 2048 "$console_log" 2>/dev/null |
	grep -aEq '(^|[[:space:]])(%|#)([[:space:]]|$)'; do
	sleep 1
done

exec 9>"$serial_fifo"
# Raw mode prevents the terminal driver from translating or buffering the
# archive. dd reads exactly the bytes sent below.
printf 'stty raw -echo; dd of=%s bs=%s count=%s\r' \
	"$guest_file" "$block_size" "$block_count" >&9
sleep 1

exec 7<"$source_file"
for ((block = 0; block < block_count; block++)); do
	dd bs="$block_size" count=1 status=none <&7 >&9
done
exec 7<&-

# Let the guest consume the final socket-buffered bytes before returning the
# terminal to the shell. The size listing makes a short transfer visible.
sleep 3
printf 'stty -raw echo; chmod 644 %s; ls -l %s\r' \
	"$guest_file" "$guest_file" >&9
exec 9>&-

printf 'serial file transfer complete: %s -> %s (%s bytes)\n' \
	"$source_file" "$guest_file" "$file_size"
