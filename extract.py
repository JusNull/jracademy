#!/usr/bin/env python3
"""
Extract Chrome Extension source code from a CRX3 file.

Usage:
    python3 extract.py <file.crx> [output_directory]

Example:
    python3 extract.py extension.crx source
"""
import struct
import sys
import zipfile
import os


def extract_crx(crx_path, output_dir="source"):
    if not os.path.exists(crx_path):
        print(f"Error: File '{crx_path}' not found")
        sys.exit(1)

    with open(crx_path, "rb") as f:
        magic = f.read(4)
        if magic != b"Cr24":
            print("Error: Not a valid CRX file (missing Cr24 magic bytes)")
            sys.exit(1)

        version = struct.unpack("<I", f.read(4))[0]
        header_len = struct.unpack("<I", f.read(4))[0]
        f.seek(12 + header_len)
        zip_data = f.read()

    zip_path = crx_path.replace(".crx", ".zip")
    with open(zip_path, "wb") as zf:
        zf.write(zip_data)

    with zipfile.ZipFile(zip_path, "r") as z:
        z.extractall(output_dir)
        file_count = len(z.namelist())

    os.remove(zip_path)
    print(f"Extracted {file_count} files to {output_dir}/")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 extract.py <file.crx> [output_directory]")
        sys.exit(1)

    crx_file = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "source"
    extract_crx(crx_file, out_dir)
