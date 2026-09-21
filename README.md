# Umbra

[English](#english) | [简体中文](#简体中文)

---

## English

Umbra is the manager app for the RootHide jailbreak environment. It hides jailbreak traces from apps and helps maintain the environment. Requires iOS 15 or later.

### Features

- **Blacklist**: Toggle jailbreak hiding per app. Search, refresh, and clear an app's data via long press or swipe. An environment check summary sits at the top of the list, with a detail page that supports pull to refresh.
- **var Cleanup**: Scan for files that apps may use to detect a jailbreak, listed by rule priority. Select items individually or in bulk, copy paths, or open them in a file manager (Fila first, then Filza). Removal asks for confirmation, runs in the background, and keeps failed items for retry.
- **Settings**
  - General: Whitelist mode (placeholder, not yet enabled).
  - Services: Manage listening ports for SSH, Dropbear, Frida and similar services. The original plist is backed up before changes.
  - Advanced: Custom cleanup rules; URL scheme replacement (requires Relaxin 0.5.4 or later).

Localized in English, Simplified Chinese, Japanese, German, French, Italian, Arabic and Vietnamese.

### Building

Requires Xcode 16 or later. The app depends on a RootHide environment on a real device and does not work in the simulator.

```sh
# Unsigned device build
xcodebuild -project Umbra.xcodeproj -scheme Umbra \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 arm64e' build

# Package a deb (requires Theos with the roothide package scheme, and ldid)
make THEOS="$HOME/theos-roothide" package
```

The app installs to `/Applications/Umbra.app`. Bundle ID and package name are `wiki.qaq.umbra`.

### Checks

```sh
make format         # Format with swift-format and clang-format
make format-check   # Strict format check
make check          # Regression checks: localization, environment summary, service ports, cleanup rules and rule CRC
```

`clang-format` must be in PATH, or set `CLANG_FORMAT="$(xcrun --find clang-format)"`. `make check` needs Python 3 and the Xcode command line tools and never performs any cleanup.

After editing `Umbra/VarCleanRules.json`, update the checksum in `Umbra/VarCleanRules.h`, or the app will refuse to load the bundled rules. Theos builds do this automatically. To update it by hand:

```sh
printf '#define VARCLEANRULESHASH %s\n' \
  "$(cksum -o 3 Umbra/VarCleanRules.json | awk '{print $1}')" > Umbra/VarCleanRules.h
```

### Layout

| Path | Description |
|---|---|
| `Umbra/` | App sources and resources |
| `Umbra/roothide/` | libroothide headers and link stubs; do not modify |
| `Umbra/VarCleanRules.json` | Bundled cleanup rules |
| `Umbra/Localizable.xcstrings` | Localized strings |
| `Tests/` | Scripts used by `make check` |
| `Tools/make-icon.swift` | Regenerates all app icon sizes: `swift Tools/make-icon.swift` |
| `layout/`, `control`, `Makefile` | Theos packaging |

### License

MIT. See `LICENSE`.

---

## 简体中文

Umbra 是 RootHide 越狱环境的管理 App，用于对 App 隐藏越狱痕迹并维护环境。需要 iOS 15 或更新版本。

### 功能

- **黑名单**：按 App 开关越狱隐藏，支持搜索、刷新，长按或侧滑清除 App 数据。列表顶部汇总环境检查结果，详情页可下拉刷新。
- **var 清理**：扫描可能被 App 用于识别越狱的文件，按规则优先级列出。支持单选、批量选择、复制路径，或在文件管理器中打开（优先 Fila，其次 Filza）。移除前确认，后台执行，失败项保留供重试。
- **设置**
  - 通用：白名单模式（占位，暂未启用）。
  - 服务：管理 SSH、Dropbear、Frida 等服务的监听端口，修改前自动备份原始 plist。
  - 高级：自定义清理规则；URL Scheme 替换（需已安装 Relaxin 0.5.4 或更新版本）。

支持英语、简体中文、日语、德语、法语、意大利语、阿拉伯语、越南语。

### 构建

需要 Xcode 16 或更新版本。App 依赖真机上的 RootHide 环境，模拟器无法使用。

```sh
# 未签名真机构建
xcodebuild -project Umbra.xcodeproj -scheme Umbra \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 arm64e' build

# 打包 deb（需要带 roothide package scheme 的 Theos 与 ldid）
make THEOS="$HOME/theos-roothide" package
```

App 安装到 `/Applications/Umbra.app`，Bundle ID 与包名均为 `wiki.qaq.umbra`。

### 检查

```sh
make format         # 使用 swift-format 与 clang-format 格式化
make format-check   # 严格格式检查
make check          # 回归检查：本地化、环境摘要、服务端口、清理规则与规则 CRC
```

`clang-format` 需在 PATH 中，或设置 `CLANG_FORMAT="$(xcrun --find clang-format)"`。`make check` 需要 Python 3 和 Xcode 命令行工具，不会执行任何清理操作。

修改 `Umbra/VarCleanRules.json` 后需更新 `Umbra/VarCleanRules.h` 中的校验值，否则 App 会拒绝加载内置规则。Theos 构建会自动生成，手动更新：

```sh
printf '#define VARCLEANRULESHASH %s\n' \
  "$(cksum -o 3 Umbra/VarCleanRules.json | awk '{print $1}')" > Umbra/VarCleanRules.h
```

### 目录结构

| 路径 | 说明 |
|---|---|
| `Umbra/` | App 源码与资源 |
| `Umbra/roothide/` | libroothide 头文件与链接存根，请勿修改 |
| `Umbra/VarCleanRules.json` | 内置清理规则 |
| `Umbra/Localizable.xcstrings` | 本地化字符串 |
| `Tests/` | `make check` 使用的检查脚本 |
| `Tools/make-icon.swift` | 重新生成全部尺寸的 App 图标：`swift Tools/make-icon.swift` |
| `layout/`、`control`、`Makefile` | Theos 打包 |

### 许可

MIT，见 `LICENSE`。
