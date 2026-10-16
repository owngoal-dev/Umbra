#!/usr/bin/env python3
"""Package an archived app without Finder metadata, preserving Unix file modes."""
import argparse
import os
from pathlib import Path
import stat
import tempfile
import zipfile


def package(app, output):
    app = Path(app)
    output = Path(output)
    if app.suffix != ".app" or not (app / "Info.plist").is_file():
        raise ValueError(f"Not an app bundle: {app}")
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".ipa", delete=False) as temporary:
        temporary_path = Path(temporary.name)
    try:
        with zipfile.ZipFile(temporary_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(app.rglob("*")):
                relative = path.relative_to(app)
                if any(part in {"__MACOSX", ".DS_Store"} or part.startswith("._")
                       for part in relative.parts):
                    continue
                mode = path.lstat().st_mode
                name = f"Payload/{app.name}/{relative.as_posix()}"
                if stat.S_ISDIR(mode):
                    name += "/"
                    content = b""
                elif stat.S_ISLNK(mode):
                    content = os.readlink(path).encode("utf-8")
                elif stat.S_ISREG(mode):
                    content = path.read_bytes()
                else:
                    raise ValueError(f"Unsupported bundle entry: {path}")
                # Stable timestamps and ordering make repeated packaging identical.
                entry = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                entry.create_system = 3
                entry.external_attr = mode << 16
                archive.writestr(entry, content, compress_type=zipfile.ZIP_DEFLATED,
                                 compresslevel=9)
        os.replace(temporary_path, output)
    finally:
        temporary_path.unlink(missing_ok=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
    print(args.output)
