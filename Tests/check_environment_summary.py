#!/usr/bin/env python3
import json
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / "Umbra/AppUI.swift").read_text()
start = source.index("    var summary: String {")
summary = source[start:source.index("\n    func refresh()", start)].replace(
    'Bundle.main.preferredLocalizations.first ?? "en"', "testLanguage"
)
catalog = json.loads((root / "Umbra/Localizable.xcstrings").read_text())["strings"]
translations = {
    locale: {
        key: unit["value"]
        for key, entry in catalog.items()
        if (unit := entry.get("localizations", {}).get(locale, {}).get("stringUnit"))
    }
    for locale in ["zh-Hans", "en", "ar"]
}
script = '''import Foundation
var testLanguage = "zh-Hans"
let translations = try JSONSerialization.jsonObject(with: Data(contentsOf:
    URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: [String: String]]
func localized(_ key: String) -> String { translations[testLanguage]![key]! }
struct Check {
    var findings: [[String: String]]
    var isChecking = false
''' + summary + '''
}
func check(_ name: String, _ keys: [String], _ expected: String, checking: Bool = false) {
    let result = Check(findings: keys.map { ["title": localized($0)] }, isChecking: checking).summary
    assert(result == expected, "\\(name): \\(result) != \\(expected)")
    print("\\(name): \\(result)")
}
check("0", [], "未发现问题")
check("0 checking", [], "正在检查环境…", checking: true)
check("1", ["SSH Server"], "SSH 服务")
check("2", ["SSH Server", "Dropbear"], "SSH 和 Dropbear 服务")
check("3", ["SSH Server", "Dropbear", "Frida Server"], "SSH、Dropbear 和 Frida 服务")
check("4", ["SSH Server", "Dropbear", "Frida Server", "VPN or Proxy"], "SSH 和 Frida 等服务；VPN 或代理")
check("no services", ["Unknown Bindfs Mount(s)", "VPN or Proxy"], "未知 Bindfs 挂载；VPN 或代理")
check("Frida only", ["Frida Server"], "Frida 服务")
check("4 with 2 services", ["Legacy rootless jailbreak(s)", "SSH Server", "Dropbear", "VPN or Proxy"],
      "旧版无根越狱文件；SSH 和 Dropbear 服务；VPN 或代理")
check("group ordering", ["VPN or Proxy", "Frida Server", "Unknown Bindfs Mount(s)", "SSH Server"],
      "VPN 或代理；Frida 和 SSH 服务；未知 Bindfs 挂载")
testLanguage = "en"
check("English 2", ["SSH Server", "Dropbear"], "SSH and Dropbear services")
check("English 3", ["SSH Server", "Dropbear", "Frida Server"], "SSH, Dropbear, and Frida services")
check("English 4", ["SSH Server", "Dropbear", "Frida Server", "VPN or Proxy"],
      "Services including SSH and Frida; VPN or Proxy")
testLanguage = "ar"
let arabic = Check(findings: ["SSH Server", "Dropbear", "Frida Server", "VPN or Proxy"].map {
    ["title": localized($0)]
}).summary
assert(arabic.contains("؛ "))
print("Arabic 4: \\(arabic)")
'''
with tempfile.TemporaryDirectory(prefix="umbra-summary-") as directory:
    temp = Path(directory)
    (temp / "check.swift").write_text(script)
    (temp / "translations.json").write_text(json.dumps(translations))
    subprocess.run([
        "xcrun", "swift", "-module-cache-path", str(temp / "cache"),
        str(temp / "check.swift"), str(temp / "translations.json"),
    ], check=True)
