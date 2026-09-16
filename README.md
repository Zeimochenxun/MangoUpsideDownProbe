# MangoUpsideDownWorld 0.1.0-alpha1

新编写的实验兼容补丁。目标：iPhone 13 mini / iOS 16.5 / Dopamine RootHide / 已核对的 Mango 版本。尚未真机验证，不宣称全场景已修复。

采用完整灵动岛根视图倒置、内部重复旋转抵消及窗口触摸命中补偿。正常竖屏和横屏不施加倒置。仅注入 SpringBoard；不修改 Mango 原版，不涉及授权或付费逻辑。

## 先准备恢复途径，再安装

1. 在手机仍正常时，确认电脑能通过 SSH 登录该手机，并保持终端连接；同时确认能从 Dopamine 关闭 tweak 注入后重新越狱。没有可用的恢复途径时先不要装。
2. 若安装后屏幕仍响应，但位置/触摸异常：用 Filza 在 `/var/mobile/Library/Preferences/` 新建空文件 `MangoUpsideDownWorld.disabled`。主线程正常时约 0.25 秒检测到，恢复可确认属于本补丁的变换；删除标记并 respring 才重新启用。
3. SSH 可用时，先在 RootHide 的越狱终端环境中运行 `command -v dpkg` 确认包管理命令存在，再用 root 执行 `dpkg -r com.chenxun.mangoupsidedownworld`，随后用已安装的越狱工具 respring。不要在 Windows PowerShell 本地执行 dpkg。
4. 若卡住/循环重启且 SSH 不可用：按音量加、音量减，然后持续按侧键至 Apple 标志强制重启；在未启用 tweak 注入的越狱状态下移除 World。关闭注入的具体控件以设备上的 Dopamine 界面为准。
5. Filza 手动恢复时，在 RootHide 当前真实 `.jbroot-…` 下找到 `Library/MobileSubstrate/DynamicLibraries/`，将 **MangoUpsideDownWorld.plist** 改为 `.plist.disabled` 后重新启动 SpringBoard；如实际包使用另一注入目录，以 `dpkg -L com.chenxun.mangoupsidedownworld` 清单为准。不要猜随机 jbroot 路径，不要删除 mango.dylib / MangoOSRendering.dylib。

## 安装与验收

- 先卸载 MangoUpsideDownFix 并 respring；建议停用旧 Probe 以减少高频日志。保留 Mango 和原来的倒置插件。World 包声明与 Fix 冲突，运行时也拒绝同时加载 Fix。
- 安装本包的 `iphoneos-arm64e.deb`，这是原生 RootHide 包，不要再次进行 rootless→RootHide 转换。
- 安装后 respring。先测普通竖屏和横屏，确认行为与安装前一致，再进入倒置。
- 分别验证：收起岛、通知、音乐/计时器、展开、收起；检查文字图标、左右排列、展开方向、点击、长按、拖动和岛外穿透；最后转回竖屏。
- 日志位于 `/var/mobile/Library/Logs/MangoUpsideDownWorld.log`。`WORLD` 仅证明变换已应用；`HIT fallback` 仅证明窗口回退命中；都不是功能全通过。`NO HOOKS` / `CONFLICT` / `SUSPEND` 表示没有启用或已停止。
- 如果没有 `TRACK` / `WORLD`，不要叠加更多补丁强制生效：这表示当前窗口结构/方向/版本未满足保护条件。

## 编译

工程使用 RootHide Theos、iOS 16.5 SDK、Apple Clang（macOS），`ARCHS=arm64e`，`THEOS_PACKAGE_SCHEME=roothide`。运行 `make package FINALPACKAGE=1`。CI 校验 SDK 哈希、拒绝 incompatible arm64e ABI 警告并审查 deb 内容。

GitHub Actions 构建产物包含 deb、编译日志、load commands 和 SHA256。源码在本分支；不包含付费 Mango 二进制。更多原理与已知不足见 EVIDENCE.md。
