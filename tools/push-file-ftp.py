#!/usr/bin/env python3
"""Push one file to SunOS ftpd through the host-facing DNAT address.

The control connection uses 10.205.192.4. SunOS advertises one passive data
port at a time, so this helper permits only that exact host-to-guest port for
the duration of the transfer and removes the nftables rule afterwards.
"""

import argparse
import ftplib
import os
import re
import socket
import subprocess


def nft(*args, check=True, capture=False):
    command = ["sudo", "-n", "nft", *args]
    return subprocess.run(command, check=check, text=True,
                          capture_output=capture)


def temporary_data_rule(port):
    nft(
        "insert", "rule", "inet", "filter", "OUTPUT",
        "ip", "saddr", "10.205.192.1", "ip", "daddr", "137.205.192.4",
        "ct", "state", "new", "tcp", "dport", str(port),
        "tcp", "flags", "syn", "/", "fin,syn,rst,ack", "counter",
        "log", "prefix", '"FTPVM: "', "accept",
    )
    rules = nft("-a", "list", "chain", "inet", "filter", "OUTPUT",
                capture=True).stdout.splitlines()
    matching = [line for line in rules if 'log prefix "FTPVM: "' in line]
    if not matching:
        raise RuntimeError("could not find temporary FTP firewall rule")
    match = re.search(r"# handle (\d+)\s*$", matching[-1])
    if not match:
        raise RuntimeError("temporary FTP firewall rule has no handle")
    return int(match.group(1))


def remove_data_rule(handle):
    nft("delete", "rule", "inet", "filter", "OUTPUT", "handle", str(handle),
        check=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("host", help="host-facing guest address (10.205.192.4)")
    parser.add_argument("source")
    parser.add_argument("guest_file")
    parser.add_argument("--user", default="rebroad")
    parser.add_argument("--password", default="pass123")
    args = parser.parse_args()

    size = os.stat(args.source).st_size
    remote_name = os.path.basename(args.guest_file)
    ftp = ftplib.FTP()
    handle = None
    data = None
    try:
        ftp.connect(args.host, 21, timeout=30)
        ftp.login(args.user, args.password)
        ftp.voidcmd("TYPE I")
        _advertised_host, port = ftp.makepasv()
        handle = temporary_data_rule(port)
        data = socket.create_connection((args.host, port), timeout=30)
        ftp.putcmd("STOR " + remote_name)
        response = ftp.getresp()
        if not response.startswith("150"):
            raise RuntimeError(f"FTP data transfer refused: {response}")
        with open(args.source, "rb") as source:
            while chunk := source.read(65536):
                data.sendall(chunk)
        data.close()
        data = None
        response = ftp.getresp()
        if not response.startswith("226"):
            raise RuntimeError(f"FTP transfer did not complete: {response}")
        print(f"FTP transfer complete: {args.source} -> {args.guest_file} ({size} bytes)")
    finally:
        if data is not None:
            data.close()
        try:
            ftp.close()
        except Exception:
            pass
        if handle is not None:
            remove_data_rule(handle)


if __name__ == "__main__":
    main()
