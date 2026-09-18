# Reproducible SunOS 4.1.4 cross-build

This repository is the source of truth. Generated configurations, host tools,
object files, logs, and the kernel are kept in the sibling build tree:

`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build`

The complete QEMU idle-test build is one command from this checkout:

```sh
./tools/build-sun4m-idle.sh
```

The default build defines `QEMU_IDLE_POWERDOWN` and is the kernel intended for
the idle tests. To produce a same-source control kernel without the new
instruction, use `SUNOS_IDLE_DEFINE=` for a separate test build; do not use
that control image as the final idle implementation:

```sh
SUNOS_IDLE_DEFINE= ./tools/build-sun4m-idle.sh
```

The checked-in kernel sources remain portable for both the historical SunOS
build and the Debian cross-build. QEMU-specific idle instructions and optional
diagnostic prints are applied only to the external build tree by the
reproducible workflow patch:

```sh
./tools/apply-qemu-idle-kernel-patch.sh /path/to/a/throwaway-sunos-tree
```

Apply that same patch to a throwaway source tree before an in-guest build; do
not edit the authoritative source checkout. This keeps the host and guest
builds on one source base while making their intentional QEMU build variant
explicit and auditable.

The driver synchronizes the source into the external build tree, runs the old
`config` utility in the escalated bubblewrap environment, builds generators as
32-bit SPARC programs, runs them with `qemu-sparc32plus`, and then builds the
kernel serially. Serial execution is required because the historical Makefile
uses a shared `a.out.c` temporary file.

The compiler command suppresses only `-Wendif-labels`, whose thousands of
instances are historical `#endif NAME` annotations. Other warnings remain
visible: return-type mismatches, integer overflows, malformed guards, and
ABI-related diagnostics must be reviewed rather than hidden. A warning that
blocks the build is fixed in the source tree when it represents a real
modern-toolchain incompatibility.

Compiler output is retained in
`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/kernel-build.log`; the
driver prints only a success line or concise failure diagnostics.
The configuration utility's output is retained separately in
`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/config-run.log`.
The standalone PROM-library output is retained in
`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/promlib-build.log`.

The generated kernel directory is:

`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE`

The driver cleans the generated kernel directory before compiling. This is
intentional: the legacy dependency file can otherwise reuse an old object
after a source edit and silently produce a stale kernel. The clean output is
retained in `kernel-clean.log` beside the other build logs.

The configuration omits HSFS and NFS because the test VM boots from its local
disk and does not need those optional subsystems. Networking remains enabled.
The serial-console idle configuration omits SunView, framebuffer, audio, and
keyboard/mouse devices (`bwtwo`, `cgthree`, `cgsix`, `cgtwelve`, `gt`, `tcx`,
`audioamd`, `dbri`, `audiocs`, `win256`, `dtop4`, `ms`, `kb`, and `fd`). It
also omits the unused SCSI optical/tape targets (`sr`, `st_conf`, and `st`)
and floppy assembly. SCSI disk, Ethernet, and UART support remain enabled;
the generic device sources remain available for a future full-hardware
configuration. The historical lock-manager objects remain in the build
because the UFS lock code references their entry points even when NFS clients
are off.
The driver also emits `vmunix_small.aout`, the SunOS SPARC a.out form required
by the PROM. The ELF `vmunix_small` is retained for host-side inspection; use
the a.out file when installing a kernel through the PROM. Both must be
installed only into a throwaway VM disk until
the QEMU idle, clock, sleep, networking, and clean-shutdown tests pass.

To install the rebuilt kernel without modifying the persistent disk, start the
launcher in a throwaway headless session with `--autologin`, then run this
single command from another host shell while the logged-in shell is idle:

```sh
./tools/install-idle-kernel-serial.sh
```

The helper switches the guest tty to raw mode, transfers the binary over the
live serial FIFO, writes `/home/rebroad/vmunix_idle`, and asks SunOS to print
its checksum. It intentionally does not replace `/vmunix`; use the PROM to boot
the test image only after checking the reported checksum. The launcher must be
run with `--throwaway`, and the VM must be shut down cleanly after testing.

When the `spod` bridge is available, prefer the network transfer over serial.
Start the one-file TFTP server on the host:

```sh
./tools/tftp-serve-one.py /mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE/vmunix_small.aout
```

In the logged-in guest, configure the temporary bridge address and fetch the
kernel with SunOS's TFTP client:

```sh
ifconfig le0 137.205.192.2 netmask 255.255.255.248 up
tftp 137.205.192.1
connect 137.205.192.1 1069
binary
get vmunix_small /home/rebroad/vmunix_idle
quit
sum /home/rebroad/vmunix_idle
```

Use only a throwaway VM for this transfer; do not replace `/vmunix`.

The preferred local installation method is the launcher’s read-only kernel
disk, which avoids serial flow control altogether:

```sh
cd /home/rebroad/SunOS && ./run_Solaris112.sh --nographic --throwaway --nocpuidle --kernel-disk /mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/vmunix_idle.disk
```

After login, copy the attached target-1 disk into the throwaway guest:

```sh
dd if=/dev/rsd1a of=/home/rebroad/vmunix_idle bs=8192
sum /home/rebroad/vmunix_idle
```

The exact device name should be confirmed from the guest boot messages before
running `dd`; the persistent disk remains unchanged.

For the complete prompt-gated install/reboot/boot check, run this from the
source checkout instead of assembling the serial commands manually:

```sh
./tools/test-idle-kernel-serial.sh
```

It starts a throwaway headless VM, waits for each actual PROM or shell marker,
copies the kernel from the read-only target-1 disk, requests a guest reboot,
and reports whether the rebuilt kernel reaches its diagnostic marker. The
launcher and QEMU paths may be overridden with environment variables, but the
defaults match the documented external build tree.

Build the labeled disk once before starting the launcher:

```sh
./tools/make-kernel-disk.py /mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE/vmunix_small.aout /mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/vmunix_idle.disk
```

Use `vmunix_idle.disk` as the `--kernel-disk` argument. In a throwaway
single-user boot, the kernel is then available as `/dev/rsd1a`.

The stock `usr.bin/sleep` is intentionally unchanged. It calls the standard
SunOS `sleep()` interface; the kernel places the calling process on a sleep
queue and switches processes. The QEMU idle change belongs in the
multiprocessor `idlework()` polling loop, where the rebuilt kernel emits the
sun4m `POWERDOWN` instruction when no runnable work exists.

To set the temporary test root password on the persistent disk, use the
explicitly destructive-to-the-disk helper (with the password supplied through
the environment, not committed to source):

```sh
SUNOS_ROOT_PASSWORD=pass123 ./tools/set-root-password-serial.sh --persistent
```

It boots single-user mode, waits for each password prompt, and requests a
clean guest reboot after updating the password. Do not run it against a
throwaway VM when the password is intended to persist.

Do not edit generated files in `.build` as a permanent fix: put build fixes in
the source tree, commit them, and rerun the single driver command.
