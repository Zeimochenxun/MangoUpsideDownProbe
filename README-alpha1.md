# 灵动岛玻璃保守修复 alpha1

基于用户实际使用的 AdaptiveColor 0.1.3 七参数校验版，以及 IdleIsland 1.1.9 的 CI 生成源码。原基准文件和当前工作仓库均保持不变。

## 仅尝试修复四项

- IdleIsland 淡入淡出交接使用 presentation layer 当前可见透明度，避免模型 alpha 已到终值时过早恢复静止玻璃。
- IdleIsland 回弹时同时检查模型与 presentation bounds，宽高差不超过 0.5 点后才恢复；普通 transform/位移动画不增加限制。
- AdaptiveColor 总强度为 0 时关闭其额外暗边、色散增强和眩光削弱；非零强度保持原版算法。
- AdaptiveColor 色散增强按实际背景映射位置取样，避免读取错误壁纸区域。

保留内容/玻璃 MAX 交接策略、marker 编码协议、参数表、偏好设置、注入范围和 hook。普通黑白低透明度颜色的 marker 误判仍未修复；内容与玻璃透明度不一致的交接风险也仍保留。

## 候选版本和回退

- IdleIsland：`1.1.9.1~alpha1`，同包标识覆盖 `1.1.9`。
- AdaptiveColor：`0.1.3.3~alpha1`，同包标识覆盖实际附件 `0.1.3`。
- `rollback/` 保留原版 deb。试验包只适用于原基准的 iOS 16.5 / RootHide / arm64e 环境。

先只替换 IdleIsland，保留 AdaptiveColor 原版，检查通知/音乐淡入淡出、长按回弹、连续快速点按。确认后再替换 AdaptiveColor，检查总强度 0、默认参数和顶部深色/中间浅色壁纸。每次替换后重新启动用户空间，避免仍运行旧 dylib。

如出现异常，通过原安装器重新安装 `rollback/` 中对应原版包，允许降级；重新启动用户空间。此候选不修改或清空偏好设置。

## 验证范围

本地验证原包 SHA256、Mach-O 字符串长度、NUL/CFString、仅允许的字节变化、签名页哈希与包内未改文件。CI 检查实际 Idle helper 行为，使用原 SDK 编译 arm64e RootHide 包，并编译插件自身 Metal 片段的接口 harness。

尚未运行 iOS hook、Mango 的运行时完整 shader 编译或真机渲染。这些编译及结构检查不等于真机兼容性已验证。候选仍应分开试用，不能保证没有回归。

AdaptiveColor 输入 deb SHA256：`840d1d77b7d6b10a6c2959371e1abc367041ef343ba9e393c831186f39b5ba5c`。

IdleIsland 原包 SHA256：`e6bd2aec00ac552d9c11f37eb287b622413b3e4221e0f2f6f091862493c85b88`。

IdleIsland 基准 commit：`4edcf6af776adcc4f065cce46d462bd7a4f9e0cf`；CI 生成 `Tweak.m` SHA256：`c0a8e0564cdc7830017b4ad73519fc62ba9ca737ba4deb5b5f0e823c9ae00b90`。候选 CI 直接编译这份已生成源码加最小修复，不再执行会覆盖修改的旧生成脚本。
