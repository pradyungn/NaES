#!/usr/bin/env python3

#  ____  _   _
# |  _ \| \ | | Pradyun Narkadamilli
# | |_) |  \| | https://pradyun.tech
# |  __/| |\  | MIT License
# |_|   |_| \_| Copyright 2022 Pradyun Narkadamilli
#
# Converts from INES .NES file format to iHEX file format
# Used for ECE385 Final Project (NES Clone)
#
# NOTE: Current iteration of Not an Entertainment System
# only supports dual-bank games (2 16KB games). Do not use with more.
# NaES will clone the banks for you in hex format.

import sys

def main():
    name = "dump"

    if len(sys.argv) > 3:
        print("wonky args")
        return

    try:
        f = open(sys.argv[1], "rb")
    except:
        print("oh hell no")
        return

    if len(sys.argv) == 3:
        name = sys.argv[2]

    for _ in range(4):
        f.read(1)

    size = int.from_bytes(f.read(1), byteorder="big")

    if size>2:
        print("PROGRAM ROM IS NOT SUPPORTED BY NaES: TOO CHUNGUS")
        return

    chr_size = int.from_bytes(f.read(1), byteorder="big")

    if chr_size==0:
        print("CHR-RAM IS NOT SUPPORTED BY NaES: LAZY DEV AT WORK")
        return
    elif chr_size>1:
        print("CHR-ROM IS NOT SUPPORTED BY NaES: TOO CHUNGUS")
        return

    flags6 = int.from_bytes(f.read(1), byteorder="big")

    # check bit 0 for vertical vs horizontal mirroring of NameTables
    if flags6%2==1:
        print("VERTICAL MIRRORING ENABLED\nconfigure datapath accordingly")
    else:
        print("HORIZONTAL MIRRORING ENABLED\nconfigure datapath accordingly")

    for _ in range(9):
        f.read(1)

    dump = open(f"{name}-prg.mif", "w")
    dump.write("DEPTH=32768;\n")
    dump.write("WIDTH=8;\n")
    dump.write("ADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\n")
    dump.write("CONTENT\nBEGIN\n")

    for i in range(16384*size):
        dump.write(f"{i:4X} : {f.read(1).hex()};\n")

    if size==1:
        f.seek(16)
        for i in range(16384):
            dump.write(f"{(16384+i):X} : {f.read(1).hex()};\n")

    dump.write("END;")
    dump.close()

    dump = open(f"{name}-chr.mif", "w")
    dump.write("DEPTH=8192;\n")
    dump.write("WIDTH=8;\n")
    dump.write("ADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\n")
    dump.write("CONTENT\nBEGIN\n")

    for i in range(8192):
        dump.write(f"{i:4X} : {f.read(1).hex()};\n")

    dump.write("END;")

    f.close()
    dump.close()
main()
