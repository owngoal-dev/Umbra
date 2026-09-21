#!/usr/bin/env python3
import collections
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "de", "ar", "fr", "zh-Hans", "it", "vi", "ja"}
STRING = r'@?"(?:\\.|[^"\\])*"'
CALL = re.compile(rf'\b(?:L|localized|Localized|NSLocalizedString)\s*\(\s*((?:{STRING}|[^",)])+)')
FORMAT = re.compile(r"%(?:\d+\$)?[-+#0 ']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLztj])?[@diuoxXfFeEgGaAcCsSp]")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        assert key not in result, f"Duplicate JSON key: {key}"
        result[key] = value
    return result


def source_keys(source):
    return {
        "".join(json.loads(literal.removeprefix("@")) for literal in re.findall(STRING, group))
        for call in CALL.finditer(source)
        for group in re.findall(rf"{STRING}(?:\s*{STRING})*", call[1])
    }


def parameters(value):
    return collections.Counter(
        re.sub(r"^%\d+\$", "%", match[0])
        for match in FORMAT.finditer(value.replace("%%", ""))
    )


def string_units(value):
    for key, child in value.items():
        if key == "stringUnit":
            yield child
        elif isinstance(child, dict):
            yield from string_units(child)


assert source_keys('L(flag ? "One" : "Two"); NSLocalizedString(@"A, " @"B", nil)') == {
    "One", "Two", "A, B"
}

catalog = json.loads(
    (ROOT / "Umbra/Localizable.xcstrings").read_text(), object_pairs_hook=unique_object
)
assert catalog["sourceLanguage"] == "en"
assert catalog["version"] == "1.0"
strings = catalog["strings"]
assert {"General", "Whitelist Mode", "Automatically blacklist newly installed apps."} <= strings.keys()

for key, entry in strings.items():
    assert set(entry["localizations"]) == LANGUAGES, f"Missing or unexpected language: {key!r}"
    for language, localization in entry["localizations"].items():
        units = list(string_units(localization))
        assert units, f"Missing translation: {language}, {key!r}"
        for unit in units:
            value = unit["value"]
            assert unit["state"] == "translated" and value.strip(), f"Unfinished translation: {language}, {key!r}"
            assert parameters(value) == parameters(key), f"Format parameters differ: {language}, {key!r}"
            assert not re.search(r"[\x00-\x08\x0b-\x1f]", value), f"Invalid control character: {language}, {key!r}"
            if "Sileo/Zebra" in key:
                assert "Sileo" in value and "Zebra" not in value, f"Outdated uninstall guidance: {language}, {key!r}"

references = set()
for path in (ROOT / "Umbra").rglob("*"):
    if path.suffix in {".swift", ".m", ".mm", ".h", ".c", ".cpp"}:
        references.update(source_keys(path.read_text()))
missing = references - strings.keys()
assert not missing, "Missing localization keys:\n" + "\n".join(sorted(missing))
assert not list((ROOT / "Umbra").glob("*.lproj/Localizable.strings")), "Legacy .strings files remain"
print(f"Localization check passed: {len(strings)} strings, {len(LANGUAGES)} languages.")
