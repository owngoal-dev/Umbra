#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/umbra-check.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun clang -fobjc-arc -DROOTHIDE_USE_STUB -I Umbra -framework Foundation \
    Umbra/RHCleaner.m Tests/CleanerRulesCheck.m -o "$check_dir/cleaner-rules"
"$check_dir/cleaner-rules"
python3 - <<'PY'
from pathlib import Path
import re
import zlib

expected = int(re.search(r"VARCLEANRULESHASH\s+(\d+)", Path("Umbra/VarCleanRules.h").read_text())[1])
assert zlib.crc32(Path("Umbra/VarCleanRules.json").read_bytes()) == expected
print("Bundled cleanup rules: CRC matches.")
PY
