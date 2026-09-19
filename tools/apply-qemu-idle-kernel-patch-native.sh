#!/bin/sh
set -eu

# Apply the QEMU idle instruction to a native SunOS checkout.  SunOS 4.1.4
# does not include patch(1), and its old awk rejects newer multi-line awk
# expressions, so keep this applicator deliberately small and portable.

root=${1:-.}
marker=$root/.qemu-idle-kernel-patch-applied-v3
if test -f "$marker"; then
	echo "QEMU idle kernel patch already applied: $root"
	exit 0
fi

move_force() {
	/bin/mv -f "$@"
}

src=$root/sys/os/init_main.c
dst=$src.native-tmp
awk '
{
	if ($0 == "#if defined(SAS)") {
		print "#ifdef QEMU_IDLE_POWERDOWN"
		print "\t\tif (!whichqs"
		print "#ifdef LWP"
		print "\t\t    && !__Nrunnable"
		print "#endif LWP"
		print "\t\t    && !qrunflag)"
		print "\t\t\tasm(\".word 0xa7800000\");"
		print "#endif QEMU_IDLE_POWERDOWN"
		print ""
	}
	print
}' "$src" > "$dst"
move_force "$dst" "$src"
> "$marker"
echo "Applied native QEMU idle kernel patch: $root"
