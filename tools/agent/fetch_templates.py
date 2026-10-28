#!/usr/bin/env python3
"""Installs only the Windows export templates of a Godot release, without downloading the whole
1.3 GB .tpz: the .tpz is a zip, so its central directory and the wanted members are fetched with
HTTP range requests (~97 MB instead of 1.3 GB). Falls back to a full download if ranges fail.

usage: fetch_templates.py [VERSION]      (default 4.5.1)
"""
import io, os, shutil, ssl, struct, sys, urllib.request, zipfile, zlib
from pathlib import Path

VERSION = sys.argv[1] if len(sys.argv) > 1 else "4.5.1"
URL = f"https://github.com/godotengine/godot/releases/download/{VERSION}-stable/Godot_v{VERSION}-stable_export_templates.tpz"
WANT = ["templates/windows_release_x86_64.exe", "templates/windows_release_x86_64_console.exe", "templates/version.txt"]
DEST = Path.home() / ".local/share/godot/export_templates" / f"{VERSION}.stable"


def ctx():
    c = ssl.create_default_context()
    for ca in (os.environ.get("SSL_CERT_FILE"), "/root/.ccr/ca-bundle.crt"):
        if ca and Path(ca).is_file():
            c.load_verify_locations(ca)
    return c


CTX = ctx()


def get(url, start=None, end=None):
    req = urllib.request.Request(url, headers={"User-Agent": "tiefbau-tycoon-setup"})
    if start is not None:
        req.add_header("Range", f"bytes={start}-{end}")
    with urllib.request.urlopen(req, context=CTX, timeout=120) as r:
        if start is not None and r.status != 206:
            raise IOError(f"server ignored range request (HTTP {r.status})")
        return r.read(), r.headers


class RemoteFile(io.RawIOBase):
    """Seekable read-only file over HTTP range requests (enough for zipfile)."""

    def __init__(self, url):
        _, h = get(url, 0, 0)
        self.url, self.pos = url, 0
        self.size = int(h["Content-Range"].split("/")[-1])

    def seekable(self):
        return True

    def readable(self):
        return True

    def seek(self, off, whence=0):
        self.pos = off if whence == 0 else (self.pos + off if whence == 1 else self.size + off)
        return self.pos

    def tell(self):
        return self.pos

    def read(self, n=-1):
        if n is None or n < 0:
            n = self.size - self.pos
        if n == 0 or self.pos >= self.size:
            return b""
        end = min(self.pos + n, self.size) - 1
        data, _ = get(self.url, self.pos, end)
        self.pos += len(data)
        return data

    def readinto(self, b):
        d = self.read(len(b))
        b[:len(d)] = d
        return len(d)


def main():
    if all((DEST / Path(w).name).exists() for w in WANT):
        print(f"Export-Vorlagen {VERSION} schon da: {DEST}")
        return
    DEST.mkdir(parents=True, exist_ok=True)
    try:
        rf = io.BufferedReader(RemoteFile(URL), buffer_size=8 << 20)
        z = zipfile.ZipFile(rf)
        for w in WANT:
            info = z.getinfo(w)
            print(f"lade {w} ({info.file_size / 1e6:.1f} MB) …", flush=True)
            with z.open(info) as src, open(DEST / Path(w).name, "wb") as dst:
                shutil.copyfileobj(src, dst, 8 << 20)
    except Exception as e:  # noqa: BLE001 - fall back to the full download
        print(f"Teil-Download ging nicht ({e}); lade die ganze .tpz (1,3 GB) …", flush=True)
        tmp = DEST / "templates.tpz.part"
        req = urllib.request.Request(URL, headers={"User-Agent": "tiefbau-tycoon-setup"})
        with urllib.request.urlopen(req, context=CTX, timeout=600) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f, 8 << 20)
        with zipfile.ZipFile(tmp) as z:
            for w in WANT:
                with z.open(w) as src, open(DEST / Path(w).name, "wb") as dst:
                    shutil.copyfileobj(src, dst)
        tmp.unlink()
    for w in WANT:
        if w.endswith(".exe"):
            os.chmod(DEST / Path(w).name, 0o755)
    print(f"Export-Vorlagen {VERSION} installiert: {DEST}")


if __name__ == "__main__":
    main()
