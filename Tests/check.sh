#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/umbra-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun clang -fobjc-arc -DROOTHIDE_USE_STUB -I Umbra -framework Foundation \
    Umbra/UMBCleaner.m Tests/CleanerRulesCheck.m -o "$check_dir/cleaner-rules"
"$check_dir/cleaner-rules"
if grep -qE 'chmod[[:space:]]+([ug]?[+]s|4[0-7][0-7][0-7])' layout/DEBIAN/postinst; then
    echo "postinst must not install the app as setuid root" >&2
    exit 1
fi
python3 - <<'PY'
from pathlib import Path
import re
import zlib

expected = int(re.search(r"VARCLEANRULESHASH\s+(\d+)", Path("Umbra/VarCleanRules.h").read_text())[1])
assert zlib.crc32(Path("Umbra/VarCleanRules.json").read_bytes()) == expected
print("Bundled cleanup rules: CRC matches.")
PY
