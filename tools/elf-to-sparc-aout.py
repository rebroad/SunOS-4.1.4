#!/usr/bin/env python3
"""Convert the linked ELF SunOS kernel to the PROM's SPARC a.out format."""

import struct
import sys

PT_LOAD = 1
OMAGIC = 0o407
M_SPARC = 3


def section_names(image):
    shoff = struct.unpack_from(">I", image, 32)[0]
    shentsize, shnum, shstrndx = struct.unpack_from(">HHH", image, 46)
    headers = [struct.unpack_from(">IIIIIIIIII", image, shoff + i * shentsize)
               for i in range(shnum)]
    strings_header = headers[shstrndx]
    strings = image[strings_header[4]:strings_header[4] + strings_header[5]]
    return {strings[h[0]:].split(b"\0", 1)[0].decode(): h
            for h in headers if h[0] < len(strings)}


def convert(source_path, output_path):
    image = open(source_path, "rb").read()
    entry = struct.unpack_from(">I", image, 24)[0]
    phoff = struct.unpack_from(">I", image, 28)[0]
    phentsize, phnum = struct.unpack_from(">HH", image, 42)
    load = next((struct.unpack_from(">IIIIIIII", image, phoff + i * phentsize)
                 for i in range(phnum)
                 if struct.unpack_from(">I", image, phoff + i * phentsize)[0] == PT_LOAD), None)
    if load is None:
        raise SystemExit("ELF has no loadable segment")
    sections = section_names(image)
    data = sections[".data"]
    payload_offset, payload_size = load[1], load[4]
    text_size = data[4] - payload_offset
    payload = image[payload_offset:payload_offset + payload_size]
    bss_size = load[5] - load[4]
    header = struct.pack(">BBH7I", 1, M_SPARC, OMAGIC, text_size, data[5], bss_size,
                         0, entry, 0, 0)
    with open(output_path, "wb") as output:
        output.write(header)
        output.write(payload)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} ELF OUTPUT")
    convert(sys.argv[1], sys.argv[2])
