#!/usr/bin/env python3
"""Push one file to a SunOS 4.1.4 login shell over telnet."""

import argparse
import os
import re
import socket
import sys
import time

IAC = 255
WILL, WONT, DO, DONT = 251, 252, 253, 254
SE, SB = 240, 250
BINARY = 0


class Telnet:
    def __init__(self, sock):
        self.sock = sock

    def _option(self, command, option):
        self.sock.sendall(bytes((IAC, command, option)))

    def _plain(self, data):
        result = bytearray()
        index = 0
        while index < len(data):
            if data[index] != IAC:
                result.append(data[index])
                index += 1
                continue
            if index + 1 >= len(data):
                break
            command = data[index + 1]
            if command == IAC:
                result.append(IAC)
                index += 2
            elif command in (WILL, WONT, DO, DONT) and index + 2 < len(data):
                option = data[index + 2]
                if command == DO:
                    self._option(WILL if option == BINARY else WONT, option)
                elif command == WILL:
                    self._option(DO if option == BINARY else DONT, option)
                index += 3
            elif command == SB:
                end = data.find(bytes((IAC, SE)), index + 2)
                if end < 0:
                    break
                index = end + 2
            else:
                index += 2
        return bytes(result)

    def read_until(self, pattern, timeout=30):
        received = bytearray()
        deadline = time.monotonic() + timeout
        while not re.search(pattern, received, re.MULTILINE):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"timed out waiting for {pattern!r}: {received[-500:]!r}")
            self.sock.settimeout(remaining)
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("telnet connection closed")
            received.extend(self._plain(chunk))
        return bytes(received)

    def line(self, value):
        self.sock.sendall(value.encode() + b"\r")

    def file(self, path):
        with open(path, "rb") as source:
            while chunk := source.read(65536):
                self.sock.sendall(chunk.replace(bytes((IAC,)), bytes((IAC, IAC))))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host")
    parser.add_argument("source")
    parser.add_argument("guest_file")
    parser.add_argument("--user", default="rebroad")
    parser.add_argument("--password", default="pass123")
    args = parser.parse_args()
    size = os.stat(args.source).st_size
    block_size = 4096
    blocks = (size + block_size - 1) // block_size

    with socket.create_connection((args.host, 23), timeout=30) as sock:
        telnet = Telnet(sock)
        telnet.read_until(rb"login:\s*$")
        telnet.line(args.user)
        telnet.read_until(rb"Password:\s*$")
        telnet.line(args.password)
        telnet.read_until(rb"(?:^|\n)[^\n%#]{0,32}[%#][ \t]*$", 60)
        telnet.line("su - root")
        telnet.read_until(rb"Password:\s*$")
        telnet.line(args.password)
        # SunOS logs the successful su audit record to the console tty, not
        # to this telnet pty. The root prompt is the authoritative marker on
        # the channel we are using.
        telnet.read_until(rb"(?:^|[\r\n])#[ \t]*(?:\r?$)", 30)

        command = f"stty raw -echo; dd of={args.guest_file} bs={block_size} count={blocks}"
        telnet.line(command)
        telnet.read_until(re.escape(str(blocks)).encode() + rb"\s*$", 30)
        telnet.file(args.source)
        telnet.line(f"stty -raw echo; chmod 644 {args.guest_file}; ls -l {args.guest_file}")
        result = telnet.read_until(re.escape(args.guest_file).encode(), 120)

    sys.stdout.write(result[-1000:].decode("ascii", "replace"))
    print(f"TCP telnet transfer complete: {args.source} -> {args.guest_file} ({size} bytes)")


if __name__ == "__main__":
    main()
