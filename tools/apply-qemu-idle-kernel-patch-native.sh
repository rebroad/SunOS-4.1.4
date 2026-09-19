#!/bin/sh
set -eu

# Apply the checked-in QEMU-only kernel workflow changes on a native SunOS
# checkout. SunOS 4.1.4 does not include patch(1), so this is the portable,
# idempotent equivalent of applying tools/patches/qemu-idle-kernel.patch.

root=${1:-.}
marker=$root/.qemu-idle-kernel-patch-applied
if test -f "$marker"; then
	echo "QEMU idle kernel patch already applied: $root"
	exit 0
fi

rewrite() {
	src=$1
	dst=$src.native-tmp
	awk '
	{
		if (mode == "idle" && index($0, "__asm__ __volatile__") != 0) {
			print "\t\tasm(\"wr %%g0, %%g0, %%asr19\");"
			next
		}
		print
		if (mode == "switch" && $0 == "#ifndef SAS") {
			print "#ifdef QEMU_IDLE_POWERDOWN"
			print "! Tell a SPARC implementation with wrpowerdown to sleep until an interrupt."
			print "! This is emitted only after the idle path has enabled interrupts."
			print "wr %g0, %g0, %asr19"
			print "#endif QEMU_IDLE_POWERDOWN"
		}
		if (mode == "idle" && $0 == "\t\t\tcontinue; /* someone disabled this processor! */") {
			print ""
			print "#ifdef QEMU_IDLE_POWERDOWN"
			print "/* Sun4m POWERDOWN lets QEMU wait for the next interrupt. */"
			print "asm(\"wr %%g0, %%g0, %%asr19\");"
			print "#endif"
		}
		if (mode == "prom" && $0 == "prom_init(pgmname)") seen_prom = 1
		if (mode == "prom" && seen_prom && $0 == "{") {
			print "\tprom_printf(\"prom_init: romp=%x magic=%x version=%x\\n\","
			print "\t\t(u_int)romp, romp->op_magic, romp->op_romvec_version);"
			seen_prom = 0
		}
		if (mode == "panic" && $0 == "\tchar *s;") {
			print "#ifdef QEMU_KERNEL_DIAGNOSTICS"
			print "\tprintf(\"panic argument=%x caller=%x\\n\", (u_int)s,"
			print "\t\t(u_int)__builtin_return_address(0));"
			print "#endif QEMU_KERNEL_DIAGNOSTICS"
		}
	}' mode="$2" "$src" > "$dst"
	mv "$dst" "$src"
}

rewrite "$root/sys/sun4m/swtch.s" switch
rewrite "$root/sys/os/init_main.c" idle
rewrite "$root/sys/boot/lib/promlib/prom_init.c" prom
rewrite "$root/sys/os/subr_prf.c" panic
> "$marker"
echo "Applied native QEMU idle kernel patch: $root"
