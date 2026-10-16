#!/usr/bin/env python3
"""Guard against Finder metadata and lost executable/symlink modes in IPAs."""
import runpy
from pathlib import Path
import stat
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
package = runpy.run_path(str(root / "Tools/package-ipa.py"))["package"]

with tempfile.TemporaryDirectory(prefix="umbra-ipa-") as directory:
    temp = Path(directory)
    app = temp / "Umbra.app"
    app.mkdir()
    (app / "Info.plist").write_bytes(b"fixture")
    (app / "Umbra").write_bytes(b"executable")
    (app / "Umbra").chmod(0o755)
    (app / "link").symlink_to("Umbra")
    (app / "Empty").mkdir()
    (app / "._Umbra").write_bytes(b"AppleDouble")
    (app / ".DS_Store").write_bytes(b"Finder")
    (app / "__MACOSX").mkdir()
    (app / "__MACOSX/metadata").write_bytes(b"metadata")
    first, second = temp / "first.ipa", temp / "second.ipa"
    package(app, first)
    package(app, second)
    assert first.read_bytes() == second.read_bytes(), "Packaging is not reproducible"
    with zipfile.ZipFile(first) as archive:
        assert set(archive.namelist()) == {
            "Payload/Umbra.app/Info.plist", "Payload/Umbra.app/Umbra",
            "Payload/Umbra.app/link", "Payload/Umbra.app/Empty/",
        }
        assert archive.getinfo("Payload/Umbra.app/Umbra").external_attr >> 16 & 0o777 == 0o755
        assert stat.S_ISLNK(archive.getinfo("Payload/Umbra.app/link").external_attr >> 16)
        assert archive.read("Payload/Umbra.app/link") == b"Umbra"
        assert archive.read("Payload/Umbra.app/Umbra") == b"executable"
print("IPA packaging: no Finder metadata; executable modes, symlinks and determinism passed.")
