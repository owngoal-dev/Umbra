# Umbra for Apple TV

[English](#english) | [简体中文](#简体中文)

## English

Umbra remains an iOS-first project. Its optional tvOS target preserves blacklist management,
app-data cleanup, file scanning/removal and environment checks on a compatible
RootHide environment. See the [main README](../README.md) for the app's general features and checks.

### Building and packaging

The independent SwiftUI tvOS target uses the `UmbraTV` scheme and builds arm64 for Apple TV. Validated with Xcode 26.6 and the tvOS 26.5 SDK; deployment target is tvOS 15.0.

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

The SwiftUI interface has three tabs: Blacklist, Cleanup and Environment Check. Blacklist combines the system keyboard with live app results; pressing an app row toggles its blacklist state, while the adjacent trash button asks to clear its data. Cleanup supports item selection and confirmed bulk removal. Environment Check displays findings directly. Data refreshes on returning to the foreground. File-manager links, port editing and URL scheme editing are omitted on tvOS. The shared backend and the iOS interface remain unchanged.

The tvOS build requires a compatible tvOS RootHide runtime, `libroothide.dylib`, privileged helper execution and LaunchServices APIs. The bundled tvOS `.tbd` is a link description, not that runtime library. Preboot inspection uses optional IOKit symbols at runtime and cannot inspect the boot directory when those symbols or the boot-manifest hash are unavailable. Simulator and stock-device operation are unsupported. Compilation and packaging do not verify these private APIs or remote-control behavior on a physical Apple TV.

### Artifacts and validation

The unsigned archive contains `Products/Applications/Umbra.app`. The deb is written to
`packages/wiki.qaq.umbra_2.2.2_appletvos-arm64e.deb` with the version from `control`.
Both contain an arm64 Mach-O executable with the tvOS platform, minimum OS 15.0 and device
family 3. The deb retains the existing RootHide signing and installation hooks.

`make check` covers IPA metadata exclusion, executable/symlink permissions and deterministic
ZIP output, alongside the existing functional checks. `make format-check` includes platform
adapters and the icon generator. The interface has been inspected on vphone running tvOS 26.6; physical Apple TV validation remains outstanding.

## 简体中文

Umbra 以 iOS 为主要平台。可选的 tvOS 目标在兼容 RootHide 环境中保留黑名单、App 数据清理、
文件扫描与删除和环境检查。通用功能与检查说明见[主 README](../README.md)。

### 构建与打包

独立的 SwiftUI tvOS target 使用 `UmbraTV` Scheme，生成 Apple TV 的 arm64 程序；已使用 Xcode 26.6、tvOS 26.5 SDK 验证，最低版本为 tvOS 15.0。

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

SwiftUI 界面包含黑名单、清理和环境检查三个标签。黑名单页将系统键盘与实时应用结果合为一页，按下应用行即可切换黑名单，旁边的垃圾桶按钮用于确认清除应用数据。清理页支持文件选择与批量删除确认；环境检查页直接显示结果。返回前台时自动更新数据。tvOS 不提供文件管理器入口、端口修改和 URL Scheme 修改。共享后端与 iOS 界面保持不变。

tvOS 版本仍需兼容的 tvOS RootHide 环境、`libroothide.dylib`、特权 helper 与 LaunchServices 私有 API。新增 `.tbd` 仅用于链接，并非运行库。preboot 检查在运行时解析可选 IOKit 符号；若 API 或 boot-manifest hash 不可用，将无法检查启动目录。模拟器和原生未修改设备不受支持。构建、归档和打包通过不代表已验证 Apple TV 真机上的私有 API 或遥控器交互。

### 产物与验证

未签名归档内含 `Products/Applications/Umbra.app`。deb 输出到
`packages/wiki.qaq.umbra_2.2.2_appletvos-arm64e.deb`，版本来自 `control`。
两者的程序实际为 arm64 Mach-O，平台为 tvOS，最低系统版本 15.0、设备族 3。
deb 沿用现有 RootHide 签名与安装脚本。

`make check` 除现有功能检查外，还覆盖 IPA 元数据排除、可执行/符号链接权限及 ZIP 可重复性；
`make format-check` 包含平台适配文件和图标生成器。已在运行 tvOS 26.6 的 vphone 上检视界面，尚未验证实体 Apple TV。
