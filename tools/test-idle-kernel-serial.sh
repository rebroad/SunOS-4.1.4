#!/bin/bash
set -euo pipefail

# Boot the stock kernel, copy the rebuilt kernel from the attached read-only
# disk, reboot cleanly, and boot the copied kernel through the PROM.  This is
# deliberately prompt-gated: it must never send a command merely because a
# fixed amount of time has elapsed.

launcher=${SUNOS_LAUNCHER:-/home/rebroad/SunOS/run_Solaris112.sh}
qemu=${SUNOS_QEMU_BINARY:-/mnt/kingston/builds/rebroad/src/qemu.build/build/qemu-system-sparc}
kernel_disk=${SUNOS_KERNEL_DISK:-/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/vmunix_idle.disk}
vm_dir=$(dirname "$launcher")
log=${SUNOS_CONSOLE_LOG:-$vm_dir/sunos-console.log}
fifo=${SUNOS_SERIAL_INPUT_FIFO:-$vm_dir/sunos-serial-input}
socket=${SUNOS_SERIAL_SOCKET:-$vm_dir/sunos-serial.sock}
launcher_log=/var/tmp/sunos-idle-kernel-launcher.$$.log
launcher_pid=

die() {
	printf 'test-idle-kernel: %s\n' "$*" >&2
	exit 1
}

cleanup() {
	local status=$?
	trap - EXIT INT TERM HUP
	# If the test kernel reached a root shell, request a guest reboot before
	# allowing the launcher to perform its final process cleanup.
	if [[ -n "$launcher_pid" ]] && kill -0 "$launcher_pid" 2>/dev/null; then
		if tail -c 512 "$log" 2>/dev/null |
			tr -d '\000\r' | grep -aEq '(^|[[:space:]])#[[:space:]]*$'; then
			printf 'reboot\r' >"$fifo" 2>/dev/null || true
			for _ in $(seq 1 20); do
				grep -aEq 'Rebooting with command|Automatic reboot' "$log" 2>/dev/null && break
				sleep 1
			done
		fi
		kill "$launcher_pid" 2>/dev/null || true
		wait "$launcher_pid" 2>/dev/null || true
	fi
	rm -f "$socket" "$fifo" "$launcher_log"
	exit "$status"
}
trap cleanup EXIT INT TERM HUP

[[ -x "$launcher" ]] || die "launcher not found: $launcher"
[[ -x "$qemu" ]] || die "QEMU binary not found: $qemu"
[[ -r "$kernel_disk" ]] || die "kernel disk not found: $kernel_disk"

rm -f "$socket" "$fifo"
: >"$log"

timeout 600s env SUNOS_QEMU_BINARY="$qemu" \
	"$launcher" --nographic --throwaway --nocpuidle --nonet --noboot \
	--kernel-disk "$kernel_disk" >"$launcher_log" 2>&1 &
launcher_pid=$!

has_console() {
	local pattern=$1
	tail -c 2048 "$log" 2>/dev/null |
		tr -d '\000\r' | grep -aEq "$pattern"
}

wait_for_console() {
	local pattern=$1
	local limit=$2
	for _ in $(seq 1 "$limit"); do
		has_console "$pattern" && return 0
		kill -0 "$launcher_pid" 2>/dev/null || return 1
		sleep 1
	done
	return 1
}

printf 'waiting for PROM prompt...\n'
wait_for_console 'Type[[:space:]]+help.*for more information|ok[[:space:]]*$' 360 \
	|| die 'PROM prompt not reached'
printf 'booting stock kernel...\n'
printf 'boot disk -s\r' >"$fifo"

wait_for_console 'SunOS Release' 360 || die 'stock kernel did not start'
wait_for_console 'root on' 120 || die 'single-user root filesystem did not mount'
wait_for_console '(^|[[:space:]])#[[:space:]]*$' 120 \
	|| die 'single-user shell prompt not reached'

printf 'copying rebuilt kernel and requesting clean reboot...\n'
printf 'dd if=/dev/rsd1a of=/tmp/vmunix_idle bs=8192\rchmod 755 /tmp/vmunix_idle\rreboot\r' >"$fifo"
wait_for_console 'Rebooting with command|Automatic reboot' 120 \
	|| die 'clean reboot marker not reached'

printf 'booting rebuilt kernel...\n'
printf 'boot disk /tmp/vmunix_idle\r' >"$fifo"
wait_for_console 'prom_init:|Illegal Instruction|Data Access Exception' 240 \
	|| die 'rebuilt-kernel result marker not reached'

printf '%s\n' '--- rebuilt-kernel result ---'
tail -c 8192 "$log" | tr -d '\000' |
	grep -aE 'prom_init:|Illegal Instruction|Data Access Exception|SunOS Release|panic|login:' |
	tail -40 || true

