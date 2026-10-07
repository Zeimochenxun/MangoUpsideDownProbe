# Mango Suite Beta9

版本 `1.2.0~beta9.1`，完整安装包 `MangoSuite-1.2.0-Beta9.1-RootHide-arm64e.deb`。

适配用户提供的 **Mango 1.0-Beta9-1 / iOS 16.5 / Dopamine RootHide / arm64e**。沿用现有 iPhone 13 mini 的工程目标。需要已经正常授权、正常运行的 Mango 主插件；本包不包含 Mango 主插件。

## 安装

1. 先安装并确认 Mango **1.0-Beta9-1** 正常运行。
2. 安装本目录的完整 MangoSuite `.deb`，可直接覆盖原 MangoSuite Beta8；旧独立修复包由包管理器替换。不要安装构建用 helper 中间包。
3. 在多巴胺中执行一次 **重新启动用户空间**。
4. 打开 **设置 → Mango 整合**。已有整合开关、原生倒置和玻璃参数继续保留。

更改四项修复开关或总开关后，重新启动用户空间；仅 Respring 不会重新加载 backboardd 中的自适应颜色模块。单独更改原生倒置开关后，完整关闭设置再打开确认保存，然后 Respring。

## 设置

| 项目 | 作用 |
|---|---|
| 启用整合修复 | 管理四项修复，保留各项选择 |
| 静止灵动岛与过渡修复 | 静止玻璃补底与原生活动透明度交接 |
| 背景颜色自适应 | 沿用 AdaptiveColor 0.1.3 的运行模块与参数 UI |
| Mango 原生屏幕倒置 | 单独保存 Mango 原生倒置偏好，不受整合总开关控制 |
| 倒置方向与小芒修复 | 系统灵动岛和小芒悬浮球、面板、通知窗口的倒置几何 |
| 分屏倒置修复 | Mango 分屏与启动器窗口的倒置、放置和拖动 |

“玻璃与边缘光参数”影响 Mango 灵动岛的静止与活动状态。自适应开启时，基础色调强度暂不可调，请使用自适应参数页的明暗不透明度；关闭自适应并重启用户空间后可调。光斑强度属于 Mango 全局设置。

首次安装不主动开启或关闭原生倒置，也不重置已有参数。原生倒置保存仍使用 `com.go.mangoosprefs` 域和 `LeXiang.UpsideDown.Enabled` 键。保存失败或数据损坏时报告错误并保留原值。

## Beta9 适配

加载器和 World/Split 身份检查切换为所提供 Beta9 的实际模块 UUID；安装依赖严格限定 Mango `1.0-Beta9-1`。不同版本或模块不匹配时不强行加载修复。

方向、小芒与原生玻璃方法按 Beta9 二进制重新核对；运行时继续检查类来源和方法 ABI，保留已有原生倒置时不重复半转、只恢复本插件拥有的变换等保护。

Beta9 二进制内原始 Metal shader 与 Beta8 逐字节相同。本版从 Beta9 真实 shader 验证 AdaptiveColor 的四项精确替换，以 LF 换行生成对应输入，并重新进行 Apple Metal 编译。AdaptiveColor 0.1.3 的模块和设置 UI 保留原件。原 Mango 文件及授权流程保持原有机制。

加载器、Idle、World（含小芒）、Split、统一设置页均由本次源码重新构建。最终包只保留一个设置入口和一个自动加载器，包含 7 个 arm64e 镜像及 15 个载荷路径。提供 manifest、SHA256、安装包验证和本次 CI 证据。

## 验证边界

成品目录的 `build-validation.json` 和 `package-verification.json` 记录实际构建、回归测试、安装布局、签名和最终组包校验结果。真机显示、触摸及动画时序仍需按 [真机验收](ACCEPTANCE.md) 检查。

Beta8 曾有媒体标题/封面缺失、分屏启动器偶发回正反馈；这些历史反馈不能证明 Beta9 仍复现，也不能仅凭编译通过宣称它们已经解决，详见 [历史问题边界](REGRESSIONS.md)。本次交付没有连接手机进行完整真机验收。

保留有期限和大小限制的几何诊断：每模块新会话最多 20 分钟、日志约 256 KiB。可选 collector 立即复制限定日志后退出；不读取媒体标题、封面数据或授权。见 [诊断说明](diagnostics/RUNTIME.md)。日常安装不需要运行 collector。

## 停用和构建

只停用四项修复：关闭整合总开关，再重启用户空间。恢复正向：单独关闭原生倒置，检查保存，再 Respring。卸载前可按需要调整原生开关；卸载不主动清空 Mango 参数。

macOS CI 使用 RootHide Theos、校验过的 iOS 16.5 SDK 和 arm64e 工具链。Beta9 完整 shader 仅作为本次编译的临时私有输入，不进入公开源码、成品或源码 ZIP；编译后删除临时输入。原 Mango 二进制同样不进入公开构建源。

```text
python tools/assemble.py --helper-deb <本次helper.deb> --source-commit <本次构建40位commit>
python tests/check_suite.py packages/MangoSuite-1.2.0-Beta9.1-RootHide-arm64e.deb --helper-deb <本次helper.deb>
python tools/export_delivery.py --run <本次成功CI编号>
```
