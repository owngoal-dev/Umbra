# Umbra

iOS 15+。Swift/UIKit 界面，保留 Objective-C 系统接口和清理规则引擎。

应用名单支持搜索、刷新、开关和长按／侧滑清除应用数据；开关保存仅更新对应应用。

“var 清理”检查指定路径中可能被 App 识别为越狱特征的文件，供用户确认用途后按需移除。保留规则优先级、手动选择、批量选择、文件管理器入口和复制路径；文件入口优先打开 Fila，其次 Filza。移除前确认，后台执行，失败项目保留供重试。

启动前同步准备首屏数据，不展示转圈页或淡入过渡。启动检查汇总到黑名单页的“环境检查”，摘要直接列出发现项，详情支持下拉刷新，不再逐项弹窗。设置保留自定义清理规则和关于区域；“通用”位于“服务”之前，包含已禁用的“白名单模式”占位开关。

设置的“高级 → URL Scheme 替换”仅在已安装 Relaxin 的营销版本不低于 `0.5.4` 时显示，不考虑构建号。通过当前环境的 `/basebin/.AppIdentifier` 查找实际安装的 Relaxin，兼容重签后更改 Bundle ID 的情况；记录缺失或 App 已卸载时隐藏入口。该页面管理自定义 Scheme 规则：列表开关立即保存，点行编辑，侧滑删除。新建规则默认开启，编辑保留开关状态；首次预置的 `filza → fila` 默认关闭，删除后不会补回。配置存入 `RootHideConfig.plist` 的 `urlSchemeReplacements` 字典，每项包含 `target` 和 `enabled`。更新后的 roothidehooks 在下一次 URL 请求中检查变更并生效，配置未变时不重复读取解析。规则仅作用于非黑名单 App，保留原 Scheme 的查询声明校验；黑名单 App 沿用原有访问限制。规则只替换 Scheme；目标未安装时保留原链接。

## 构建与检查

建议使用 Xcode 16 或更新版本打开 `Umbra.xcodeproj`。真实功能依赖设备上的 RootHide 环境及原有权限；普通模拟器不具备这些系统接口。

```sh
# 无需 Theos：格式化、严格检查和非破坏性回归检查
make format
make format-check
make check

# 未签名真机构建
xcodebuild -project Umbra.xcodeproj -scheme Umbra \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 arm64e' build

# 配置好包含 roothide package scheme 的 Theos 和签名工具后打包
make THEOS="$HOME/theos-roothide" package
```

`make format` 合并 Xcode 自带的 `swift-format` 与 `clang-format`，后者须在 PATH 中（可用 `brew install clang-format` 安装）。可通过 `SWIFT_FORMAT`、`CLANG_FORMAT` 覆盖命令。第三方 JSON 注释解析器及 roothide 头文件不批量改写。

`make check` 需要 Python 3 和 Xcode 命令行工具，验证八语言翻译覆盖及参数一致性、环境摘要的分组与简写、服务端口配置的读写与校验、清理规则优先级和选择恢复、内置规则 CRC；不执行清理操作。修改 `VarCleanRules.json` 后需同步更新 `VarCleanRules.h`，Theos 的 `before-all` 会自动生成该校验值。

本地化集中于 `Umbra/Localizable.xcstrings`：英语、简体中文、日语、德语、法语、意大利语、阿拉伯语、越南语。旧配置文件路径及格式保持兼容。

Bundle ID 与 deb 包名为 `com.umbra.manager`，可执行文件安装到 `/Applications/Umbra.app/Umbra`；deb 通过 `Conflicts`/`Replaces` 声明取代旧的 `com.roothide.manager`，升级时不会并存两个 App。服务端口备份后缀改为 `.umbra-backup`，旧版本留下的 `.roothide-backup` 文件不再被识别，需要时可手动删除。`RootHideConfig.plist` 等与 roothidehooks 共享的路径和格式不变。

## 图标

运行 `swift Tools/make-icon.swift` 重新生成全部图标：脚本用 CoreGraphics 矢量绘制，4 倍超采样后逐级缩放，直接写出 `Umbra/Assets.xcassets/AppIcon.appiconset/` 中 `Contents.json` 列出的全部 18 个 iPhone/iPad 尺寸，以及设置页使用的 228×228 `BrandIcon`。输出确定性可重现，不依赖外部素材。之后可选地压一次源图：

```sh
magick Umbra/Assets.xcassets/AppIcon.appiconset/icon-1024.png \
  -strip -define png:compression-level=9 \
  Umbra/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

设计取 Umbra（本影）之意：近黑深蓝的径向渐变底色上，暖色太阳被略大的深色本影圆盘自左下遮蔽，只在右上留下一弯细亮边与向外扩散的日冕辉光；本影边缘保留一圈极细的冷色高光，缩小到 29 px 时轮廓仍可辨认。纯图形，不含文字、边框或圆角（圆角由 iOS 自动遮罩）。
