# Reproducible SunOS 4.1.4 cross-build

This repository is the source of truth. Generated configurations, host tools,
object files, logs, and the kernel are kept in the sibling build tree:

`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build`

The complete QEMU idle-test build is one command from this checkout:

```sh
./tools/build-sun4m-idle.sh
```

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

The generated kernel directory is:

`/mnt/kingston/builds/rebroad/src/SunOS-4.1.4.build/sys/sun4m/SUN4M_IDLE`

The configuration omits HSFS and NFS because the test VM boots from its local
disk and does not need those optional subsystems. Networking remains enabled.
The serial-console idle configuration omits SunView, framebuffer, audio, and
keyboard/mouse devices (`bwtwo`, `cgthree`, `cgsix`, `cgtwelve`, `gt`, `tcx`,
`audioamd`, `dbri`, `audiocs`, `win256`, `dtop4`, `ms`, and `kb`). Disk,
Ethernet, and UART support remain enabled; the generic device sources remain
available for a future full-hardware configuration.
The generated `vmunix` must be installed only into a throwaway VM disk until
the QEMU idle, clock, sleep, networking, and clean-shutdown tests pass.

Do not edit generated files in `.build` as a permanent fix: put build fixes in
the source tree, commit them, and rerun the single driver command.
