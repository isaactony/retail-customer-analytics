"""Unpack a Contoso CSV archive into a target folder, refusing any path that escapes it."""
import pathlib
import sys

import py7zr

archive, target = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]).resolve()
with py7zr.SevenZipFile(archive, "r") as z:
    names = z.getnames()
    for n in names:
        dest = (target / n).resolve()
        if target not in dest.parents and dest != target:
            sys.exit(f"refusing unsafe path in archive: {n}")
    if "--list" in sys.argv:
        for info in z.list():
            print(f"{info.uncompressed / 1e6:9.1f} MB  {info.filename}")
        sys.exit(0)
    z.extractall(path=target)
print(f"extracted {len(names)} entries to {target}")
