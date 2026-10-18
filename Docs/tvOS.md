# Umbra for Apple TV

[English](#english) | [简体中文](#简体中文)

## English

Umbra remains an iOS-first project. Its optional tvOS target preserves blacklist management,
app-data cleanup, file scanning/removal, service ports, and URL scheme rules on a compatible
RootHide environment. See the [main README](../README.md) for the app's general features and checks.

### Building and packaging

The tvOS target uses the same scheme and builds arm64 for Apple TV. Validated with Xcode 26.6 and the tvOS 26.5 SDK; deployment target is tvOS 15.0.

```sh
# Unsigned tvOS archive and IPA (no Theos required)
make UMBRA_PLATFORM=tvos ipa
# Outputs: .build/Umbra-tvos.xcarchive and .build/Umbra-tvos-unsigned.ipa

# RootHide tvOS deb (appletvos-arm64e is the package ABI; the executable is arm64)
make THEOS="$HOME/theos-roothide" UMBRA_PLATFORM=tvos package

# Regenerate the two-layer Apple TV icons only
swift Tools/make-icon.swift --tvos
```

The `archive` and `ipa` targets also accept `UMBRA_PLATFORM=ios` (the default). `IPA_PATH`, `ARCHIVE_PATH` and `BUILD_DIR` can override output locations. IPA packaging preserves executable permissions and symlinks, excludes Finder/AppleDouble metadata, and produces identical ZIP bytes for an unchanged app bundle. The IPA is unsigned; use the signed RootHide deb for installation in the supported environment.

On tvOS 17 and later, selecting an app row toggles its blacklist state, and selecting a cleanup item toggles its selection. Hold either row for secondary actions such as clearing app data or opening a path in a file manager. On tvOS 15/16, selecting a row opens an action dialog that includes both the primary and secondary actions. App search opens in a dedicated system search screen instead of occupying the list header. Use the Refresh button at the bottom of each list. Service and URL scheme forms remain available. Copy Path is omitted because tvOS has no public pasteboard; file-manager links still work when a compatible Fila or Filza is installed. If neither opens, the full path is displayed. The iOS interactions remain unchanged.

The tvOS build requires a compatible tvOS RootHide runtime, `libroothide.dylib`, privileged helper execution and LaunchServices APIs. The bundled tvOS `.tbd` is a link description, not that runtime library. Preboot inspection uses optional IOKit symbols at runtime and cannot inspect the boot directory when those symbols or the boot-manifest hash are unavailable. Simulator and stock-device operation are unsupported. Compilation and packaging do not verify these private APIs or remote-control behavior on a physical Apple TV.

### Artifacts and validation

The unsigned archive contains `Products/Applications/Umbra.app`. The deb is written to
`packages/wiki.qaq.umbra_2.1_appletvos-arm64e.deb` with the version from `control`.
Both contain an arm64 Mach-O executable with the tvOS platform, minimum OS 15.0 and device
family 3. The deb retains the existing RootHide signing and installation hooks.

`make check` covers IPA metadata exclusion, executable/symlink permissions and deterministic
ZIP output, alongside the existing functional checks. `make format-check` includes platform
adapters and the icon generator. Device execution and visual acceptance have not been performed.

## 简体中文

Umbra 以 iOS 为主要平台。可选的 tvOS 目标在兼容 RootHide 环境中保留黑名单、App 数据清理、
文件扫描与删除、服务端口和 URL Scheme 规则。通用功能与检查说明见[主 README](../README.md)。

### 构建与打包

tvOS 使用同一 Scheme，生成 Apple TV 的 arm64 程序；已使用 Xcode 26.6、tvOS 26.5 SDK 验证，最低版本为 tvOS 15.0。

```sh
# 未签名 tvOS 归档和 IPA（无需 Theos）
make UMBRA_PLATFORM=tvos ipa
# 产物：.build/Umbra-tvos.xcarchive 和 .build/Umbra-tvos-unsigned.ipa

# tvOS RootHide deb：appletvos-arm64e 是包 ABI 名，程序实际为 arm64
make THEOS="$HOME/theos-roothide" UMBRA_PLATFORM=tvos package

# 仅重新生成双层 Apple TV 图标
swift Tools/make-icon.swift --tvos
```

`archive` 和 `ipa` 目标也接受 `UMBRA_PLATFORM=ios`（默认值）；可用 `IPA_PATH`、`ARCHIVE_PATH`、`BUILD_DIR` 指定输出位置。IPA 打包保留可执行权限和符号链接，排除 Finder/AppleDouble 元数据，相同 App 内容可得到相同 ZIP。IPA 未签名；受支持环境下安装请使用已签名的 RootHide deb。

tvOS 17 及以上选择 App 行会直接切换黑名单状态，选择清理项目会直接切换选中状态；长按对应行可使用清除 App 数据、在文件管理器中打开等次要操作。tvOS 15/16 选择行时打开操作弹窗，保留主要及次要操作入口。App 搜索使用独立的系统搜索界面，不再占据列表顶部。各列表底部提供刷新按钮；服务端口与 URL Scheme 表单仍可使用。tvOS 没有公开剪贴板 API，因此移除“复制路径”，但保留文件管理器跳转；需要已安装兼容的 Fila 或 Filza，均无法打开时直接显示完整路径。iOS 原有交互不变。

tvOS 版本仍需兼容的 tvOS RootHide 环境、`libroothide.dylib`、特权 helper 与 LaunchServices 私有 API。新增 `.tbd` 仅用于链接，并非运行库。preboot 检查在运行时解析可选 IOKit 符号；若 API 或 boot-manifest hash 不可用，将无法检查启动目录。模拟器和原生未修改设备不受支持。构建、归档和打包通过不代表已验证 Apple TV 真机上的私有 API 或遥控器交互。

### 产物与验证

未签名归档内含 `Products/Applications/Umbra.app`。deb 输出到
`packages/wiki.qaq.umbra_2.1_appletvos-arm64e.deb`，版本来自 `control`。
两者的程序实际为 arm64 Mach-O，平台为 tvOS，最低系统版本 15.0、设备族 3。
deb 沿用现有 RootHide 签名与安装脚本。

`make check` 除现有功能检查外，还覆盖 IPA 元数据排除、可执行/符号链接权限及 ZIP 可重复性；
`make format-check` 包含平台适配文件和图标生成器。尚未进行真机执行或视觉验收。
