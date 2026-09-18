#!/usr/bin/env python3
"""Serve one file to the SunOS 4.1.4 tftp client on the test bridge."""

import os
import socket
import struct
import sys

BLOCK_SIZE = 512
PORT = 1069


def serve(path):
    with open(path, "rb") as source, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("0.0.0.0", PORT))
        print(f"serving {path} on UDP {PORT}", flush=True)
        request, client = listener.recvfrom(2048)
        if len(request) < 4 or struct.unpack(">H", request[:2])[0] != 1:
            raise SystemExit("expected a tftp read request")

        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as transfer:
            transfer.settimeout(3)
            block = 1
            while True:
                data = source.read(BLOCK_SIZE)
                packet = struct.pack(">HH", 3, block) + data
                for _ in range(5):
                    transfer.sendto(packet, client)
                    try:
                        ack, address = transfer.recvfrom(4)
                    except socket.timeout:
                        continue
                    if (address == client and len(ack) == 4 and
                            ack[:2] == b"\x00\x04" and
                            struct.unpack(">H", ack[2:])[0] == block):
                        break
                else:
                    raise SystemExit(f"no acknowledgement for block {block}")
                if len(data) < BLOCK_SIZE:
                    return
                block = (block + 1) & 0xffff


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} FILE")
    serve(sys.argv[1])
