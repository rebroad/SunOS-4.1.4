#!/usr/bin/env python3
"""Put a SunOS kernel in partition a of a minimal labeled Sun disk image."""

import os
import struct
import sys

SECTOR = 512
SECTORS_PER_CYLINDER = 2342
CYLINDERS = 2


def main(kernel_path, disk_path):
    partition_sectors = (os.stat(kernel_path).st_size + SECTOR - 1) // SECTOR
    label = bytearray(SECTOR)
    label[:128] = b"QEMU test kernel cyl 2 alt 0 hd 1 sec 2342".ljust(128, b"\0")
    # rpm, pcyl, apc, obs1, obs2, interleave, ncyl, acyl, nhead, nsect,
    # obs3, obs4.
    struct.pack_into(
        ">12H", label, 420,
        3600, CYLINDERS, 0, 0, 0, 1, CYLINDERS, 0, 1,
        SECTORS_PER_CYLINDER, 0, 0,
    )
    # Partition a starts at cylinder 1, leaving the label cylinder unused.
    struct.pack_into(">ii", label, 444, 1, partition_sectors)
    struct.pack_into(">H", label, 508, 0xDABE)
    checksum = 0
    for offset in range(0, 510, 2):
        checksum ^= struct.unpack_from(">H", label, offset)[0]
    struct.pack_into(">H", label, 510, checksum)

    start = SECTOR * SECTORS_PER_CYLINDER
    with open(kernel_path, "rb") as source, open(disk_path, "wb") as target:
        target.write(label)
        target.seek(start)
        target.write(source.read())
        target.truncate(start + partition_sectors * SECTOR)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} KERNEL OUTPUT_DISK")
    main(sys.argv[1], sys.argv[2])
