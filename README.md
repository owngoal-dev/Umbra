# Umbra

Umbra 是 RootHide 越狱环境的管理 App，用于隐藏越狱痕迹并维护环境。iOS 15 及以上，Swift/UIKit 界面，Objective-C 负责系统接口与清理规则引擎。

## 功能

- **黑名单**：按 App 开关越狱隐藏，支持搜索、刷新，长按或侧滑清除 App 数据。页面顶部汇总"环境检查"结果，详情页可下拉刷新。
- **var 清理**：扫描可能被 App 识别为越狱特征的文件，按规则优先级列出，支持单选、批量选择、复制路径和在文件管理器中打开（优先 Fila，其次 Filza）。移除前确认，后台执行，失败项保留供重试。
- **设置**
  - 通用：白名单模式（占位，暂未启用）。
  - 服务：管理 SSH、Dropbear、Frida 等服务的监听端口，修改前自动备份原始 plist。
  - 高级：自定义清理规则；URL Scheme 替换（需已安装 Relaxin 0.5.4 或更新版本）。

## 构建

需要 Xcode 16 或更新版本。真实功能依赖设备上的 RootHide 环境，模拟器无法使用。

```sh
# 未签名真机构建
xcodebuild -project Umbra.xcodeproj -scheme Umbra \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 arm64e' build

# 打包 deb（需要带 roothide package scheme 的 Theos 与 ldid）
make THEOS="$HOME/theos-roothide" package
```

安装后可执行文件位于 `/Applications/Umbra.app/Umbra`，Bundle ID 与 deb 包名均为 `com.umbra.manager`。

## 检查

```sh
make format         # swift-format + clang-format 格式化
make format-check   # 严格格式检查
make check          # 本地化、环境摘要、服务端口、清理规则与规则 CRC 的回归检查
```

`clang-format` 需在 PATH 中，或通过 `CLANG_FORMAT="$(xcrun --find clang-format)"` 指定。`make check` 需要 Python 3 和 Xcode 命令行工具，不会执行任何清理操作。

修改 `Umbra/VarCleanRules.json` 后必须同步更新 `Umbra/VarCleanRules.h` 中的校验值，否则 App 启动时会拒绝加载内置规则。Theos 构建会自动生成，手动更新：

```sh
printf '#define VARCLEANRULESHASH %s\n' \
  "$(cksum -o 3 Umbra/VarCleanRules.json | awk '{print $1}')" > Umbra/VarCleanRules.h
```

## 目录结构

| 路径 | 说明 |
|---|---|
| `Umbra/` | App 源码与资源 |
| `Umbra/roothide/` | libroothide 头文件与链接存根，不要修改 |
| `Umbra/VarCleanRules.json` | 内置清理规则 |
| `Umbra/Localizable.xcstrings` | 本地化字符串，八种语言 |
| `Tests/` | `make check` 使用的检查脚本 |
| `Tools/make-icon.swift` | App 图标生成脚本 |
| `layout/`、`control`、`Makefile` | Theos 打包 |

## 图标

图标由 CoreGraphics 绘制，无外部素材，重新生成全部尺寸：

```sh
swift Tools/make-icon.swift
```

脚本写出 `AppIcon.appiconset` 中的全部 18 个尺寸和设置页使用的 `BrandIcon`。设计取 Umbra（本影）之意：深色本影圆盘遮蔽暖色太阳，右上留下一弯细亮边与日冕辉光。

## 兼容性说明

- 配置文件 `/var/mobile/Library/RootHide/RootHideConfig.plist` 与 roothidehooks 共享，路径和格式保持不变。
- deb 声明 `Conflicts`/`Replaces: com.roothide.manager`，安装时会替换旧的 RootHide Manager。
- 服务端口备份后缀为 `.umbra-backup`。旧版本留下的 `.roothide-backup` 不再被识别，可手动删除。

## 许可

MIT，见 `LICENSE`。
