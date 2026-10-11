#!/usr/bin/env python3
"""Validate a packaged app before extraction."""
import pathlib
import sys
import zipfile

archives = list(pathlib.Path(sys.argv[1]).glob("*.zip"))
if len(archives) != 1:
    raise SystemExit("Expected exactly one app ZIP.")
with zipfile.ZipFile(archives[0]) as archive:
    total = 0
    names = set()
    for item in archive.infolist():
        name = pathlib.PurePosixPath(item.filename)
        if name.is_absolute() or ".." in name.parts or not name.parts or "\\" in item.filename:
            raise SystemExit("Unsafe archive path.")
        canonical_name = str(name)
        if name.parts[0] not in {"CopyShelf.app", "__MACOSX"} or canonical_name in names:
            raise SystemExit("Unexpected or duplicate archive entry.")
        names.add(canonical_name)
        mode = (item.external_attr >> 16) & 0o170000
        if mode not in {0, 0o100000, 0o040000}:
            raise SystemExit("Symlinks and special files are not supported in this app archive.")
        total += item.file_size
        if total > 128 * 1024 * 1024 or len(names) > 1000:
            raise SystemExit("App archive is too large.")
    if "CopyShelf.app/Contents/Info.plist" not in names or "CopyShelf.app/Contents/MacOS/CopyShelf" not in names:
        raise SystemExit("App contents are missing.")
    if archive.testzip() is not None:
        raise SystemExit("Archive integrity check failed.")
print("App archive paths, size, and integrity verified.")
