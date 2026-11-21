#!/usr/bin/env python3
"""Download the pinned llama.cpp runtime used by Cedar. Run before opening Xcode."""
import hashlib
from pathlib import Path
import shutil
import tempfile
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'ios' / 'Vendor'
VERSION = 'b9000'
CHECKSUM = 'bb1e87e44543dd22dd9a9b344d529c3146e3f6a0364bef0570c407d5d69a3b0c'
URL = f'https://github.com/ggml-org/llama.cpp/releases/download/{VERSION}/llama-{VERSION}-xcframework.zip'


def main():
    VENDOR.mkdir(exist_ok=True)
    marker = VENDOR / 'runtime-version.txt'
    if (VENDOR / 'llama.xcframework').exists() and marker.exists() and marker.read_text().strip() == VERSION:
        print(f'llama.cpp {VERSION} is ready.')
        return
    with tempfile.TemporaryDirectory() as temporary:
        archive = Path(temporary) / 'llama.zip'
        urllib.request.urlretrieve(URL, archive)
        if hashlib.sha256(archive.read_bytes()).hexdigest() != CHECKSUM:
            raise RuntimeError('llama.cpp download failed SHA-256 verification')
        subprocess.run(["ditto", "-x", "-k", str(archive), temporary], check=True)
        destination = VENDOR / 'llama.xcframework'
        if destination.exists():
            shutil.rmtree(destination)
        shutil.move(str(Path(temporary) / 'build-apple' / 'llama.xcframework'), destination)
        marker.write_text(VERSION + '\n')
    print(f'llama.cpp {VERSION} is ready.')


if __name__ == '__main__':
    main()
